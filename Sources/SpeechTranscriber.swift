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
        guard let speechRecognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoxError.transcriptionFailed("Speech recognizer not available for locale: \(locale.identifier)")
        }
        
        guard speechRecognizer.isAvailable else {
            throw VoxError.transcriptionFailed("Speech recognizer is not available")
        }
        
        self.speechRecognizer = speechRecognizer
        
        // Request authorization if needed
        try requestSpeechRecognitionPermission()
    }
    
    // MARK: - Public Interface
    
    /// Transcribe audio file to text with segments
    func transcribe(audioFile: AudioFile, progressCallback: ProgressCallback? = nil) async throws -> TranscriptionResult {
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
    }
    
    private func createRecognitionRequest(for audioURL: URL) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true // Force local processing
        return request
    }
    
    private func performSpeechRecognition(request: SFSpeechURLRecognitionRequest,
                                        audioFile: AudioFile,
                                        startTime: Date,
                                        progressReporter: EnhancedProgressReporter,
                                        progressCallback: ProgressCallback?) async throws -> TranscriptionResult {
        return try await withCheckedThrowingContinuation { continuation in
            var segments: [TranscriptionSegment] = []
            var finalTranscriptionText = ""
            var confidence: Double = 0.0
            
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    Logger.shared.error("Speech recognition error: \(error.localizedDescription)", component: "SpeechTranscriber")
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
            Logger.shared.debug("Transcription progress: \(String(format: "%.1f%%", progress * 100)) - \(currentSegmentCount) segments, \(String(format: "%.1f", audioProcessed))s processed", component: "SpeechTranscriber")
        }
        
        if result.isFinal {
            let processingTime = Date().timeIntervalSince(context.startTime)
            let realTimeRatio = context.audioFile.format.duration > 0 ? processingTime / context.audioFile.format.duration : 0
            
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
            
            Logger.shared.info("Speech transcription completed in \(String(format: "%.2f", processingTime))s (\(String(format: "%.2f", realTimeRatio))x real-time)", component: "SpeechTranscriber")
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
    
    private func determineSegmentType(
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
    
    private func extractWordTimings(from segment: SFTranscriptionSegment) -> WordTiming? {
        // Apple's SFTranscriptionSegment represents word-level segments
        // Each segment typically contains one word with timing information
        let word = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !word.isEmpty else { return nil }
        
        Logger.shared.debug("Processing segment: '\(word)' - This should contain exactly one word", component: "SpeechTranscriber")
        if word.split(separator: " ").count > 1 {
            Logger.shared.warn("Unexpected multi-word segment found: '\(word)'", component: "SpeechTranscriber")
        }
        
        return WordTiming(
            word: word,
            startTime: segment.timestamp,
            endTime: segment.timestamp + segment.duration,
            confidence: Double(segment.confidence)
        )
    }
    
    private func detectSpeakerChange(at index: Int, in segments: [SFTranscriptionSegment]) -> String? {
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
    
    private func requestSpeechRecognitionPermission() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var authError: Error?
        
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                Logger.shared.info("Speech recognition authorization granted", component: "SpeechTranscriber")
            case .denied:
                authError = VoxError.transcriptionFailed("Speech recognition access denied by user")
            case .restricted:
                authError = VoxError.transcriptionFailed("Speech recognition restricted on this device")
            case .notDetermined:
                authError = VoxError.transcriptionFailed("Speech recognition authorization not determined")
            @unknown default:
                authError = VoxError.transcriptionFailed("Unknown speech recognition authorization status")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
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

// MARK: - Extensions

extension SpeechTranscriber {
    /// Validate and normalize language code
    static func validateLanguageCode(_ languageCode: String) -> String? {
        let supportedLocales = Self.supportedLocales()
        let supportedIdentifiers = Set(supportedLocales.map { $0.identifier })
        
        // Try exact match first
        if supportedIdentifiers.contains(languageCode) {
            return languageCode
        }
        
        // Try language-only match (e.g., "en" -> "en-US")
        let languageOnly = String(languageCode.prefix(2))
        if let match = supportedIdentifiers.first(where: { $0.hasPrefix(languageOnly + "-") }) {
            Logger.shared.info("Language code '\(languageCode)' normalized to '\(match)'", component: "SpeechTranscriber")
            return match
        }
        
        // Try case-insensitive match
        if let match = supportedIdentifiers.first(where: { $0.lowercased() == languageCode.lowercased() }) {
            Logger.shared.info("Language code '\(languageCode)' normalized to '\(match)'", component: "SpeechTranscriber")
            return match
        }
        
        Logger.shared.warn("Language code '\(languageCode)' is not supported", component: "SpeechTranscriber")
        return nil
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
    func transcribeWithLanguageDetection(audioFile: AudioFile, preferredLanguages: [String] = ["en-US"], progressCallback: ProgressCallback? = nil) async throws -> TranscriptionResult {
        // Validate and normalize all preferred languages
        let validatedLanguages = preferredLanguages.compactMap { Self.validateLanguageCode($0) }
        
        if validatedLanguages.isEmpty {
            Logger.shared.warn("No valid languages provided, falling back to en-US", component: "SpeechTranscriber")
            let fallbackLanguages = ["en-US"]
            return try await attemptTranscriptionWithLanguages(audioFile: audioFile, languages: fallbackLanguages, progressCallback: progressCallback)
        }
        
        Logger.shared.info("Validated languages: \(validatedLanguages.joined(separator: ", "))", component: "SpeechTranscriber")
        return try await attemptTranscriptionWithLanguages(audioFile: audioFile, languages: validatedLanguages, progressCallback: progressCallback)
    }
    
    /// Attempt transcription with a list of validated languages
    private func attemptTranscriptionWithLanguages(audioFile: AudioFile, languages: [String], progressCallback: ProgressCallback?) async throws -> TranscriptionResult {
        var lastError: Error?
        var bestResult: TranscriptionResult?
        let confidenceManager = ConfidenceManager()
        _ = ConfidenceConfig.default
        
        // Try each language in order
        for (index, languageCode) in languages.enumerated() {
            let locale = Locale(identifier: languageCode)
            
            guard Self.isAvailable(for: locale) else {
                Logger.shared.warn("Speech recognition not available for \(languageCode)", component: "SpeechTranscriber")
                continue
            }
            
            Logger.shared.info("Attempting transcription with language: \(languageCode) (\(index + 1)/\(languages.count))", component: "SpeechTranscriber")
            
            do {
                let speechTranscriber = try SpeechTranscriber(locale: locale)
                let result = try await speechTranscriber.transcribe(audioFile: audioFile, progressCallback: progressCallback)
                
                Logger.shared.info("Transcription confidence for \(languageCode): \(String(format: "%.1f%%", result.confidence * 100))", component: "SpeechTranscriber")
                
                // Use ConfidenceManager to assess quality
                let qualityAssessment = confidenceManager.assessQuality(result: result)
                
                // Log quality assessment
                Logger.shared.info("Quality level: \(qualityAssessment.qualityLevel.rawValue)", component: "SpeechTranscriber")
                if !qualityAssessment.lowConfidenceSegments.isEmpty {
                    Logger.shared.warn("Found \(qualityAssessment.lowConfidenceSegments.count) low-confidence segments", component: "SpeechTranscriber")
                }
                
                // If confidence meets quality standards, return immediately
                if confidenceManager.meetsQualityStandards(result: result) {
                    Logger.shared.info("High quality result achieved with \(languageCode)", component: "SpeechTranscriber")
                    return result
                }
                
                // Keep the best result so far
                if bestResult == nil || result.confidence > (bestResult?.confidence ?? 0.0) {
                    bestResult = result
                }
                
            } catch {
                Logger.shared.warn("Failed transcription with \(languageCode): \(error.localizedDescription)", component: "SpeechTranscriber")
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
                Logger.shared.warn("Transcription quality is low - consider using cloud fallback services", component: "SpeechTranscriber")
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
