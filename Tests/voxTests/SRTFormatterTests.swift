import XCTest
@testable import vox

class SRTFormatterTests: XCTestCase {
    // MARK: - Test Data

    private func createTestResult() -> TranscriptionResult {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 2.5,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            ),
            TranscriptionSegment(
                text: "This is a test of the SRT formatter",
                startTime: 3.0,
                endTime: 6.8,
                confidence: 0.85,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            ),
            TranscriptionSegment(
                text: "With multiple segments for testing",
                startTime: 7.2,
                endTime: 10.1,
                confidence: 0.92,
                speakerID: "Speaker2",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        return TranscriptionResult(
            text: "Hello world This is a test of the SRT formatter With multiple segments for testing",
            language: "en-US",
            confidence: 0.89,
            duration: 10.1,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 2.3,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 10.1
            )
        )
    }

    // MARK: - SRT Format Compliance Tests

    func testSRTFormatCompliance() throws {
        let result = createTestResult()
        let formatter = OutputFormatter()

        let srtOutput = try formatter.format(result, as: .srt)
        let lines = srtOutput.components(separatedBy: "\n")

        // Test basic SRT structure
        XCTAssertTrue(!lines.isEmpty, "SRT output should not be empty")

        // First subtitle entry
        XCTAssertEqual(lines[0], "1", "First line should be sequence number 1")
        XCTAssertEqual(lines[1], "00:00:00,000 --> 00:00:02,500", "Second line should be timestamp")
        XCTAssertEqual(lines[2], "Hello world", "Third line should be subtitle text")
        XCTAssertEqual(lines[3], "", "Fourth line should be empty")

        // Second subtitle entry
        XCTAssertEqual(lines[4], "2", "Fifth line should be sequence number 2")
        XCTAssertEqual(lines[5], "00:00:03,000 --> 00:00:06,799", "Sixth line should be timestamp")
        XCTAssertEqual(lines[6], "This is a test of the SRT formatter", "Seventh line should be subtitle text")
        XCTAssertEqual(lines[7], "", "Eighth line should be empty")

        // Third subtitle entry
        XCTAssertEqual(lines[8], "3", "Ninth line should be sequence number 3")
        XCTAssertEqual(lines[9], "00:00:07,200 --> 00:00:10,099", "Tenth line should be timestamp")
        XCTAssertEqual(lines[10], "With multiple segments for testing", "Eleventh line should be subtitle text")
        XCTAssertEqual(lines[11], "", "Twelfth line should be empty")
    }

    func testSRTTimeFormatting() throws {
        let result = createTestResult()
        let formatter = OutputFormatter()

        let srtOutput = try formatter.format(result, as: .srt)

        // Test various time formats with correct precision
        XCTAssertTrue(srtOutput.contains("00:00:00,000 --> 00:00:02,500"), "Should format 0.0-2.5 seconds correctly")
        XCTAssertTrue(srtOutput.contains("00:00:03,000 --> 00:00:06,799"), "Should format 3.0-6.8 seconds correctly")
        XCTAssertTrue(srtOutput.contains("00:00:07,200 --> 00:00:10,099"), "Should format 7.2-10.1 seconds correctly")
    }

    func testSRTTimeFormatWithHours() throws {
        let segments = [
            TranscriptionSegment(
                text: "Long video test",
                startTime: 3661.5, // 1:01:01.500
                endTime: 3665.750, // 1:01:05.750
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Long video test",
            language: "en-US",
            confidence: 0.9,
            duration: 3665.750,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 3665.750
            )
        )

        let formatter = OutputFormatter()
        let srtOutput = try formatter.format(result, as: .srt)

        XCTAssertTrue(srtOutput.contains("01:01:01,500 --> 01:01:05,750"), "Should format hours correctly")
    }

    func testSRTSequenceNumbering() throws {
        let result = createTestResult()
        let formatter = OutputFormatter()

        let srtOutput = try formatter.format(result, as: .srt)

        // Check that sequence numbers are correct
        XCTAssertTrue(srtOutput.contains("1\n00:00:00,000"), "First subtitle should have sequence number 1")
        XCTAssertTrue(srtOutput.contains("2\n00:00:03,000"), "Second subtitle should have sequence number 2")
        XCTAssertTrue(srtOutput.contains("3\n00:00:07,200"), "Third subtitle should have sequence number 3")
    }

    func testEmptySegments() throws {
        let segments: [TranscriptionSegment] = []
        let result = TranscriptionResult(
            text: "",
            language: "en-US",
            confidence: 0.0,
            duration: 0.0,
            segments: segments,
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

        let formatter = OutputFormatter()
        let srtOutput = try formatter.format(result, as: .srt)

        XCTAssertEqual(srtOutput, "", "Empty segments should produce empty SRT output")
    }

    func testSingleSegment() throws {
        let segments = [
            TranscriptionSegment(
                text: "Single segment test",
                startTime: 1.0,
                endTime: 3.0,
                confidence: 0.95,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Single segment test",
            language: "en-US",
            confidence: 0.95,
            duration: 3.0,
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
        let srtOutput = try formatter.format(result, as: .srt)

        let expectedOutput = "1\n00:00:01,000 --> 00:00:03,000\nSingle segment test\n\n"
        XCTAssertEqual(srtOutput, expectedOutput, "Single segment should format correctly")
    }

    func testMillisecondPrecision() throws {
        let segments = [
            TranscriptionSegment(
                text: "Precision test",
                startTime: 0.123,
                endTime: 1.456,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]

        let result = TranscriptionResult(
            text: "Precision test",
            language: "en-US",
            confidence: 0.9,
            duration: 1.456,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: 1.456
            )
        )

        let formatter = OutputFormatter()
        let srtOutput = try formatter.format(result, as: .srt)

        XCTAssertTrue(srtOutput.contains("00:00:00,123 --> 00:00:01,455"), "Should handle millisecond precision")
    }

    func testSpecialCharacters() throws {
        let segments = [
            TranscriptionSegment(
                text: "Special chars: àáâãäåæçèéêë & <test> \"quoted\"",
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
            text: "Special chars: àáâãäåæçèéêë & <test> \"quoted\"",
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
                duration: 2.0
            )
        )

        let formatter = OutputFormatter()
        let srtOutput = try formatter.format(result, as: .srt)

        XCTAssertTrue(srtOutput.contains("Special chars: àáâãäåæçèéêë & <test> \"quoted\""), "Should preserve special characters")
    }

    func testSRTFileSaving() throws {
        let result = createTestResult()
        let formatter = OutputFormatter()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_output.srt")
        let tempPath = tempURL.path

        try formatter.saveTranscriptionResult(result, to: tempPath, format: .srt)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), "SRT file should be created")

        let savedContent = try String(contentsOfFile: tempPath, encoding: .utf8)
        let expectedContent = try formatter.format(result, as: .srt)

        XCTAssertEqual(savedContent, expectedContent, "Saved SRT content should match formatted content")

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }
}
