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
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    fputs("DEBUG: Speech recognition error: \(error.localizedDescription)\n", stderr)
                    // TEMP DEBUG: Bypass Logger call
                    // Logger.shared.error("Speech recognition error: \(error.localizedDescription)", 
                    //                   component: "SpeechTranscriber")
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
                        context: context
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
        context: RecognitionContext
    ) {
        let finalText = result.bestTranscription.formattedString

        // Calculate average confidence
        let confidences = result.bestTranscription.segments.compactMap { segment in
            segment.confidence > 0 ? Double(segment.confidence) : nil
        }
        let confidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

        // Convert SFTranscriptionSegment to enhanced TranscriptionSegment
        let segments = createEnhancedSegments(from: result.bestTranscription.segments)

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
            let progressPercent = String(format: "%.1f%%", progress * 100)
            let audioProcessedStr = String(format: "%.1f", audioProcessed)
            let progressMessage = "DEBUG: Transcription progress: \(progressPercent) - " +
                "\(currentSegmentCount) segments, \(audioProcessedStr)s processed\n"
            fputs(progressMessage, stderr)
            // TEMP DEBUG: Bypass Logger call
            // let progressPercent = String(format: "%.1f%%", progress * 100)
            // let audioProcessedStr = String(format: "%.1f", audioProcessed)
            // Logger.shared.debug("Transcription progress: \(progressPercent) - \(currentSegmentCount) segments, 
            //                   \(audioProcessedStr)s processed", component: "SpeechTranscriber")
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

            let completionMessage = "DEBUG: Speech transcription completed in " +
                "\(String(format: "%.2f", processingTime))s (\(String(format: "%.2f", realTimeRatio))x real-time)\n"
            fputs(completionMessage, stderr)
            // TEMP DEBUG: Bypass Logger call
            // let processingTimeStr = String(format: "%.2f", processingTime)
            // let realTimeRatioStr = String(format: "%.2f", realTimeRatio)
            // Logger.shared.info("Speech transcription completed in \(processingTimeStr)s 
            //                  (\(realTimeRatioStr)x real-time)", component: "SpeechTranscriber")
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

// MARK: - Private Language Processing Extension

extension SpeechTranscriber {
    /// Attempt transcription with a list of validated languages
    internal func attemptTranscriptionWithLanguages(
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
            do {
                if let result = try await attemptTranscriptionWithLanguage(
                    languageCode: languageCode,
                    index: index,
                    totalCount: languages.count,
                    audioFile: audioFile,
                    progressCallback: progressCallback,
                    confidenceManager: confidenceManager
                ) {
                    if confidenceManager.meetsQualityStandards(result: result) {
                        Logger.shared.info(
                            "High quality result achieved with \(languageCode)",
                            component: "SpeechTranscriber"
                        )
                        return result
                    }
                    
                    if bestResult == nil || result.confidence > (bestResult?.confidence ?? 0.0) {
                        bestResult = result
                    }
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

        return try processBestResult(bestResult: bestResult, confidenceManager: confidenceManager, lastError: lastError)
    }
    
    internal func attemptTranscriptionWithLanguage(
        languageCode: String,
        index: Int,
        totalCount: Int,
        audioFile: AudioFile,
        progressCallback: ProgressCallback?,
        confidenceManager: ConfidenceManager
    ) async throws -> TranscriptionResult? {
        fputs("DEBUG: Trying language \(languageCode) (\(index + 1)/\(totalCount))\n", stderr)
        let locale = Locale(identifier: languageCode)

        fputs("DEBUG: About to check if speech recognition is available for \(languageCode)\n", stderr)
        guard Self.isAvailable(for: locale) else {
            fputs("DEBUG: Speech recognition not available for \(languageCode)\n", stderr)
            return nil
        }

        let attemptMessage = "DEBUG: Attempting transcription with language: \(languageCode) " +
            "(\(index + 1)/\(totalCount))\n"
        fputs(attemptMessage, stderr)

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

        return logQualityAssessment(result: result, confidenceManager: confidenceManager)
    }
    
    internal func logQualityAssessment(result: TranscriptionResult, confidenceManager: ConfidenceManager) -> TranscriptionResult {
        let qualityAssessment = confidenceManager.assessQuality(result: result)

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
        
        return result
    }
    
    internal func processBestResult(
        bestResult: TranscriptionResult?,
        confidenceManager: ConfidenceManager,
        lastError: Error?
    ) throws -> TranscriptionResult {
        if let result = bestResult {
            let qualityAssessment = confidenceManager.assessQuality(result: result)

            for warning in qualityAssessment.warnings {
                Logger.shared.warn(warning, component: "SpeechTranscriber")
            }

            if qualityAssessment.shouldUseFallback {
                Logger.shared.warn(
                    "Transcription quality is low - consider using cloud fallback services",
                    component: "SpeechTranscriber"
                )
            }

            return result
        }
        
        if let error = lastError {
            throw error
        } else {
            throw VoxError.transcriptionFailed("No supported languages available for transcription")
        }
    }
}
