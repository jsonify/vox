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
        
        XCTAssertEqual(segment.startTime, segment.endTime, accuracy: 0.001)
        XCTAssertEqual(segment.startTime, 5.0, accuracy: 0.001)
        XCTAssertEqual(segment.duration, 0.0, accuracy: 0.001)
    }
    
    // MARK: - Enhanced Timing Features Tests
    
    func testTranscriptionSegmentWithWordTimings() {
        let wordTiming = WordTiming(word: "Hello", startTime: 0.0, endTime: 0.5, confidence: 0.9)
        
        let segment = TranscriptionSegment(
            text: "Hello",
            startTime: 0.0,
            endTime: 0.5,
            confidence: 0.9,
            speakerID: "Speaker1",
            words: wordTiming,
            segmentType: .speech
        )
        
        XCTAssertNotNil(segment.words)
        XCTAssertEqual(segment.words?.word, "Hello")
        XCTAssertEqual(segment.words?.duration ?? 0.0, 0.5, accuracy: 0.001)
        XCTAssertEqual(segment.segmentType, .speech)
    }
    
    func testTranscriptionSegmentWithSentenceBoundary() {
        let segment = TranscriptionSegment(
            text: "This is a complete sentence.",
            startTime: 0.0,
            endTime: 3.0,
            confidence: 0.9,
            segmentType: .sentenceBoundary
        )
        
        XCTAssertTrue(segment.isSentenceBoundary)
        XCTAssertEqual(segment.segmentType, .sentenceBoundary)
    }
    
    func testTranscriptionSegmentWithSpeakerChange() {
        let segment = TranscriptionSegment(
            text: "Now a different person speaks",
            startTime: 5.0,
            endTime: 8.0,
            confidence: 0.8,
            speakerID: "Speaker2",
            segmentType: .speakerChange,
            pauseDuration: 2.5
        )
        
        XCTAssertTrue(segment.hasSpeakerChange)
        XCTAssertEqual(segment.speakerID, "Speaker2")
        XCTAssertEqual(segment.pauseDuration ?? 0.0, 2.5, accuracy: 0.001)
    }
    
    func testTranscriptionSegmentWithSilenceGap() {
        let segment = TranscriptionSegment(
            text: "",
            startTime: 10.0,
            endTime: 12.0,
            confidence: 0.0,
            segmentType: .silence,
            pauseDuration: 2.0
        )
        
        XCTAssertTrue(segment.hasSilenceGap)
        XCTAssertEqual(segment.segmentType, .silence)
    }
    
    func testTranscriptionSegmentParagraphBoundary() {
        let segment = TranscriptionSegment(
            text: "End of paragraph.",
            startTime: 15.0,
            endTime: 18.0,
            confidence: 0.85,
            segmentType: .paragraphBoundary,
            pauseDuration: 1.8
        )
        
        XCTAssertTrue(segment.isParagraphBoundary)
        XCTAssertTrue(segment.isSentenceBoundary) // Should also be sentence boundary
        XCTAssertEqual(segment.pauseDuration ?? 0.0, 1.8, accuracy: 0.001)
    }
    
    // MARK: - WordTiming Tests
    
    func testWordTimingCreation() {
        let wordTiming = WordTiming(
            word: "example",
            startTime: 1.0,
            endTime: 1.7,
            confidence: 0.92
        )
        
        XCTAssertEqual(wordTiming.word, "example")
        XCTAssertEqual(wordTiming.startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(wordTiming.endTime, 1.7, accuracy: 0.001)
        XCTAssertEqual(wordTiming.duration, 0.7, accuracy: 0.001)
        XCTAssertEqual(wordTiming.confidence, 0.92, accuracy: 0.001)
    }
    
    // MARK: - SegmentType Tests
    
    func testSegmentTypeValues() {
        XCTAssertEqual(SegmentType.speech.rawValue, "speech")
        XCTAssertEqual(SegmentType.silence.rawValue, "silence")
        XCTAssertEqual(SegmentType.sentenceBoundary.rawValue, "sentence_boundary")
        XCTAssertEqual(SegmentType.paragraphBoundary.rawValue, "paragraph_boundary")
        XCTAssertEqual(SegmentType.speakerChange.rawValue, "speaker_change")
        XCTAssertEqual(SegmentType.backgroundNoise.rawValue, "background_noise")
    }
    
    func testSegmentTypeAllCases() {
        let allCases = SegmentType.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.speech))
        XCTAssertTrue(allCases.contains(.silence))
        XCTAssertTrue(allCases.contains(.sentenceBoundary))
        XCTAssertTrue(allCases.contains(.paragraphBoundary))
        XCTAssertTrue(allCases.contains(.speakerChange))
        XCTAssertTrue(allCases.contains(.backgroundNoise))
    }
}