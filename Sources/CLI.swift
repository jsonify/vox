import ArgumentParser
import Foundation

struct Vox: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vox",
        abstract: "Audio transcription CLI for MP4 video files",
        version: "1.0.0"
    )
    
    @Argument(help: "Input MP4 video file path")
    var inputFile: String
    
    @Option(name: [.short, .long], help: "Output file path")
    var output: String?
    
    @Option(name: [.short, .long], help: "Output format: txt, srt, json")
    var format: OutputFormat = .txt
    
    @Option(name: [.short, .long], help: "Language code (e.g., en-US, es-ES)")
    var language: String?
    
    @Option(help: "Fallback API: openai, revai")
    var fallbackApi: FallbackAPI?
    
    @Option(help: "API key for fallback service")
    var apiKey: String?
    
    @Flag(name: [.short, .long], help: "Enable verbose output")
    var verbose = false
    
    @Flag(help: "Force cloud transcription (skip native)")
    var forceCloud = false
    
    @Flag(help: "Include timestamps in output")
    var timestamps = false
    
    @Flag(help: "Include speaker IDs in output")
    var speakers = false
    
    @Flag(help: "Include confidence scores in output")
    var confidence = false
    
    @Flag(help: "Use detailed text format with metadata")
    var detailed = false
    
    @Option(help: "Paragraph break threshold in seconds (default: 2.0)")
    var paragraphBreak: Double = 2.0
    
    @Option(help: "Line width for text wrapping (default: 80)")
    var lineWidth: Int = 80
    
    func run() throws {
        // TEMP DEBUG: Progressive debug to find crash point
        fputs("DEBUG: Entered run() method\n", stderr)
        fflush(stderr)
        Logger.shared.debug("Entered run() method", component: "CLI")
        
        fputs("DEBUG: About to call configureLogging()\n", stderr)
        Logger.shared.debug("About to call configureLogging()", component: "CLI")
        configureLogging()
        fputs("DEBUG: configureLogging() completed\n", stderr)
        Logger.shared.debug("configureLogging() completed", component: "CLI")
        
        fputs("DEBUG: About to call displayStartupInfo()\n", stderr)
        Logger.shared.debug("About to call displayStartupInfo()", component: "CLI")
        displayStartupInfo()
        fputs("DEBUG: displayStartupInfo() completed\n", stderr)
        Logger.shared.debug("displayStartupInfo() completed", component: "CLI")
        
        fputs("DEBUG: About to call processAudioFile()\n", stderr)
        Logger.shared.debug("About to call processAudioFile()", component: "CLI")
        try processAudioFile()
        fputs("DEBUG: processAudioFile() completed\n", stderr)
        Logger.shared.debug("processAudioFile() completed", component: "CLI")
    }
    
    private func configureLogging() {
        fputs("DEBUG: In configureLogging(), about to access Logger.shared\n", stderr)
        Logger.shared.debug("In configureLogging(), about to access Logger.shared", component: "CLI")
        Logger.shared.configure(verbose: verbose)
        fputs("DEBUG: Logger.shared.configure() completed\n", stderr)
        Logger.shared.debug("Logger.shared.configure() completed", component: "CLI")
        
        fputs("DEBUG: About to call Logger.shared.info\n", stderr)
        // TEMP DEBUG: Bypass Logger calls to isolate the issue
        // Logger.shared.info("Vox CLI - Audio transcription tool", component: "CLI")
        fputs("DEBUG: Logger.shared.info bypassed\n", stderr)
        // Logger.shared.debug("Verbose logging enabled", component: "CLI")
        fputs("DEBUG: Logger.shared.debug bypassed\n", stderr)
        
        // TEMP DEBUG: Bypass all Logger calls to isolate the issue
        fputs("DEBUG: Bypassing all remaining Logger calls in configureLogging\n", stderr)
        /*
        Logger.shared.info("Input file: \(inputFile)", component: "CLI")
        Logger.shared.info("Output format: \(format)", component: "CLI")
        
        if let output = output {
            Logger.shared.info("Output file: \(output)", component: "CLI")
        }
        
        if let language = language {
            Logger.shared.info("Language: \(language)", component: "CLI")
        }
        
        if let fallbackApi = fallbackApi {
            Logger.shared.info("Fallback API: \(fallbackApi)", component: "CLI")
        }
        
        if forceCloud {
            Logger.shared.info("Using cloud transcription (forced)", component: "CLI")
        } else {
            Logger.shared.info("Using native transcription with fallback", component: "CLI")
        }
        
        if timestamps {
            Logger.shared.info("Timestamps enabled", component: "CLI")
        }
        */
    }
    
    private func displayStartupInfo() {
        Logger.shared.info("Vox CLI - Audio transcription tool", component: "CLI")
        Logger.shared.info("Input file: \(inputFile)", component: "CLI")
        Logger.shared.info("Output format: \(format)", component: "CLI")
        
        if let output = output {
            Logger.shared.info("Output file: \(output)", component: "CLI")
        }
        
        if forceCloud {
            Logger.shared.info("Using cloud transcription", component: "CLI")
        } else {
            Logger.shared.info("Using native transcription with fallback", component: "CLI")
        }
    }
    
    private func processAudioFile() throws {
        fputs("DEBUG: In processAudioFile(), about to call extractAudio()\n", stderr)
        let audioFile = try extractAudio()
        fputs("DEBUG: extractAudio() completed successfully\n", stderr)
        
        fputs("DEBUG: About to call transcribeAudio()\n", stderr)
        let transcriptionResult = try transcribeAudio(audioFile)
        fputs("DEBUG: transcribeAudio() completed successfully\n", stderr)
        displayResults(transcriptionResult)
        saveOutput(transcriptionResult)
        cleanup(audioFile)
        
        Logger.shared.info("Audio processing completed successfully!", component: "CLI")
    }
    
    private func extractAudio() throws -> AudioFile {
        fputs("DEBUG: In extractAudio(), about to create AudioProcessor\n", stderr)
        let audioProcessor = AudioProcessor()
        fputs("DEBUG: AudioProcessor created successfully\n", stderr)
        
        fputs("DEBUG: About to create ProgressDisplayManager\n", stderr)
        let progressDisplay = ProgressDisplayManager(verbose: verbose)
        fputs("DEBUG: ProgressDisplayManager created successfully\n", stderr)
        
        let semaphore = DispatchSemaphore(value: 0)
        var processingError: Error?
        var extractedAudioFile: AudioFile?
        
        fputs("DEBUG: About to print 'Extracting audio from...'\n", stderr)
        Logger.shared.info("Extracting audio from: \(inputFile)", component: "CLI")
        fputs("DEBUG: Print completed, about to call audioProcessor.extractAudio\n", stderr)
        
        audioProcessor.extractAudio(
            from: inputFile,
            progressCallback: { progressReport in
                progressDisplay.displayProgress(progressReport)
            },
            completion: { result in
            switch result {
            case .success(let audioFile):
                fputs("DEBUG: CLI extractAudio success callback received\n", stderr)
                // TEMP DEBUG: Bypass Logger call
                // Logger.shared.info("Audio extraction completed successfully", component: "CLI")
                fputs("DEBUG: About to call displayAudioExtractionSuccess\n", stderr)
                self.displayAudioExtractionSuccess(audioFile)
                fputs("DEBUG: displayAudioExtractionSuccess completed\n", stderr)
                extractedAudioFile = audioFile
                fputs("DEBUG: extractedAudioFile set, about to signal semaphore\n", stderr)
                
            case .failure(let error):
                fputs("DEBUG: CLI extractAudio failure callback received\n", stderr)
                // TEMP DEBUG: Bypass Logger call
                // Logger.shared.error("Audio extraction failed: \(error.localizedDescription)", component: "CLI")
                processingError = error
            }
            
            semaphore.signal()
            }
        )
        
        semaphore.wait()
        
        if let error = processingError {
            throw error
        }
        
        guard let audioFile = extractedAudioFile else {
            throw VoxError.processingFailed("Failed to extract audio file")
        }
        
        return audioFile
    }
    
    private func displayAudioExtractionSuccess(_ audioFile: AudioFile) {
        Logger.shared.info("✓ Audio extracted successfully", component: "CLI")
        Logger.shared.info("  - Format: \(audioFile.format.codec)", component: "CLI")
        Logger.shared.info("  - Sample Rate: \(audioFile.format.sampleRate) Hz", component: "CLI")
        Logger.shared.info("  - Channels: \(audioFile.format.channels)", component: "CLI")
        Logger.shared.info("  - Duration: \(String(format: "%.2f", audioFile.format.duration)) seconds", component: "CLI")
        
        if let bitRate = audioFile.format.bitRate {
            Logger.shared.info("  - Bit Rate: \(bitRate) bps", component: "CLI")
        }
        
        if let tempPath = audioFile.temporaryPath {
            Logger.shared.info("  - Temporary file: \(tempPath)", component: "CLI")
        }
    }
    
    private func transcribeAudio(_ audioFile: AudioFile) throws -> TranscriptionResult {
        fputs("DEBUG: In transcribeAudio(), about to create TranscriptionManager\n", stderr)
        let transcriptionManager = TranscriptionManager(
            forceCloud: forceCloud,
            verbose: verbose,
            language: language,
            fallbackAPI: fallbackApi,
            apiKey: apiKey,
            includeTimestamps: timestamps
        )
        fputs("DEBUG: TranscriptionManager created, about to call transcribeAudio\n", stderr)
        
        return try transcriptionManager.transcribeAudio(audioFile: audioFile)
    }
    
    private func displayResults(_ result: TranscriptionResult) {
        let displayManager = ResultDisplayManager(forceCloud: forceCloud, timestamps: timestamps)
        displayManager.displayTranscriptionResult(result)
    }
    
    private func saveOutput(_ result: TranscriptionResult) {
        guard let outputPath = output else { return }
        
        do {
            let formatter = OutputFormatter()
            
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
                
                // Use detailed format if requested
                let content = detailed ? 
                    formatter.formatAsDetailedText(result, options: textOptions) :
                    formatter.formatAsEnhancedText(result, options: textOptions)
                
                try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } else {
                // Use standard formatting for SRT and JSON
                try formatter.saveTranscriptionResult(result, to: outputPath, format: format)
            }
            
            Logger.shared.info("✓ Output saved to: \(outputPath)", component: "CLI")
        } catch {
            Logger.shared.error("Failed to save output: \(error.localizedDescription)", component: "CLI")
            Logger.shared.error("❌ Failed to save output: \(error.localizedDescription)", component: "CLI")
        }
    }
    
    private func cleanup(_ audioFile: AudioFile) {
        let audioProcessor = AudioProcessor()
        audioProcessor.cleanupTemporaryFiles(for: audioFile)
    }
}
