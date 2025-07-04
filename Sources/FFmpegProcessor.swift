import Foundation

class FFmpegProcessor {
    typealias CompletionCallback = (Result<AudioFile, VoxError>) -> Void

    private let logger = Logger.shared
    private var processingStartTime: Date?
    /// Check if ffmpeg is available on the system
    static func isFFmpegAvailable() -> Bool {
        return FFmpegUtilities.isFFmpegAvailable()
    }

    /// Find the ffmpeg executable path
    private static func findFFmpegPath() -> String? {
        return FFmpegUtilities.findFFmpegPath()
    }

    func extractAudio(from inputPath: String,
                      progressCallback: ProgressCallback? = nil,
                      completion: @escaping CompletionCallback) {
        processingStartTime = Date()

        logger.info("Starting ffmpeg audio extraction from: \(inputPath)", component: "FFmpegProcessor")

        // Report initialization phase
        reportProgress(0.0, phase: .initializing, callback: progressCallback)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            let error = VoxError.invalidInputFile("File does not exist: \(inputPath)")
            logger.error(error.localizedDescription, component: "FFmpegProcessor")
            completion(.failure(error))
            return
        }

        // Report analyzing phase
        reportProgress(0.05, phase: .analyzing, callback: progressCallback)

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

        // Report extracting phase
        reportProgress(0.1, phase: .extracting, callback: progressCallback)

        // Extract audio using ffmpeg
        extractAudioUsingFFmpeg(
            ffmpegPath: ffmpegPath,
            inputPath: inputPath,
            outputPath: tempOutputURL.path,
            progressCallback: progressCallback
        ) { [weak self] result in
            switch result {
            case .success(let audioFormat):
                // Report finalizing phase
                self?.reportProgress(0.95, phase: .finalizing, callback: progressCallback)

                let audioFile = AudioFile(
                    path: inputPath,
                    format: audioFormat,
                    temporaryPath: tempOutputURL.path
                )

                // Report completion
                self?.reportProgress(1.0, phase: .complete, callback: progressCallback)

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
            var lastProgress: Double = 0.1

            // Parse stderr for progress information
            errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if let output = String(data: data, encoding: .utf8) {
                    // Parse duration from initial output
                    if duration == 0 {
                        duration = self?.parseDuration(from: output) ?? 0
                    }

                    // Parse progress and map to our range (0.1 to 0.9)
                    if let rawProgress = self?.parseProgress(from: output, totalDuration: duration) {
                        let adjustedProgress = 0.1 + (rawProgress * 0.8)
                        if adjustedProgress > lastProgress {
                            lastProgress = adjustedProgress
                            DispatchQueue.main.async {
                                self?.reportProgress(adjustedProgress, phase: .extracting, callback: progressCallback)
                            }
                        }
                    }
                }
            }

            do {
                try process.run()

                // Start a backup progress timer in case progress parsing fails
                if progressCallback != nil {
                    let processStartTime = Date()
                    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        if process.isRunning {
                            // Estimated progress based on file processing (fallback)
                            let elapsed = Date().timeIntervalSince(processStartTime)
                            let estimatedProgress = min(0.1 + (elapsed / max(duration, 60)) * 0.8, 0.9)
                            if estimatedProgress > lastProgress {
                                lastProgress = estimatedProgress
                                DispatchQueue.main.async {
                                    self?.reportProgress(estimatedProgress, phase: .extracting, callback: progressCallback)
                                }
                            }
                        }
                    }
                }

                process.waitUntilExit()
                progressTimer?.invalidate()

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        // Report validating phase
                        self?.reportProgress(0.9, phase: .validating, callback: progressCallback)

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
        return FFmpegAudioFormatParser.parseDuration(from: output)
    }

    private func parseProgress(from output: String, totalDuration: TimeInterval) -> Double? {
        return FFmpegAudioFormatParser.parseProgress(from: output, totalDuration: totalDuration)
    }

    private func parseAudioFormat(from output: String, filePath: String) -> AudioFormat? {
        return FFmpegAudioFormatParser.parseAudioFormat(from: output, filePath: filePath)
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
