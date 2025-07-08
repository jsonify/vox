import Foundation
import AVFoundation

class AudioProcessor {
    private let logger = Logger.shared
    private let tempFileManager = TempFileManager.shared
    private let ffmpegProcessor = FFmpegProcessor()
    
    typealias CompletionCallback = (Result<AudioFile, VoxError>) -> Void
    
    init() {
        // Initialize audio processor
    }
    
    func extractAudio(
        from inputPath: String,
        progressCallback: ProgressCallback? = nil,
        completion: @escaping CompletionCallback
    ) {
        logger.info("Starting audio extraction from: \(inputPath)", component: "AudioProcessor")
        
        // Validate input file
        guard FileManager.default.fileExists(atPath: inputPath) else {
            let error = VoxError.invalidInputFile(inputPath)
            logger.error("Input file not found: \(inputPath)", component: "AudioProcessor")
            completion(.failure(error))
            return
        }
        
        // Create temporary output file
        guard let tempOutputURL = tempFileManager.createTemporaryAudioFile(extension: "m4a") else {
            let voxError = VoxError.temporaryFileCreationFailed("Failed to create temporary audio file")
            logger.error("Failed to create temporary file", component: "AudioProcessor")
            completion(.failure(voxError))
            return
        }
        
        let inputURL = URL(fileURLWithPath: inputPath)
        
        // Perform audio extraction with fallback
        performAudioExtractionWithFallback(
            inputURL: inputURL,
            inputPath: inputPath,
            tempOutputURL: tempOutputURL,
            progressCallback: progressCallback,
            completion: completion
        )
    }
    
    private func performAudioExtractionWithFallback(
        inputURL: URL,
        inputPath: String,
        tempOutputURL: URL,
        progressCallback: ProgressCallback?,
        completion: @escaping CompletionCallback
    ) {
        logger.debug("Attempting AVFoundation extraction first", component: "AudioProcessor")
        
        // Try AVFoundation first
        extractAudioUsingAVFoundation(
            from: inputURL,
            to: tempOutputURL,
            progressCallback: progressCallback
        ) { [weak self] result in
            switch result {
            case .success(let audioFormat):
                // Validate the extracted audio format
                if audioFormat.isTranscriptionReady {
                    let audioFile = AudioFile(
                        path: tempOutputURL.path,
                        format: audioFormat,
                        temporaryPath: tempOutputURL.path
                    )
                    self?.logger.info("AVFoundation extraction successful", component: "AudioProcessor")
                    completion(.success(audioFile))
                } else {
                    let error = VoxError.incompatibleAudioProperties(
                        "Audio format not compatible with transcription engines: \(audioFormat.description)"
                    )
                    self?.handleFailedExtraction(
                        inputPath: inputPath,
                        tempOutputURL: tempOutputURL,
                        error: error,
                        progressCallback: progressCallback,
                        completion: completion
                    )
                }
                
            case .failure(let error):
                self?.logger.warn(
                    "AVFoundation extraction failed, attempting ffmpeg fallback: \(error.localizedDescription)",
                    component: "AudioProcessor"
                )
                self?.handleFailedExtraction(
                    inputPath: inputPath,
                    tempOutputURL: tempOutputURL,
                    error: error,
                    progressCallback: progressCallback,
                    completion: completion
                )
            }
        }
    }
    
    private func handleFailedExtraction(
        inputPath: String,
        tempOutputURL: URL,
        error: VoxError,
        progressCallback: ProgressCallback?,
        completion: @escaping CompletionCallback
    ) {
        logger.info("Falling back to ffmpeg extraction", component: "AudioProcessor")
        
        // Try ffmpeg fallback
        ffmpegProcessor.extractAudio(
            from: inputPath,
            progressCallback: progressCallback
        ) { [weak self] ffmpegResult in
            switch ffmpegResult {
            case .success(let audioFile):
                self?.logger.info("FFmpeg extraction successful", component: "AudioProcessor")
                completion(.success(audioFile))
                
            case .failure(let ffmpegError):
                self?.logger.error("Both AVFoundation and ffmpeg extraction failed", component: "AudioProcessor")
                // Return the original error or the more specific one
                completion(.failure(ffmpegError))
            }
        }
    }
    
    private func extractAudioUsingAVFoundation(
        from inputURL: URL,
        to outputURL: URL,
        progressCallback: ProgressCallback?,
        completion: @escaping (Result<AudioFormat, VoxError>) -> Void
    ) {
        let asset = AVAsset(url: inputURL)
        
        // Check if asset has audio tracks
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            
            guard status == .loaded else {
                let voxError = VoxError.audioExtractionFailed(
                    "Failed to load asset tracks: \(error?.localizedDescription ?? "Unknown error")"
                )
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            let audioTracks = asset.tracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                let voxError = VoxError.audioExtractionFailed("No audio tracks found in input file")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            // Configure export session
            debugPrint("About to create AVAssetExportSession")
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                debugPrint("Failed to create AVAssetExportSession")
                let voxError = VoxError.audioExtractionFailed("Failed to create export session")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            debugPrint("Export session created successfully")
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a
            
            debugPrint("Starting export session with output URL: \(outputURL.path)")
            
            // Initial progress report
            if let callback = progressCallback {
                debugPrint("Sending initial progress report")
                let initialProgress = TranscriptionProgress(
                    progress: 0.0,
                    status: "Starting audio extraction...",
                    phase: .extracting,
                    startTime: Date()
                )
                callback(initialProgress)
            }
            
            // Start progress monitoring
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let progress = Double(exportSession.progress)
                debugPrint("Export progress: \(String(format: "%.1f", progress * 100))%")
                if let callback = progressCallback {
                    debugPrint("Calling progress callback with progress: \(String(format: "%.1f", progress * 100))%")
                    let transcriptionProgress = TranscriptionProgress(
                        progress: progress * 0.8, // Reserve 20% for post-processing
                        status: "Extracting audio using AVFoundation",
                        phase: .extracting,
                        startTime: Date()
                    )
                    callback(transcriptionProgress)
                } else {
                    debugPrint("No progress callback available")
                }
            }
            
            // Add timeout protection (5 minutes max)
            let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: false) { _ in
                debugPrint("Export session timed out after 5 minutes")
                exportSession.cancelExport()
                progressTimer.invalidate()
                let voxError = VoxError.audioExtractionFailed("Audio extraction timed out after 5 minutes")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
            }
            
            exportSession.exportAsynchronously {
                debugPrint("Export completion handler called")
                progressTimer.invalidate()
                timeoutTimer.invalidate()
                
                debugPrint("Export session completed with status: \(exportSession.status) (raw: \(exportSession.status.rawValue))")
                
                debugPrint("About to call handleExportCompletion")
                self.handleExportCompletion(
                    exportSession: exportSession,
                    asset: asset,
                    outputURL: outputURL,
                    progressTimer: progressTimer,
                    completion: completion
                )
                debugPrint("handleExportCompletion call completed")
            }
        }
    }
    
    private func handleExportCompletion(
        exportSession: AVAssetExportSession,
        asset: AVAsset,
        outputURL: URL,
        progressTimer: Timer,
        completion: @escaping (Result<AudioFormat, VoxError>) -> Void
    ) {
        debugPrint("handleExportCompletion called with status: \(exportSession.status) (raw: \(exportSession.status.rawValue))")
        
        switch exportSession.status {
        case .completed:
            debugPrint("Export completed successfully, extracting audio format")
            // Extract audio format information
            self.extractAudioFormat(from: asset, outputURL: outputURL) { formatResult in
                // Always dispatch completion handlers to main queue for consistent thread safety
                DispatchQueue.main.async {
                    completion(formatResult)
                }
            }
            
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            debugPrint("Export failed with error: \(errorMessage)")
            let voxError = VoxError.audioExtractionFailed("AVFoundation export failed: \(errorMessage)")
            DispatchQueue.main.async {
                completion(.failure(voxError))
            }
            
        case .cancelled:
            debugPrint("Export was cancelled")
            let voxError = VoxError.audioExtractionFailed("Export was cancelled")
            DispatchQueue.main.async {
                completion(.failure(voxError))
            }
            
        default:
            debugPrint("Export completed with unknown status: \(exportSession.status.rawValue)")
            let voxError = VoxError.audioExtractionFailed("Export completed with unknown status")
            DispatchQueue.main.async {
                completion(.failure(voxError))
            }
        }
    }
    
    private func extractAudioFormat(
        from asset: AVAsset,
        outputURL: URL,
        completion: @escaping (Result<AudioFormat, VoxError>) -> Void
    ) {
        debugPrint("extractAudioFormat called")
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
            debugPrint("Asset values loaded asynchronously")
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            
            debugPrint("Asset duration status: \(status.rawValue)")
            
            guard status == .loaded else {
                debugPrint("Failed to load asset duration")
                let voxError = VoxError.audioExtractionFailed(
                    "Failed to load asset duration: \(error?.localizedDescription ?? "Unknown error")"
                )
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            debugPrint("Asset duration loaded successfully")
            let duration = CMTimeGetSeconds(asset.duration)
            debugPrint("Duration: \(duration) seconds")
            
            let audioTracks = asset.tracks(withMediaType: .audio)
            debugPrint("Found \(audioTracks.count) audio tracks")
            
            guard let audioTrack = audioTracks.first else {
                debugPrint("No audio tracks found")
                let voxError = VoxError.audioExtractionFailed("No audio tracks found")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            // Extract format descriptions
            debugPrint("Extracting format descriptions")
            let formatDescriptions = audioTrack.formatDescriptions
            debugPrint("Found \(formatDescriptions.count) format descriptions")
            
            guard let formatDescription = formatDescriptions.first else {
                debugPrint("No format description found")
                let voxError = VoxError.audioExtractionFailed("No format description found")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            // Extract audio format details
            debugPrint("Extracting audio format details")
            // swiftlint:disable force_cast
            let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription as! CMAudioFormatDescription
            )
            // swiftlint:enable force_cast
            let sampleRate = Int(audioStreamBasicDescription?.pointee.mSampleRate ?? 44100)
            let channels = Int(audioStreamBasicDescription?.pointee.mChannelsPerFrame ?? 2)
            
            debugPrint("Sample rate: \(sampleRate), Channels: \(channels)")
            
            // Get file size
            debugPrint("Getting file size for: \(outputURL.path)")
            let fileSize = try? FileManager.default.attributesOfItem(
                atPath: outputURL.path
            )[.size] as? UInt64
            
            debugPrint("File size: \(fileSize ?? 0) bytes")
            
            let audioFormat = AudioFormat(
                codec: "aac",
                sampleRate: sampleRate,
                channels: channels,
                bitRate: nil, // Will be estimated or extracted separately
                duration: duration,
                fileSize: fileSize
            )
            
            debugPrint("Audio format created successfully, calling completion")
            // Ensure completion is called on main thread for consistent thread safety
            DispatchQueue.main.async {
                completion(.success(audioFormat))
            }
        }
    }
    
    func cleanupTemporaryFiles(for audioFile: AudioFile) {
        if let tempPath = audioFile.temporaryPath {
            do {
                try FileManager.default.removeItem(atPath: tempPath)
                logger.debug("Cleaned up temporary file: \(tempPath)", component: "AudioProcessor")
            } catch {
                logger.error(
                    "Failed to cleanup temporary file: \(error.localizedDescription)",
                    component: "AudioProcessor"
                )
            }
        }
    }
}
