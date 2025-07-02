import Foundation

class FFmpegProcessor {
    
    typealias ProgressCallback = (Double) -> Void
    typealias CompletionCallback = (Result<AudioFile, VoxError>) -> Void
    
    private let logger = Logger.shared
    private static let ffmpegPath = "/opt/homebrew/bin/ffmpeg" // Common homebrew path
    private static let alternativePaths = [
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
        "/opt/local/bin/ffmpeg"
    ]
    
    /// Check if ffmpeg is available on the system
    static func isFFmpegAvailable() -> Bool {
        // First check common installation paths
        let allPaths = [ffmpegPath] + alternativePaths
        
        for path in allPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }
        
        // Fallback: try to execute ffmpeg from PATH
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["ffmpeg"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Find the ffmpeg executable path
    private static func findFFmpegPath() -> String? {
        let allPaths = [ffmpegPath] + alternativePaths
        
        for path in allPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Try to find in PATH
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    return output
                }
            }
        } catch {
            // Fall through to return nil
        }
        
        return nil
    }
    
    func extractAudio(from inputPath: String,
                     progressCallback: ProgressCallback? = nil,
                     completion: @escaping CompletionCallback) {
        
        logger.info("Starting ffmpeg audio extraction from: \(inputPath)", component: "FFmpegProcessor")
        
        guard FileManager.default.fileExists(atPath: inputPath) else {
            let error = VoxError.invalidInputFile("File does not exist: \(inputPath)")
            logger.error(error.localizedDescription, component: "FFmpegProcessor")
            completion(.failure(error))
            return
        }
        
        guard Self.isFFmpegAvailable() else {
            let error = VoxError.audioExtractionFailed("ffmpeg is not available on this system")
            logger.error(error.localizedDescription, component: "FFmpegProcessor")
            completion(.failure(error))
            return
        }
        
        guard let ffmpegPath = Self.findFFmpegPath() else {
            let error = VoxError.audioExtractionFailed("Could not locate ffmpeg executable")
            logger.error(error.localizedDescription, component: "FFmpegProcessor")
            completion(.failure(error))
            return
        }
        
        guard let tempOutputURL = createTemporaryAudioFile() else {
            let error = VoxError.audioExtractionFailed("Failed to create temporary file")
            logger.error(error.localizedDescription, component: "FFmpegProcessor")
            completion(.failure(error))
            return
        }
        
        // Extract audio using ffmpeg
        extractAudioUsingFFmpeg(
            ffmpegPath: ffmpegPath,
            inputPath: inputPath,
            outputPath: tempOutputURL.path,
            progressCallback: progressCallback
        ) { [weak self] result in
            switch result {
            case .success(let audioFormat):
                let audioFile = AudioFile(
                    path: inputPath,
                    format: audioFormat,
                    temporaryPath: tempOutputURL.path
                )
                self?.logger.info("FFmpeg audio extraction completed successfully", component: "FFmpegProcessor")
                completion(.success(audioFile))
                
            case .failure(let error):
                self?.cleanupTemporaryFile(at: tempOutputURL)
                completion(.failure(error))
            }
        }
    }
    
    private func extractAudioUsingFFmpeg(
        ffmpegPath: String,
        inputPath: String,
        outputPath: String,
        progressCallback: ProgressCallback?,
        completion: @escaping (Result<AudioFormat, VoxError>) -> Void
    ) {
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.launchPath = ffmpegPath
            
            // FFmpeg arguments for audio extraction
            process.arguments = [
                "-i", inputPath,           // Input file
                "-vn",                     // No video
                "-acodec", "aac",          // AAC codec for compatibility
                "-f", "mp4",               // MP4 container
                "-movflags", "+faststart", // Optimize for streaming
                "-y",                      // Overwrite output file
                outputPath                 // Output file
            ]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            var duration: TimeInterval = 0
            var progressTimer: Timer?
            
            // Parse stderr for progress information
            errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if let output = String(data: data, encoding: .utf8) {
                    // Parse duration from initial output
                    if duration == 0 {
                        duration = self?.parseDuration(from: output) ?? 0
                    }
                    
                    // Parse progress
                    if let progress = self?.parseProgress(from: output, totalDuration: duration) {
                        DispatchQueue.main.async {
                            progressCallback?(progress)
                        }
                    }
                }
            }
            
            do {
                try process.run()
                
                // Start a backup progress timer in case progress parsing fails
                if progressCallback != nil {
                    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        if process.isRunning {
                            // Estimated progress based on file processing (fallback)
                            let elapsed = Date().timeIntervalSince(Date())
                            let estimatedProgress = min(elapsed / max(duration, 60), 0.9) // Cap at 90%
                            DispatchQueue.main.async {
                                progressCallback?(estimatedProgress)
                            }
                        }
                    }
                }
                
                process.waitUntilExit()
                progressTimer?.invalidate()
                
                DispatchQueue.main.async {
                    progressCallback?(1.0) // Complete
                    
                    if process.terminationStatus == 0 {
                        // Extraction successful, now get audio format info
                        self?.getAudioFormat(
                            ffmpegPath: ffmpegPath,
                            filePath: outputPath
                        ) { formatResult in
                            completion(formatResult)
                        }
                    } else {
                        // Get error output
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        
                        let error = VoxError.audioExtractionFailed(
                            "FFmpeg extraction failed (exit code: \(process.terminationStatus)): \(errorOutput)"
                        )
                        self?.logger.error(error.localizedDescription, component: "FFmpegProcessor")
                        completion(.failure(error))
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    let voxError = VoxError.audioExtractionFailed("Failed to start ffmpeg process: \(error.localizedDescription)")
                    self?.logger.error(voxError.localizedDescription, component: "FFmpegProcessor")
                    completion(.failure(voxError))
                }
            }
        }
    }
    
    private func getAudioFormat(
        ffmpegPath: String,
        filePath: String,
        completion: @escaping (Result<AudioFormat, VoxError>) -> Void
    ) {
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.launchPath = ffmpegPath
            
            // Use ffprobe-like functionality built into ffmpeg
            process.arguments = [
                "-i", filePath,
                "-f", "null",
                "-"
            ]
            
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe() // Discard
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: errorData, encoding: .utf8) ?? ""
                
                if let audioFormat = self?.parseAudioFormat(from: output, filePath: filePath) {
                    DispatchQueue.main.async {
                        completion(.success(audioFormat))
                    }
                } else {
                    DispatchQueue.main.async {
                        let error = VoxError.audioExtractionFailed("Failed to parse audio format information")
                        self?.logger.error(error.localizedDescription, component: "FFmpegProcessor")
                        completion(.failure(error))
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    let voxError = VoxError.audioExtractionFailed("Failed to get audio format: \(error.localizedDescription)")
                    self?.logger.error(voxError.localizedDescription, component: "FFmpegProcessor")
                    completion(.failure(voxError))
                }
            }
        }
    }
    
    // MARK: - Parsing Helpers
    
    private func parseDuration(from output: String) -> TimeInterval {
        // Look for duration pattern: Duration: 00:01:23.45
        let durationPattern = #"Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})"#
        
        guard let regex = try? NSRegularExpression(pattern: durationPattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) else {
            return 0
        }
        
        let hours = Double(String(output[Range(match.range(at: 1), in: output)!])) ?? 0
        let minutes = Double(String(output[Range(match.range(at: 2), in: output)!])) ?? 0
        let seconds = Double(String(output[Range(match.range(at: 3), in: output)!])) ?? 0
        let centiseconds = Double(String(output[Range(match.range(at: 4), in: output)!])) ?? 0
        
        return hours * 3600 + minutes * 60 + seconds + centiseconds / 100
    }
    
    private func parseProgress(from output: String, totalDuration: TimeInterval) -> Double? {
        guard totalDuration > 0 else { return nil }
        
        // Look for time pattern: time=00:01:23.45
        let timePattern = #"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})"#
        
        guard let regex = try? NSRegularExpression(pattern: timePattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) else {
            return nil
        }
        
        let hours = Double(String(output[Range(match.range(at: 1), in: output)!])) ?? 0
        let minutes = Double(String(output[Range(match.range(at: 2), in: output)!])) ?? 0
        let seconds = Double(String(output[Range(match.range(at: 3), in: output)!])) ?? 0
        let centiseconds = Double(String(output[Range(match.range(at: 4), in: output)!])) ?? 0
        
        let currentTime = hours * 3600 + minutes * 60 + seconds + centiseconds / 100
        return min(currentTime / totalDuration, 1.0)
    }
    
    private func parseAudioFormat(from output: String, filePath: String) -> AudioFormat? {
        // Parse audio stream info from ffmpeg output
        // Example: Stream #0:1(und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, stereo, fltp, 128 kb/s
        
        let audioPattern = #"Audio: (\w+).*?(\d+) Hz.*?(\w+).*?(\d+) kb/s"#
        
        var codec = "aac"
        var sampleRate = 44100
        var channels = 2
        var bitRate: Int? = nil
        
        if let regex = try? NSRegularExpression(pattern: audioPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            codec = String(output[Range(match.range(at: 1), in: output)!])
            sampleRate = Int(String(output[Range(match.range(at: 2), in: output)!])) ?? 44100
            let channelInfo = String(output[Range(match.range(at: 3), in: output)!])
            let bitRateKbps = Int(String(output[Range(match.range(at: 4), in: output)!])) ?? 128
            
            channels = channelInfo.contains("stereo") ? 2 : 1
            bitRate = bitRateKbps * 1000 // Convert kb/s to b/s
        }
        
        let duration = getDuration(from: output)
        
        // Get actual file size
        let fileSize = getFileSize(for: filePath)
        
        // Validate the audio format
        let validation = AudioFormatValidator.validate(
            codec: codec,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate
        )
        
        return AudioFormat(
            codec: codec,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate,
            duration: duration,
            fileSize: fileSize,
            isValid: validation.isValid,
            validationError: validation.error
        )
    }
    
    private func getFileSize(for filePath: String) -> UInt64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            return attributes[.size] as? UInt64
        } catch {
            logger.debug("Could not get file size for \(filePath): \(error)", component: "FFmpegProcessor")
            return nil
        }
    }
    
    private func getDuration(from output: String) -> TimeInterval {
        return parseDuration(from: output)
    }
    
    // MARK: - File Management
    
    internal func createTemporaryAudioFile() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "vox_ffmpeg_temp_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(fileName)
    }
    
    func cleanupTemporaryFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            logger.debug("Cleaned up temporary file: \(url.path)", component: "FFmpegProcessor")
        } catch {
            logger.warn("Failed to cleanup temporary file: \(error.localizedDescription)", component: "FFmpegProcessor")
        }
    }
    
    func cleanupTemporaryFiles(for audioFile: AudioFile) {
        if let tempPath = audioFile.temporaryPath {
            let tempURL = URL(fileURLWithPath: tempPath)
            cleanupTemporaryFile(at: tempURL)
        }
    }
}