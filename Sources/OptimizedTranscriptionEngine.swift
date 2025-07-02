import Foundation
import Speech
import AVFoundation

/// High-performance transcription engine with platform-specific optimizations and multi-threading
public final class OptimizedTranscriptionEngine {
    
    // MARK: - Types
    
    public typealias ProgressCallback = (TranscriptionProgress) -> Void
    public typealias CompletionCallback = (Result<TranscriptionResult, Error>) -> Void
    
    private struct TranscriptionTask {
        let audioSegment: AudioSegmenter.AudioSegmentFile
        let recognizer: SFSpeechRecognizer
        let startTime: Date
        let taskID: String
    }
    
    // AudioSegment replaced by AudioSegmenter.AudioSegmentFile
    
    // MARK: - Properties
    
    private let platformOptimizer = PlatformOptimizer.shared
    private let speechConfig: PlatformOptimizer.SpeechRecognitionConfig
    private let memoryConfig: PlatformOptimizer.MemoryConfig
    
    private let processingQueue: DispatchQueue
    private let progressQueue: DispatchQueue
    private let memoryQueue: DispatchQueue
    
    private var recognitionTasks: [String: SFSpeechRecognitionTask] = [:]
    private var completedSegments: [TranscriptionSegment] = []
    private var totalSegmentsExpected = 0
    private var transcriptionStartTime: Date?
    private var isProcessing = false
    private var audioSegmenter: AudioSegmenter?
    
    private let segmentLock = NSLock()
    private let taskLock = NSLock()
    
    // Enhanced progress reporting
    private var progressReporter: EnhancedProgressReporter?
    private var memoryMonitor: MemoryMonitor?
    private var progressTimer: Timer?
    
    // MARK: - Initialization
    
    public init() {
        self.speechConfig = platformOptimizer.getSpeechRecognitionConfig()
        self.memoryConfig = platformOptimizer.getMemoryConfig()
        
        // Create optimized dispatch queues
        let audioConfig = platformOptimizer.getAudioProcessingConfig()
        
        self.processingQueue = DispatchQueue(
            label: "vox.transcription.processing",
            qos: DispatchQoS(qosClass: audioConfig.priorityQOS, relativePriority: 0),
            attributes: .concurrent,
            target: .global(qos: audioConfig.priorityQOS)
        )
        
        self.progressQueue = DispatchQueue(
            label: "vox.transcription.progress",
            qos: .userInteractive
        )
        
        self.memoryQueue = DispatchQueue(
            label: "vox.transcription.memory",
            qos: .utility
        )
        
        Logger.shared.info("Initialized OptimizedTranscriptionEngine with \(platformOptimizer.architecture.displayName) optimizations", component: "OptimizedTranscriptionEngine")
    }
    
    deinit {
        cleanup()
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
        audioSegmenter = AudioSegmenter()
        
        // Initialize enhanced progress reporting
        setupProgressReporting(for: audioFile, progressCallback: progressCallback)
        
        // Check if we should segment the audio file
        let segmentDuration = platformOptimizer.getRecommendedFileChunkSize(for: audioFile.format.duration)
        
        if audioFile.format.duration <= segmentDuration {
            // Process as single file
            transcribeSingleFile(audioFile, language: language, startTime: startTime, completion: completion)
        } else {
            // Process with segmentation for better performance
            transcribeSegmentedFile(audioFile, segmentDuration: segmentDuration, language: language, startTime: startTime, completion: completion)
        }
    }
    
    public func cancelTranscription() {
        Logger.shared.info("Cancelling transcription", component: "OptimizedTranscriptionEngine")
        
        taskLock.lock()
        for (_, task) in recognitionTasks {
            task.cancel()
        }
        recognitionTasks.removeAll()
        taskLock.unlock()
        
        cleanup()
    }
    
    // MARK: - Single File Transcription
    
    private func transcribeSingleFile(
        _ audioFile: AudioFile,
        language: String?,
        startTime: Date,
        completion: @escaping CompletionCallback
    ) {
        guard let speechRecognizer = createSpeechRecognizer(for: language) else {
            completion(.failure(VoxError.speechRecognitionUnavailable))
            return
        }
        
        processingQueue.async { [weak self] in
            self?.performSingleFileTranscription(
                audioFile: audioFile,
                recognizer: speechRecognizer,
                startTime: startTime,
                completion: completion
            )
        }
    }
    
    private func performSingleFileTranscription(
        audioFile: AudioFile,
        recognizer: SFSpeechRecognizer,
        startTime: Date,
        completion: @escaping CompletionCallback
    ) {
        let request = SFSpeechURLRecognitionRequest(url: audioFile.url)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = speechConfig.useOnDeviceRecognition
        
        // Apple Silicon specific optimizations
        if platformOptimizer.architecture == .appleSilicon {
            request.taskHint = .search // Use available task hint
            if #available(macOS 13.0, *) {
                request.addsPunctuation = true
            }
        }
        
        let taskID = UUID().uuidString
        var segments: [TranscriptionSegment] = []
        var finalText = ""
        var confidence: Double = 0.0
        
        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.handleTranscriptionError(error, taskID: taskID, completion: completion)
                return
            }
            
            if let result = result {
                self.processSingleFileResult(
                    result,
                    audioFile: audioFile,
                    startTime: startTime,
                    segments: &segments,
                    finalText: &finalText,
                    confidence: &confidence,
                    completion: result.isFinal ? completion : nil
                )
            }
        }
        
        taskLock.lock()
        recognitionTasks[taskID] = recognitionTask
        taskLock.unlock()
    }
    
    // MARK: - Segmented File Transcription
    
    private func transcribeSegmentedFile(
        _ audioFile: AudioFile,
        segmentDuration: TimeInterval,
        language: String?,
        startTime: Date,
        completion: @escaping CompletionCallback
    ) {
        Logger.shared.info("Using segmented transcription with \(segmentDuration)s segments", component: "OptimizedTranscriptionEngine")
        
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Create actual audio segment files
                guard let segmenter = self.audioSegmenter else {
                    throw VoxError.invalidAudioFile
                }
                
                let segments = try await segmenter.createSegments(
                    from: audioFile,
                    segmentDuration: segmentDuration
                )
                
                guard !segments.isEmpty else {
                    completion(.failure(VoxError.invalidAudioFile))
                    return
                }
                
                // Update total segments expected for progress reporting
                self.totalSegmentsExpected = segments.count
                
                // Process segments concurrently with platform-optimized concurrency
                let audioConfig = self.platformOptimizer.getAudioProcessingConfig()
                let maxConcurrentTasks = audioConfig.concurrentOperations
                
                self.transcribeSegmentsConcurrently(
                    segments,
                    maxConcurrentTasks: maxConcurrentTasks,
                    language: language,
                    originalAudioFile: audioFile,
                    startTime: startTime,
                    completion: completion
                )
                
            } catch {
                completion(.failure(VoxError.transcriptionFailed("Audio segmentation failed: \(error.localizedDescription)")))
            }
        }
    }
    
    // Audio segmentation now handled by AudioSegmenter
    
    private func transcribeSegmentsConcurrently(
        _ segments: [AudioSegmenter.AudioSegmentFile],
        maxConcurrentTasks: Int,
        language: String?,
        originalAudioFile: AudioFile,
        startTime: Date,
        completion: @escaping CompletionCallback
    ) {
        let semaphore = DispatchSemaphore(value: maxConcurrentTasks)
        let group = DispatchGroup()
        var segmentResults: [Int: TranscriptionSegment] = [:]
        let resultsLock = NSLock()
        var hasError = false
        
        Logger.shared.info("Processing \(segments.count) segments with max \(maxConcurrentTasks) concurrent tasks", component: "OptimizedTranscriptionEngine")
        
        for segment in segments {
            group.enter()
            
            processingQueue.async {
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                
                guard !hasError else { return }
                
                self.transcribeSegment(segment, language: language) { [weak self] result in
                    resultsLock.lock()
                    switch result {
                    case .success(let segmentResult):
                        segmentResults[segment.segmentIndex] = segmentResult
                        // Update completed segments for progress reporting
                        self?.segmentLock.lock()
                        self?.completedSegments.append(segmentResult)
                        self?.segmentLock.unlock()
                    case .failure:
                        hasError = true
                    }
                    resultsLock.unlock()
                }
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            // Cleanup segment files after processing
            self?.audioSegmenter?.cleanupSegments(segments)
            
            if hasError {
                completion(.failure(VoxError.transcriptionFailed("Segment processing failed")))
                return
            }
            
            // Combine segment results
            let combinedResult = self?.combineSegmentResults(
                segmentResults,
                totalSegments: segments.count,
                originalAudioFile: originalAudioFile,
                startTime: startTime
            )
            
            if let result = combinedResult {
                completion(.success(result))
            } else {
                completion(.failure(VoxError.transcriptionFailed("Failed to combine segment results")))
            }
        }
    }
    
    private func transcribeSegment(
        _ segment: AudioSegmenter.AudioSegmentFile,
        language: String?,
        completion: @escaping (Result<TranscriptionSegment, Error>) -> Void
    ) {
        guard let speechRecognizer = createSpeechRecognizer(for: language) else {
            completion(.failure(VoxError.speechRecognitionUnavailable))
            return
        }
        
        // Create time-based recognition request for segment
        let request = SFSpeechURLRecognitionRequest(url: segment.url)
        request.requiresOnDeviceRecognition = speechConfig.useOnDeviceRecognition
        request.shouldReportPartialResults = false // Only final results for segments
        
        let recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let result = result, result.isFinal {
                let segmentResult = TranscriptionSegment(
                    text: result.bestTranscription.formattedString,
                    startTime: segment.startTime,
                    endTime: segment.startTime + segment.duration,
                    confidence: self?.calculateConfidence(from: result) ?? 0.0,
                    speakerID: nil
                )
                completion(.success(segmentResult))
            }
        }
        
        let taskID = UUID().uuidString
        taskLock.lock()
        recognitionTasks[taskID] = recognitionTask
        taskLock.unlock()
    }
    
    // MARK: - Progress Reporting and Memory Management
    
    private func setupProgressReporting(for audioFile: AudioFile, progressCallback: ProgressCallback?) {
        guard let progressCallback = progressCallback else { return }
        
        progressReporter = EnhancedProgressReporter(totalAudioDuration: audioFile.format.duration)
        memoryMonitor = MemoryMonitor()
        
        // Start memory monitoring with platform-optimized interval
        startMemoryMonitoring()
        
        // Start progress reporting timer
        progressTimer = Timer.scheduledTimer(withTimeInterval: speechConfig.progressReportingInterval, repeats: true) { [weak self] _ in
            self?.reportProgress(progressCallback)
        }
    }
    
    private func startMemoryMonitoring() {
        memoryQueue.async { [weak self] in
            guard let self = self else { return }
            
            let timer = Timer.scheduledTimer(withTimeInterval: self.speechConfig.memoryMonitoringInterval, repeats: true) { _ in
                guard self.isProcessing else { return }
                
                let memoryUsage = self.memoryMonitor?.getCurrentUsage()
                if let usage = memoryUsage, usage.currentBytes > self.memoryConfig.maxMemoryUsage {
                    Logger.shared.warn("Memory usage exceeded threshold: \(usage.currentBytes / 1024 / 1024)MB", component: "OptimizedTranscriptionEngine")
                    // Could trigger garbage collection or processing throttling
                }
            }
            
            RunLoop.current.add(timer, forMode: .default)
            RunLoop.current.run()
        }
    }
    
    private func reportProgress(_ callback: @escaping ProgressCallback) {
        progressQueue.async { [weak self] in
            guard let self = self,
                  let _ = self.progressReporter,
                  let memoryMonitor = self.memoryMonitor else { return }
            
            let memoryUsage = memoryMonitor.getCurrentUsage()
            let thermalState = ProcessInfo.processInfo.thermalState
            
            // Calculate transcription progress based on completed segments
            let progress = self.calculateCurrentProgress()
            
            let transcriptionProgress = TranscriptionProgress(
                progress: progress,
                status: "Transcribing with \(self.platformOptimizer.architecture.displayName) optimizations...",
                phase: .extracting,
                startTime: self.transcriptionStartTime ?? Date(),
                processingSpeed: nil,
                currentSegment: self.completedSegments.count,
                totalSegments: self.totalSegmentsExpected > 0 ? self.totalSegmentsExpected : nil,
                confidence: nil,
                memoryUsage: memoryUsage,
                thermalState: thermalState,
                message: "Transcribing with \(self.platformOptimizer.architecture.displayName) optimizations..."
            )
            
            callback(transcriptionProgress)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createSpeechRecognizer(for language: String?) -> SFSpeechRecognizer? {
        let locale = language.flatMap { Locale(identifier: $0) } ?? Locale.current
        let recognizer = SFSpeechRecognizer(locale: locale)
        recognizer?.defaultTaskHint = .search
        return recognizer
    }
    
    private func calculateConfidence(from result: SFSpeechRecognitionResult) -> Double {
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else { return 0.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + Double($1.confidence) }
        return totalConfidence / Double(segments.count)
    }
    
    private func calculateCurrentProgress() -> Double {
        segmentLock.lock()
        defer { segmentLock.unlock() }
        
        // Calculate progress based on completed segments vs total expected
        if totalSegmentsExpected > 0 {
            return Double(completedSegments.count) / Double(totalSegmentsExpected)
        }
        
        // Fallback for single file transcription
        taskLock.lock()
        let activeTaskCount = recognitionTasks.count
        taskLock.unlock()
        
        if activeTaskCount > 0 {
            // For single file, return partial progress while processing
            return 0.5 // Midway point while processing
        }
        
        return completedSegments.isEmpty ? 0.0 : 1.0
    }
    
    private func combineSegmentResults(
        _ segmentResults: [Int: TranscriptionSegment],
        totalSegments: Int,
        originalAudioFile: AudioFile,
        startTime: Date
    ) -> TranscriptionResult {
        // Sort segments by index and combine
        let sortedSegments = (0..<totalSegments).compactMap { segmentResults[$0] }
        let combinedText = sortedSegments.map { $0.text }.joined(separator: " ")
        
        let averageConfidence = sortedSegments.isEmpty ? 0.0 : 
            sortedSegments.reduce(0.0) { $0 + $1.confidence } / Double(sortedSegments.count)
        
        return TranscriptionResult(
            text: combinedText,
            language: "en-US", // Would need to detect from segments
            confidence: averageConfidence,
            duration: originalAudioFile.format.duration,
            segments: sortedSegments,
            engine: .speechAnalyzer,
            processingTime: Date().timeIntervalSince(startTime),
            audioFormat: originalAudioFile.format
        )
    }
    
    private func processSingleFileResult(
        _ result: SFSpeechRecognitionResult,
        audioFile: AudioFile,
        startTime: Date,
        segments: inout [TranscriptionSegment],
        finalText: inout String,
        confidence: inout Double,
        completion: CompletionCallback?
    ) {
        finalText = result.bestTranscription.formattedString
        confidence = calculateConfidence(from: result)
        
        // Extract segments with timing information
        segments = result.bestTranscription.segments.map { segment in
            TranscriptionSegment(
                text: segment.substring,
                startTime: segment.timestamp,
                endTime: segment.timestamp + segment.duration,
                confidence: Double(segment.confidence),
                speakerID: nil
            )
        }
        
        if let completion = completion {
            let transcriptionResult = TranscriptionResult(
                text: finalText,
                language: result.bestTranscription.segments.first?.alternativeSubstrings.first ?? "en-US",
                confidence: confidence,
                duration: audioFile.format.duration,
                segments: segments,
                engine: .speechAnalyzer,
                processingTime: Date().timeIntervalSince(startTime),
                audioFormat: audioFile.format
            )
            
            completion(.success(transcriptionResult))
        }
    }
    
    private func handleTranscriptionError(_ error: Error, taskID: String, completion: CompletionCallback) {
        Logger.shared.error("Transcription error: \(error.localizedDescription)", component: "OptimizedTranscriptionEngine")
        
        taskLock.lock()
        recognitionTasks.removeValue(forKey: taskID)
        taskLock.unlock()
        
        cleanup()
        completion(.failure(VoxError.transcriptionFailed(error.localizedDescription)))
    }
    
    private func cleanup() {
        isProcessing = false
        progressTimer?.invalidate()
        progressTimer = nil
        progressReporter = nil
        memoryMonitor = nil
        transcriptionStartTime = nil
        
        // Cleanup audio segments
        audioSegmenter?.cleanupAllSegments()
        audioSegmenter = nil
        
        segmentLock.lock()
        completedSegments.removeAll()
        totalSegmentsExpected = 0
        segmentLock.unlock()
    }
}