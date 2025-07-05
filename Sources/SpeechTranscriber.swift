import Foundation
import Speech
import AVFoundation

@available(macOS 10.15, *)
class SpeechTranscriber {
    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Initialization

    init(locale: Locale = Locale(identifier: "en-US")) throws {
        fputs("DEBUG: SpeechTranscriber init start\n", stderr)
        guard let speechRecognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoxError.transcriptionFailed(
                "Speech recognizer not available for locale: \(locale.identifier)"
            )
        }

        fputs("DEBUG: SpeechTranscriber created successfully\n", stderr)
        guard speechRecognizer.isAvailable else {
            throw VoxError.transcriptionFailed("Speech recognizer is not available")
        }

        fputs("DEBUG: SpeechTranscriber is available\n", stderr)
        self.speechRecognizer = speechRecognizer

        fputs("DEBUG: About to request speech recognition permission\n", stderr)
        // Request authorization if needed
        try requestSpeechRecognitionPermission()
        fputs("DEBUG: Speech recognition permission request completed\n", stderr)
    }

    // MARK: - Public Interface

    /// Transcribe audio file to text with segments
    func transcribe(
        audioFile: AudioFile,
        progressCallback: ProgressCallback? = nil
    ) async throws -> TranscriptionResult {
        fputs("DEBUG: TEMP BYPASS: Native speech recognition disabled due to system compatibility issues\n", stderr)

        // TEMP FIX: Immediately throw error to trigger cloud fallback
        throw VoxError.transcriptionFailed(
            "Native speech recognition temporarily disabled due to system compatibility issues"
        )

        /*
         // Original implementation commented out
         let startTime = Date()
         let progressReporter = EnhancedProgressReporter(totalAudioDuration: audioFile.format.duration)

         // Initial progress report
         if let callback = progressCallback {
         callback(progressReporter.generateDetailedProgressReport())
         }

         guard FileManager.default.fileExists(atPath: audioFile.path) else {
         throw VoxError.invalidInputFile(audioFile.path)
         }

         let audioURL = URL(fileURLWithPath: audioFile.path)
         progressReporter.updateProgress(segmentIndex: 0,
         totalSegments: estimateSegmentCount(for: audioFile.format.duration),
         segmentText: "Loading audio file",
         segmentConfidence: 1.0,
         audioTimeProcessed: 0)
         if let callback = progressCallback {
         callback(progressReporter.generateDetailedProgressReport())
         }

         let request = createRecognitionRequest(for: audioURL)
         progressReporter.updateProgress(segmentIndex: 0,
         totalSegments: estimateSegmentCount(for: audioFile.format.duration),
         segmentText: "Initializing speech recognition",
         segmentConfidence: 1.0,
         audioTimeProcessed: 0)
         if let callback = progressCallback {
         callback(progressReporter.generateDetailedProgressReport())
         }

         return try await performSpeechRecognition(request: request,
         audioFile: audioFile,
         startTime: startTime,
         progressReporter: progressReporter,
         progressCallback: progressCallback)
         */
    }

    private func createRecognitionRequest(for audioURL: URL) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true // Force local processing
        return request
    }

    private func performSpeechRecognition(
        request: SFSpeechURLRecognitionRequest,
        audioFile: AudioFile,
        startTime: Date,
        progressReporter: EnhancedProgressReporter,
        progressCallback: ProgressCallback?
    ) async throws -> TranscriptionResult {
        return try await withCheckedThrowingContinuation { continuation in
            var segments: [TranscriptionSegment] = []
            var finalTranscriptionText = ""
            var confidence: Double = 0.0

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    fputs("DEBUG: Speech recognition error: \(error.localizedDescription)\n", stderr)
                    // TEMP DEBUG: Bypass Logger call
                    // Logger.shared.error("Speech recognition error: \(error.localizedDescription)", component: "SpeechTranscriber")
                    continuation.resume(throwing: VoxError.transcriptionFailed(error.localizedDescription))
                    return
                }

                if let result = result {
                    let context = RecognitionContext(
                        audioFile: audioFile,
                        startTime: startTime,
                        progressReporter: progressReporter,
                        progressCallback: progressCallback,
                        continuation: continuation
                    )

                    self.processRecognitionResult(
                        result,
                        context: context,
                        segments: &segments,
                        finalText: &finalTranscriptionText,
                        confidence: &confidence
                    )
                }
            }
        }
    }

    private struct RecognitionContext {
        let audioFile: AudioFile
        let startTime: Date
        let progressReporter: EnhancedProgressReporter
        let progressCallback: ProgressCallback?
        let continuation: CheckedContinuation<TranscriptionResult, Error>
    }

    private func processRecognitionResult(
        _ result: SFSpeechRecognitionResult,
        context: RecognitionContext,
        segments: inout [TranscriptionSegment],
        finalText: inout String,
        confidence: inout Double
    ) {
        finalText = result.bestTranscription.formattedString

        // Calculate average confidence
        let confidences = result.bestTranscription.segments.compactMap { segment in
            segment.confidence > 0 ? Double(segment.confidence) : nil
        }
        confidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

        // Convert SFTranscriptionSegment to enhanced TranscriptionSegment
        segments = createEnhancedSegments(from: result.bestTranscription.segments)

        // Enhanced progress reporting with segment-level details
        let currentSegmentCount = result.bestTranscription.segments.count
        let estimatedTotalSegments = estimateSegmentCount(for: context.audioFile.format.duration)
        let audioProcessed = calculateAudioProcessed(from: result.bestTranscription.segments)

        // Update progress with enhanced metrics
        let lastSegmentText = result.bestTranscription.segments.last?.substring
        context.progressReporter.updateProgress(
            segmentIndex: currentSegmentCount,
            totalSegments: estimatedTotalSegments,
            segmentText: lastSegmentText,
            segmentConfidence: confidence,
            audioTimeProcessed: audioProcessed
        )

        if let callback = context.progressCallback {
            callback(context.progressReporter.generateDetailedProgressReport())
        }

        // Log detailed progress for verbose mode
        if !result.isFinal {
            let progress = Double(currentSegmentCount) / Double(estimatedTotalSegments)
            let progressMessage = "DEBUG: Transcription progress: \(String(format: "%.1f%%", progress * 100)) - \(currentSegmentCount) segments, \(String(format: "%.1f", audioProcessed))s processed\n"
            fputs(progressMessage, stderr)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.debug("Transcription progress: \(String(format: "%.1f%%", progress * 100)) - \(currentSegmentCount) segments, \(String(format: "%.1f", audioProcessed))s processed", component: "SpeechTranscriber")
        }

        if result.isFinal {
            let processingTime = Date().timeIntervalSince(context.startTime)
            let realTimeRatio = context.audioFile.format.duration > 0 ? 
                processingTime / context.audioFile.format.duration : 0

            let transcriptionResult = TranscriptionResult(
                text: finalText,
                language: self.speechRecognizer.locale.identifier,
                confidence: confidence,
                duration: context.audioFile.format.duration,
                segments: segments,
                engine: .speechAnalyzer,
                processingTime: processingTime,
                audioFormat: context.audioFile.format
            )

            let completionMessage = "DEBUG: Speech transcription completed in \(String(format: "%.2f", processingTime))s (\(String(format: "%.2f", realTimeRatio))x real-time)\n"
            fputs(completionMessage, stderr)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.info("Speech transcription completed in \(String(format: "%.2f", processingTime))s (\(String(format: "%.2f", realTimeRatio))x real-time)", component: "SpeechTranscriber")
            context.continuation.resume(returning: transcriptionResult)
        }
    }

    private func estimateSegmentCount(for duration: TimeInterval) -> Int {
        // Rough estimate: Apple's Speech framework typically creates segments for individual words
        // Average speaking rate is ~150 words per minute
        let estimatedWordsPerMinute: Double = 150
        let estimatedWords = (duration / 60.0) * estimatedWordsPerMinute
        return max(1, Int(estimatedWords))
    }

    private func calculateAudioProcessed(from segments: [SFTranscriptionSegment]) -> TimeInterval {
        guard let lastSegment = segments.last else { return 0 }
        return lastSegment.timestamp + lastSegment.duration
    }

    /// Check if speech recognition is available for the given locale
    static func isAvailable(for locale: Locale = Locale(identifier: "en-US")) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable
    }

    /// Get list of supported locales for speech recognition
    static func supportedLocales() -> [Locale] {
        return SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
    }

    // MARK: - Private Methods

    private func createEnhancedSegments(from sfSegments: [SFTranscriptionSegment]) -> [TranscriptionSegment] {
        var enhancedSegments: [TranscriptionSegment] = []
        var previousEndTime: TimeInterval = 0.0

        for (index, segment) in sfSegments.enumerated() {
            let startTime = segment.timestamp
            let endTime = segment.timestamp + segment.duration
            let text = segment.substring
            let confidence = Double(segment.confidence)

            // Detect pause/silence before this segment
            let pauseDuration = index > 0 ? startTime - previousEndTime : nil

            // Determine segment type based on content and timing
            let segmentType = determineSegmentType(
                text: text,
                pauseDuration: pauseDuration,
                isFirstSegment: index == 0,
                isLastSegment: index == sfSegments.count - 1,
                previousText: index > 0 ? sfSegments[index - 1].substring : nil
            )

            // Extract word-level timing if available
            let wordTimings = extractWordTimings(from: segment)

            // Create enhanced segment
            let enhancedSegment = TranscriptionSegment(
                text: text,
                startTime: startTime,
                endTime: endTime,
                confidence: confidence,
                speakerID: detectSpeakerChange(at: index, in: sfSegments),
                words: wordTimings,
                segmentType: segmentType,
                pauseDuration: pauseDuration
            )

            enhancedSegments.append(enhancedSegment)
            previousEndTime = endTime
        }

        return enhancedSegments
    }

    private func requestSpeechRecognitionPermission() throws {
        fputs("DEBUG: In requestSpeechRecognitionPermission\n", stderr)
        let semaphore = DispatchSemaphore(value: 0)
        var authError: Error?

        fputs("DEBUG: About to call SFSpeechRecognizer.requestAuthorization\n", stderr)
        SFSpeechRecognizer.requestAuthorization { status in
            fputs("DEBUG: SFSpeechRecognizer.requestAuthorization callback called\n", stderr)
            switch status {
            case .authorized:
                fputs("DEBUG: Speech recognition authorization granted\n", stderr)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.info("Speech recognition authorization granted", component: "SpeechTranscriber")
            case .denied:
                fputs("DEBUG: Speech recognition access denied by user\n", stderr)
                authError = VoxError.transcriptionFailed("Speech recognition access denied by user")
            case .restricted:
                fputs("DEBUG: Speech recognition restricted on this device\n", stderr)
                authError = VoxError.transcriptionFailed("Speech recognition restricted on this device")
            case .notDetermined:
                fputs("DEBUG: Speech recognition authorization not determined\n", stderr)
                authError = VoxError.transcriptionFailed("Speech recognition authorization not determined")
            @unknown default:
                fputs("DEBUG: Unknown speech recognition authorization status\n", stderr)
                authError = VoxError.transcriptionFailed("Unknown speech recognition authorization status")
            }
            fputs("DEBUG: About to signal semaphore\n", stderr)
            semaphore.signal()
        }

        fputs("DEBUG: About to wait on semaphore\n", stderr)
        semaphore.wait()
        fputs("DEBUG: Semaphore wait completed\n", stderr)

        if let error = authError {
            throw error
        }
    }

    // MARK: - Cleanup

    deinit {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}

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

// MARK: - Private Language Processing Extension

private extension SpeechTranscriber {
    /// Attempt transcription with a list of validated languages
    func attemptTranscriptionWithLanguages(
        audioFile: AudioFile,
        languages: [String],
        progressCallback: ProgressCallback?
    ) async throws -> TranscriptionResult {
        fputs("DEBUG: In attemptTranscriptionWithLanguages\n", stderr)
        var lastError: Error?
        var bestResult: TranscriptionResult?
        fputs("DEBUG: About to create ConfidenceManager\n", stderr)
        let confidenceManager = ConfidenceManager()
        _ = ConfidenceConfig.default
        fputs("DEBUG: ConfidenceManager created\n", stderr)

        // Try each language in order
        fputs("DEBUG: About to iterate languages: \(languages.joined(separator: ", "))\n", stderr)
        for (index, languageCode) in languages.enumerated() {
            fputs("DEBUG: Trying language \(languageCode) (\(index + 1)/\(languages.count))\n", stderr)
            let locale = Locale(identifier: languageCode)

            fputs("DEBUG: About to check if speech recognition is available for \(languageCode)\n", stderr)
            guard Self.isAvailable(for: locale) else {
                fputs("DEBUG: Speech recognition not available for \(languageCode)\n", stderr)
                // TEMP DEBUG: Bypass Logger call
                // Logger.shared.warn("Speech recognition not available for \(languageCode)", component: "SpeechTranscriber")
                continue
            }

            let attemptMessage = "DEBUG: Attempting transcription with language: \(languageCode) (\(index + 1)/\(languages.count))\n"
            fputs(attemptMessage, stderr)
            // TEMP DEBUG: Bypass Logger call
            // Logger.shared.info("Attempting transcription with language: \(languageCode) (\(index + 1)/\(languages.count))", component: "SpeechTranscriber")

            do {
                fputs("DEBUG: About to create SpeechTranscriber with locale \(languageCode)\n", stderr)
                let speechTranscriber = try SpeechTranscriber(locale: locale)
                fputs("DEBUG: SpeechTranscriber created successfully, about to call transcribe\n", stderr)
                let result = try await speechTranscriber.transcribe(
                    audioFile: audioFile,
                    progressCallback: progressCallback
                )
                fputs("DEBUG: transcribe() completed successfully\n", stderr)

                Logger.shared.info(
                    "Transcription confidence for \(languageCode): \(String(format: "%.1f%%", result.confidence * 100))",
                    component: "SpeechTranscriber"
                )

                // Use ConfidenceManager to assess quality
                let qualityAssessment = confidenceManager.assessQuality(result: result)

                // Log quality assessment
                Logger.shared.info(
                    "Quality level: \(qualityAssessment.qualityLevel.rawValue)",
                    component: "SpeechTranscriber"
                )
                if !qualityAssessment.lowConfidenceSegments.isEmpty {
                    Logger.shared.warn(
                        "Found \(qualityAssessment.lowConfidenceSegments.count) low-confidence segments",
                        component: "SpeechTranscriber"
                    )
                }

                // If confidence meets quality standards, return immediately
                if confidenceManager.meetsQualityStandards(result: result) {
                    Logger.shared.info(
                        "High quality result achieved with \(languageCode)",
                        component: "SpeechTranscriber"
                    )
                    return result
                }

                // Keep the best result so far
                if bestResult == nil || result.confidence > (bestResult?.confidence ?? 0.0) {
                    bestResult = result
                }
            } catch {
                Logger.shared.warn(
                    "Failed transcription with \(languageCode): \(error.localizedDescription)",
                    component: "SpeechTranscriber"
                )
                lastError = error
                continue
            }
        }

        // Return the best result we got, with quality assessment warnings
        if let result = bestResult {
            let qualityAssessment = confidenceManager.assessQuality(result: result)

            // Log quality warnings
            for warning in qualityAssessment.warnings {
                Logger.shared.warn(warning, component: "SpeechTranscriber")
            }

            // Log fallback recommendation
            if qualityAssessment.shouldUseFallback {
                Logger.shared.warn(
                    "Transcription quality is low - consider using cloud fallback services",
                    component: "SpeechTranscriber"
                )
            }

            return result
        }
        // If we got here, all languages failed
        if let error = lastError {
            throw error
        } else {
            throw VoxError.transcriptionFailed("No supported languages available for transcription")
        }
    }
}

// MARK: - Segment Processing Extension

private extension SpeechTranscriber {
    func determineSegmentType(
        text: String,
        pauseDuration: TimeInterval?,
        isFirstSegment: Bool,
        isLastSegment: Bool,
        previousText: String?
    ) -> SegmentType {
        // Check for silence gaps (pause > speaker change threshold typically indicates speaker change or paragraph break)
        if let pause = pauseDuration, pause > TimingThresholds.speakerChangeThreshold {
            return .speakerChange
        }

        // Check for sentence boundaries
        if text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
            return .sentenceBoundary
        }

        // Check for paragraph boundaries (long pause + sentence ending)
        if let pause = pauseDuration, pause > TimingThresholds.paragraphBoundaryThreshold,
           let prevText = previousText,
           prevText.hasSuffix(".") || prevText.hasSuffix("!") || prevText.hasSuffix("?") {
            return .paragraphBoundary
        }

        // Check for silence (empty or very short segments with low confidence)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .silence
        }

        return .speech
    }

    func extractWordTimings(from segment: SFTranscriptionSegment) -> WordTiming? {
        // Apple's SFTranscriptionSegment represents word-level segments
        // Each segment typically contains one word with timing information
        let word = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !word.isEmpty else { return nil }

        // TEMP DEBUG: Bypass Logger calls
        if word.split(separator: " ").count > 1 {
            fputs("DEBUG: Unexpected multi-word segment found: '\(word)'\n", stderr)
        }

        return WordTiming(
            word: word,
            startTime: segment.timestamp,
            endTime: segment.timestamp + segment.duration,
            confidence: Double(segment.confidence)
        )
    }

    func detectSpeakerChange(at index: Int, in segments: [SFTranscriptionSegment]) -> String? {
        // Apple Speech framework doesn't provide speaker diarization
        // This is a placeholder for future enhancement or integration with other services
        // For now, we'll detect potential speaker changes based on significant pause patterns

        guard index > 0 else { return "Speaker1" }

        let currentSegment = segments[index]
        let previousSegment = segments[index - 1]
        let pauseDuration = currentSegment.timestamp - (previousSegment.timestamp + previousSegment.duration)

        // Simple heuristic: if there's a pause > definite speaker change threshold, assume speaker change
        if pauseDuration > TimingThresholds.definiteSpeakerChangeThreshold {
            return "Speaker\((index % 4) + 1)" // Cycle through up to 4 speakers
        }

        return "Speaker1" // Default to single speaker
    }
}
