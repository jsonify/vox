import XCTest
@testable import vox

final class TranscriptionTests: XCTestCase {
    
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
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertEqual(result.confidence, 0.0)
    }
    
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
}