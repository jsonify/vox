import Foundation

/// Manages the transcription process including language preferences and async operations
struct TranscriptionManager {
    private let forceCloud: Bool
    private let verbose: Bool
    private let language: String?
    private let fallbackAPI: FallbackAPI?
    private let apiKey: String?
    private let includeTimestamps: Bool
    
    init(forceCloud: Bool, verbose: Bool, language: String?, fallbackAPI: FallbackAPI? = nil, apiKey: String? = nil, includeTimestamps: Bool = false) {
        self.forceCloud = forceCloud
        self.verbose = verbose
        self.language = language
        self.fallbackAPI = fallbackAPI
        self.apiKey = apiKey
        self.includeTimestamps = includeTimestamps
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
        let fallbackAPICapture = fallbackAPI
        let apiKeyCapture = apiKey
        let includeTimestampsCapture = includeTimestamps
        let languageCapture = language
        
        return try runAsyncAndWait { @Sendable in
            if forceCloudCapture {
                // Use cloud transcription (forced)
                return try await performCloudTranscription(
                    audioFile: audioFile,
                    preferredLanguage: languageCapture,
                    fallbackAPI: fallbackAPICapture,
                    apiKey: apiKeyCapture,
                    includeTimestamps: includeTimestampsCapture,
                    verbose: verboseCapture
                )
            } else {
                // Try native transcription first, fallback to cloud if needed
                do {
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
                } catch {
                    Logger.shared.warn("Native transcription failed, attempting cloud fallback: \(error.localizedDescription)", component: "TranscriptionManager")
                    
                    // Try cloud transcription as fallback
                    if fallbackAPICapture != nil || apiKeyCapture != nil {
                        return try await performCloudTranscription(
                            audioFile: audioFile,
                            preferredLanguage: languageCapture,
                            fallbackAPI: fallbackAPICapture,
                            apiKey: apiKeyCapture,
                            includeTimestamps: includeTimestampsCapture,
                            verbose: verboseCapture
                        )
                    } else {
                        Logger.shared.error("No cloud fallback configured", component: "TranscriptionManager")
                        throw error
                    }
                }
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
    
    private func performCloudTranscription(
        audioFile: AudioFile,
        preferredLanguage: String?,
        fallbackAPI: FallbackAPI?,
        apiKey: String?,
        includeTimestamps: Bool,
        verbose: Bool
    ) async throws -> TranscriptionResult {
        
        // Determine which cloud API to use
        let selectedAPI = fallbackAPI ?? .openai
        
        Logger.shared.info("Using cloud transcription: \(selectedAPI.rawValue)", component: "TranscriptionManager")
        
        switch selectedAPI {
        case .openai:
            let whisperClient = try WhisperAPIClient.create(with: apiKey)
            
            return try await whisperClient.transcribe(
                audioFile: audioFile,
                language: preferredLanguage,
                includeTimestamps: includeTimestamps,
                progressCallback: { @Sendable progressReport in
                    // Create thread-safe progress display
                    DispatchQueue.main.sync {
                        ProgressDisplayManager.displayProgressReport(progressReport, verbose: verbose)
                    }
                }
            )
        case .revai:
            Logger.shared.error("Rev.ai API not yet implemented", component: "TranscriptionManager")
            throw VoxError.transcriptionFailed("Rev.ai API not yet implemented")
        }
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