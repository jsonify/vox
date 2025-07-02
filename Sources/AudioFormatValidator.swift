import Foundation

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