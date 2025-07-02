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
        progressCallback?(ProgressReport(progress: 0.0, status: "Starting transcription", phase: .initializing, startTime: startTime))
        
        guard FileManager.default.fileExists(atPath: audioFile.path) else {
            throw VoxError.invalidInputFile(audioFile.path)
        }
        
        let audioURL = URL(fileURLWithPath: audioFile.path)
        
        progressCallback?(ProgressReport(progress: 0.2, status: "Loading audio file", phase: .analyzing, startTime: startTime))
        
        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true // Force local processing
        
        progressCallback?(ProgressReport(progress: 0.4, status: "Processing speech recognition", phase: .extracting, startTime: startTime))
        
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
                    finalTranscriptionText = result.bestTranscription.formattedString
                    
                    // Calculate average confidence
                    let confidences = result.bestTranscription.segments.compactMap { segment in
                        segment.confidence > 0 ? Double(segment.confidence) : nil
                    }
                    confidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)
                    
                    // Convert SFTranscriptionSegment to TranscriptionSegment
                    segments = result.bestTranscription.segments.map { segment in
                        TranscriptionSegment(
                            text: segment.substring,
                            startTime: segment.timestamp,
                            endTime: segment.timestamp + segment.duration,
                            confidence: Double(segment.confidence),
                            speakerID: nil // Apple Speech framework doesn't provide speaker ID
                        )
                    }
                    
                    // Update progress
                    let progress = result.isFinal ? 1.0 : 0.8
                    progressCallback?(ProgressReport(
                        progress: progress,
                        status: result.isFinal ? "Transcription complete" : "Processing...",
                        phase: result.isFinal ? .complete : .extracting,
                        startTime: startTime
                    ))
                    
                    if result.isFinal {
                        let processingTime = Date().timeIntervalSince(startTime)
                        
                        let transcriptionResult = TranscriptionResult(
                            text: finalTranscriptionText,
                            language: self.speechRecognizer.locale.identifier,
                            confidence: confidence,
                            duration: audioFile.format.duration,
                            segments: segments,
                            engine: .speechAnalyzer,
                            processingTime: processingTime,
                            audioFormat: audioFile.format
                        )
                        
                        Logger.shared.info("Speech transcription completed in \(String(format: "%.2f", processingTime))s", component: "SpeechTranscriber")
                        continuation.resume(returning: transcriptionResult)
                    }
                }
            }
        }
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
    
    /// Transcribe with automatic language detection
    func transcribeWithLanguageDetection(audioFile: AudioFile, preferredLanguages: [String] = ["en-US"], progressCallback: ProgressCallback? = nil) async throws -> TranscriptionResult {
        
        // Try preferred languages in order
        for languageCode in preferredLanguages {
            let locale = Locale(identifier: languageCode)
            
            if Self.isAvailable(for: locale) {
                Logger.shared.info("Attempting transcription with language: \(languageCode)", component: "SpeechTranscriber")
                
                do {
                    let speechTranscriber = try SpeechTranscriber(locale: locale)
                    let result = try await speechTranscriber.transcribe(audioFile: audioFile, progressCallback: progressCallback)
                    
                    // If confidence is reasonable, return result
                    if result.confidence > 0.3 {
                        return result
                    }
                } catch {
                    Logger.shared.warn("Failed transcription with \(languageCode): \(error.localizedDescription)", component: "SpeechTranscriber")
                    continue
                }
            }
        }
        
        // Fallback to default locale
        Logger.shared.info("Falling back to default locale transcription", component: "SpeechTranscriber")
        return try await transcribe(audioFile: audioFile, progressCallback: progressCallback)
    }
}