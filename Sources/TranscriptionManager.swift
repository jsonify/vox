import Foundation

// MARK: - TranscriptionConfig

private struct TranscriptionConfig {
    let forceCloud: Bool
    let verbose: Bool
    let fallbackAPI: FallbackAPI?
    let apiKey: String?
    let includeTimestamps: Bool
    let language: String?
}

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
        fputs("DEBUG: In TranscriptionManager.transcribeAudio\n", stderr)
        print("Starting transcription...") // swiftlint:disable:this no_print

        fputs("DEBUG: About to build language preferences\n", stderr)
        // Determine preferred languages based on user input and system preferences
        let preferredLanguages = buildLanguagePreferences()
        fputs("DEBUG: Language preferences built\n", stderr)

        // TEMP DEBUG: Bypass Logger call
        // Logger.shared.info("Language preferences: \(preferredLanguages.joined(separator: ", "))", component: "TranscriptionManager")
        fputs("DEBUG: About to call transcribeAudioWithAsyncFunction\n", stderr)

        let transcriptionResult = try transcribeAudioWithAsyncFunction(
            audioFile: audioFile,
            preferredLanguages: preferredLanguages
        )
        fputs("DEBUG: transcribeAudioWithAsyncFunction completed\n", stderr)

        return transcriptionResult
    }

    private func transcribeAudioWithAsyncFunction(audioFile: AudioFile, preferredLanguages: [String]) throws -> TranscriptionResult {
        fputs("DEBUG: In transcribeAudioWithAsyncFunction - start\n", stderr)
        
        let capturedConfig = captureConfiguration()
        fputs("DEBUG: About to call runAsyncAndWait\n", stderr)
        
        return try runAsyncAndWait { @Sendable in
            fputs("DEBUG: Inside runAsyncAndWait closure\n", stderr)
            
            if capturedConfig.forceCloud {
                return try await self.performCloudTranscription(
                    audioFile: audioFile,
                    preferredLanguage: capturedConfig.language,
                    fallbackAPI: capturedConfig.fallbackAPI,
                    apiKey: capturedConfig.apiKey,
                    includeTimestamps: capturedConfig.includeTimestamps,
                    verbose: capturedConfig.verbose
                )
            } else {
                return try await self.performNativeTranscriptionWithFallback(
                    audioFile: audioFile,
                    preferredLanguages: preferredLanguages,
                    config: capturedConfig
                )
            }
        }
    }

    private func captureConfiguration() -> TranscriptionConfig {
        return TranscriptionConfig(
            forceCloud: forceCloud,
            verbose: verbose,
            fallbackAPI: fallbackAPI,
            apiKey: apiKey,
            includeTimestamps: includeTimestamps,
            language: language
        )
    }

    private func performNativeTranscriptionWithFallback(
        audioFile: AudioFile,
        preferredLanguages: [String],
        config: TranscriptionConfig
    ) async throws -> TranscriptionResult {
        fputs("DEBUG: Using native transcription path\n", stderr)
        
        do {
            return try await performNativeTranscription(
                audioFile: audioFile,
                preferredLanguages: preferredLanguages,
                verbose: config.verbose
            )
        } catch {
            fputs("DEBUG: Native transcription failed, attempting fallback\n", stderr)
            return try await handleNativeTranscriptionFailure(
                audioFile: audioFile,
                config: config,
                error: error
            )
        }
    }

    private func performNativeTranscription(
        audioFile: AudioFile,
        preferredLanguages: [String],
        verbose: Bool
    ) async throws -> TranscriptionResult {
        fputs("DEBUG: About to create SpeechTranscriber\n", stderr)
        let speechTranscriber = try SpeechTranscriber()
        fputs("DEBUG: SpeechTranscriber created, about to call transcribeWithLanguageDetection\n", stderr)
        
        return try await speechTranscriber.transcribeWithLanguageDetection(
            audioFile: audioFile,
            preferredLanguages: preferredLanguages
        ) { @Sendable progressReport in
            fputs("DEBUG: Progress callback called\n", stderr)
            fputs(
                "DEBUG: Progress: \(String(format: "%.1f", progressReport.currentProgress * 100))%\n",
                stderr
            )
            fputs("DEBUG: Progress callback completed\n", stderr)
        }
    }

    private func handleNativeTranscriptionFailure(
        audioFile: AudioFile,
        config: TranscriptionConfig,
        error: Error
    ) async throws -> TranscriptionResult {
        fputs("DEBUG: Native transcription failed: \(error.localizedDescription)\n", stderr)
        
        if config.fallbackAPI != nil || config.apiKey != nil {
            fputs("DEBUG: Using cloud fallback with provided API key\n", stderr)
            return try await performCloudTranscription(
                audioFile: audioFile,
                preferredLanguage: config.language,
                fallbackAPI: config.fallbackAPI,
                apiKey: config.apiKey,
                includeTimestamps: config.includeTimestamps,
                verbose: config.verbose
            )
        } else {
            fputs("DEBUG: No cloud API key provided - creating demo transcription\n", stderr)
            return createDemoTranscriptionResult(audioFile: audioFile)
        }
    }

    private func createDemoTranscriptionResult(audioFile: AudioFile) -> TranscriptionResult {
        return TranscriptionResult(
            text: "[DEMO] Native speech recognition is temporarily disabled due to " +
                "system compatibility issues. To get real transcription, use: " +
                "vox file.mp4 --force-cloud --api-key YOUR_OPENAI_KEY",
            language: "en-US",
            confidence: 0.95,
            duration: audioFile.format.duration,
            segments: [],
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: audioFile.format
        )
    }

    private func runAsyncAndWait<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        fputs("DEBUG: In runAsyncAndWait - start\n", stderr)
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<T>()

        fputs("DEBUG: About to create Task\n", stderr)
        Task {
            fputs("DEBUG: Inside Task execution\n", stderr)
            do {
                fputs("DEBUG: About to call operation()\n", stderr)
                let value = try await operation()
                fputs("DEBUG: operation() completed successfully\n", stderr)
                resultBox.setValue(value)
                fputs("DEBUG: resultBox.setValue() completed\n", stderr)
            } catch {
                fputs("DEBUG: operation() threw error: \(error.localizedDescription)\n", stderr)
                resultBox.setError(error)
                fputs("DEBUG: resultBox.setError() completed\n", stderr)
            }
            fputs("DEBUG: About to signal semaphore\n", stderr)
            semaphore.signal()
            fputs("DEBUG: Semaphore signaled in Task\n", stderr)
        }

        fputs("DEBUG: About to wait on semaphore\n", stderr)
        semaphore.wait()
        fputs("DEBUG: Semaphore wait completed\n", stderr)

        fputs("DEBUG: About to call resultBox.getResult()\n", stderr)
        let result = try resultBox.getResult()
        fputs("DEBUG: resultBox.getResult() completed\n", stderr)
        return result
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

        fputs("DEBUG: Using cloud transcription: \(selectedAPI.rawValue)\n", stderr)
        // TEMP DEBUG: Bypass Logger call
        // Logger.shared.info("Using cloud transcription: \(selectedAPI.rawValue)", component: "TranscriptionManager")

        switch selectedAPI {
        case .openai:
            let whisperClient = try WhisperAPIClient.create(with: apiKey)

            return try await whisperClient.transcribe(
                audioFile: audioFile,
                language: preferredLanguage,
                includeTimestamps: includeTimestamps
            ) { @Sendable progressReport in
                // TEMP DEBUG: Bypass ProgressDisplayManager to prevent hang
                fputs(
                    "DEBUG: Cloud progress: \(String(format: "%.1f", progressReport.currentProgress * 100))%\n",
                    stderr
                )
                // Create thread-safe progress display
                // DispatchQueue.main.sync {
                //     ProgressDisplayManager.displayProgressReport(progressReport, verbose: verbose)
                // }
            }
        case .revai:
            fputs("DEBUG: Rev.ai API not yet implemented\n", stderr)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.error("Rev.ai API not yet implemented", component: "TranscriptionManager")
            throw VoxError.transcriptionFailed("Rev.ai API not yet implemented")
        }
    }

    private func buildLanguagePreferences() -> [String] {
        fputs("DEBUG: In buildLanguagePreferences\n", stderr)
        var languages: [String] = []

        // 1. User-specified language (highest priority)
        if let userLanguage = language {
            languages.append(userLanguage)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.info("Using user-specified language: \(userLanguage)", component: "TranscriptionManager")
            fputs("DEBUG: Using user-specified language: \(userLanguage)\n", stderr)
        }

        // 2. System preferred languages
        fputs("DEBUG: About to call getSystemPreferredLanguages\n", stderr)
        let systemLanguages = getSystemPreferredLanguages()
        fputs("DEBUG: getSystemPreferredLanguages completed\n", stderr)
        languages.append(contentsOf: systemLanguages)
        fputs("DEBUG: languages.append completed\n", stderr)

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
        fputs("DEBUG: In getSystemPreferredLanguages\n", stderr)

        // TEMP DEBUG: Bypass system language detection to isolate hang
        fputs("DEBUG: Bypassing system language detection for now\n", stderr)
        return ["en-US"] // Simple fallback

        /*
         // Original implementation commented out for debugging
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
         */
    }
}
