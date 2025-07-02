import XCTest
@testable import vox

final class ModelsTests: XCTestCase {
    
    // MARK: - TranscriptionResult Tests
    
    func testTranscriptionResultCreation() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 2.0,
                confidence: 0.9,
                speakerID: "speaker1"
            )
        ]
        
        let audioFormat = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 120.0
        )
        
        let result = TranscriptionResult(
            text: "Hello world from audio",
            language: "en-US",
            confidence: 0.95,
            duration: 120.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 5.0,
            audioFormat: audioFormat
        )
        
        XCTAssertEqual(result.text, "Hello world from audio")
        XCTAssertEqual(result.language, "en-US")
        XCTAssertEqual(result.confidence, 0.95)
        XCTAssertEqual(result.duration, 120.0)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.engine, .speechAnalyzer)
        XCTAssertEqual(result.processingTime, 5.0)
        XCTAssertEqual(result.audioFormat.codec, "m4a")
    }
    
    // MARK: - TranscriptionSegment Tests
    
    func testTranscriptionSegmentCreation() {
        let segment = TranscriptionSegment(
            text: "Test segment",
            startTime: 1.5,
            endTime: 3.2,
            confidence: 0.87,
            speakerID: "speaker2"
        )
        
        XCTAssertEqual(segment.text, "Test segment")
        XCTAssertEqual(segment.startTime, 1.5)
        XCTAssertEqual(segment.endTime, 3.2)
        XCTAssertEqual(segment.confidence, 0.87)
        XCTAssertEqual(segment.speakerID, "speaker2")
    }
    
    func testTranscriptionSegmentWithoutSpeaker() {
        let segment = TranscriptionSegment(
            text: "No speaker segment",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.95,
            speakerID: nil
        )
        
        XCTAssertEqual(segment.text, "No speaker segment")
        XCTAssertNil(segment.speakerID)
    }
    
    // MARK: - TranscriptionEngine Tests
    
    func testTranscriptionEngineValues() {
        XCTAssertEqual(TranscriptionEngine.speechAnalyzer.rawValue, "apple-speechanalyzer")
        XCTAssertEqual(TranscriptionEngine.openaiWhisper.rawValue, "openai-whisper")
        XCTAssertEqual(TranscriptionEngine.revai.rawValue, "rev-ai")
    }
    
    func testTranscriptionEngineAllCases() {
        let allCases = TranscriptionEngine.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.speechAnalyzer))
        XCTAssertTrue(allCases.contains(.openaiWhisper))
        XCTAssertTrue(allCases.contains(.revai))
    }
    
    // MARK: - AudioFormat Tests
    
    func testAudioFormatCreation() {
        let format = AudioFormat(
            codec: "mp4",
            sampleRate: 48000,
            channels: 2,
            bitRate: 256000,
            duration: 180.5
        )
        
        XCTAssertEqual(format.codec, "mp4")
        XCTAssertEqual(format.sampleRate, 48000)
        XCTAssertEqual(format.channels, 2)
        XCTAssertEqual(format.bitRate, 256000)
        XCTAssertEqual(format.duration, 180.5)
        XCTAssertTrue(format.isValid)
        XCTAssertNil(format.validationError)
        XCTAssertEqual(format.quality, .high)
    }
    
    func testAudioFormatWithoutBitRate() {
        let format = AudioFormat(
            codec: "wav",
            sampleRate: 44100,
            channels: 1,
            bitRate: nil,
            duration: 60.0
        )
        
        XCTAssertEqual(format.codec, "wav")
        XCTAssertEqual(format.channels, 1)
        XCTAssertNil(format.bitRate)
        XCTAssertEqual(format.quality, .medium)
    }
    
    func testAudioFormatWithFileSize() {
        let format = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 120.0,
            fileSize: 1920000 // 1.92MB
        )
        
        XCTAssertEqual(format.fileSize, 1920000)
        XCTAssertTrue(format.description.contains("1.9 MB"))
    }
    
    func testAudioFormatValidationFailed() {
        let format = AudioFormat(
            codec: "unsupported",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 60.0,
            isValid: false,
            validationError: "Unsupported codec: unsupported"
        )
        
        XCTAssertFalse(format.isValid)
        XCTAssertEqual(format.validationError, "Unsupported codec: unsupported")
        XCTAssertFalse(format.isCompatible)
    }
    
    func testAudioFormatDescription() {
        let format = AudioFormat(
            codec: "aac",
            sampleRate: 48000,
            channels: 2,
            bitRate: 256000,
            duration: 123.45,
            fileSize: 4000000
        )
        
        let description = format.description
        XCTAssertTrue(description.contains("AAC"))
        XCTAssertTrue(description.contains("48000Hz"))
        XCTAssertTrue(description.contains("2ch"))
        XCTAssertTrue(description.contains("256 kbps"))
        XCTAssertTrue(description.contains("123.5s"))
        XCTAssertTrue(description.contains("MB"))
    }
    
    // MARK: - AudioFile Tests
    
    func testAudioFileCreation() {
        let format = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 300.0
        )
        
        let audioFile = AudioFile(
            path: "/path/to/input.mp4",
            format: format,
            temporaryPath: "/tmp/temp_audio.m4a"
        )
        
        XCTAssertEqual(audioFile.path, "/path/to/input.mp4")
        XCTAssertEqual(audioFile.format.codec, "m4a")
        XCTAssertEqual(audioFile.temporaryPath, "/tmp/temp_audio.m4a")
    }
    
    func testAudioFileWithoutTempPath() {
        let format = AudioFormat(
            codec: "wav",
            sampleRate: 22050,
            channels: 1,
            bitRate: 64000,
            duration: 120.0
        )
        
        let audioFile = AudioFile(
            path: "/path/to/audio.wav",
            format: format,
            temporaryPath: nil
        )
        
        XCTAssertEqual(audioFile.path, "/path/to/audio.wav")
        XCTAssertNil(audioFile.temporaryPath)
    }
    
    // MARK: - VoxError Tests
    
    func testVoxErrorDescriptions() {
        let invalidFileError = VoxError.invalidInputFile("/nonexistent/file.mp4")
        XCTAssertEqual(invalidFileError.errorDescription, "Invalid input file: /nonexistent/file.mp4")
        
        let audioError = VoxError.audioExtractionFailed("Codec not supported")
        XCTAssertEqual(audioError.errorDescription, "Audio extraction failed: Codec not supported")
        
        let transcriptionError = VoxError.transcriptionFailed("Network timeout")
        XCTAssertEqual(transcriptionError.errorDescription, "Transcription failed: Network timeout")
        
        let outputError = VoxError.outputWriteFailed("Permission denied")
        XCTAssertEqual(outputError.errorDescription, "Failed to write output: Permission denied")
        
        let apiKeyError = VoxError.apiKeyMissing("OpenAI")
        XCTAssertEqual(apiKeyError.errorDescription, "API key missing for OpenAI")
        
        let formatError = VoxError.unsupportedFormat("avi")
        XCTAssertEqual(formatError.errorDescription, "Unsupported format: avi")
    }
    
    func testVoxErrorLocalizedDescription() {
        let error = VoxError.audioExtractionFailed("Test reason")
        XCTAssertEqual(error.localizedDescription, "Audio extraction failed: Test reason")
    }
    
    // MARK: - OutputFormat Tests
    
    func testOutputFormatValues() {
        XCTAssertEqual(OutputFormat.txt.rawValue, "txt")
        XCTAssertEqual(OutputFormat.srt.rawValue, "srt")
        XCTAssertEqual(OutputFormat.json.rawValue, "json")
    }
    
    func testOutputFormatAllCases() {
        let allCases = OutputFormat.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.txt))
        XCTAssertTrue(allCases.contains(.srt))
        XCTAssertTrue(allCases.contains(.json))
    }
    
    func testOutputFormatDefaultValue() {
        let format = OutputFormat.txt
        XCTAssertEqual(format.defaultValueDescription, "txt")
    }
    
    // MARK: - FallbackAPI Tests
    
    func testFallbackAPIValues() {
        XCTAssertEqual(FallbackAPI.openai.rawValue, "openai")
        XCTAssertEqual(FallbackAPI.revai.rawValue, "revai")
    }
    
    func testFallbackAPIAllCases() {
        let allCases = FallbackAPI.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.openai))
        XCTAssertTrue(allCases.contains(.revai))
    }
    
    // MARK: - Edge Cases and Error Conditions
    
    func testTranscriptionSegmentWithZeroDuration() {
        let segment = TranscriptionSegment(
            text: "Instant",
            startTime: 5.0,
            endTime: 5.0,
            confidence: 1.0,
            speakerID: nil
        )
        
        XCTAssertEqual(segment.startTime, segment.endTime)
        XCTAssertEqual(segment.startTime, 5.0)
    }
    
    func testAudioFormatWithZeroDuration() {
        let format = AudioFormat(
            codec: "silence",
            sampleRate: 44100,
            channels: 1,
            bitRate: 0,
            duration: 0.0
        )
        
        XCTAssertEqual(format.duration, 0.0)
        XCTAssertEqual(format.bitRate, 0)
    }
    
    func testTranscriptionResultWithEmptySegments() {
        let audioFormat = AudioFormat(
            codec: "test",
            sampleRate: 44100,
            channels: 1,
            bitRate: 128000,
            duration: 0.0
        )
        
        let result = TranscriptionResult(
            text: "",
            language: "en-US",
            confidence: 0.0,
            duration: 0.0,
            segments: [],
            engine: .speechAnalyzer,
            processingTime: 0.1,
            audioFormat: audioFormat
        )
        
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.confidence, 0.0)
    }
    
    func testVoxErrorEquality() {
        let error1 = VoxError.invalidInputFile("test.mp4")
        let error2 = VoxError.invalidInputFile("test.mp4")
        
        // Note: VoxError doesn't conform to Equatable, but we can test error descriptions
        XCTAssertEqual(error1.errorDescription, error2.errorDescription)
    }
    
    func testNewVoxErrorTypes() {
        let validationError = VoxError.audioFormatValidationFailed("Invalid sample rate")
        XCTAssertEqual(validationError.errorDescription, "Audio format validation failed: Invalid sample rate")
        
        let compatibilityError = VoxError.incompatibleAudioProperties("Unsupported channel configuration")
        XCTAssertEqual(compatibilityError.errorDescription, "Incompatible audio properties: Unsupported channel configuration")
    }
    
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
    
    // MARK: - Enhanced Audio Format Tests
    
    func testAudioFormatTranscriptionCompatibility() {
        // Test transcription-ready formats
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "aac"))
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "m4a"))
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "wav"))
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "mp3"))
        
        // Test non-transcription-ready formats  
        XCTAssertFalse(AudioFormatValidator.isTranscriptionCompatible(codec: "opus"))
        XCTAssertFalse(AudioFormatValidator.isTranscriptionCompatible(codec: "vorbis"))
        XCTAssertFalse(AudioFormatValidator.isTranscriptionCompatible(codec: "unknown"))
    }
    
    func testAudioFormatIsTranscriptionReady() {
        // Valid and transcription-compatible format
        let readyFormat = AudioFormat(
            codec: "aac",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 60.0
        )
        XCTAssertTrue(readyFormat.isTranscriptionReady)
        
        // Valid but not transcription-compatible format
        let notReadyFormat = AudioFormat(
            codec: "opus", 
            sampleRate: 48000,
            channels: 2,
            bitRate: 128000,
            duration: 60.0,
            isValid: true
        )
        XCTAssertFalse(notReadyFormat.isTranscriptionReady)
        
        // Invalid format
        let invalidFormat = AudioFormat(
            codec: "aac",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 60.0,
            isValid: false
        )
        XCTAssertFalse(invalidFormat.isTranscriptionReady)
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