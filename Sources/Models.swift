import Foundation
import ArgumentParser

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
        let bitRateStr = bitRate.map { "\($0/1000) kbps" } ?? "unknown"
        return "\(codec.uppercased()) - \(sampleRate)Hz, \(channels)ch, \(bitRateStr), \(String(format: "%.1f", duration))s, \(sizeStr)"
    }
}

enum AudioQuality: String, CaseIterable {
    case low = "low"
    case medium = "medium" 
    case high = "high"
    case lossless = "lossless"
    
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