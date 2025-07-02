import Foundation
import ArgumentParser

// MARK: - Timing Constants

/// Timing thresholds for audio segment analysis and boundary detection
struct TimingThresholds {
    /// Threshold for detecting significant silence gaps that might indicate speaker changes
    static let significantPauseThreshold: TimeInterval = 1.0
    
    /// Minimum pause duration to consider a speaker change (typically indicates turn-taking)
    static let speakerChangeThreshold: TimeInterval = 2.0
    
    /// Minimum pause duration combined with sentence ending to indicate paragraph boundary
    static let paragraphBoundaryThreshold: TimeInterval = 1.5
    
    /// Threshold for detecting definitive speaker changes based on longer pauses
    static let definiteSpeakerChangeThreshold: TimeInterval = 3.0
}

struct TranscriptionResult: Codable {
    let text: String
    let language: String
    let confidence: Double
    let duration: TimeInterval
    let segments: [TranscriptionSegment]
    let engine: TranscriptionEngine
    let processingTime: TimeInterval
    let audioFormat: AudioFormat
}

struct TranscriptionSegment: Codable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let speakerID: String?
    let words: WordTiming?  // Updated to single WordTiming since each segment represents one word
    let segmentType: SegmentType
    let pauseDuration: TimeInterval?
    
    init(text: String,
         startTime: TimeInterval,
         endTime: TimeInterval,
         confidence: Double,
         speakerID: String? = nil,
         words: WordTiming? = nil,
         segmentType: SegmentType = .speech,
         pauseDuration: TimeInterval? = nil) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speakerID = speakerID
        self.words = words
        self.segmentType = segmentType
        self.pauseDuration = pauseDuration
    }
    
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    var isSentenceBoundary: Bool {
        return segmentType == .sentenceBoundary || text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
    }
    
    var isParagraphBoundary: Bool {
        return segmentType == .paragraphBoundary
    }
    
    var hasSpeakerChange: Bool {
        return segmentType == .speakerChange
    }
    
    var hasSilenceGap: Bool {
        return segmentType == .silence || (pauseDuration ?? 0) > TimingThresholds.significantPauseThreshold
    }
}

struct WordTiming: Codable {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    
    var duration: TimeInterval {
        return endTime - startTime
    }
}

enum SegmentType: String, CaseIterable, Codable {
    case speech = "speech"
    case silence = "silence"
    case sentenceBoundary = "sentence_boundary"
    case paragraphBoundary = "paragraph_boundary"
    case speakerChange = "speaker_change"
    case backgroundNoise = "background_noise"
}

enum TranscriptionEngine: String, CaseIterable, Codable {
    case speechAnalyzer = "apple-speechanalyzer"
    case openaiWhisper = "openai-whisper"
    case revai = "rev-ai"
}

struct AudioFormat: Codable {
    let codec: String
    let sampleRate: Int
    let channels: Int
    let bitRate: Int?
    let duration: TimeInterval
    let fileSize: UInt64?
    let isValid: Bool
    let validationError: String?
    let quality: AudioQuality
    
    init(codec: String, 
         sampleRate: Int, 
         channels: Int, 
         bitRate: Int?, 
         duration: TimeInterval,
         fileSize: UInt64? = nil,
         isValid: Bool = true,
         validationError: String? = nil) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
        self.duration = duration
        self.fileSize = fileSize
        self.isValid = isValid
        self.validationError = validationError
        self.quality = AudioQuality.determine(from: sampleRate, bitRate: bitRate, channels: channels)
    }
    
    var isCompatible: Bool {
        return AudioFormatValidator.isSupported(codec: codec, sampleRate: sampleRate, channels: channels)
    }
    
    var isTranscriptionReady: Bool {
        return isValid && AudioFormatValidator.isTranscriptionCompatible(codec: codec)
    }
    
    var description: String {
        let sizeStr = fileSize.map { "\(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))" } ?? "unknown"
        let bitRateStr = bitRate.map { "\($0 / 1000) kbps" } ?? "unknown"
        return "\(codec.uppercased()) - \(sampleRate)Hz, \(channels)ch, \(bitRateStr), \(String(format: "%.1f", duration))s, \(sizeStr)"
    }
}

enum AudioQuality: String, CaseIterable, Codable {
    case low
    case medium
    case high
    case lossless
    
    static func determine(from sampleRate: Int, bitRate: Int?, channels: Int) -> AudioQuality {
        guard let bitRate = bitRate else { return .medium }
        
        let effectiveBitRate = bitRate / max(channels, 1)
        
        if sampleRate >= 96000 && effectiveBitRate >= 256000 {
            return .lossless
        } else if sampleRate >= 44100 && effectiveBitRate >= 128000 {
            return .high
        } else if sampleRate >= 22050 && effectiveBitRate >= 64000 {
            return .medium
        } else {
            return .low
        }
    }
}

struct AudioFile {
    let path: String
    let format: AudioFormat
    let temporaryPath: String?
}

enum VoxError: Error, LocalizedError {
    case invalidInputFile(String)
    case audioExtractionFailed(String)
    case transcriptionFailed(String)
    case outputWriteFailed(String)
    case apiKeyMissing(String)
    case unsupportedFormat(String)
    case audioFormatValidationFailed(String)
    case incompatibleAudioProperties(String)
    case temporaryFileCreationFailed(String)
    case temporaryFileCleanupFailed(String)
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInputFile(let path):
            return "Invalid input file: \(path)"
        case .audioExtractionFailed(let reason):
            return "Audio extraction failed: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .outputWriteFailed(let reason):
            return "Failed to write output: \(reason)"
        case .apiKeyMissing(let service):
            return "API key missing for \(service)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .audioFormatValidationFailed(let details):
            return "Audio format validation failed: \(details)"
        case .incompatibleAudioProperties(let details):
            return "Incompatible audio properties: \(details)"
        case .temporaryFileCreationFailed(let reason):
            return "Failed to create temporary file: \(reason)"
        case .temporaryFileCleanupFailed(let reason):
            return "Failed to cleanup temporary file: \(reason)"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        }
    }
    
    func log() {
        Logger.shared.error(self.localizedDescription, component: componentName)
    }
    
    private var componentName: String {
        switch self {
        case .invalidInputFile, .unsupportedFormat:
            return "FileProcessor"
        case .audioExtractionFailed, .audioFormatValidationFailed, .incompatibleAudioProperties:
            return "AudioProcessor"
        case .transcriptionFailed:
            return "Transcription"
        case .outputWriteFailed:
            return "OutputWriter"
        case .apiKeyMissing:
            return "API"
        case .temporaryFileCreationFailed, .temporaryFileCleanupFailed:
            return "TempFileManager"
        case .processingFailed:
            return "Processor"
        }
    }
}

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case txt
    case srt
    case json
    
    var defaultValueDescription: String {
        return "txt"
    }
}

enum FallbackAPI: String, CaseIterable, ExpressibleByArgument {
    case openai
    case revai
}

// MARK: - Progress Reporting

protocol ProgressReporting {
    var currentProgress: Double { get }
    var estimatedTimeRemaining: TimeInterval? { get }
    var currentStatus: String { get }
    var isComplete: Bool { get }
    var processingSpeed: Double? { get }
}

struct ProgressReport: ProgressReporting {
    let currentProgress: Double
    let estimatedTimeRemaining: TimeInterval?
    let currentStatus: String
    let isComplete: Bool
    let processingSpeed: Double?
    let startTime: Date
    let elapsedTime: TimeInterval
    let currentPhase: ProcessingPhase
    
    init(progress: Double, 
         status: String, 
         phase: ProcessingPhase,
         startTime: Date,
         processingSpeed: Double? = nil) {
        self.currentProgress = max(0.0, min(1.0, progress))
        self.currentStatus = status
        self.currentPhase = phase
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

enum ProcessingPhase: String, CaseIterable {
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

typealias ProgressCallback = (ProgressReport) -> Void

// MARK: - Enhanced Progress Reporting

protocol TranscriptionProgressReporting {
    var currentSegmentIndex: Int { get }
    var totalSegments: Int { get }
    var currentSegmentText: String? { get }
    var memoryUsage: MemoryUsage { get }
    var processingStats: ProcessingStats { get }
}

struct MemoryUsage {
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
        let totalMemory = currentBytes + availableBytes
        return totalMemory > 0 ? Double(currentBytes) / Double(totalMemory) * 100 : 0
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
    
    func generateDetailedProgressReport() -> ProgressReport {
        let progress = totalSegments > 0 ? Double(currentSegmentIndex) / Double(totalSegments) : 0.0
        
        let status: String
        if let text = currentSegmentText {
            status = "Processing: \"\(String(text.prefix(30)))\(text.count > 30 ? "..." : "")\""
        } else {
            status = "Processing audio segment \(currentSegmentIndex + 1)/\(totalSegments)"
        }
        
        return ProgressReport(
            progress: progress,
            status: status,
            phase: .extracting,
            startTime: startTime,
            processingSpeed: processingStats.processingRate
        )
    }
}

class MemoryMonitor {
    func getCurrentUsage() -> MemoryUsage {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let currentBytes = result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        
        // Get system memory info
        var systemInfo = vm_statistics64()
        var systemCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let systemResult = withUnsafeMutablePointer(to: &systemInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &systemCount)
            }
        }
        
        let pageSize = UInt64(vm_page_size)
        let availableBytes = systemResult == KERN_SUCCESS ? 
            UInt64(systemInfo.free_count + systemInfo.inactive_count) * pageSize : 0
        
        // Track peak usage (simplified - in real implementation would need persistent tracking)
        let peakBytes = currentBytes
        
        return MemoryUsage(
            currentBytes: currentBytes,
            peakBytes: peakBytes,
            availableBytes: availableBytes
        )
    }
}
