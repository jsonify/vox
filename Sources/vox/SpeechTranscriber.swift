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
        let startTime = Date()
        
        guard FileManager.default.fileExists(atPath: audioFile.path) else {
            throw VoxError.invalidInputFile(audioFile.path)
        }

        let audioURL = URL(fileURLWithPath: audioFile.path)
        let request = createRecognitionRequest(for: audioURL)
        
        fputs("DEBUG: About to start speech recognition task\n", stderr)
        
        // Use the exact same pattern as our working test
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            fputs("DEBUG: About to create recognitionTask\n", stderr)
            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                fputs("DEBUG: Speech recognition callback called\n", stderr)
                
                if hasResumed { 
                    fputs("DEBUG: Already resumed, ignoring callback\n", stderr)
                    return 
                }
                
                if let error = error {
                    fputs("DEBUG: Speech recognition error: \(error.localizedDescription)\n", stderr)
                    hasResumed = true
                    continuation.resume(throwing: VoxError.transcriptionFailed(error.localizedDescription))
                    return
                }
                
                if let result = result, result.isFinal {
                    fputs("DEBUG: Final result received: \(result.bestTranscription.formattedString)\n", stderr)
                    hasResumed = true
                    continuation.resume(returning: result)
                } else if let result = result {
                    fputs("DEBUG: Partial result: \(result.bestTranscription.formattedString)\n", stderr)
                    // Handle progress updates here if needed
                }
            }
            fputs("DEBUG: Recognition task created, setting up timeout\n", stderr)
            
            // Add timeout with task cancellation 
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                fputs("DEBUG: Timeout timer fired\n", stderr)
                if !hasResumed {
                    hasResumed = true
                    fputs("DEBUG: Canceling recognition task due to timeout\n", stderr)
                    self?.recognitionTask?.cancel()
                    continuation.resume(throwing: VoxError.transcriptionFailed("Speech recognition timed out"))
                }
            }
            fputs("DEBUG: Timeout set, waiting for recognition results\n", stderr)
        }
        
        fputs("DEBUG: Building final transcription result\n", stderr)
        return try buildTranscriptionResult(
            result: result,
            audioFile: audioFile,
            startTime: startTime,
            progressReporter: EnhancedProgressReporter(totalAudioDuration: audioFile.format.duration),
            progressCallback: progressCallback
        )
    }

    private func createRecognitionRequest(for audioURL: URL) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Allow both local and cloud processing for now
        request.requiresOnDeviceRecognition = false
        return request
    }


    private func buildTranscriptionResult(
        result: SFSpeechRecognitionResult,
        audioFile: AudioFile,
        startTime: Date,
        progressReporter: EnhancedProgressReporter,
        progressCallback: ProgressCallback?
    ) throws -> TranscriptionResult {
        fputs("DEBUG: Building transcription result\n", stderr)
        let finalText = result.bestTranscription.formattedString
        fputs("DEBUG: Got final text: \(finalText)\n", stderr)

        // Calculate average confidence
        let confidences = result.bestTranscription.segments.compactMap { segment in
            segment.confidence > 0 ? Double(segment.confidence) : nil
        }
        let confidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)
        fputs("DEBUG: Calculated confidence: \(confidence)\n", stderr)

        // Convert SFTranscriptionSegment to enhanced TranscriptionSegment
        let segments = createEnhancedSegments(from: result.bestTranscription.segments)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        let transcriptionResult = TranscriptionResult(
            text: finalText,
            language: self.speechRecognizer.locale.identifier,
            confidence: confidence,
            duration: audioFile.format.duration,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: processingTime,
            audioFormat: audioFile.format
        )
        
        fputs("DEBUG: Transcription result built successfully\n", stderr)
        return transcriptionResult
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
