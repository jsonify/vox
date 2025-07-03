import Foundation

/// Manages the transcription process including language preferences and async operations
struct TranscriptionManager {
    private let forceCloud: Bool
    private let verbose: Bool
    private let language: String?
    
    init(forceCloud: Bool, verbose: Bool, language: String?) {
        self.forceCloud = forceCloud
        self.verbose = verbose
        self.language = language
    }
    
    func transcribeAudio(audioFile: AudioFile) throws -> TranscriptionResult {
        print("Starting transcription...") // swiftlint:disable:this no_print
        
        // Determine preferred languages based on user input and system preferences
        let preferredLanguages = buildLanguagePreferences()
        
        Logger.shared.info("Language preferences: \(preferredLanguages.joined(separator: ", "))", component: "TranscriptionManager")
        
        let transcriptionResult = try transcribeAudioWithAsyncFunction(audioFile: audioFile, preferredLanguages: preferredLanguages)
        
        return transcriptionResult
    }
    
    private func transcribeAudioWithAsyncFunction(audioFile: AudioFile, preferredLanguages: [String]) throws -> TranscriptionResult {
        let forceCloudCapture = forceCloud
        let verboseCapture = verbose
        return try runAsyncAndWait { @Sendable in
            if forceCloudCapture {
                // swiftlint:disable:next todo
                // FIXME: Implement cloud transcription
                Logger.shared.warn("Cloud transcription not yet implemented", component: "TranscriptionManager")
                throw VoxError.transcriptionFailed("Cloud transcription not yet implemented")
            } else {
                // Use native transcription with language detection
                let speechTranscriber = try SpeechTranscriber()
                return try await speechTranscriber.transcribeWithLanguageDetection(
                    audioFile: audioFile,
                    preferredLanguages: preferredLanguages,
                    progressCallback: { @Sendable progressReport in
                        // Create thread-safe progress display
                        DispatchQueue.main.sync {
                            ProgressDisplayManager.displayProgressReport(progressReport, verbose: verboseCapture)
                        }
                    }
                )
            }
        }
    }
    
    private func runAsyncAndWait<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<T>()
        
        Task {
            do {
                let value = try await operation()
                resultBox.setValue(value)
            } catch {
                resultBox.setError(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        return try resultBox.getResult()
    }
    
    private func buildLanguagePreferences() -> [String] {
        var languages: [String] = []
        
        // 1. User-specified language (highest priority)
        if let userLanguage = language {
            languages.append(userLanguage)
            Logger.shared.info("Using user-specified language: \(userLanguage)", component: "TranscriptionManager")
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
        
        Logger.shared.info("System preferred languages: \(systemLanguages.joined(separator: ", "))", component: "TranscriptionManager")
        return systemLanguages
    }
}