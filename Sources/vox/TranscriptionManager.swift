import Foundation

// MARK: - Network Configuration for Testing

/// Configuration class for network-related test settings
class NetworkConfiguration {
    /// Shared instance for test configuration
    static var current = NetworkConfiguration()
    
    // Network timeout configuration
    var requestTimeout: TimeInterval = 30.0
    var resourceTimeout: TimeInterval = 60.0
    
    // DNS configuration
    var dnsServers: [String] = []
    
    // Rate limiting configuration
    var maxRequestsPerSecond: Int = 10
    var rateLimitingEnabled: Bool = false
    
    // Service status configuration
    var forceServiceUnavailable: Bool = false
    
    // API endpoint configuration
    var customAPIEndpoint: String?
    
    private init() {}
    
    /// Resets all configuration to default values
    func reset() {
        requestTimeout = 30.0
        resourceTimeout = 60.0
        dnsServers = []
        maxRequestsPerSecond = 10
        rateLimitingEnabled = false
        forceServiceUnavailable = false
        customAPIEndpoint = nil
    }
}

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
public struct TranscriptionManager {
    private let forceCloud: Bool
    private let verbose: Bool
    private let language: String?
    private let fallbackAPI: FallbackAPI?
    private let apiKey: String?
    private let includeTimestamps: Bool
    
    // Testing configuration - internal for testing purposes
    internal var retryEnabled: Bool = false
    internal var maxRetries: Int = 3
    internal var apiClient: APIClient?

    init(forceCloud: Bool, verbose: Bool, language: String?, fallbackAPI: FallbackAPI? = nil, apiKey: String? = nil, includeTimestamps: Bool = false) {
        self.forceCloud = forceCloud
        self.verbose = verbose
        self.language = language
        self.fallbackAPI = fallbackAPI
        self.apiKey = apiKey
        self.includeTimestamps = includeTimestamps
    }

    func transcribeAudio(audioFile: AudioFile, progressCallback: ProgressCallback? = nil) async throws -> TranscriptionResult {
        Logger.shared.debug("In TranscriptionManager.transcribeAudio", component: "TranscriptionManager")
        Logger.shared.info("Starting transcription...", component: "TranscriptionManager")

        Logger.shared.debug("About to build language preferences", component: "TranscriptionManager")
        // Determine preferred languages based on user input and system preferences
        let preferredLanguages = buildLanguagePreferences()
        Logger.shared.debug("Language preferences built", component: "TranscriptionManager")

        Logger.shared.info("Language preferences: \(preferredLanguages.joined(separator: ", "))", component: "TranscriptionManager")
        Logger.shared.debug("About to call transcribeAudioWithAsyncFunction", component: "TranscriptionManager")

        let transcriptionResult = try await transcribeAudioWithAsyncFunction(
            audioFile: audioFile,
            preferredLanguages: preferredLanguages,
            progressCallback: progressCallback
        )
        Logger.shared.debug("transcribeAudioWithAsyncFunction completed", component: "TranscriptionManager")

        return transcriptionResult
    }

    private func transcribeAudioWithAsyncFunction(audioFile: AudioFile, preferredLanguages: [String], progressCallback: ProgressCallback? = nil) async throws -> TranscriptionResult {
        Logger.shared.debug("In transcribeAudioWithAsyncFunction - start", component: "TranscriptionManager")
        
        let capturedConfig = captureConfiguration()
        Logger.shared.debug("Configuration captured, proceeding with async transcription", component: "TranscriptionManager")
        
        if capturedConfig.forceCloud {
            return try await self.performCloudTranscription(
                audioFile: audioFile,
                preferredLanguage: capturedConfig.language,
                fallbackAPI: capturedConfig.fallbackAPI,
                apiKey: capturedConfig.apiKey,
                includeTimestamps: capturedConfig.includeTimestamps,
                verbose: capturedConfig.verbose,
                progressCallback: progressCallback
            )
        } else {
            return try await self.performNativeTranscriptionWithFallback(
                audioFile: audioFile,
                preferredLanguages: preferredLanguages,
                config: capturedConfig,
                progressCallback: progressCallback
            )
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
        config: TranscriptionConfig,
        progressCallback: ProgressCallback? = nil
    ) async throws -> TranscriptionResult {
        Logger.shared.debug("Using native transcription path", component: "TranscriptionManager")
        
        do {
            return try await performNativeTranscription(
                audioFile: audioFile,
                preferredLanguages: preferredLanguages,
                verbose: config.verbose,
                progressCallback: progressCallback
            )
        } catch {
            Logger.shared.debug("Native transcription failed, attempting fallback", component: "TranscriptionManager")
            return try await handleNativeTranscriptionFailure(
                audioFile: audioFile,
                config: config,
                error: error,
                progressCallback: progressCallback
            )
        }
    }

    private func performNativeTranscription(
        audioFile: AudioFile,
        preferredLanguages: [String],
        verbose: Bool,
        progressCallback: ProgressCallback? = nil
    ) async throws -> TranscriptionResult {
        Logger.shared.debug("About to create SpeechTranscriber", component: "TranscriptionManager")
        let speechTranscriber = try SpeechTranscriber()
        Logger.shared.debug("SpeechTranscriber created, calling direct transcribe method", component: "TranscriptionManager")
        
        // Use direct transcribe method instead of complex language detection
        return try await speechTranscriber.transcribe(
            audioFile: audioFile,
            progressCallback: progressCallback ?? { @Sendable progressReport in
                Logger.shared.debug("Progress callback called", component: "TranscriptionManager")
                Logger.shared.debug("Progress: \(String(format: "%.1f", progressReport.currentProgress * 100))%", component: "TranscriptionManager")
                Logger.shared.debug("Progress callback completed", component: "TranscriptionManager")
            }
        )
    }

    private func handleNativeTranscriptionFailure(
        audioFile: AudioFile,
        config: TranscriptionConfig,
        error: Error,
        progressCallback: ProgressCallback? = nil
    ) async throws -> TranscriptionResult {
        Logger.shared.debug("Native transcription failed: \(error.localizedDescription)", component: "TranscriptionManager")
        
        // No fallback - throw the original error to surface the real issue
        throw error
    }


    private func performCloudTranscription(
        audioFile: AudioFile,
        preferredLanguage: String?,
        fallbackAPI: FallbackAPI?,
        apiKey: String?,
        includeTimestamps: Bool,
        verbose: Bool,
        progressCallback: ProgressCallback? = nil
    ) async throws -> TranscriptionResult {
        // Use injected test client if available, otherwise use real client
        let selectedAPI = fallbackAPI ?? .openai
        Logger.shared.debug("Using cloud transcription: \(selectedAPI.rawValue)", component: "TranscriptionManager")

        if let testClient = apiClient {
            return try await testClient.transcribe(
                audioFile: audioFile,
                language: preferredLanguage,
                includeTimestamps: includeTimestamps,
                progressCallback: progressCallback ?? { @Sendable progress in
                    if verbose {
                        Logger.shared.debug("Cloud progress: \(String(format: "%.1f", progress.currentProgress * 100))%", component: "TranscriptionManager")
                    }
                }
            )
        }

        switch selectedAPI {
        case .openai:
            let config = WhisperClientConfig(
                apiKey: apiKey ?? "",
                endpoint: NetworkConfiguration.current.customAPIEndpoint
            )
            let whisperClient = try WhisperAPIClient.create(with: config)
            return try await whisperClient.transcribe(
                audioFile: audioFile,
                language: preferredLanguage,
                includeTimestamps: includeTimestamps,
                progressCallback: progressCallback ?? { @Sendable progressReport in
                    if verbose {
                        Logger.shared.debug("Cloud progress: \(String(format: "%.1f", progressReport.currentProgress * 100))%", component: "TranscriptionManager")
                    }
                }
            )
        case .revai:
            Logger.shared.debug("Rev.ai API not yet implemented", component: "TranscriptionManager")
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.error("Rev.ai API not yet implemented", component: "TranscriptionManager")
            throw VoxError.transcriptionFailed("Rev.ai API not yet implemented")
        }
    }

    private func buildLanguagePreferences() -> [String] {
        Logger.shared.debug("In buildLanguagePreferences", component: "TranscriptionManager")
        var languages: [String] = []

        // 1. User-specified language (highest priority)
        if let userLanguage = language {
            languages.append(userLanguage)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.info("Using user-specified language: \(userLanguage)", component: "TranscriptionManager")
            Logger.shared.debug("Using user-specified language: \(userLanguage)", component: "TranscriptionManager")
        }

        // 2. System preferred languages
        Logger.shared.debug("About to call getSystemPreferredLanguages", component: "TranscriptionManager")
        let systemLanguages = getSystemPreferredLanguages()
        Logger.shared.debug("getSystemPreferredLanguages completed", component: "TranscriptionManager")
        languages.append(contentsOf: systemLanguages)
        Logger.shared.debug("languages.append completed", component: "TranscriptionManager")

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
        Logger.shared.debug("In getSystemPreferredLanguages", component: "TranscriptionManager")

        // TEMP DEBUG: Bypass system language detection to isolate hang
        Logger.shared.debug("Bypassing system language detection for now", component: "TranscriptionManager")
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
