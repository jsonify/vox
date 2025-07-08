import ArgumentParser
import Foundation

// Global debug flag accessible throughout the application
var globalDebugEnabled = false

// Debug utility function
func debugPrint(_ message: String) {
    if globalDebugEnabled {
        fputs("DEBUG: \(message)\n", stderr)
    }
}

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct Vox: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vox",
        abstract: "Extract audio from MP4 videos and transcribe to text using Apple's native speech recognition",
        usage: """
        vox <input-file> [options]
        
        Examples:
          vox video.mp4                              # Basic transcription to stdout
          vox video.mp4 -o transcript.txt            # Save to file
          vox video.mp4 --format srt                 # Generate SRT subtitles
          vox video.mp4 --timestamps --verbose       # Show timestamps and details
          vox presentation.mp4 --language en-US      # Specify language
          vox lecture.mp4 --fallback-api openai      # Use OpenAI as fallback
        """,
        discussion: """
        Vox prioritizes privacy by using Apple's native speech recognition when available,
        falling back to cloud APIs only when specified or when native recognition fails.
        
        Supported output formats: txt (default), srt, json
        Supported languages: en-US, en-GB, es-ES, fr-FR, de-DE, and more
        
        For more information, visit: https://github.com/jsonify/vox
        """,
        version: "1.0.0"
    )

    @Argument(help: "Path to MP4 video file to transcribe")
    var inputFile: String?

    @Option(name: [.short, .long], help: "Save transcription to file (default: output to stdout)")
    var output: String?

    @Option(name: [.short, .long], help: "Output format: txt (plain text), srt (subtitles), json (structured data)")
    var format: OutputFormat = .txt

    @Option(name: [.short, .long], help: "Language code for transcription (e.g., en-US, es-ES, fr-FR)")
    var language: String?

    @Option(help: "Cloud API to use when native transcription fails: openai, revai")
    var fallbackApi: FallbackAPI?

    @Option(help: "API key for fallback cloud service (or set OPENAI_API_KEY/REVAI_API_KEY env var)")
    var apiKey: String?

    @Flag(name: [.short, .long], help: "Show detailed progress and processing information")
    var verbose = false

    @Flag(help: "Show debug output for troubleshooting")
    var debug = false

    @Flag(help: "Skip native transcription and use cloud API directly")
    var forceCloud = false

    @Flag(help: "Include timestamps in output (shows when each word/phrase was spoken)")
    var timestamps = false
  
    @Flag(help: "Include speaker identification in output (when available)")
    var speakers = false

    @Flag(help: "Include confidence scores showing transcription accuracy")
    var confidence = false

    @Flag(help: "Use detailed text format with comprehensive metadata")
    var detailed = false

    @Option(help: "Seconds of silence to create paragraph breaks (default: 2.0)")
    var paragraphBreak: Double = 2.0

    @Option(help: "Maximum line width for text wrapping (default: 80)")
    var lineWidth: Int = 80

    func run() throws {
        // Check if input file is provided
        guard let inputFile = inputFile else {
            throw VoxError.missingInputFile
        }
        
        try validateInputs(inputFile: inputFile)
        
        // Set global debug flag
        globalDebugEnabled = debug
        
        configureLogging()
        displayStartupInfo(inputFile: inputFile)
        
        // Run async code in a blocking manner - this is safe at the top level
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<Void>()
        
        Task {
            do {
                try await processAudioFile(inputFile: inputFile)
                resultBox.setValue(())
            } catch {
                resultBox.setError(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        try resultBox.getResult()
    }

    private func validateInputs(inputFile: String) throws {
        // Check if input file exists
        guard FileManager.default.fileExists(atPath: inputFile) else {
            throw VoxError.invalidInputFile(inputFile)
        }
        
        // Check if input file is readable
        guard FileManager.default.isReadableFile(atPath: inputFile) else {
            throw VoxError.permissionDenied(inputFile)
        }
        
        // Check file extension
        let fileExtension = URL(fileURLWithPath: inputFile).pathExtension.lowercased()
        let supportedExtensions = ["mp4", "m4v", "mov"]
        guard supportedExtensions.contains(fileExtension) else {
            throw VoxError.unsupportedFormat(fileExtension)
        }
        
        // Check if output directory exists and is writable (if output is specified)
        if let outputPath = output {
            let outputURL = URL(fileURLWithPath: outputPath)
            let outputDir = outputURL.deletingLastPathComponent()
            
            if !FileManager.default.fileExists(atPath: outputDir.path) {
                throw VoxError.invalidOutputPath("Directory does not exist: \(outputDir.path)")
            }
            
            if !FileManager.default.isWritableFile(atPath: outputDir.path) {
                throw VoxError.permissionDenied(outputDir.path)
            }
        }
        
        // Check if API key is required but missing
        if forceCloud && fallbackApi != nil && apiKey == nil {
            let envKey = fallbackApi == .openai ? "OPENAI_API_KEY" : "REVAI_API_KEY"
            if ProcessInfo.processInfo.environment[envKey] == nil {
                throw VoxError.apiKeyMissing(fallbackApi?.rawValue ?? "cloud service")
            }
        }
    }

    private func configureLogging() {
        Logger.shared.configure(verbose: verbose)
        
        // Logging configuration is complete - startup info will be displayed separately
    }

    private func displayStartupInfo(inputFile: String) {
        if !verbose {
            print("🎤 Vox - Transcribing \(inputFile)...")
        }
        
        if verbose {
            Logger.shared.info("🎤 Vox - Starting transcription", component: "CLI")
            Logger.shared.info("Input: \(inputFile)", component: "CLI")
            Logger.shared.info("Output: \(output ?? "stdout")", component: "CLI")
            Logger.shared.info("Format: \(format)", component: "CLI")
            
            if let language = language {
                Logger.shared.info("Language: \(language)", component: "CLI")
            }
            
            if forceCloud {
                Logger.shared.info("Mode: Cloud transcription (forced)", component: "CLI")
            } else {
                Logger.shared.info("Mode: Native transcription with cloud fallback", component: "CLI")
            }
            
            if timestamps {
                Logger.shared.info("Including timestamps", component: "CLI")
            }
        }
    }

    private func processAudioFile(inputFile: String) async throws {
        let audioFile = try await extractAudio(inputFile: inputFile)
        let transcriptionResult = try await transcribeAudio(audioFile)
        
        displayResults(transcriptionResult)
        saveOutput(transcriptionResult)
        cleanup(audioFile)

        displayCompletionMessage(transcriptionResult)
    }

    private func extractAudio(inputFile: String) async throws -> AudioFile {
        let audioProcessor = AudioProcessor()
        let progressDisplay = ProgressDisplayManager(verbose: verbose)

        if verbose {
            Logger.shared.info("🎵 Extracting audio from: \(inputFile)", component: "CLI")
        }

        return try await withCheckedThrowingContinuation { continuation in
            audioProcessor.extractAudio(
                from: inputFile,
                progressCallback: { progressReport in
                    progressDisplay.displayProgress(progressReport)
                },
                completion: { result in
                    switch result {
                    case .success(let audioFile):
                        if self.verbose {
                            Logger.shared.info("✅ Audio extraction completed successfully", component: "CLI")
                        }
                        self.displayAudioExtractionSuccess(audioFile)
                        continuation.resume(returning: audioFile)

                    case .failure(let error):
                        Logger.shared.error("❌ Audio extraction failed: \(error.localizedDescription)", component: "CLI")
                        continuation.resume(throwing: error)
                    }
                }
            )
        }
    }

    private func displayAudioExtractionSuccess(_ audioFile: AudioFile) {
        if verbose {
            Logger.shared.info("✅ Audio extracted successfully", component: "CLI")
            Logger.shared.info("  Format: \(audioFile.format.codec)", component: "CLI")
            Logger.shared.info("  Sample Rate: \(audioFile.format.sampleRate) Hz", component: "CLI")
            Logger.shared.info("  Channels: \(audioFile.format.channels)", component: "CLI")
            Logger.shared.info("  Duration: \(String(format: "%.2f", audioFile.format.duration)) seconds", component: "CLI")

            if let bitRate = audioFile.format.bitRate {
                Logger.shared.info("  Bit Rate: \(bitRate) bps", component: "CLI")
            }

            if let tempPath = audioFile.temporaryPath {
                Logger.shared.info("  Temporary file: \(tempPath)", component: "CLI")
            }
        }
    }

    private func transcribeAudio(_ audioFile: AudioFile) async throws -> TranscriptionResult {
        let transcriptionManager = TranscriptionManager(
            forceCloud: forceCloud,
            verbose: verbose,
            language: language,
            fallbackAPI: fallbackApi,
            apiKey: apiKey,
            includeTimestamps: timestamps
        )
        
        let progressDisplay = ProgressDisplayManager(verbose: verbose)

        if verbose {
            Logger.shared.info("🗣️ Starting transcription...", component: "CLI")
        }

        return try await transcriptionManager.transcribeAudio(
            audioFile: audioFile,
            progressCallback: { progressReport in
                progressDisplay.displayProgress(progressReport)
            }
        )
    }

    private func displayResults(_ result: TranscriptionResult) {
        let displayManager = ResultDisplayManager(forceCloud: forceCloud, timestamps: timestamps)
        displayManager.displayTranscriptionResult(result)
    }

    private func saveOutput(_ result: TranscriptionResult) {
        guard let outputPath = output else { return }

        do {
            let outputWriter = OutputWriter()

            // Configure formatting options based on CLI flags
            if format == .txt {
                let textOptions = TextFormattingOptions(
                    includeTimestamps: timestamps,
                    includeSpeakerIDs: speakers,
                    includeConfidenceScores: confidence,
                    paragraphBreakThreshold: paragraphBreak,
                    sentenceBreakThreshold: 0.8,
                    timestampFormat: .hms,
                    confidenceThreshold: 0.7,
                    lineWidth: lineWidth
                )

                // Write with validation using OutputWriter
                let successConfirmation = try outputWriter.writeTranscriptionResult(
                    result, 
                    to: outputPath, 
                    format: format, 
                    textOptions: textOptions
                )
                
                displaySuccessConfirmation(successConfirmation)
            } else {
                // Use OutputWriter for SRT and JSON with validation
                let successConfirmation = try outputWriter.writeTranscriptionResult(
                    result, 
                    to: outputPath, 
                    format: format
                )
                
                displaySuccessConfirmation(successConfirmation)
            }
        } catch {
            Logger.shared.error("Failed to save output: \(error.localizedDescription)", component: "CLI")
            Logger.shared.error("❌ Failed to save output: \(error.localizedDescription)", component: "CLI")
        }
    }

    private func displaySuccessConfirmation(_ confirmation: SuccessConfirmation) {
        // Display success message
        Logger.shared.info("✓ \(confirmation.message)", component: "CLI")
        
        // Display validation status if verbose
        if verbose {
            let report = confirmation.validationReport
            Logger.shared.info("  Validation Status: \(report.overallStatus.rawValue)", component: "CLI")
            Logger.shared.info("  File Size: \(confirmation.fileSize) bytes", component: "CLI")
            Logger.shared.info("  Processing Time: \(String(format: "%.3f", confirmation.processingTime))s", component: "CLI")
            Logger.shared.info("  Validation Time: \(String(format: "%.3f", report.validationTime))s", component: "CLI")
            
            // Display any validation issues
            if !report.formatValidation.issues.isEmpty {
                Logger.shared.warn("  Format Issues: \(report.formatValidation.issues.joined(separator: ", "))", 
                                   component: "CLI")
            }
            if !report.integrityValidation.issues.isEmpty {
                Logger.shared.warn("  Integrity Issues: \(report.integrityValidation.issues.joined(separator: ", "))", 
                                   component: "CLI")
            }
            if !report.encodingValidation.issues.isEmpty {
                Logger.shared.warn("  Encoding Issues: \(report.encodingValidation.issues.joined(separator: ", "))", 
                                   component: "CLI")
            }
        }
    }

    private func cleanup(_ audioFile: AudioFile) {
        let audioProcessor = AudioProcessor()
        audioProcessor.cleanupTemporaryFiles(for: audioFile)
    }
    
    private func displayCompletionMessage(_ result: TranscriptionResult) {
        if verbose {
            Logger.shared.info("✅ Transcription completed successfully!", component: "CLI")
            Logger.shared.info("  Duration: \(String(format: "%.2f", result.duration)) seconds", component: "CLI")
            Logger.shared.info("  Words: ~\(result.text.split(separator: " ").count)", component: "CLI")
            Logger.shared.info("  Processing time: \(String(format: "%.2f", result.processingTime)) seconds", component: "CLI")
            Logger.shared.info("  Engine: \(result.engine.rawValue)", component: "CLI")
            
            if let output = output {
                Logger.shared.info("  Output saved to: \(output)", component: "CLI")
            }
        } else {
            if let output = output {
                print("✅ Transcription complete! Output saved to: \(output)")
            } else {
                print("✅ Transcription complete!")
            }
        }
    }
}
