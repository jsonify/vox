import Foundation
import AVFoundation

class AudioProcessor {
    typealias CompletionCallback = (Result<AudioFile, VoxError>) -> Void
    
    private let logger = Logger.shared
    private let ffmpegProcessor = FFmpegProcessor()
    private let tempFileManager = TempFileManager.shared
    private var processingStartTime: Date?
    
    func extractAudio(from inputPath: String, progressCallback: ProgressCallback? = nil, completion: @escaping CompletionCallback) {
        processingStartTime = Date()
        
        // TEMP DEBUG: Bypass Logger call to prevent hang
        // logger.info("Starting audio extraction from: \(inputPath)", component: "AudioProcessor")
        fputs("DEBUG: AudioProcessor.extractAudio() started for: \(inputPath)\n", stderr)
        
        // Report initialization phase
        fputs("DEBUG: About to call reportProgress (initializing)\n", stderr)
        reportProgress(0.0, phase: .initializing, callback: progressCallback)
        fputs("DEBUG: reportProgress (initializing) completed\n", stderr)
        
        fputs("DEBUG: About to check if file exists\n", stderr)
        guard FileManager.default.fileExists(atPath: inputPath) else {
            let error = VoxError.invalidInputFile("File does not exist: \(inputPath)")
            // TEMP DEBUG: Bypass Logger call
            // logger.error(error.localizedDescription, component: "AudioProcessor")
            fputs("DEBUG: File does not exist: \(inputPath)\n", stderr)
            completion(.failure(error))
            return
        }
        fputs("DEBUG: File exists check passed\n", stderr)
        
        // Report analyzing phase
        fputs("DEBUG: About to call reportProgress (analyzing)\n", stderr)
        reportProgress(0.1, phase: .analyzing, callback: progressCallback)
        fputs("DEBUG: reportProgress (analyzing) completed\n", stderr)
        
        fputs("DEBUG: About to check if valid MP4 file\n", stderr)
        guard isValidMP4File(path: inputPath) else {
            let error = VoxError.unsupportedFormat("Not a valid MP4 file: \(inputPath)")
            // TEMP DEBUG: Bypass Logger call
            // logger.error(error.localizedDescription, component: "AudioProcessor")
            fputs("DEBUG: Not a valid MP4 file: \(inputPath)\n", stderr)
            completion(.failure(error))
            return
        }
        fputs("DEBUG: Valid MP4 file check passed\n", stderr)
        
        let inputURL = URL(fileURLWithPath: inputPath)
        
        fputs("DEBUG: About to create temporary audio file\n", stderr)
        guard let tempOutputURL = tempFileManager.createTemporaryAudioFile() else {
            let error = VoxError.audioExtractionFailed("Failed to create temporary file")
            // TEMP DEBUG: Bypass Logger call
            // logger.error(error.localizedDescription, component: "AudioProcessor")
            fputs("DEBUG: Failed to create temporary file\n", stderr)
            completion(.failure(error))
            return
        }
        fputs("DEBUG: Temporary audio file created successfully\n", stderr)
        
        // Report extracting phase
        fputs("DEBUG: About to call reportProgress (extracting)\n", stderr)
        // TEMP DEBUG: Bypass reportProgress to isolate issue
        // reportProgress(0.2, phase: .extracting, callback: progressCallback)
        fputs("DEBUG: reportProgress (extracting) bypassed\n", stderr)
        
        fputs("DEBUG: About to call extractAudioUsingAVFoundation\n", stderr)
        extractAudioUsingAVFoundation(from: inputURL, to: tempOutputURL, progressCallback: progressCallback) { [weak self] result in
            fputs("DEBUG: extractAudioUsingAVFoundation callback called\n", stderr)
            switch result {
            case .success(let audioFormat):
                fputs("DEBUG: Main extractAudio success callback - creating AudioFile\n", stderr)
                // TEMP DEBUG: Bypass reportProgress calls
                // self?.reportProgress(0.95, phase: .finalizing, callback: progressCallback)
                
                let audioFile = AudioFile(
                    path: inputPath,
                    format: audioFormat,
                    temporaryPath: tempOutputURL.path
                )
                fputs("DEBUG: AudioFile created successfully\n", stderr)
                
                // TEMP DEBUG: Bypass reportProgress and Logger calls
                // self?.reportProgress(1.0, phase: .complete, callback: progressCallback)
                // self?.logger.info("Audio extraction completed successfully", component: "AudioProcessor")
                fputs("DEBUG: About to call completion(.success(audioFile))\n", stderr)
                completion(.success(audioFile))
                fputs("DEBUG: completion(.success(audioFile)) called\n", stderr)
                
            case .failure(let error):
                _ = self?.tempFileManager.cleanupFile(at: tempOutputURL)
                self?.logger.warn("AVFoundation extraction failed, attempting ffmpeg fallback: \(error.localizedDescription)", component: "AudioProcessor")
                
                // Try ffmpeg fallback
                self?.ffmpegProcessor.extractAudio(from: inputPath, progressCallback: progressCallback) { fallbackResult in
                    switch fallbackResult {
                    case .success(let audioFile):
                        self?.logger.info("FFmpeg fallback extraction succeeded", component: "AudioProcessor")
                        completion(.success(audioFile))
                    case .failure:
                        self?.logger.error("Both AVFoundation and ffmpeg extraction failed", component: "AudioProcessor")
                        // Return the original AVFoundation error as it's the primary method
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    private func extractAudioUsingAVFoundation(from inputURL: URL, to outputURL: URL, progressCallback: ProgressCallback?, completion: @escaping (Result<AudioFormat, VoxError>) -> Void) {
        fputs("DEBUG: In extractAudioUsingAVFoundation, about to create AVAsset\n", stderr)
        let asset = AVAsset(url: inputURL)
        fputs("DEBUG: AVAsset created, about to create AVAssetExportSession\n", stderr)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            let error = VoxError.audioExtractionFailed("Failed to create export session")
            // TEMP DEBUG: Bypass Logger call
            // logger.error(error.localizedDescription, component: "AudioProcessor")
            fputs("DEBUG: Failed to create export session\n", stderr)
            completion(.failure(error))
            return
        }
        fputs("DEBUG: AVAssetExportSession created successfully\n", stderr)
        
        fputs("DEBUG: About to set outputURL and outputFileType\n", stderr)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        fputs("DEBUG: outputURL and outputFileType set\n", stderr)
        
        fputs("DEBUG: About to get audio track and create audio mix\n", stderr)
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            fputs("DEBUG: Audio track found, about to create audio mix\n", stderr)
            exportSession.audioMix = createAudioMix(for: audioTrack)
            fputs("DEBUG: Audio mix created\n", stderr)
        } else {
            fputs("DEBUG: No audio track found\n", stderr)
        }
        
        fputs("DEBUG: About to create progress timer\n", stderr)
        var lastProgress: Double = 0.2
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let exportProgress = Double(exportSession.progress)
            let adjustedProgress = 0.2 + (exportProgress * 0.7)
            
            if adjustedProgress > lastProgress {
                lastProgress = adjustedProgress
                // TEMP DEBUG: Bypass reportProgress call
                // self?.reportProgress(adjustedProgress, phase: .extracting, callback: progressCallback)
            }
        }
        fputs("DEBUG: Progress timer created\n", stderr)
        
        fputs("DEBUG: About to call exportSession.exportAsynchronously\n", stderr)
        exportSession.exportAsynchronously { [weak self] in
            self?.handleExportCompletion(exportSession: exportSession, asset: asset, outputURL: outputURL, progressTimer: progressTimer, completion: completion)
        }
    }
    
    private func handleExportCompletion(exportSession: AVAssetExportSession, asset: AVAsset, outputURL: URL, progressTimer: Timer, completion: @escaping (Result<AudioFormat, VoxError>) -> Void) {
        fputs("DEBUG: exportAsynchronously callback called\n", stderr)
        fputs("DEBUG: Export session status: \(exportSession.status.rawValue)\n", stderr)
        progressTimer.invalidate()
        
        // TEMP DEBUG: Process status directly without DispatchQueue.main.async
        fputs("DEBUG: Processing export status directly\n", stderr)
        if exportSession.status == .failed {
            fputs("DEBUG: Export failed - checking error\n", stderr)
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            fputs("DEBUG: Export error: \(errorMsg)\n", stderr)
            let error = VoxError.audioExtractionFailed("Export failed: \(errorMsg)")
            fputs("DEBUG: About to call completion(.failure(error)) for failed export\n", stderr)
            completion(.failure(error))
            return
        } else if exportSession.status == .completed {
            fputs("DEBUG: Export completed successfully - processing result\n", stderr)
            
            fputs("DEBUG: About to extract audio format\n", stderr)
            if let audioFormat = self.extractAudioFormat(from: asset, outputPath: outputURL.path) {
                fputs("DEBUG: Audio format extracted successfully\n", stderr)
                fputs("DEBUG: Calling completion(.success(audioFormat))\n", stderr)
                completion(.success(audioFormat))
                return
            } else {
                fputs("DEBUG: Failed to extract audio format\n", stderr)
                let error = VoxError.audioFormatValidationFailed("Failed to extract audio format")
                completion(.failure(error))
                return
            }
        }
        
        handleExportFallback(exportSession: exportSession, asset: asset, outputURL: outputURL, completion: completion)
    }
    
    private func handleExportFallback(exportSession: AVAssetExportSession, asset: AVAsset, outputURL: URL, completion: @escaping (Result<AudioFormat, VoxError>) -> Void) {
        DispatchQueue.main.async {
            fputs("DEBUG: In DispatchQueue.main.async, checking export status\n", stderr)
            switch exportSession.status {
            case .completed:
                fputs("DEBUG: Export status is .completed\n", stderr)
                // TEMP DEBUG: Bypass reportProgress and Logger calls
                // self?.reportProgress(0.9, phase: .validating, callback: progressCallback)
                // self?.logger.info("AVFoundation export completed", component: "AudioProcessor")
                fputs("DEBUG: About to extract audio format\n", stderr)
                
                if let audioFormat = self.extractAudioFormat(from: asset, outputPath: outputURL.path) {
                    // Check if the format validation failed
                    if !audioFormat.isValid {
                        let validationError = audioFormat.validationError ?? "Unknown validation error"
                        let error = VoxError.audioFormatValidationFailed(validationError)
                        self.logger.error(error.localizedDescription, component: "AudioProcessor")
                        completion(.failure(error))
                        return
                    }
                    
                    // Check compatibility for transcription
                    if !audioFormat.isCompatible {
                        let error = VoxError.incompatibleAudioProperties("Audio format not compatible with transcription engines: \(audioFormat.description)")
                        self.logger.warn(error.localizedDescription, component: "AudioProcessor")
                        // Don't fail completely, but log the warning
                    }
                    
                    completion(.success(audioFormat))
                } else {
                    let error = VoxError.audioExtractionFailed("Failed to extract audio format information")
                    self.logger.error(error.localizedDescription, component: "AudioProcessor")
                    completion(.failure(error))
                }
                
            case .failed:
                fputs("DEBUG: Export status is .failed\n", stderr)
                let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
                fputs("DEBUG: Export error: \(errorMsg)\n", stderr)
                let error = VoxError.audioExtractionFailed("Export failed: \(errorMsg)")
                // TEMP DEBUG: Bypass Logger call
                // self?.logger.error(error.localizedDescription, component: "AudioProcessor")
                fputs("DEBUG: About to call completion(.failure(error))\n", stderr)
                completion(.failure(error))
                
            case .cancelled:
                let error = VoxError.audioExtractionFailed("Export was cancelled")
                self.logger.error(error.localizedDescription, component: "AudioProcessor")
                completion(.failure(error))
                
            default:
                let error = VoxError.audioExtractionFailed("Export failed with status: \(exportSession.status.rawValue)")
                self.logger.error(error.localizedDescription, component: "AudioProcessor")
                completion(.failure(error))
            }
        }
    }
    
    private func isValidMP4File(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let pathExtension = url.pathExtension.lowercased()
        let validExtensions = ["mp4", "m4v", "mov"]
        
        // Check extension first to avoid creating AVAsset for obviously invalid files
        guard validExtensions.contains(pathExtension) else {
            // TEMP DEBUG: Bypass Logger call
            // logger.debug("File validation failed - Invalid extension: \(pathExtension)", 
            //            component: "AudioProcessor")
            fputs("DEBUG: File validation failed - Invalid extension: \(pathExtension)\n", stderr)
            return false
        }
        
        fputs("DEBUG: About to create AVAsset\n", stderr)
        let asset = AVAsset(url: url)
        fputs("DEBUG: AVAsset created, about to check video tracks\n", stderr)
        let hasVideoTrack = !asset.tracks(withMediaType: .video).isEmpty
        fputs("DEBUG: Video track check completed, about to check audio tracks\n", stderr)
        let hasAudioTrack = !asset.tracks(withMediaType: .audio).isEmpty
        fputs("DEBUG: Audio track check completed\n", stderr)
        
        // TEMP DEBUG: Bypass Logger call
        // logger.debug("File validation - Extension: valid, Video: \(hasVideoTrack), Audio: \(hasAudioTrack)", 
        //            component: "AudioProcessor")
        fputs("DEBUG: File validation - Extension: valid, Video: \(hasVideoTrack), Audio: \(hasAudioTrack)\n", stderr)
        
        fputs("DEBUG: About to return from isValidMP4File\n", stderr)
        return hasVideoTrack && hasAudioTrack
    }
    
    private func createAudioMix(for audioTrack: AVAssetTrack) -> AVAudioMix {
        let audioMix = AVMutableAudioMix()
        let audioMixInputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
        
        audioMixInputParameters.setVolume(1.0, at: .zero)
        audioMix.inputParameters = [audioMixInputParameters]
        
        return audioMix
    }
    
    private func extractAudioFormat(from asset: AVAsset, outputPath: String? = nil) -> AudioFormat? {
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            return nil
        }
        
        let formatDescriptions = audioTrack.formatDescriptions
        guard let formatDescription = formatDescriptions.first else {
            return nil
        }
        
        // AVAssetTrack.formatDescriptions contains CMFormatDescription objects
        // swiftlint:disable:next force_cast
        let cmFormatDescription = formatDescription as! CMFormatDescription
        
        guard CMFormatDescriptionGetMediaType(cmFormatDescription) == kCMMediaType_Audio,
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(cmFormatDescription) else {
            return nil
        }
        
        let sampleRate = Int(basicDescription.pointee.mSampleRate)
        let channels = Int(basicDescription.pointee.mChannelsPerFrame)
        let bitRate = Int(audioTrack.estimatedDataRate)
        let duration = CMTimeGetSeconds(asset.duration)
        let codec = "m4a"
        
        // Calculate file size if possible
        let fileSize = calculateFileSize(for: asset, outputPath: outputPath)
        
        // Validate the audio format
        let validation = AudioFormatValidator.validate(
            codec: codec,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate > 0 ? bitRate : nil
        )
        
        return AudioFormat(
            codec: codec,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate > 0 ? bitRate : nil,
            duration: duration,
            fileSize: fileSize,
            isValid: validation.isValid,
            validationError: validation.error
        )
    }
    
    private func calculateFileSize(for asset: AVAsset, outputPath: String?) -> UInt64? {
        // Try to get file size from output path first
        if let outputPath = outputPath {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: outputPath)
                return attributes[.size] as? UInt64
            } catch {
                logger.debug("Could not get file size from output path: \(error)", component: "AudioProcessor")
            }
        }
        
        // Estimate file size based on bitrate and duration if available
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else { return nil }
        
        let bitRate = audioTrack.estimatedDataRate
        let duration = CMTimeGetSeconds(asset.duration)
        
        if bitRate > 0 && duration > 0 {
            // Estimate: (bitrate in bits/sec * duration in seconds) / 8 = bytes
            return UInt64((Double(bitRate) * duration) / 8.0)
        }
        
        return nil
    }
    
    func cleanupTemporaryFiles(for audioFile: AudioFile) {
        if let tempPath = audioFile.temporaryPath {
            let tempURL = URL(fileURLWithPath: tempPath)
            _ = tempFileManager.cleanupFile(at: tempURL)
        }
    }
    
    private func reportProgress(_ progress: Double, phase: ProcessingPhase, callback: ProgressCallback?) {
        guard let startTime = processingStartTime else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let processingSpeed = elapsedTime > 0 ? progress / elapsedTime : nil
        
        let progressReport = TranscriptionProgress(
            progress: progress,
            status: phase.statusMessage,
            phase: phase,
            startTime: startTime,
            processingSpeed: processingSpeed
        )
        
        callback?(progressReport)
    }
}
