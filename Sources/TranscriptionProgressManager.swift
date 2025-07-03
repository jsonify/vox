import Foundation

/// Manages progress reporting and memory monitoring for transcription operations
final class TranscriptionProgressManager {
    
    // MARK: - Properties
    
    private let speechConfig: PlatformOptimizer.SpeechRecognitionConfig
    private let memoryConfig: PlatformOptimizer.MemoryConfig
    private let progressQueue: DispatchQueue
    private let memoryQueue: DispatchQueue
    
    private var progressReporter: EnhancedProgressReporter?
    private var memoryMonitor: MemoryMonitor?
    private var progressTimer: Timer?
    private var memoryTimer: Timer?
    
    private var transcriptionStartTime: Date?
    private var isProcessing = false
    
    // MARK: - Initialization
    
    init(speechConfig: PlatformOptimizer.SpeechRecognitionConfig,
         memoryConfig: PlatformOptimizer.MemoryConfig,
         progressQueue: DispatchQueue,
         memoryQueue: DispatchQueue) {
        self.speechConfig = speechConfig
        self.memoryConfig = memoryConfig
        self.progressQueue = progressQueue
        self.memoryQueue = memoryQueue
    }
    
    // MARK: - Public API
    
    func setupProgressReporting(for audioFile: AudioFile, 
                               progressCallback: @escaping (TranscriptionProgress) -> Void) {
        progressReporter = EnhancedProgressReporter(totalAudioDuration: audioFile.format.duration)
        memoryMonitor = MemoryMonitor()
        transcriptionStartTime = Date()
        isProcessing = true
        
        startMemoryMonitoring()
        startProgressReporting(callback: progressCallback)
    }
    
    func updateProgress(completedSegments: Int, totalSegments: Int) {
        progressReporter?.updateProgress(
            segmentIndex: completedSegments - 1,
            totalSegments: totalSegments,
            segmentText: nil,
            segmentConfidence: 0.0,
            audioTimeProcessed: 0.0
        )
    }
    
    func stopProgressReporting() {
        isProcessing = false
        progressTimer?.invalidate()
        progressTimer = nil
        memoryTimer?.invalidate()
        memoryTimer = nil
    }
    
    // MARK: - Private Methods
    
    private func startMemoryMonitoring() {
        memoryQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.memoryTimer = Timer.scheduledTimer(withTimeInterval: self.speechConfig.memoryMonitoringInterval, repeats: true) { _ in
                guard self.isProcessing else { return }
                
                let memoryUsage = self.memoryMonitor?.getCurrentUsage()
                if let usage = memoryUsage, usage.currentBytes > self.memoryConfig.maxMemoryUsage {
                    Logger.shared.warn("Memory usage exceeded threshold: \(usage.currentBytes / 1024 / 1024)MB", component: "TranscriptionProgressManager")
                }
            }
            
            if let timer = self.memoryTimer {
                RunLoop.current.add(timer, forMode: .default)
                RunLoop.current.run()
            }
        }
    }
    
    private func startProgressReporting(callback: @escaping (TranscriptionProgress) -> Void) {
        progressTimer = Timer.scheduledTimer(withTimeInterval: speechConfig.progressReportingInterval, repeats: true) { [weak self] _ in
            self?.reportProgress(callback)
        }
    }
    
    private func reportProgress(_ callback: @escaping (TranscriptionProgress) -> Void) {
        progressQueue.async { [weak self] in
            guard let self = self,
                  let memoryMonitor = self.memoryMonitor else { return }
            
            let memoryUsage = memoryMonitor.getCurrentUsage()
            let thermalState = ProcessInfo.processInfo.thermalState
            
            let transcriptionProgress = TranscriptionProgress(
                progress: 0.5, // This would be calculated based on actual progress
                status: "Transcribing with optimizations...",
                phase: .extracting,
                startTime: self.transcriptionStartTime ?? Date(),
                processingSpeed: nil,
                currentSegment: nil,
                totalSegments: nil,
                confidence: nil,
                memoryUsage: memoryUsage,
                thermalState: thermalState,
                message: "Transcribing with optimizations..."
            )
            
            callback(transcriptionProgress)
        }
    }
}