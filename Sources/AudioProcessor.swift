import Foundation
import AVFoundation

class AudioProcessor {
    
    typealias ProgressCallback = (Double) -> Void
    typealias CompletionCallback = (Result<AudioFile, VoxError>) -> Void
    
    private let logger = Logger.shared
    private let ffmpegProcessor = FFmpegProcessor()
    
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
        
        guard let tempOutputURL = createTemporaryAudioFile() else {
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
                self?.cleanupTemporaryFile(at: tempOutputURL)
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
                    
                    if let audioFormat = self?.extractAudioFormat(from: asset) {
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
    
    internal func createTemporaryAudioFile() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "vox_temp_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(fileName)
    }
    
    private func createAudioMix(for audioTrack: AVAssetTrack) -> AVAudioMix {
        let audioMix = AVMutableAudioMix()
        let audioMixInputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
        
        audioMixInputParameters.setVolume(1.0, at: .zero)
        audioMix.inputParameters = [audioMixInputParameters]
        
        return audioMix
    }
    
    private func extractAudioFormat(from asset: AVAsset) -> AudioFormat? {
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
        
        return AudioFormat(
            codec: "m4a",
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate > 0 ? bitRate : nil,
            duration: duration
        )
    }
    
    func cleanupTemporaryFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            logger.debug("Cleaned up temporary file: \(url.path)", component: "AudioProcessor")
        } catch {
            logger.warn("Failed to cleanup temporary file: \(error.localizedDescription)", component: "AudioProcessor")
        }
    }
    
    func cleanupTemporaryFiles(for audioFile: AudioFile) {
        if let tempPath = audioFile.temporaryPath {
            let tempURL = URL(fileURLWithPath: tempPath)
            cleanupTemporaryFile(at: tempURL)
        }
    }
}