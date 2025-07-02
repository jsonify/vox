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
        Logger.shared.configure(verbose: verbose)
        
        Logger.shared.info("Vox CLI - Audio transcription tool", component: "CLI")
        Logger.shared.debug("Verbose logging enabled", component: "CLI")
        
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
        
        // User-facing output (not logging)
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
        
        try processAudioFile()
    }
    
    private func processAudioFile() throws {
        let audioProcessor = AudioProcessor()
        let semaphore = DispatchSemaphore(value: 0)
        var processingError: Error?
        var extractedAudioFile: AudioFile?
        
        print("Extracting audio from: \(inputFile)") // swiftlint:disable:this no_print
        
        audioProcessor.extractAudio(from: inputFile,
                                    progressCallback: { progressReport in
                                        self.displayProgress(progressReport)
                                    }) { result in
            switch result {
            case .success(let audioFile):
                Logger.shared.info("Audio extraction completed successfully", component: "CLI")
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
        
        // Start transcription process
        try transcribeAudio(audioFile: audioFile)
        
        // Cleanup temporary files
        audioProcessor.cleanupTemporaryFiles(for: audioFile)
        
        print("Audio processing completed successfully!") // swiftlint:disable:this no_print
    }
    
    private func transcribeAudio(audioFile: AudioFile) throws {
        print("Starting transcription...") // swiftlint:disable:this no_print
        
        // Determine preferred languages based on user input and system preferences
        let preferredLanguages = buildLanguagePreferences()
        
        Logger.shared.info("Language preferences: \(preferredLanguages.joined(separator: ", "))", component: "CLI")
        
        let semaphore = DispatchSemaphore(value: 0)
        var taskResult: Result<TranscriptionResult, Error>?
        
        Task {
            let result: Result<TranscriptionResult, Error>
            do {
                if forceCloud {
                    // swiftlint:disable:next todo
                    // FIXME: Implement cloud transcription
                    Logger.shared.warn("Cloud transcription not yet implemented", component: "CLI")
                    throw VoxError.transcriptionFailed("Cloud transcription not yet implemented")
                } else {
                    // Use native transcription with language detection
                    let speechTranscriber = try SpeechTranscriber()
                    let transcriptionResult = try await speechTranscriber.transcribeWithLanguageDetection(
                        audioFile: audioFile,
                        preferredLanguages: preferredLanguages,
                        progressCallback: { progressReport in
                            self.displayProgress(progressReport)
                        })
                    result = .success(transcriptionResult)
                }
            } catch {
                result = .failure(error)
            }
            taskResult = result
            semaphore.signal()
        }
        
        semaphore.wait()
        
        guard let taskResult = taskResult else {
            throw VoxError.transcriptionFailed("Transcription task did not complete")
        }
        
        let transcriptionResult: TranscriptionResult
        switch taskResult {
        case .success(let result):
            transcriptionResult = result
        case .failure(let error):
            throw error
        }
        
        displayTranscriptionResult(transcriptionResult)
        
        // Save output if requested
        if let outputPath = output {
            try saveTranscriptionResult(transcriptionResult, to: outputPath)
        }
    }
    
    private func buildLanguagePreferences() -> [String] {
        var languages: [String] = []
        
        // 1. User-specified language (highest priority)
        if let userLanguage = language {
            languages.append(userLanguage)
            Logger.shared.info("Using user-specified language: \(userLanguage)", component: "CLI")
        }
        
        // 2. System preferred languages
        let systemLanguages = getSystemPreferredLanguages()
        languages.append(contentsOf: systemLanguages)
        
        // 3. Default fallback
        if !languages.contains("en-US") {
            languages.append("en-US")
        }
        
        // Remove duplicates while preserving order
        var uniqueLanguages: [String] = []
        var seen = Set<String>()
        for lang in languages where !seen.contains(lang) {
            uniqueLanguages.append(lang)
            seen.insert(lang)
        }
        
        return uniqueLanguages
    }
    
    private func getSystemPreferredLanguages() -> [String] {
        let preferredLanguages = Locale.preferredLanguages
        
        // Convert to proper locale identifiers and filter for supported ones
        let supportedLocales = SpeechTranscriber.supportedLocales()
        let supportedIdentifiers = Set(supportedLocales.map { $0.identifier })
        
        var systemLanguages: [String] = []
        
        for langCode in preferredLanguages.prefix(3) { // Limit to top 3 system preferences
            // Try exact match first
            if supportedIdentifiers.contains(langCode) {
                systemLanguages.append(langCode)
                continue
            }
            
            // Try language-only match (e.g., "en" -> "en-US")
            let languageOnly = String(langCode.prefix(2))
            if let match = supportedIdentifiers.first(where: { $0.hasPrefix(languageOnly + "-") }) {
                systemLanguages.append(match)
            }
        }
        
        Logger.shared.info("System preferred languages: \(systemLanguages.joined(separator: ", "))", component: "CLI")
        return systemLanguages
    }
    
    private func displayTranscriptionResult(_ result: TranscriptionResult) {
        print("\n✓ Transcription completed successfully") // swiftlint:disable:this no_print
        print("  - Language: \(result.language)") // swiftlint:disable:this no_print
        print("  - Confidence: \(String(format: "%.1f%%", result.confidence * 100))") // swiftlint:disable:this no_print
        print("  - Duration: \(String(format: "%.2f", result.duration)) seconds") // swiftlint:disable:this no_print
        print("  - Processing time: \(String(format: "%.2f", result.processingTime)) seconds") // swiftlint:disable:this no_print
        print("  - Engine: \(result.engine.rawValue)") // swiftlint:disable:this no_print
        
        if timestamps && !result.segments.isEmpty {
            print("\n--- Transcript with timestamps ---") // swiftlint:disable:this no_print
            for segment in result.segments {
                let startTime = formatTime(segment.startTime)
                let endTime = formatTime(segment.endTime)
                print("[\(startTime) - \(endTime)] \(segment.text)") // swiftlint:disable:this no_print
            }
        } else {
            print("\n--- Transcript ---") // swiftlint:disable:this no_print
            print(result.text) // swiftlint:disable:this no_print
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    private func saveTranscriptionResult(_ result: TranscriptionResult, to path: String) throws {
        let content: String
        
        switch format {
        case .txt:
            content = result.text
        case .srt:
            content = formatAsSRT(result)
        case .json:
            content = try formatAsJSON(result)
        }
        
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("✓ Output saved to: \(path)") // swiftlint:disable:this no_print
    }
    
    private func formatAsSRT(_ result: TranscriptionResult) -> String {
        var srtContent = ""
        
        for (index, segment) in result.segments.enumerated() {
            let startTime = formatSRTTime(segment.startTime)
            let endTime = formatSRTTime(segment.endTime)
            
            srtContent += "\(index + 1)\n"
            srtContent += "\(startTime) --> \(endTime)\n"
            srtContent += "\(segment.text)\n\n"
        }
        
        return srtContent
    }
    
    private func formatSRTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }
    
    private func formatAsJSON(_ result: TranscriptionResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func displayProgress(_ progress: ProgressReport) {
        if verbose {
            // Detailed progress in verbose mode
            let timeInfo = if progress.estimatedTimeRemaining != nil {
                " (ETA: \(progress.formattedTimeRemaining), elapsed: \(progress.formattedElapsedTime))"
            } else {
                " (elapsed: \(progress.formattedElapsedTime))"
            }
            
            let speedInfo = if let speed = progress.processingSpeed {
                " [\(String(format: "%.2f", speed * 100))/s]"
            } else {
                ""
            }
            
            print("[\(progress.currentPhase.rawValue)] \(progress.formattedProgress) - \(progress.currentStatus)\(timeInfo)\(speedInfo)") // swiftlint:disable:this no_print
        } else {
            // Simple progress bar in normal mode
            if progress.currentProgress > 0 {
                let barWidth = 30
                let filled = Int(progress.currentProgress * Double(barWidth))
                let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barWidth - filled)
                
                let timeInfo = if progress.estimatedTimeRemaining != nil {
                    " ETA: \(progress.formattedTimeRemaining)"
                } else {
                    ""
                }
                
                print("\r[\(bar)] \(progress.formattedProgress) - \(progress.currentPhase.rawValue)\(timeInfo)", terminator: "") // swiftlint:disable:this no_print
                
                if progress.isComplete {
                    print() // New line after completion // swiftlint:disable:this no_print
                }
            }
        }
    }
}
