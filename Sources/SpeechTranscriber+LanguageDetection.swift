import Foundation
import Speech

// MARK: - Language Detection Extension

extension SpeechTranscriber {
    /// Validate and normalize language code
    static func validateLanguageCode(_ languageCode: String) -> String? {
        fputs("DEBUG: In validateLanguageCode for: \(languageCode)\n", stderr)

        // TEMP DEBUG: Bypass supportedLocales() call which might cause hang
        fputs("DEBUG: Bypassing supportedLocales() call for debugging\n", stderr)
        // let supportedLocales = Self.supportedLocales()
        // let supportedIdentifiers = Set(supportedLocales.map { $0.identifier })

        // Simple fallback for debugging - just return the input if it looks like a valid language code
        if languageCode == "en-US" || languageCode == "en" {
            fputs("DEBUG: Validated \(languageCode) as en-US\n", stderr)
            return "en-US"
        }

        fputs("DEBUG: Language code '\(languageCode)' not in simple validation, returning en-US fallback\n", stderr)
        return "en-US" // Simple fallback for debugging

        /*
         // Original implementation commented out for debugging
         // Try exact match first
         if supportedIdentifiers.contains(languageCode) {
         return languageCode
         }

         // Try language-only match (e.g., "en" -> "en-US")
         let languageOnly = String(languageCode.prefix(2))
         if let match = supportedIdentifiers.first(where: { $0.hasPrefix(languageOnly + "-") }) {
         // TEMP DEBUG: Bypass Logger call
         // Logger.shared.info("Language code '\(languageCode)' normalized to '\(match)'", component: "SpeechTranscriber")
         return match
         }

         // Try case-insensitive match
         if let match = supportedIdentifiers.first(where: { $0.lowercased() == languageCode.lowercased() }) {
         // TEMP DEBUG: Bypass Logger call
         // Logger.shared.info("Language code '\(languageCode)' normalized to '\(match)'", component: "SpeechTranscriber")
         return match
         }

         // TEMP DEBUG: Bypass Logger call
         // Logger.shared.warn("Language code '\(languageCode)' is not supported", component: "SpeechTranscriber")
         return nil
         */
    }

    /// Get list of common language codes for easier user reference
    static func commonLanguages() -> [String: String] {
        return [
            "en-US": "English (United States)",
            "en-GB": "English (United Kingdom)",
            "es-ES": "Spanish (Spain)",
            "es-MX": "Spanish (Mexico)",
            "fr-FR": "French (France)",
            "de-DE": "German (Germany)",
            "it-IT": "Italian (Italy)",
            "pt-BR": "Portuguese (Brazil)",
            "ja-JP": "Japanese (Japan)",
            "ko-KR": "Korean (South Korea)",
            "zh-CN": "Chinese (Simplified)",
            "zh-TW": "Chinese (Traditional)",
            "ru-RU": "Russian (Russia)",
            "ar-SA": "Arabic (Saudi Arabia)"
        ]
    }

    /// Transcribe with automatic language detection and validation
    func transcribeWithLanguageDetection(
        audioFile: AudioFile,
        preferredLanguages: [String] = ["en-US"],
        progressCallback: ProgressCallback? = nil
    ) async throws -> TranscriptionResult {
        fputs("DEBUG: In transcribeWithLanguageDetection\n", stderr)
        // Validate and normalize all preferred languages
        fputs("DEBUG: About to validate languages\n", stderr)
        let validatedLanguages = preferredLanguages.compactMap { Self.validateLanguageCode($0) }
        fputs("DEBUG: Languages validated\n", stderr)

        if validatedLanguages.isEmpty {
            fputs("DEBUG: No valid languages provided, falling back to en-US\n", stderr)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.warn("No valid languages provided, falling back to en-US", component: "SpeechTranscriber")
            let fallbackLanguages = ["en-US"]
            return try await attemptTranscriptionWithLanguages(
                audioFile: audioFile,
                languages: fallbackLanguages,
                progressCallback: progressCallback
            )
        }

        fputs("DEBUG: Validated languages: \(validatedLanguages.joined(separator: ", "))\n", stderr)
        // TEMP DEBUG: Bypass Logger call
        // Logger.shared.info("Validated languages: \(validatedLanguages.joined(separator: ", "))", component: "SpeechTranscriber")
        fputs("DEBUG: About to call attemptTranscriptionWithLanguages\n", stderr)
        return try await attemptTranscriptionWithLanguages(
            audioFile: audioFile,
            languages: validatedLanguages,
            progressCallback: progressCallback
        )
    }
}
