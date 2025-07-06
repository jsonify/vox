import XCTest
@testable import vox

class TextFormatterTests: XCTestCase {
    // Basic setup or shared test utilities can go here
}

// MARK: - Basic Text Formatting Tests
extension TextFormatterTests {
    func testBasicTextFormatting() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            ),
            TranscriptionSegment(
                text: "This is a test",
                startTime: 1.5,
                endTime: 3.0,
                confidence: 0.8,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Hello world This is a test",
            language: "en-US",
            confidence: 0.85,
            duration: 3.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.2,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3.0
            )
        )

        let options = TextFormattingOptions(
            includeTimestamps: false,
            includeSpeakerIDs: true,
            includeConfidenceScores: false,
            paragraphBreakThreshold: 2.0,
            sentenceBreakThreshold: 0.8,
            timestampFormat: .hms,
            confidenceThreshold: 0.5,
            lineWidth: 80
        )
        let formatter = TextFormatter(options: options)
        let output = formatter.formatAsText(result)

        XCTAssertTrue(output.contains("Hello world"))
        XCTAssertTrue(output.contains("This is a test"))
        XCTAssertTrue(output.contains("Speaker1:"))
    }

    func testMultipleSpacesHandling() {
        let segments = [
            TranscriptionSegment(
                text: "Hello    world   with    multiple     spaces",
                startTime: 0.0,
                endTime: 2.0,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Hello    world   with    multiple     spaces",
            language: "en-US",
            confidence: 0.9,
            duration: 2.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3.0
            )
        )

        let formatter = TextFormatter()
        let detailedOutput = formatter.formatAsDetailedText(result)

        XCTAssertTrue(detailedOutput.contains("Total Words: 5"))

        let options = TextFormattingOptions(
            includeTimestamps: false,
            includeSpeakerIDs: false,
            includeConfidenceScores: false,
            paragraphBreakThreshold: 2.0,
            sentenceBreakThreshold: 0.8,
            timestampFormat: .hms,
            confidenceThreshold: 0.5,
            lineWidth: 20
        )
        let formatterWithWrapping = TextFormatter(options: options)
        let wrappedOutput = formatterWithWrapping.formatAsText(result)

        XCTAssertFalse(wrappedOutput.contains("  "))
        XCTAssertTrue(wrappedOutput.contains("Hello world with"))
    }
}

// MARK: - Speaker & Timestamp Tests
extension TextFormatterTests {
    func testTimestampFormatting() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Hello world",
            language: "en-US",
            confidence: 0.9,
            duration: 1.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3.0
            )
        )

        let options = TextFormattingOptions(
            includeTimestamps: true,
            includeSpeakerIDs: true,
            includeConfidenceScores: false,
            paragraphBreakThreshold: 2.0,
            sentenceBreakThreshold: 0.8,
            timestampFormat: .hms,
            confidenceThreshold: 0.5,
            lineWidth: 80
        )

        let formatter = TextFormatter(options: options)
        let output = formatter.formatAsText(result)

        XCTAssertTrue(output.contains("[00:00]"))
        XCTAssertTrue(output.contains("Speaker1:"))
    }

    func testSpeakerIdentification() {
        let segments = [
            TranscriptionSegment(
                text: "Hello",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            ),
            TranscriptionSegment(
                text: "Hi there",
                startTime: 4.0,
                endTime: 5.0,
                confidence: 0.8,
                speakerID: "Speaker2",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Hello Hi there",
            language: "en-US",
            confidence: 0.85,
            duration: 5.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3.0
            )
        )

        let options = TextFormattingOptions(
            includeTimestamps: false,
            includeSpeakerIDs: true,
            includeConfidenceScores: false,
            paragraphBreakThreshold: 2.0,
            sentenceBreakThreshold: 0.8,
            timestampFormat: .hms,
            confidenceThreshold: 0.5,
            lineWidth: 80
        )

        let formatter = TextFormatter(options: options)
        let output = formatter.formatAsText(result)

        XCTAssertTrue(output.contains("Speaker1: Hello"))
        XCTAssertTrue(output.contains("Speaker2: Hi there"))
    }
}

// MARK: - Configuration & Options Tests
extension TextFormatterTests {
    func testConfigurableOptionsInOutputFormatter() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.3,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Hello world",
            language: "en-US",
            confidence: 0.3,
            duration: 1.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3.0
            )
        )

        let formatter = OutputFormatter()

        let customOptions = TextFormattingOptions(
            includeTimestamps: true,
            includeSpeakerIDs: true,
            includeConfidenceScores: true,
            paragraphBreakThreshold: 2.0,
            sentenceBreakThreshold: 0.8,
            timestampFormat: .seconds,
            confidenceThreshold: 0.5,
            lineWidth: 40
        )

        do {
            let outputWithOptions = try formatter.format(result, as: .txt, options: customOptions)
            XCTAssertTrue(outputWithOptions.contains("[0.0s]"))
            XCTAssertTrue(outputWithOptions.contains("Speaker1:"))
            XCTAssertTrue(outputWithOptions.contains("[confidence: 30.0%]"))
        } catch {
            XCTFail("Failed to format with custom options: \(error)")
        }

        do {
            let defaultOutput = try formatter.format(result, as: .txt, includeTimestamps: false)
            XCTAssertFalse(defaultOutput.contains("[confidence:"))
            XCTAssertTrue(defaultOutput.contains("Speaker1:"))
        } catch {
            XCTFail("Failed to format with default options: \(error)")
        }
    }

    func testConfidenceScoreAnnotation() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.3,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Hello world",
            language: "en-US",
            confidence: 0.3,
            duration: 1.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3.0
            )
        )

        let options = TextFormattingOptions(
            includeTimestamps: false,
            includeSpeakerIDs: true,
            includeConfidenceScores: true,
            paragraphBreakThreshold: 2.0,
            sentenceBreakThreshold: 0.8,
            timestampFormat: .hms,
            confidenceThreshold: 0.5,
            lineWidth: 80
        )

        let formatter = TextFormatter(options: options)
        let output = formatter.formatAsText(result)

        XCTAssertTrue(output.contains("[confidence: 30.0%]"))
    }
}

// MARK: - Edge Cases & Validation Tests
extension TextFormatterTests {
    func testEmptySegmentsHandling() {
        let result = TranscriptionResult(
            text: "",
            language: "en-US",
            confidence: 0.0,
            duration: 0.0,
            segments: [],
            engine: .speechAnalyzer,
            processingTime: 0.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 0.0
            )
        )

        let formatter = TextFormatter()

        let basicOutput = formatter.formatAsText(result)
        XCTAssertEqual(basicOutput, "")

        let detailedOutput = formatter.formatAsDetailedText(result)
        XCTAssertTrue(detailedOutput.contains("TRANSCRIPTION REPORT"))
        XCTAssertTrue(detailedOutput.contains("STATISTICS"))
        XCTAssertTrue(detailedOutput.contains("No segments available"))
        XCTAssertTrue(detailedOutput.contains("Segments: 0"))
    }

    func testDetailedTextFormatting() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Hello world",
            language: "en-US",
            confidence: 0.9,
            duration: 1.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3.0
            )
        )

        let formatter = TextFormatter()
        let output = formatter.formatAsDetailedText(result)

        XCTAssertTrue(output.contains("TRANSCRIPTION REPORT"))
        XCTAssertTrue(output.contains("Duration: 00:01"))
        XCTAssertTrue(output.contains("Language: en-US"))
        XCTAssertTrue(output.contains("STATISTICS"))
        XCTAssertTrue(output.contains("Total Words:"))
    }
}

// MARK: - Extended Test Cases
extension TextFormatterTests {
    func testTextFormatterExtended() {
        // Test placeholder for future expansion
        XCTAssertTrue(true)
    }
}
