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
}