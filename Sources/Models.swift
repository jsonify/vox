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

struct AudioFormatValidator {
    private static let supportedCodecs: Set<String> = ["aac", "m4a", "mp4", "wav", "flac", "mp3", "opus", "vorbis"]
    private static let supportedSampleRates: Set<Int> = [8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000]
    private static let supportedChannelCounts: Set<Int> = [1, 2, 4, 6, 8]
    
    // Enhanced codec compatibility matrix
    private static let codecTranscriptionCompatibility: [String: Bool] = [
        "aac": true,
        "m4a": true, 
        "mp4": true,
        "wav": true,
        "flac": true,
        "mp3": true,
        "opus": false,  // Not widely supported by transcription services
        "vorbis": false // Limited support
    ]
    
    static func isSupported(codec: String, sampleRate: Int, channels: Int) -> Bool {
        return supportedCodecs.contains(codec.lowercased()) &&
               supportedSampleRates.contains(sampleRate) &&
               supportedChannelCounts.contains(channels)
    }
    
    static func isTranscriptionCompatible(codec: String) -> Bool {
        return codecTranscriptionCompatibility[codec.lowercased()] ?? false
    }
    
    static func validate(codec: String, sampleRate: Int, channels: Int, bitRate: Int?) -> (isValid: Bool, error: String?) {
        if !supportedCodecs.contains(codec.lowercased()) {
            return (false, "Unsupported codec: \(codec). Supported codecs: \(supportedCodecs.sorted().joined(separator: ", "))")
        }
        
        if !supportedSampleRates.contains(sampleRate) {
            return (false, "Unsupported sample rate: \(sampleRate)Hz. Supported rates: \(supportedSampleRates.sorted().map { "\($0)Hz" }.joined(separator: ", "))")
        }
        
        if !supportedChannelCounts.contains(channels) {
            return (false, "Unsupported channel count: \(channels). Supported counts: \(supportedChannelCounts.sorted().map(String.init).joined(separator: ", "))")
        }
        
        if let bitRate = bitRate, bitRate < 1000 {
            return (false, "Bitrate too low: \(bitRate) bps. Minimum: 1000 bps")
        }
        
        if let bitRate = bitRate, bitRate > 2000000 {
            return (false, "Bitrate too high: \(bitRate) bps. Maximum: 2000000 bps")
        }
        
        return (true, nil)
    }
    
    static func calculateQualityScore(sampleRate: Int, bitRate: Int?, channels: Int) -> Double {
        guard let bitRate = bitRate else { return 0.5 }
        
        let normalizedSampleRate = Double(sampleRate) / 192000.0
        let normalizedBitRate = Double(bitRate) / 1000000.0
        let channelBonus = channels > 2 ? 0.1 : 0.0
        
        return min(1.0, normalizedSampleRate * 0.4 + normalizedBitRate * 0.5 + channelBonus)
    }
    
    static func detectOptimalTranscriptionSettings(for format: AudioFormat) -> (recommendedEngine: String, confidence: Double) {
        guard format.isTranscriptionReady else {
            return ("none", 0.0)
        }
        
        // Determine best transcription engine based on audio characteristics
        let qualityScore = calculateQualityScore(sampleRate: format.sampleRate, bitRate: format.bitRate, channels: format.channels)
        
        if format.sampleRate >= 44100 && qualityScore > 0.7 {
            return ("apple-speechanalyzer", 0.95)
        } else if format.sampleRate >= 16000 && qualityScore > 0.3 {
            return ("openai-whisper", 0.85)
        } else {
            return ("rev-ai", 0.75)
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