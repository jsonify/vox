import Foundation
import AVFoundation

class AudioProcessor {
    
    typealias ProgressCallback = (Double) -> Void
    typealias CompletionCallback = (Result<AudioFile, VoxError>) -> Void
    
    private let logger = Logger.shared
    private let ffmpegProcessor = FFmpegProcessor()
    private let tempFileManager = TempFileManager.shared
    
    func extractAudio(from inputPath: String, 
                     progressCallback: ProgressCallback? = nil,
                     completion: @escaping CompletionCallback) {
        
        logger.info("Starting audio extraction from: \(inputPath)", component: "AudioProcessor")
        
        guard FileManager.default.fileExists(atPath: inputPath) else {
            let error = VoxError.invalidInputFile("File does not exist: \(inputPath)")
            logger.error(error.localizedDescription, component: "AudioProcessor")
            completion(.failure(error))
            return
        }
        
        guard isValidMP4File(path: inputPath) else {
            let error = VoxError.unsupportedFormat("Not a valid MP4 file: \(inputPath)")
            logger.error(error.localizedDescription, component: "AudioProcessor")
            completion(.failure(error))
            return
        }
        
        let inputURL = URL(fileURLWithPath: inputPath)
        
        guard let tempOutputURL = tempFileManager.createTemporaryAudioFile() else {
            let error = VoxError.audioExtractionFailed("Failed to create temporary file")
            logger.error(error.localizedDescription, component: "AudioProcessor")
            completion(.failure(error))
            return
        }
        
        extractAudioUsingAVFoundation(from: inputURL, 
                                    to: tempOutputURL, 
                                    progressCallback: progressCallback) { [weak self] result in
            switch result {
            case .success(let audioFormat):
                let audioFile = AudioFile(
                    path: inputPath,
                    format: audioFormat,
                    temporaryPath: tempOutputURL.path
                )
                self?.logger.info("Audio extraction completed successfully", component: "AudioProcessor")
                completion(.success(audioFile))
                
            case .failure(let error):
                _ = self?.tempFileManager.cleanupFile(at: tempOutputURL)
                self?.logger.warn("AVFoundation extraction failed, attempting ffmpeg fallback: \(error.localizedDescription)", component: "AudioProcessor")
                
                // Try ffmpeg fallback
                self?.ffmpegProcessor.extractAudio(from: inputPath, progressCallback: progressCallback) { fallbackResult in
                    switch fallbackResult {
                    case .success(let audioFile):
                        self?.logger.info("FFmpeg fallback extraction succeeded", component: "AudioProcessor")
                        completion(.success(audioFile))
                    case .failure(_):
                        self?.logger.error("Both AVFoundation and ffmpeg extraction failed", component: "AudioProcessor")
                        // Return the original AVFoundation error as it's the primary method
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    private func extractAudioUsingAVFoundation(from inputURL: URL,
                                             to outputURL: URL,
                                             progressCallback: ProgressCallback?,
                                             completion: @escaping (Result<AudioFormat, VoxError>) -> Void) {
        
        let asset = AVAsset(url: inputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            let error = VoxError.audioExtractionFailed("Failed to create export session")
            logger.error(error.localizedDescription, component: "AudioProcessor")
            completion(.failure(error))
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            exportSession.audioMix = createAudioMix(for: audioTrack)
        }
        
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let progress = Double(exportSession.progress)
            progressCallback?(progress)
        }
        
        exportSession.exportAsynchronously { [weak self] in
            progressTimer.invalidate()
            
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    self?.logger.info("AVFoundation export completed", component: "AudioProcessor")
                    
                    if let audioFormat = self?.extractAudioFormat(from: asset, outputPath: outputURL.path) {
                        // Check if the format validation failed
                        if !audioFormat.isValid {
                            let validationError = audioFormat.validationError ?? "Unknown validation error"
                            let error = VoxError.audioFormatValidationFailed(validationError)
                            self?.logger.error(error.localizedDescription, component: "AudioProcessor")
                            completion(.failure(error))
                            return
                        }
                        
                        // Check compatibility for transcription
                        if !audioFormat.isCompatible {
                            let error = VoxError.incompatibleAudioProperties("Audio format not compatible with transcription engines: \(audioFormat.description)")
                            self?.logger.warn(error.localizedDescription, component: "AudioProcessor")
                            // Don't fail completely, but log the warning
                        }
                        
                        completion(.success(audioFormat))
                    } else {
                        let error = VoxError.audioExtractionFailed("Failed to extract audio format information")
                        self?.logger.error(error.localizedDescription, component: "AudioProcessor")
                        completion(.failure(error))
                    }
                    
                case .failed:
                    let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
                    let error = VoxError.audioExtractionFailed("Export failed: \(errorMsg)")
                    self?.logger.error(error.localizedDescription, component: "AudioProcessor")
                    completion(.failure(error))
                    
                case .cancelled:
                    let error = VoxError.audioExtractionFailed("Export was cancelled")
                    self?.logger.error(error.localizedDescription, component: "AudioProcessor")
                    completion(.failure(error))
                    
                default:
                    let error = VoxError.audioExtractionFailed("Export failed with status: \(exportSession.status.rawValue)")
                    self?.logger.error(error.localizedDescription, component: "AudioProcessor")
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func isValidMP4File(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let pathExtension = url.pathExtension.lowercased()
        let validExtensions = ["mp4", "m4v", "mov"]
        
        // Check extension first to avoid creating AVAsset for obviously invalid files
        guard validExtensions.contains(pathExtension) else {
            logger.debug("File validation failed - Invalid extension: \(pathExtension)", 
                        component: "AudioProcessor")
            return false
        }
        
        let asset = AVAsset(url: url)
        let hasVideoTrack = !asset.tracks(withMediaType: .video).isEmpty
        let hasAudioTrack = !asset.tracks(withMediaType: .audio).isEmpty
        
        logger.debug("File validation - Extension: valid, Video: \(hasVideoTrack), Audio: \(hasAudioTrack)", 
                    component: "AudioProcessor")
        
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
}