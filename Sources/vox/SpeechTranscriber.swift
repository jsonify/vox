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
        Logger.shared.debug("SpeechTranscriber init start", component: "SpeechTranscriber")
        guard let speechRecognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoxError.transcriptionFailed(
                "Speech recognizer not available for locale: \(locale.identifier)"
            )
        }

        Logger.shared.debug("SpeechTranscriber created successfully", component: "SpeechTranscriber")
        guard speechRecognizer.isAvailable else {
            throw VoxError.transcriptionFailed("Speech recognizer is not available")
        }

        Logger.shared.debug("SpeechTranscriber is available", component: "SpeechTranscriber")
        self.speechRecognizer = speechRecognizer

        Logger.shared.debug("About to request speech recognition permission", component: "SpeechTranscriber")
        // Request authorization if needed
        try requestSpeechRecognitionPermission()
        Logger.shared.debug("Speech recognition permission request completed", component: "SpeechTranscriber")
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
        
        Logger.shared.debug("About to start speech recognition task", component: "SpeechTranscriber")
        
        // Create recognition task with proper main thread handling for Speech framework
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            Logger.shared.debug("About to create recognitionTask", component: "SpeechTranscriber")
            
            // Create the recognition task - ensure it runs on main thread
            recognitionTask = speechRecognizer.recognitionTask(with: request, resultHandler: { result, error in
                // Process callback directly (Speech framework already uses main thread)
                    Logger.shared.debug("Speech recognition callback called", component: "SpeechTranscriber")
                    
                    if hasResumed { 
                        Logger.shared.debug("Already resumed, ignoring callback", component: "SpeechTranscriber")
                        return 
                    }
                    
                    if let error = error {
                        Logger.shared.debug("Speech recognition error: \(error.localizedDescription)", component: "SpeechTranscriber")
                        hasResumed = true
                        continuation.resume(throwing: VoxError.transcriptionFailed(error.localizedDescription))
                        return
                    }
                    
                    if let result = result, result.isFinal {
                        Logger.shared.debug("Final result received: \(result.bestTranscription.formattedString)", component: "SpeechTranscriber")
                        hasResumed = true
                        continuation.resume(returning: result)
                    } else if let result = result {
                        Logger.shared.debug("Partial result: \(result.bestTranscription.formattedString)", component: "SpeechTranscriber")
                        // Handle progress updates here if needed
                        if let callback = progressCallback {
                            let progress = TranscriptionProgress(
                                progress: 0.5, // Partial progress
                                status: "Processing...",
                                phase: .converting,
                                startTime: Date()
                            )
                            callback(progress)
                        }
                    }
            })
            
            Logger.shared.debug("Recognition task created, setting up timeout", component: "SpeechTranscriber")
            
            // Ensure recognition task was created successfully
            guard recognitionTask != nil else {
                hasResumed = true
                continuation.resume(throwing: VoxError.transcriptionFailed("Failed to create recognition task"))
                return
            }
            
            // Add timeout with task cancellation (5 minutes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                Logger.shared.debug("Timeout timer fired", component: "SpeechTranscriber")
                if !hasResumed {
                    hasResumed = true
                    Logger.shared.debug("Canceling recognition task due to timeout", component: "SpeechTranscriber")
                    self?.recognitionTask?.cancel()
                    continuation.resume(throwing: VoxError.transcriptionFailed("Speech recognition timed out after 5 minutes"))
                }
            }
            
            Logger.shared.debug("Timeout set, waiting for recognition results", component: "SpeechTranscriber")
        }
        
        Logger.shared.debug("Building final transcription result", component: "SpeechTranscriber")
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
        Logger.shared.debug("Building transcription result", component: "SpeechTranscriber")
        let finalText = result.bestTranscription.formattedString
        Logger.shared.debug("Got final text: \(finalText)", component: "SpeechTranscriber")

        // Calculate average confidence
        let confidences = result.bestTranscription.segments.compactMap { segment in
            segment.confidence > 0 ? Double(segment.confidence) : nil
        }
        let confidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)
        Logger.shared.debug("Calculated confidence: \(confidence)", component: "SpeechTranscriber")

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
        
        Logger.shared.debug("Transcription result built successfully", component: "SpeechTranscriber")
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
        Logger.shared.debug("In requestSpeechRecognitionPermission", component: "SpeechTranscriber")
        
        // Check current authorization status first
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        switch currentStatus {
        case .authorized:
            Logger.shared.debug("Speech recognition already authorized", component: "SpeechTranscriber")
            return
        case .denied:
            throw VoxError.transcriptionFailed("Speech recognition access denied by user")
        case .restricted:
            throw VoxError.transcriptionFailed("Speech recognition restricted on this device")
        case .notDetermined:
            Logger.shared.debug("Need to request speech recognition authorization", component: "SpeechTranscriber")
        @unknown default:
            throw VoxError.transcriptionFailed("Unknown speech recognition authorization status")
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var authError: Error?

        Logger.shared.debug("About to call SFSpeechRecognizer.requestAuthorization", component: "SpeechTranscriber")
        SFSpeechRecognizer.requestAuthorization { status in
            Logger.shared.debug("SFSpeechRecognizer.requestAuthorization callback called", component: "SpeechTranscriber")
            switch status {
            case .authorized:
                Logger.shared.debug("Speech recognition authorization granted", component: "SpeechTranscriber")
            case .denied:
                Logger.shared.debug("Speech recognition access denied by user", component: "SpeechTranscriber")
                authError = VoxError.transcriptionFailed("Speech recognition access denied by user")
            case .restricted:
                Logger.shared.debug("Speech recognition restricted on this device", component: "SpeechTranscriber")
                authError = VoxError.transcriptionFailed("Speech recognition restricted on this device")
            case .notDetermined:
                Logger.shared.debug("Speech recognition authorization not determined", component: "SpeechTranscriber")
                authError = VoxError.transcriptionFailed("Speech recognition authorization not determined")
            @unknown default:
                Logger.shared.debug("Unknown speech recognition authorization status", component: "SpeechTranscriber")
                authError = VoxError.transcriptionFailed("Unknown speech recognition authorization status")
            }
            Logger.shared.debug("About to signal semaphore", component: "SpeechTranscriber")
            semaphore.signal()
        }

        Logger.shared.debug("About to wait on semaphore", component: "SpeechTranscriber")
        semaphore.wait()
        Logger.shared.debug("Semaphore wait completed", component: "SpeechTranscriber")

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
        Logger.shared.debug("In attemptTranscriptionWithLanguages", component: "SpeechTranscriber")
        var lastError: Error?
        var bestResult: TranscriptionResult?
        Logger.shared.debug("About to create ConfidenceManager", component: "SpeechTranscriber")
        let confidenceManager = ConfidenceManager()
        _ = ConfidenceConfig.default
        Logger.shared.debug("ConfidenceManager created", component: "SpeechTranscriber")

        // Try each language in order
        Logger.shared.debug("About to iterate languages: \(languages.joined(separator: ", "))", component: "SpeechTranscriber")
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
        Logger.shared.debug("Trying language \(languageCode) (\(index + 1)/\(totalCount))", component: "SpeechTranscriber")
        let locale = Locale(identifier: languageCode)

        Logger.shared.debug("About to check if speech recognition is available for \(languageCode)", component: "SpeechTranscriber")
        guard Self.isAvailable(for: locale) else {
            Logger.shared.debug("Speech recognition not available for \(languageCode)", component: "SpeechTranscriber")
            return nil
        }

        Logger.shared.debug("Attempting transcription with language: \(languageCode) (\(index + 1)/\(totalCount))", component: "SpeechTranscriber")

        Logger.shared.debug("About to create SpeechTranscriber with locale \(languageCode)", component: "SpeechTranscriber")
        let speechTranscriber = try SpeechTranscriber(locale: locale)
        Logger.shared.debug("SpeechTranscriber created successfully, about to call transcribe", component: "SpeechTranscriber")
        let result = try await speechTranscriber.transcribe(
            audioFile: audioFile,
            progressCallback: progressCallback
        )
        Logger.shared.debug("transcribe() completed successfully", component: "SpeechTranscriber")

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
