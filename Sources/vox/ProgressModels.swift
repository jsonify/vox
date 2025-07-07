import Foundation

// MARK: - Progress Reporting Models

protocol ProgressReporting {
    var currentProgress: Double { get }
    var estimatedTimeRemaining: TimeInterval? { get }
    var currentStatus: String { get }
    var isComplete: Bool { get }
    var processingSpeed: Double? { get }
}

public struct TranscriptionProgress: ProgressReporting {
    public let currentProgress: Double
    public let estimatedTimeRemaining: TimeInterval?
    public let currentStatus: String
    public let isComplete: Bool
    public let processingSpeed: Double?
    public let startTime: Date
    public let elapsedTime: TimeInterval
    public let currentPhase: ProcessingPhase
    
    // Additional properties for enhanced progress reporting
    public let stage: ProcessingPhase
    public let currentSegment: Int?
    public let totalSegments: Int?
    public let confidence: Double?
    public let memoryUsage: MemoryUsage?
    public let thermalState: ProcessInfo.ThermalState?
    public let message: String?
    
    public init(progress: Double,
                status: String,
                phase: ProcessingPhase,
                startTime: Date,
                processingSpeed: Double? = nil,
                currentSegment: Int? = nil,
                totalSegments: Int? = nil,
                confidence: Double? = nil,
                memoryUsage: MemoryUsage? = nil,
                thermalState: ProcessInfo.ThermalState? = nil,
                message: String? = nil) {
        self.currentProgress = max(0.0, min(1.0, progress))
        self.currentStatus = status
        self.currentPhase = phase
        self.stage = phase
        self.startTime = startTime
        self.elapsedTime = Date().timeIntervalSince(startTime)
        self.processingSpeed = processingSpeed
        self.isComplete = progress >= 1.0
        
        if let speed = processingSpeed, speed > 0, progress > 0, progress < 1.0 {
            let remainingWork = 1.0 - progress
            self.estimatedTimeRemaining = remainingWork / speed
        } else {
            self.estimatedTimeRemaining = nil
        }
        
        // Set additional properties
        self.currentSegment = currentSegment
        self.totalSegments = totalSegments
        self.confidence = confidence
        self.memoryUsage = memoryUsage
        self.thermalState = thermalState
        self.message = message
    }
    
    var formattedProgress: String {
        return String(format: "%.1f%%", currentProgress * 100)
    }
    
    var formattedTimeRemaining: String {
        guard let timeRemaining = estimatedTimeRemaining else { return "calculating..." }
        
        if timeRemaining < 60 {
            return String(format: "%.0fs", timeRemaining)
        } else if timeRemaining < 3600 {
            let minutes = Int(timeRemaining / 60)
            let seconds = Int(timeRemaining.truncatingRemainder(dividingBy: 60))
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            let hours = Int(timeRemaining / 3600)
            let minutes = Int((timeRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %dm", hours, minutes)
        }
    }
    
    var formattedElapsedTime: String {
        if elapsedTime < 60 {
            return String(format: "%.1fs", elapsedTime)
        } else if elapsedTime < 3600 {
            let minutes = Int(elapsedTime / 60)
            let seconds = Int(elapsedTime.truncatingRemainder(dividingBy: 60))
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            let hours = Int(elapsedTime / 3600)
            let minutes = Int((elapsedTime.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %dm", hours, minutes)
        }
    }
}

public enum ProcessingPhase: String, CaseIterable {
    case initializing = "Initializing"
    case analyzing = "Analyzing input"
    case extracting = "Extracting audio"
    case converting = "Converting format"
    case validating = "Validating output"
    case finalizing = "Finalizing"
    case complete = "Complete"
    
    var statusMessage: String {
        switch self {
        case .initializing:
            return "Initializing audio extraction..."
        case .analyzing:
            return "Analyzing input file properties..."
        case .extracting:
            return "Extracting audio tracks..."
        case .converting:
            return "Converting audio format..."
        case .validating:
            return "Validating audio properties..."
        case .finalizing:
            return "Finalizing extraction..."
        case .complete:
            return "Audio extraction complete"
        }
    }
}

public typealias ProgressCallback = (TranscriptionProgress) -> Void

// MARK: - Enhanced Progress Reporting

protocol TranscriptionProgressReporting {
    var currentSegmentIndex: Int { get }
    var totalSegments: Int { get }
    var currentSegmentText: String? { get }
    var memoryUsage: MemoryUsage { get }
    var processingStats: ProcessingStats { get }
}

public struct MemoryUsage {
    let currentBytes: UInt64
    let peakBytes: UInt64
    let availableBytes: UInt64
    
    var currentMB: Double {
        return Double(currentBytes) / (1024 * 1024)
    }
    
    var peakMB: Double {
        return Double(peakBytes) / (1024 * 1024)
    }
    
    var availableMB: Double {
        return Double(availableBytes) / (1024 * 1024)
    }
    
    var usagePercentage: Double {
        let totalSystemMemory = ProcessInfo.processInfo.physicalMemory
        guard totalSystemMemory > 0 else { return 0.0 }
        return (Double(currentBytes) / Double(totalSystemMemory)) * 100.0
    }
}

struct ProcessingStats {
    let segmentsProcessed: Int
    let wordsProcessed: Int
    let averageConfidence: Double
    let processingRate: Double // segments per second
    let audioProcessed: TimeInterval // seconds of audio processed
    let audioRemaining: TimeInterval // seconds of audio remaining
    
    var estimatedCompletion: TimeInterval? {
        return processingRate > 0 ? audioRemaining / processingRate : nil
    }
    
    var formattedProcessingRate: String {
        return String(format: "%.1fx", processingRate)
    }
}
