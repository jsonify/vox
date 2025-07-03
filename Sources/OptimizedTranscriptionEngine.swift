import Foundation
import Speech
import AVFoundation

/// Simplified high-performance transcription engine with platform-specific optimizations
public final class OptimizedTranscriptionEngine {
    
    // MARK: - Types
    
    public typealias ProgressCallback = (TranscriptionProgress) -> Void
    public typealias CompletionCallback = (Result<TranscriptionResult, Error>) -> Void
    
    // MARK: - Properties
    
    private let platformOptimizer = PlatformOptimizer.shared
    private let speechConfig: PlatformOptimizer.SpeechRecognitionConfig
    private let memoryConfig: PlatformOptimizer.MemoryConfig
    
    private let processingQueue: DispatchQueue
    private let progressQueue: DispatchQueue
    private let memoryQueue: DispatchQueue
    
    private var transcriptionStartTime: Date?
    private var isProcessing = false
    
    // Component managers
    private lazy var progressManager: TranscriptionProgressManager = {
        TranscriptionProgressManager(
            speechConfig: speechConfig,
            memoryConfig: memoryConfig,
            progressQueue: progressQueue,
            memoryQueue: memoryQueue
        )
    }()
    
    private lazy var taskManager: TranscriptionTaskManager = {
        TranscriptionTaskManager(
            processingQueue: processingQueue,
            speechConfig: speechConfig
        )
    }()
    
    // MARK: - Initialization
    
    public init() {
        self.speechConfig = platformOptimizer.getSpeechRecognitionConfig()
        self.memoryConfig = platformOptimizer.getMemoryConfig()
        
        // Create platform-optimized queues
        self.processingQueue = DispatchQueue(
            label: "vox.transcription.processing",
            qos: .userInitiated,
            attributes: .concurrent
        )
        
        self.progressQueue = DispatchQueue(
            label: "vox.transcription.progress",
            qos: .utility
        )
        
        self.memoryQueue = DispatchQueue(
            label: "vox.transcription.memory",
            qos: .background
        )
        
        Logger.shared.info("OptimizedTranscriptionEngine initialized with \(platformOptimizer.architecture.displayName) optimizations", component: "OptimizedTranscriptionEngine")
    }
    
    // MARK: - Public API
    
    public func transcribeAudio(
        from audioFile: AudioFile,
        language: String? = nil,
        progressCallback: ProgressCallback? = nil,
        completion: @escaping CompletionCallback
    ) {
        guard !isProcessing else {
            completion(.failure(VoxError.transcriptionInProgress))
            return
        }
        
        isProcessing = true
        let startTime = Date()
        transcriptionStartTime = startTime
        
        // Initialize enhanced progress reporting
        if let progressCallback = progressCallback {
            progressManager.setupProgressReporting(for: audioFile, progressCallback: progressCallback)
        }
        
        // For simplicity, always use single file approach
        transcribeSingleFile(audioFile, language: language, startTime: startTime, completion: completion)
    }
    
    public func cancelTranscription() {
        Logger.shared.info("Cancelling transcription", component: "OptimizedTranscriptionEngine")
        taskManager.cancelAllTasks()
        cleanup()
    }
    
    // MARK: - Single File Transcription
    
    private func transcribeSingleFile(
        _ audioFile: AudioFile,
        language: String?,
        startTime: Date,
        completion: @escaping CompletionCallback
    ) {
        guard let recognizer = taskManager.createSpeechRecognizer(for: language) else {
            cleanup()
            completion(.failure(VoxError.speechRecognitionUnavailable))
            return
        }
        
        let taskID = UUID().uuidString
        let request = createRecognitionRequest(for: audioFile.url)
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                self?.handleSingleFileResult(result, error: error, audioFile: audioFile, language: language ?? "en-US", startTime: startTime, completion: completion)
            }
            
            self.taskManager.addRecognitionTask(recognitionTask, for: taskID)
        }
    }
    
    private func handleSingleFileResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        audioFile: AudioFile,
        language: String,
        startTime: Date,
        completion: @escaping CompletionCallback
    ) {
        defer { cleanup() }
        
        if let error = error {
            completion(.failure(VoxError.transcriptionFailed("Speech recognition failed: \(error.localizedDescription)")))
            return
        }
        
        guard let result = result, result.isFinal else { return }
        
        let transcriptionResult = createTranscriptionResult(
            from: result,
            audioFile: audioFile,
            language: language,
            startTime: startTime
        )
        
        completion(.success(transcriptionResult))
    }
    
    // MARK: - Helper Methods
    
    private func createRecognitionRequest(for audioURL: URL) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = speechConfig.useOnDeviceRecognition
        request.taskHint = .dictation
        
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        
        return request
    }
    
    private func createTranscriptionResult(
        from result: SFSpeechRecognitionResult,
        audioFile: AudioFile,
        language: String,
        startTime: Date
    ) -> TranscriptionResult {
        let text = result.bestTranscription.formattedString
        let confidence = Double(result.bestTranscription.segments.first?.confidence ?? 0.0)
        let processingTime = Date().timeIntervalSince(startTime)
        
        let segment = TranscriptionSegment(
            text: text,
            startTime: 0.0,
            endTime: audioFile.format.duration,
            confidence: confidence
        )
        
        return TranscriptionResult(
            text: text,
            language: language,
            confidence: confidence,
            duration: audioFile.format.duration,
            segments: [segment],
            engine: .speechAnalyzer,
            processingTime: processingTime,
            audioFormat: audioFile.format
        )
    }
    
    private func cleanup() {
        isProcessing = false
        progressManager.stopProgressReporting()
        taskManager.clearCompletedSegments()
        transcriptionStartTime = nil
        
        Logger.shared.debug("OptimizedTranscriptionEngine cleanup completed", component: "OptimizedTranscriptionEngine")
    }
}