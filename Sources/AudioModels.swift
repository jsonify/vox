import Foundation

// MARK: - Audio Format Models

public struct AudioFormat: Codable {
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

public struct AudioFile {
    public let path: String
    public let format: AudioFormat
    public let temporaryPath: String?
    
    public var url: URL {
        return URL(fileURLWithPath: path)
    }
    
    public init(path: String, format: AudioFormat, temporaryPath: String? = nil) {
        self.path = path
        self.format = format
        self.temporaryPath = temporaryPath
    }
}
