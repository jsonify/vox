import Foundation

// MARK: - Enhanced Progress Reporting Implementation

class EnhancedProgressReporter: TranscriptionProgressReporting {
    private(set) var currentSegmentIndex: Int = 0
    private(set) var totalSegments: Int = 0
    private(set) var currentSegmentText: String?
    private(set) var memoryUsage: MemoryUsage
    private(set) var processingStats: ProcessingStats
    
    private let startTime: Date
    private let totalAudioDuration: TimeInterval
    private var segmentStartTimes: [Date] = []
    private var confidenceValues: [Double] = []
    private let memoryMonitor: MemoryMonitor
    
    init(totalAudioDuration: TimeInterval) {
        self.startTime = Date()
        self.totalAudioDuration = totalAudioDuration
        self.memoryMonitor = MemoryMonitor()
        self.memoryUsage = memoryMonitor.getCurrentUsage()
        self.processingStats = ProcessingStats(
            segmentsProcessed: 0,
            wordsProcessed: 0,
            averageConfidence: 0.0,
            processingRate: 0.0,
            audioProcessed: 0.0,
            audioRemaining: totalAudioDuration
        )
    }
    
    func updateProgress(segmentIndex: Int,
                        totalSegments: Int,
                        segmentText: String?,
                        segmentConfidence: Double,
                        audioTimeProcessed: TimeInterval) {
        self.currentSegmentIndex = segmentIndex
        self.totalSegments = totalSegments
        self.currentSegmentText = segmentText
        
        // Update memory usage
        self.memoryUsage = memoryMonitor.getCurrentUsage()
        
        // Track confidence values
        confidenceValues.append(segmentConfidence)
        
        // Calculate processing stats
        let elapsedTime = Date().timeIntervalSince(startTime)
        let processingRate = elapsedTime > 0 ? audioTimeProcessed / elapsedTime : 0
        let averageConfidence = confidenceValues.isEmpty ? 0 : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        let wordsProcessed = segmentText?.split(separator: " ").count ?? 0
        
        self.processingStats = ProcessingStats(
            segmentsProcessed: segmentIndex + 1,
            wordsProcessed: self.processingStats.wordsProcessed + wordsProcessed,
            averageConfidence: averageConfidence,
            processingRate: processingRate,
            audioProcessed: audioTimeProcessed,
            audioRemaining: max(0, totalAudioDuration - audioTimeProcessed)
        )
    }
    
    func generateDetailedProgressReport() -> TranscriptionProgress {
        let progress = totalSegments > 0 ? Double(currentSegmentIndex) / Double(totalSegments) : 0.0
        
        let status: String
        if let text = currentSegmentText {
            status = "Processing: \"\(String(text.prefix(30)))\(text.count > 30 ? "..." : "")\""
        } else {
            status = "Processing audio segment \(currentSegmentIndex + 1)/\(totalSegments)"
        }
        
        return TranscriptionProgress(
            progress: progress,
            status: status,
            phase: .extracting,
            startTime: startTime,
            processingSpeed: processingStats.processingRate
        )
    }
}
