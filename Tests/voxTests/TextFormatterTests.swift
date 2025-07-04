import XCTest
@testable import vox

class TextFormatterTests: XCTestCase {
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

    func testConfidenceScoreAnnotation() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.3, // Low confidence
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

        // Should correctly count 5 words, not more due to empty strings from multiple spaces
        XCTAssertTrue(detailedOutput.contains("Total Words: 5"))

        // Test text wrapping with multiple spaces
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

        // Should not have extra spaces in wrapped output
        XCTAssertFalse(wrappedOutput.contains("  ")) // No double spaces
        XCTAssertTrue(wrappedOutput.contains("Hello world with"))
    }

    func testEmptySegmentsHandling() {
        // Test with empty segments array to verify no division-by-zero crash
        let result = TranscriptionResult(
            text: "",
            language: "en-US",
            confidence: 0.0,
            duration: 0.0,
            segments: [], // Empty segments array
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

        // Should not crash and should handle empty segments gracefully
        let basicOutput = formatter.formatAsText(result)
        XCTAssertEqual(basicOutput, "")

        let detailedOutput = formatter.formatAsDetailedText(result)
        XCTAssertTrue(detailedOutput.contains("TRANSCRIPTION REPORT"))
        XCTAssertTrue(detailedOutput.contains("STATISTICS"))
        XCTAssertTrue(detailedOutput.contains("No segments available"))
        XCTAssertTrue(detailedOutput.contains("Segments: 0"))
    }

    func testConfigurableOptionsInOutputFormatter() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.3, // Low confidence
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

        // Test with custom options that enable confidence scores and timestamps
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

            // Should include timestamps, speaker IDs, and confidence scores
            XCTAssertTrue(outputWithOptions.contains("[0.0s]"))
            XCTAssertTrue(outputWithOptions.contains("Speaker1:"))
            XCTAssertTrue(outputWithOptions.contains("[confidence: 30.0%]"))
        } catch {
            XCTFail("Failed to format with custom options: \(error)")
        }

        // Test backward compatibility - default format should not include confidence scores
        do {
            let defaultOutput = try formatter.format(result, as: .txt, includeTimestamps: false)
            XCTAssertFalse(defaultOutput.contains("[confidence:"))
            XCTAssertTrue(defaultOutput.contains("Speaker1:"))
        } catch {
            XCTFail("Failed to format with default options: \(error)")
        }
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
