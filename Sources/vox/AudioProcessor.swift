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
            fputs("DEBUG: About to create AVAssetExportSession\n", stderr)
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                fputs("DEBUG: Failed to create AVAssetExportSession\n", stderr)
                let voxError = VoxError.audioExtractionFailed("Failed to create export session")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            fputs("DEBUG: Export session created successfully\n", stderr)
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a
            
            fputs("DEBUG: Starting export session with output URL: \(outputURL.path)\n", stderr)
            
            // Start progress monitoring
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let progress = Double(exportSession.progress)
                if let callback = progressCallback {
                    let transcriptionProgress = TranscriptionProgress(
                        progress: progress * 0.8, // Reserve 20% for post-processing
                        status: "Extracting audio using AVFoundation",
                        phase: .extracting,
                        startTime: Date()
                    )
                    callback(transcriptionProgress)
                }
            }
            
            // Add timeout protection (5 minutes max)
            let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: false) { _ in
                fputs("DEBUG: Export session timed out after 5 minutes\n", stderr)
                exportSession.cancelExport()
                progressTimer.invalidate()
                let voxError = VoxError.audioExtractionFailed("Audio extraction timed out after 5 minutes")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
            }
            
            exportSession.exportAsynchronously {
                fputs("DEBUG: Export completion handler called\n", stderr)
                progressTimer.invalidate()
                timeoutTimer.invalidate()
                
                fputs("DEBUG: Export session completed with status: \(exportSession.status) (raw: \(exportSession.status.rawValue))\n", stderr)
                
                fputs("DEBUG: About to call handleExportCompletion\n", stderr)
                self.handleExportCompletion(
                    exportSession: exportSession,
                    asset: asset,
                    outputURL: outputURL,
                    progressTimer: progressTimer,
                    completion: completion
                )
                fputs("DEBUG: handleExportCompletion call completed\n", stderr)
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
        fputs("DEBUG: handleExportCompletion called with status: \(exportSession.status) (raw: \(exportSession.status.rawValue))\n", stderr)
        
        switch exportSession.status {
        case .completed:
            fputs("DEBUG: Export completed successfully, extracting audio format\n", stderr)
            // Extract audio format information
            self.extractAudioFormat(from: asset, outputURL: outputURL) { formatResult in
                completion(formatResult)
            }
            
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown export error"
            fputs("DEBUG: Export failed with error: \(errorMessage)\n", stderr)
            let voxError = VoxError.audioExtractionFailed("AVFoundation export failed: \(errorMessage)")
            completion(.failure(voxError))
            
        case .cancelled:
            fputs("DEBUG: Export was cancelled\n", stderr)
            let voxError = VoxError.audioExtractionFailed("Export was cancelled")
            completion(.failure(voxError))
            
        default:
            fputs("DEBUG: Export completed with unknown status: \(exportSession.status.rawValue)\n", stderr)
            let voxError = VoxError.audioExtractionFailed("Export completed with unknown status")
            completion(.failure(voxError))
        }
    }
    
    private func extractAudioFormat(
        from asset: AVAsset,
        outputURL: URL,
        completion: @escaping (Result<AudioFormat, VoxError>) -> Void
    ) {
        fputs("DEBUG: extractAudioFormat called\n", stderr)
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
            fputs("DEBUG: Asset values loaded asynchronously\n", stderr)
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            
            fputs("DEBUG: Asset duration status: \(status.rawValue)\n", stderr)
            
            guard status == .loaded else {
                fputs("DEBUG: Failed to load asset duration\n", stderr)
                let voxError = VoxError.audioExtractionFailed(
                    "Failed to load asset duration: \(error?.localizedDescription ?? "Unknown error")"
                )
                completion(.failure(voxError))
                return
            }
            
            fputs("DEBUG: Asset duration loaded successfully\n", stderr)
            let duration = CMTimeGetSeconds(asset.duration)
            fputs("DEBUG: Duration: \(duration) seconds\n", stderr)
            
            let audioTracks = asset.tracks(withMediaType: .audio)
            fputs("DEBUG: Found \(audioTracks.count) audio tracks\n", stderr)
            
            guard let audioTrack = audioTracks.first else {
                fputs("DEBUG: No audio tracks found\n", stderr)
                let voxError = VoxError.audioExtractionFailed("No audio tracks found")
                completion(.failure(voxError))
                return
            }
            
            // Extract format descriptions
            fputs("DEBUG: Extracting format descriptions\n", stderr)
            let formatDescriptions = audioTrack.formatDescriptions
            fputs("DEBUG: Found \(formatDescriptions.count) format descriptions\n", stderr)
            
            guard let formatDescription = formatDescriptions.first else {
                fputs("DEBUG: No format description found\n", stderr)
                let voxError = VoxError.audioExtractionFailed("No format description found")
                completion(.failure(voxError))
                return
            }
            
            // Extract audio format details
            fputs("DEBUG: Extracting audio format details\n", stderr)
            // swiftlint:disable force_cast
            let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription as! CMAudioFormatDescription
            )
            // swiftlint:enable force_cast
            let sampleRate = Int(audioStreamBasicDescription?.pointee.mSampleRate ?? 44100)
            let channels = Int(audioStreamBasicDescription?.pointee.mChannelsPerFrame ?? 2)
            
            fputs("DEBUG: Sample rate: \(sampleRate), Channels: \(channels)\n", stderr)
            
            // Get file size
            fputs("DEBUG: Getting file size for: \(outputURL.path)\n", stderr)
            let fileSize = try? FileManager.default.attributesOfItem(
                atPath: outputURL.path
            )[.size] as? UInt64
            
            fputs("DEBUG: File size: \(fileSize ?? 0) bytes\n", stderr)
            
            let audioFormat = AudioFormat(
                codec: "aac",
                sampleRate: sampleRate,
                channels: channels,
                bitRate: nil, // Will be estimated or extracted separately
                duration: duration,
                fileSize: fileSize
            )
            
            fputs("DEBUG: Audio format created successfully, calling completion\n", stderr)
            completion(.success(audioFormat))
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
