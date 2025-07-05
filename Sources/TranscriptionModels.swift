import Foundation

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

// MARK: - Core Transcription Models

public struct TranscriptionResult: Codable {
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
