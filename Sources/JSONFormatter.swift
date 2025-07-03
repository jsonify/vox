import Foundation

/// Handles structured JSON output formatting for complete transcription data
class JSONFormatter {
    
    /// Configuration options for JSON output formatting
    struct JSONFormattingOptions {
        let includeMetadata: Bool
        let includeProcessingStats: Bool
        let includeSegmentDetails: Bool
        let includeAudioInformation: Bool
        let includeWordTimings: Bool
        let includeConfidenceScores: Bool
        let prettyPrint: Bool
        let dateFormat: DateFormat
        
        enum DateFormat {
            case iso8601
            case timestamp
            case milliseconds
        }
        
        static let `default` = JSONFormattingOptions(
            includeMetadata: true,
            includeProcessingStats: true,
            includeSegmentDetails: true,
            includeAudioInformation: true,
            includeWordTimings: true,
            includeConfidenceScores: true,
            prettyPrint: true,
            dateFormat: .iso8601
        )
    }
    
    private let options: JSONFormattingOptions
    
    init(options: JSONFormattingOptions = .default) {
        self.options = options
    }
    
    /// Formats a TranscriptionResult as comprehensive JSON with all metadata
    func formatAsJSON(_ result: TranscriptionResult) throws -> String {
        let jsonData = buildComprehensiveJSON(from: result)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = options.prettyPrint ? .prettyPrinted : []
        
        switch options.dateFormat {
        case .iso8601:
            encoder.dateEncodingStrategy = .iso8601
        case .timestamp:
            encoder.dateEncodingStrategy = .secondsSince1970
        case .milliseconds:
            encoder.dateEncodingStrategy = .millisecondsSince1970
        }
        
        let data = try encoder.encode(jsonData)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Builds a comprehensive JSON structure with all requested data
    private func buildComprehensiveJSON(from result: TranscriptionResult) -> JSONTranscriptionData {
        let timestamp = Date()
        
        return JSONTranscriptionData(
            transcription: buildTranscriptionContent(from: result),
            metadata: options.includeMetadata ? buildMetadata(from: result, timestamp: timestamp) : nil,
            audioInformation: options.includeAudioInformation ? buildAudioInformation(from: result) : nil,
            processingStats: options.includeProcessingStats ? buildProcessingStats(from: result) : nil,
            segments: options.includeSegmentDetails ? buildSegments(from: result) : nil,
            generatedAt: timestamp,
            version: "1.0.0",
            format: "vox-json"
        )
    }
    
    private func buildTranscriptionContent(from result: TranscriptionResult) -> JSONTranscriptionContent {
        return JSONTranscriptionContent(
            text: result.text,
            language: result.language,
            confidence: result.confidence,
            duration: result.duration,
            wordCount: result.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count,
            segmentCount: result.segments.count
        )
    }
    
    private func buildMetadata(from result: TranscriptionResult, timestamp: Date) -> JSONMetadata {
        let speakers = Set(result.segments.compactMap { $0.speakerID })
        let averageConfidence = result.segments.isEmpty ? 0.0 : 
            result.segments.map { $0.confidence }.reduce(0, +) / Double(result.segments.count)
        
        let lowConfidenceSegments = result.segments.filter { $0.confidence < 0.5 }
        
        return JSONMetadata(
            engine: result.engine.rawValue,
            engineVersion: getEngineVersion(for: result.engine),
            processingTime: result.processingTime,
            generatedAt: timestamp,
            speakerCount: speakers.count,
            speakers: speakers.sorted(),
            averageConfidence: averageConfidence,
            lowConfidenceSegmentCount: lowConfidenceSegments.count,
            qualityScore: calculateQualityScore(from: result)
        )
    }
    
    private func buildAudioInformation(from result: TranscriptionResult) -> JSONAudioInformation {
        let format = result.audioFormat
        
        return JSONAudioInformation(
            codec: format.codec,
            sampleRate: format.sampleRate,
            channels: format.channels,
            bitRate: format.bitRate,
            duration: format.duration,
            fileSize: format.fileSize,
            isValid: format.isValid,
            validationError: format.validationError,
            quality: format.quality.rawValue,
            isCompatible: format.isCompatible,
            isTranscriptionReady: format.isTranscriptionReady,
            formatDescription: format.description
        )
    }
    
    private func buildProcessingStats(from result: TranscriptionResult) -> JSONProcessingStats {
        let processingRate = result.duration > 0 ? result.duration / result.processingTime : 0.0
        let totalWords = result.segments.reduce(0) { count, segment in
            count + segment.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        }
        
        return JSONProcessingStats(
            processingTime: result.processingTime,
            processingRate: processingRate,
            totalSegments: result.segments.count,
            totalWords: totalWords,
            averageSegmentLength: result.segments.isEmpty ? 0.0 : 
                result.segments.map { $0.duration }.reduce(0, +) / Double(result.segments.count),
            processingEfficiency: result.processingTime > 0 ? result.duration / result.processingTime : 0.0
        )
    }
    
    private func buildSegments(from result: TranscriptionResult) -> [JSONSegment] {
        return result.segments.map { segment in
            JSONSegment(
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                duration: segment.duration,
                confidence: options.includeConfidenceScores ? segment.confidence : nil,
                speakerID: segment.speakerID,
                segmentType: segment.segmentType.rawValue,
                pauseDuration: segment.pauseDuration,
                wordTiming: options.includeWordTimings ? buildWordTiming(from: segment.words) : nil,
                isSentenceBoundary: segment.isSentenceBoundary,
                isParagraphBoundary: segment.isParagraphBoundary,
                hasSpeakerChange: segment.hasSpeakerChange,
                hasSilenceGap: segment.hasSilenceGap,
                wordCount: segment.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            )
        }
    }
    
    private func buildWordTiming(from wordTiming: WordTiming?) -> JSONWordTiming? {
        guard let wordTiming = wordTiming else { return nil }
        
        return JSONWordTiming(
            word: wordTiming.word,
            startTime: wordTiming.startTime,
            endTime: wordTiming.endTime,
            duration: wordTiming.duration,
            confidence: wordTiming.confidence
        )
    }
    
    private func getEngineVersion(for engine: TranscriptionEngine) -> String {
        switch engine {
        case .speechAnalyzer:
            return "Apple SpeechAnalyzer"
        case .openaiWhisper:
            return "OpenAI Whisper API"
        case .revai:
            return "Rev.ai API"
        }
    }
    
    private func calculateQualityScore(from result: TranscriptionResult) -> Double {
        let confidenceScore = result.confidence * 0.4
        let audioQualityScore = result.audioFormat.quality == .high ? 0.3 : 
                               result.audioFormat.quality == .medium ? 0.2 : 0.1
        let completenessScore = result.segments.isEmpty ? 0.0 : 0.3
        
        return confidenceScore + audioQualityScore + completenessScore
    }
}

// MARK: - JSON Data Structures

/// Root JSON structure for complete transcription data
struct JSONTranscriptionData: Codable {
    let transcription: JSONTranscriptionContent
    let metadata: JSONMetadata?
    let audioInformation: JSONAudioInformation?
    let processingStats: JSONProcessingStats?
    let segments: [JSONSegment]?
    let generatedAt: Date
    let version: String
    let format: String
}

/// Core transcription content
struct JSONTranscriptionContent: Codable {
    let text: String
    let language: String
    let confidence: Double
    let duration: TimeInterval
    let wordCount: Int
    let segmentCount: Int
}

/// Comprehensive metadata about the transcription
struct JSONMetadata: Codable {
    let engine: String
    let engineVersion: String
    let processingTime: TimeInterval
    let generatedAt: Date
    let speakerCount: Int
    let speakers: [String]
    let averageConfidence: Double
    let lowConfidenceSegmentCount: Int
    let qualityScore: Double
}

/// Audio format and quality information
struct JSONAudioInformation: Codable {
    let codec: String
    let sampleRate: Int
    let channels: Int
    let bitRate: Int?
    let duration: TimeInterval
    let fileSize: UInt64?
    let isValid: Bool
    let validationError: String?
    let quality: String
    let isCompatible: Bool
    let isTranscriptionReady: Bool
    let formatDescription: String
}

/// Processing performance statistics
struct JSONProcessingStats: Codable {
    let processingTime: TimeInterval
    let processingRate: Double
    let totalSegments: Int
    let totalWords: Int
    let averageSegmentLength: TimeInterval
    let processingEfficiency: Double
}

/// Detailed segment information
struct JSONSegment: Codable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
    let confidence: Double?
    let speakerID: String?
    let segmentType: String
    let pauseDuration: TimeInterval?
    let wordTiming: JSONWordTiming?
    let isSentenceBoundary: Bool
    let isParagraphBoundary: Bool
    let hasSpeakerChange: Bool
    let hasSilenceGap: Bool
    let wordCount: Int
}

/// Word-level timing information
struct JSONWordTiming: Codable {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
    let confidence: Double
}