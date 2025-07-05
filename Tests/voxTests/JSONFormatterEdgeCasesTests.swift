import XCTest
@testable import vox

final class JSONFormatterEdgeCasesTests: XCTestCase {
    // MARK: - Edge Cases Tests

    func testEmptySegmentsHandling() throws {
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

        let formatter = JSONFormatter()
        let jsonString = try formatter.formatAsJSON(result)

        XCTAssertFalse(jsonString.isEmpty)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Should handle empty segments gracefully
        XCTAssertNotNil(parsedData)
        let segments = parsedData?["segments"] as? [[String: Any]]
        XCTAssertTrue(segments?.isEmpty == true)

        let processingStats = parsedData?["processingStats"] as? [String: Any]
        XCTAssertEqual(processingStats?["totalSegments"] as? Int, 0)
        XCTAssertEqual(processingStats?["totalWords"] as? Int, 0)
    }

    func testLowConfidenceSegments() throws {
        let segments = [
            TranscriptionSegment(
                text: "Low confidence text",
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
            text: "Low confidence text",
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
                duration: 1.0
            )
        )

        let formatter = JSONFormatter()
        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let metadata = parsedData?["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["lowConfidenceSegmentCount"] as? Int, 1)
        XCTAssertEqual(metadata?["averageConfidence"] as? Double, 0.3)
    }

    func testVeryLongTranscriptionHandling() throws {
        // Create a very long transcription with many segments
        var segments: [TranscriptionSegment] = []
        let segmentCount = 1000
        
        for index in 0..<segmentCount {
            let segment = TranscriptionSegment(
                text: "Segment \(index) with some test content",
                startTime: Double(index),
                endTime: Double(index + 1),
                confidence: 0.8,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
            segments.append(segment)
        }

        let result = TranscriptionResult(
            text: segments.map { $0.text }.joined(separator: " "),
            language: "en-US",
            confidence: 0.8,
            duration: Double(segmentCount),
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 10.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: 256000,
                duration: Double(segmentCount)
            )
        )

        let formatter = JSONFormatter()
        let jsonString = try formatter.formatAsJSON(result)

        XCTAssertFalse(jsonString.isEmpty)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let parsedSegments = parsedData?["segments"] as? [[String: Any]]
        XCTAssertEqual(parsedSegments?.count, segmentCount)

        let processingStats = parsedData?["processingStats"] as? [String: Any]
        XCTAssertEqual(processingStats?["totalSegments"] as? Int, segmentCount)
    }

    func testMalformedAudioFormatHandling() throws {
        let result = TranscriptionResult(
            text: "Test transcription",
            language: "en-US",
            confidence: 0.8,
            duration: 1.0,
            segments: [],
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "unknown",
                sampleRate: 0,
                channels: 0,
                bitRate: nil,
                duration: 1.0,
                fileSize: nil,
                isValid: false,
                validationError: "Invalid audio format"
            )
        )

        let formatter = JSONFormatter()
        
        // Should not throw even with malformed audio format
        XCTAssertNoThrow {
            let jsonString = try formatter.formatAsJSON(result)
            XCTAssertFalse(jsonString.isEmpty)
        }
    }

    func testNilAndOptionalValueHandling() throws {
        let segments = [
            TranscriptionSegment(
                text: "Test segment",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.8,
                speakerID: nil, // Test nil speaker ID
                words: nil, // Test nil word timing
                segmentType: .speech,
                pauseDuration: nil // Test nil pause duration
            )
        ]

        let result = TranscriptionResult(
            text: "Test segment",
            language: "en-US",
            confidence: 0.8,
            duration: 1.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 16000,
                channels: 1,
                bitRate: nil, // Test nil bit rate
                duration: 1.0,
                fileSize: nil // Test nil file size
            )
        )

        let formatter = JSONFormatter()
        let jsonString = try formatter.formatAsJSON(result)

        XCTAssertFalse(jsonString.isEmpty)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        
        // Should parse successfully even with nil values
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(parsedData)
    }
}
