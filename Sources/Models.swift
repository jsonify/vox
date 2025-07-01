import Foundation

struct TranscriptionResult {
    let text: String
    let language: String
    let confidence: Double
    let duration: TimeInterval
    let segments: [TranscriptionSegment]
    let engine: TranscriptionEngine
    let processingTime: TimeInterval
    let audioFormat: AudioFormat
}

struct TranscriptionSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let speakerID: String?
}

enum TranscriptionEngine: String, CaseIterable {
    case speechAnalyzer = "apple-speechanalyzer"
    case openaiWhisper = "openai-whisper"
    case revai = "rev-ai"
}

struct AudioFormat {
    let codec: String
    let sampleRate: Int
    let channels: Int
    let bitRate: Int?
    let duration: TimeInterval
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
        }
    }
}