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
    
    func run() throws {
        // TEMP DEBUG: Progressive debug to find crash point
        fputs("DEBUG: Entered run() method\n", stderr)
        fflush(stderr)
        print("DEBUG: Entered run() method")
        
        fputs("DEBUG: About to call configureLogging()\n", stderr)
        print("DEBUG: About to call configureLogging()")
        configureLogging()
        fputs("DEBUG: configureLogging() completed\n", stderr)
        print("DEBUG: configureLogging() completed")
        
        fputs("DEBUG: About to call displayStartupInfo()\n", stderr)
        print("DEBUG: About to call displayStartupInfo()")
        displayStartupInfo()
        fputs("DEBUG: displayStartupInfo() completed\n", stderr)
        print("DEBUG: displayStartupInfo() completed")
        
        fputs("DEBUG: About to call processAudioFile()\n", stderr)
        print("DEBUG: About to call processAudioFile()")
        try processAudioFile()
        fputs("DEBUG: processAudioFile() completed\n", stderr)
        print("DEBUG: processAudioFile() completed")
    }
    
    private func configureLogging() {
        fputs("DEBUG: In configureLogging(), about to access Logger.shared\n", stderr)
        print("DEBUG: In configureLogging(), about to access Logger.shared")
        Logger.shared.configure(verbose: verbose)
        fputs("DEBUG: Logger.shared.configure() completed\n", stderr)
        print("DEBUG: Logger.shared.configure() completed")
        
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
        print("Vox CLI - Audio transcription tool") // swiftlint:disable:this no_print
        print("Input file: \(inputFile)") // swiftlint:disable:this no_print
        print("Output format: \(format)") // swiftlint:disable:this no_print
        
        if let output = output {
            print("Output file: \(output)") // swiftlint:disable:this no_print
        }
        
        if forceCloud {
            print("Using cloud transcription") // swiftlint:disable:this no_print
        } else {
            print("Using native transcription with fallback") // swiftlint:disable:this no_print
        }
    }
    
    private func processAudioFile() throws {
        fputs("DEBUG: In processAudioFile(), about to call extractAudio()\n", stderr)
        let audioFile = try extractAudio()
        fputs("DEBUG: extractAudio() completed successfully\n", stderr)
        
        let transcriptionResult = try transcribeAudio(audioFile)
        displayResults(transcriptionResult)
        saveOutput(transcriptionResult)
        cleanup(audioFile)
        
        print("Audio processing completed successfully!") // swiftlint:disable:this no_print
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
        print("Extracting audio from: \(inputFile)") // swiftlint:disable:this no_print
        fputs("DEBUG: Print completed, about to call audioProcessor.extractAudio\n", stderr)
        
        audioProcessor.extractAudio(from: inputFile,
                                    progressCallback: { progressReport in
                                        progressDisplay.displayProgress(progressReport)
                                    }) { result in
            switch result {
            case .success(let audioFile):
                Logger.shared.info("Audio extraction completed successfully", component: "CLI")
                self.displayAudioExtractionSuccess(audioFile)
                extractedAudioFile = audioFile
                
            case .failure(let error):
                Logger.shared.error("Audio extraction failed: \(error.localizedDescription)", component: "CLI")
                processingError = error
            }
            
            semaphore.signal()
        }
        
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
        print("✓ Audio extracted successfully") // swiftlint:disable:this no_print
        print("  - Format: \(audioFile.format.codec)") // swiftlint:disable:this no_print
        print("  - Sample Rate: \(audioFile.format.sampleRate) Hz") // swiftlint:disable:this no_print
        print("  - Channels: \(audioFile.format.channels)") // swiftlint:disable:this no_print
        print("  - Duration: \(String(format: "%.2f", audioFile.format.duration)) seconds") // swiftlint:disable:this no_print
        
        if let bitRate = audioFile.format.bitRate {
            print("  - Bit Rate: \(bitRate) bps") // swiftlint:disable:this no_print
        }
        
        if let tempPath = audioFile.temporaryPath {
            print("  - Temporary file: \(tempPath)") // swiftlint:disable:this no_print
        }
    }
    
    private func transcribeAudio(_ audioFile: AudioFile) throws -> TranscriptionResult {
        let transcriptionManager = TranscriptionManager(
            forceCloud: forceCloud,
            verbose: verbose,
            language: language,
            fallbackAPI: fallbackApi,
            apiKey: apiKey,
            includeTimestamps: timestamps
        )
        
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
            try formatter.saveTranscriptionResult(result, to: outputPath, format: format)
            print("✓ Output saved to: \(outputPath)") // swiftlint:disable:this no_print
        } catch {
            Logger.shared.error("Failed to save output: \(error.localizedDescription)", component: "CLI")
            print("❌ Failed to save output: \(error.localizedDescription)") // swiftlint:disable:this no_print
        }
    }
    
    private func cleanup(_ audioFile: AudioFile) {
        let audioProcessor = AudioProcessor()
        audioProcessor.cleanupTemporaryFiles(for: audioFile)
    }
}
