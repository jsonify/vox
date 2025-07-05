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
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                let voxError = VoxError.audioExtractionFailed("Failed to create export session")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a
            
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
            
            exportSession.exportAsynchronously {
                progressTimer.invalidate()
                
                self.handleExportCompletion(
                    exportSession: exportSession,
                    asset: asset,
                    outputURL: outputURL,
                    progressTimer: progressTimer,
                    completion: completion
                )
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
        DispatchQueue.main.async {
            switch exportSession.status {
            case .completed:
                // Extract audio format information
                self.extractAudioFormat(from: asset, outputURL: outputURL) { formatResult in
                    completion(formatResult)
                }
                
            case .failed:
                let errorMessage = exportSession.error?.localizedDescription ?? "Unknown export error"
                let voxError = VoxError.audioExtractionFailed("AVFoundation export failed: \(errorMessage)")
                completion(.failure(voxError))
                
            case .cancelled:
                let voxError = VoxError.audioExtractionFailed("Export was cancelled")
                completion(.failure(voxError))
                
            default:
                let voxError = VoxError.audioExtractionFailed("Export completed with unknown status")
                completion(.failure(voxError))
            }
        }
    }
    
    private func extractAudioFormat(
        from asset: AVAsset,
        outputURL: URL,
        completion: @escaping (Result<AudioFormat, VoxError>) -> Void
    ) {
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            
            guard status == .loaded else {
                let voxError = VoxError.audioExtractionFailed(
                    "Failed to load asset duration: \(error?.localizedDescription ?? "Unknown error")"
                )
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            let duration = CMTimeGetSeconds(asset.duration)
            let audioTracks = asset.tracks(withMediaType: .audio)
            
            guard let audioTrack = audioTracks.first else {
                let voxError = VoxError.audioExtractionFailed("No audio tracks found")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            // Extract format descriptions
            let formatDescriptions = audioTrack.formatDescriptions
            guard let formatDescription = formatDescriptions.first else {
                let voxError = VoxError.audioExtractionFailed("No format description found")
                DispatchQueue.main.async {
                    completion(.failure(voxError))
                }
                return
            }
            
            // Extract audio format details
            // swiftlint:disable force_cast
            let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription as! CMAudioFormatDescription
            )
            // swiftlint:enable force_cast
            let sampleRate = Int(audioStreamBasicDescription?.pointee.mSampleRate ?? 44100)
            let channels = Int(audioStreamBasicDescription?.pointee.mChannelsPerFrame ?? 2)
            
            // Get file size
            let fileSize = try? FileManager.default.attributesOfItem(
                atPath: outputURL.path
            )[.size] as? UInt64
            
            let audioFormat = AudioFormat(
                codec: "aac",
                sampleRate: sampleRate,
                channels: channels,
                bitRate: nil, // Will be estimated or extracted separately
                duration: duration,
                fileSize: fileSize
            )
            
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
