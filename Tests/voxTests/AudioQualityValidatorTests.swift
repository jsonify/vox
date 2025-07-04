import XCTest
@testable import vox

final class AudioQualityValidatorTests: XCTestCase {
    // MARK: - AudioQuality Tests

    func testAudioQualityDetermination() {
        // Test lossless quality
        let lossless = AudioQuality.determine(from: 96000, bitRate: 512000, channels: 2)
        XCTAssertEqual(lossless, .lossless)

        // Test high quality
        let high = AudioQuality.determine(from: 48000, bitRate: 256000, channels: 2)
        XCTAssertEqual(high, .high)

        // Test medium quality
        let medium = AudioQuality.determine(from: 44100, bitRate: 128000, channels: 2)
        XCTAssertEqual(medium, .medium) // 44100Hz + 64kbps per channel = medium

        // Test low quality
        let low = AudioQuality.determine(from: 22050, bitRate: 32000, channels: 1)
        XCTAssertEqual(low, .low)

        // Test with nil bitRate
        let nilBitRate = AudioQuality.determine(from: 44100, bitRate: nil, channels: 2)
        XCTAssertEqual(nilBitRate, .medium)
    }

    func testAudioQualityRawValues() {
        XCTAssertEqual(AudioQuality.low.rawValue, "low")
        XCTAssertEqual(AudioQuality.medium.rawValue, "medium")
        XCTAssertEqual(AudioQuality.high.rawValue, "high")
        XCTAssertEqual(AudioQuality.lossless.rawValue, "lossless")
    }

    // MARK: - AudioFormatValidator Tests

    func testAudioFormatValidatorSupportedFormats() {
        // Test supported codecs
        XCTAssertTrue(AudioFormatValidator.isSupported(codec: "aac", sampleRate: 44100, channels: 2))
        XCTAssertTrue(AudioFormatValidator.isSupported(codec: "m4a", sampleRate: 48000, channels: 2))
        XCTAssertTrue(AudioFormatValidator.isSupported(codec: "wav", sampleRate: 44100, channels: 1))
        XCTAssertTrue(AudioFormatValidator.isSupported(codec: "mp3", sampleRate: 44100, channels: 2))

        // Test unsupported codec
        XCTAssertFalse(AudioFormatValidator.isSupported(codec: "ogg", sampleRate: 44100, channels: 2))

        // Test unsupported sample rate
        XCTAssertFalse(AudioFormatValidator.isSupported(codec: "aac", sampleRate: 12345, channels: 2))

        // Test unsupported channel count
        XCTAssertFalse(AudioFormatValidator.isSupported(codec: "aac", sampleRate: 44100, channels: 10))
    }

    func testAudioFormatValidatorValidation() {
        // Test valid format
        let validResult = AudioFormatValidator.validate(codec: "aac", sampleRate: 44100, channels: 2, bitRate: 128000)
        XCTAssertTrue(validResult.isValid)
        XCTAssertNil(validResult.error)

        // Test invalid codec
        let invalidCodec = AudioFormatValidator.validate(codec: "xyz", sampleRate: 44100, channels: 2, bitRate: 128000)
        XCTAssertFalse(invalidCodec.isValid)
        XCTAssertNotNil(invalidCodec.error)
        XCTAssertTrue(invalidCodec.error?.contains("Unsupported codec") ?? false)

        // Test invalid sample rate
        let invalidSampleRate = AudioFormatValidator.validate(codec: "aac", sampleRate: 12345, channels: 2, bitRate: 128000)
        XCTAssertFalse(invalidSampleRate.isValid)
        XCTAssertTrue(invalidSampleRate.error?.contains("Unsupported sample rate") ?? false)

        // Test bitrate too low
        let lowBitRate = AudioFormatValidator.validate(codec: "aac", sampleRate: 44100, channels: 2, bitRate: 500)
        XCTAssertFalse(lowBitRate.isValid)
        XCTAssertTrue(lowBitRate.error?.contains("Bitrate too low") ?? false)

        // Test bitrate too high
        let highBitRate = AudioFormatValidator.validate(codec: "aac", sampleRate: 44100, channels: 2, bitRate: 3000000)
        XCTAssertFalse(highBitRate.isValid)
        XCTAssertTrue(highBitRate.error?.contains("Bitrate too high") ?? false)
    }

    func testAudioFormatValidatorQualityScore() {
        // Test high quality score
        let highScore = AudioFormatValidator.calculateQualityScore(sampleRate: 96000, bitRate: 512000, channels: 2)
        XCTAssertGreaterThan(highScore, 0.4)

        // Test medium quality score
        let mediumScore = AudioFormatValidator.calculateQualityScore(sampleRate: 44100, bitRate: 128000, channels: 2)
        XCTAssertGreaterThan(mediumScore, 0.1)
        XCTAssertLessThan(mediumScore, 0.5)

        // Test low quality score
        let lowScore = AudioFormatValidator.calculateQualityScore(sampleRate: 22050, bitRate: 64000, channels: 1)
        XCTAssertLessThan(lowScore, 0.3)

        // Test nil bitrate
        let nilBitRateScore = AudioFormatValidator.calculateQualityScore(sampleRate: 44100, bitRate: nil, channels: 2)
        XCTAssertEqual(nilBitRateScore, 0.5)
    }

    func testOptimalTranscriptionEngineDetection() {
        // High quality format -> Apple SpeechAnalyzer
        let highQualityFormat = AudioFormat(
            codec: "aac",
            sampleRate: 48000,
            channels: 2,
            bitRate: 256000,
            duration: 120.0
        )
        let highQualityResult = AudioFormatValidator.detectOptimalTranscriptionSettings(for: highQualityFormat)
        XCTAssertEqual(highQualityResult.recommendedEngine, "apple-speechanalyzer")
        XCTAssertEqual(highQualityResult.confidence, 0.95)

        // Medium quality format -> OpenAI Whisper
        let mediumQualityFormat = AudioFormat(
            codec: "m4a",
            sampleRate: 22050,
            channels: 1,
            bitRate: 64000,
            duration: 90.0
        )
        let mediumQualityResult = AudioFormatValidator.detectOptimalTranscriptionSettings(for: mediumQualityFormat)
        XCTAssertEqual(mediumQualityResult.recommendedEngine, "openai-whisper")
        XCTAssertEqual(mediumQualityResult.confidence, 0.85)

        // Low quality format -> Rev.ai
        let lowQualityFormat = AudioFormat(
            codec: "mp3",
            sampleRate: 16000,
            channels: 1,
            bitRate: 32000,
            duration: 60.0
        )
        let lowQualityResult = AudioFormatValidator.detectOptimalTranscriptionSettings(for: lowQualityFormat)
        XCTAssertEqual(lowQualityResult.recommendedEngine, "rev-ai")
        XCTAssertEqual(lowQualityResult.confidence, 0.75)

        // Non-transcription-ready format
        let incompatibleFormat = AudioFormat(
            codec: "opus",
            sampleRate: 48000,
            channels: 2,
            bitRate: 128000,
            duration: 60.0
        )
        let incompatibleResult = AudioFormatValidator.detectOptimalTranscriptionSettings(for: incompatibleFormat)
        XCTAssertEqual(incompatibleResult.recommendedEngine, "none")
        XCTAssertEqual(incompatibleResult.confidence, 0.0)
    }

    func testEnhancedCodecSupport() {
        // Test newly added codecs
        XCTAssertTrue(AudioFormatValidator.isSupported(codec: "opus", sampleRate: 48000, channels: 2))
        XCTAssertTrue(AudioFormatValidator.isSupported(codec: "vorbis", sampleRate: 44100, channels: 2))

        // Test additional sample rate
        XCTAssertTrue(AudioFormatValidator.isSupported(codec: "aac", sampleRate: 32000, channels: 2))
    }
}
