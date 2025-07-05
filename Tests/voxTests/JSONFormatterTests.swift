import XCTest
@testable import vox

final class JSONFormatterTests: XCTestCase {
    // MARK: - Test Data Setup

    func createTestTranscriptionResult() -> TranscriptionResult {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0.0,
                endTime: 1.0,
                confidence: 0.9,
                speakerID: "Speaker1",
                words: WordTiming(word: "Hello", startTime: 0.0, endTime: 0.5, confidence: 0.95),
                segmentType: .speech,
                pauseDuration: nil
            ),
            TranscriptionSegment(
                text: "This is a test",
                startTime: 2.0,
                endTime: 4.0,
                confidence: 0.8,
                speakerID: "Speaker2",
                words: WordTiming(word: "This", startTime: 2.0, endTime: 2.3, confidence: 0.85),
                segmentType: .speech,
                pauseDuration: 1.0
            )
        ]

        return TranscriptionResult(
            text: "Hello world This is a test",
            language: "en-US",
            confidence: 0.85,
            duration: 4.0,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 2.5,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 44100,
                channels: 2,
                bitRate: 256000,
                duration: 4.0,
                fileSize: 1024000,
                isValid: true,
                validationError: nil
            )
        )
    }

    // MARK: - Basic JSON Formatting Tests

    func testBasicJSONFormatting() throws {
        let result = createTestTranscriptionResult()
        let formatter = JSONFormatter()

        let jsonString = try formatter.formatAsJSON(result)

        XCTAssertFalse(jsonString.isEmpty)
        XCTAssertTrue(jsonString.contains("\"transcription\""))
        XCTAssertTrue(jsonString.contains("\"text\" : \"Hello world This is a test\""))
        XCTAssertTrue(jsonString.contains("\"language\" : \"en-US\""))
        XCTAssertTrue(jsonString.contains("\"confidence\" : 0.85"))
        XCTAssertTrue(jsonString.contains("\"duration\" : 4"))
        XCTAssertTrue(jsonString.contains("\"metadata\""))
        XCTAssertTrue(jsonString.contains("\"audioInformation\""))
        XCTAssertTrue(jsonString.contains("\"processingStats\""))
        XCTAssertTrue(jsonString.contains("\"segments\""))
    }

    func testJSONStructureValidity() throws {
        let result = createTestTranscriptionResult()
        let formatter = JSONFormatter()

        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }

        // Verify that the JSON can be parsed back
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(parsedData)

        // Verify root structure
        XCTAssertNotNil(parsedData?["transcription"])
        XCTAssertNotNil(parsedData?["metadata"])
        XCTAssertNotNil(parsedData?["audioInformation"])
        XCTAssertNotNil(parsedData?["processingStats"])
        XCTAssertNotNil(parsedData?["segments"])
        XCTAssertNotNil(parsedData?["generatedAt"])
        XCTAssertNotNil(parsedData?["version"])
        XCTAssertNotNil(parsedData?["format"])
    }

    // MARK: - Metadata Tests

    func testMetadataInclusion() throws {
        let result = createTestTranscriptionResult()
        let formatter = JSONFormatter()

        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let metadata = parsedData?["metadata"] as? [String: Any]
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?["engine"] as? String, "apple-speechanalyzer")
        XCTAssertEqual(metadata?["speakerCount"] as? Int, 2)
        XCTAssertEqual(metadata?["processingTime"] as? Double, 2.5)
        XCTAssertNotNil(metadata?["averageConfidence"])
        XCTAssertNotNil(metadata?["qualityScore"])
    }

    func testAudioInformationInclusion() throws {
        let result = createTestTranscriptionResult()
        let formatter = JSONFormatter()

        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let audioInfo = parsedData?["audioInformation"] as? [String: Any]
        XCTAssertNotNil(audioInfo)
        XCTAssertEqual(audioInfo?["codec"] as? String, "wav")
        XCTAssertEqual(audioInfo?["sampleRate"] as? Int, 44100)
        XCTAssertEqual(audioInfo?["channels"] as? Int, 2)
        XCTAssertEqual(audioInfo?["bitRate"] as? Int, 256000)
        XCTAssertEqual(audioInfo?["isValid"] as? Bool, true)
        XCTAssertNotNil(audioInfo?["quality"])
    }

    func testProcessingStatsInclusion() throws {
        let result = createTestTranscriptionResult()
        let formatter = JSONFormatter()

        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let processingStats = parsedData?["processingStats"] as? [String: Any]
        XCTAssertNotNil(processingStats)
        XCTAssertEqual(processingStats?["processingTime"] as? Double, 2.5)
        XCTAssertEqual(processingStats?["totalSegments"] as? Int, 2)
        XCTAssertNotNil(processingStats?["processingRate"])
        XCTAssertNotNil(processingStats?["totalWords"])
        XCTAssertNotNil(processingStats?["averageSegmentLength"])
    }

    // MARK: - Segment Details Tests

    func testSegmentDetailsInclusion() throws {
        let result = createTestTranscriptionResult()
        let formatter = JSONFormatter()

        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let segments = parsedData?["segments"] as? [[String: Any]]
        XCTAssertNotNil(segments)
        XCTAssertEqual(segments?.count, 2)

        let firstSegment = segments?[0]
        XCTAssertEqual(firstSegment?["text"] as? String, "Hello world")
        XCTAssertEqual(firstSegment?["startTime"] as? Double, 0.0)
        XCTAssertEqual(firstSegment?["endTime"] as? Double, 1.0)
        XCTAssertEqual(firstSegment?["confidence"] as? Double, 0.9)
        XCTAssertEqual(firstSegment?["speakerID"] as? String, "Speaker1")
        XCTAssertEqual(firstSegment?["segmentType"] as? String, "speech")
        XCTAssertNotNil(firstSegment?["wordTiming"])
        XCTAssertNotNil(firstSegment?["wordCount"])
    }

    func testWordTimingInclusion() throws {
        let result = createTestTranscriptionResult()
        let formatter = JSONFormatter()

        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let segments = parsedData?["segments"] as? [[String: Any]]
        let firstSegment = segments?[0]
        let wordTiming = firstSegment?["wordTiming"] as? [String: Any]

        XCTAssertNotNil(wordTiming)
        XCTAssertEqual(wordTiming?["word"] as? String, "Hello")
        XCTAssertEqual(wordTiming?["startTime"] as? Double, 0.0)
        XCTAssertEqual(wordTiming?["endTime"] as? Double, 0.5)
        XCTAssertEqual(wordTiming?["confidence"] as? Double, 0.95)
    }

    // MARK: - Configuration Options Tests

    func testCustomJSONFormattingOptions() throws {
        let result = createTestTranscriptionResult()
        let options = JSONFormatter.JSONFormattingOptions(
            includeMetadata: false,
            includeProcessingStats: false,
            includeSegmentDetails: false,
            includeAudioInformation: false,
            includeWordTimings: false,
            includeConfidenceScores: false,
            prettyPrint: false,
            dateFormat: .timestamp
        )
        let formatter = JSONFormatter(options: options)

        let jsonString = try formatter.formatAsJSON(result)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        // Should not include optional sections
        XCTAssertNil(parsedData?["metadata"])
        XCTAssertNil(parsedData?["processingStats"])
        XCTAssertNil(parsedData?["segments"])
        XCTAssertNil(parsedData?["audioInformation"])

        // Should still include core transcription data
        XCTAssertNotNil(parsedData?["transcription"])
        XCTAssertNotNil(parsedData?["generatedAt"])
        XCTAssertNotNil(parsedData?["version"])
        XCTAssertNotNil(parsedData?["format"])
    }

    func testCompactJSONFormatting() throws {
        let result = createTestTranscriptionResult()
        let options = JSONFormatter.JSONFormattingOptions(
            includeMetadata: true,
            includeProcessingStats: true,
            includeSegmentDetails: true,
            includeAudioInformation: true,
            includeWordTimings: true,
            includeConfidenceScores: true,
            prettyPrint: false,
            dateFormat: .iso8601
        )
        let formatter = JSONFormatter(options: options)

        let jsonString = try formatter.formatAsJSON(result)

        // Compact formatting should not contain extra whitespace
        XCTAssertFalse(jsonString.contains("  "))
        XCTAssertFalse(jsonString.contains("\n"))
        XCTAssertTrue(jsonString.contains("{"))
        XCTAssertTrue(jsonString.contains("}"))
    }
}
