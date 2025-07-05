import XCTest
@testable import vox

final class JSONFormatterIntegrationTests: XCTestCase {
    // MARK: - Integration Tests

    func testOutputFormatterIntegration() throws {
        let result = createTestTranscriptionResult()
        let formatter = OutputFormatter()

        let jsonOutput = try formatter.format(result, as: .json)

        XCTAssertFalse(jsonOutput.isEmpty)
        XCTAssertTrue(jsonOutput.contains("\"transcription\""))
        XCTAssertTrue(jsonOutput.contains("\"metadata\""))
        XCTAssertTrue(jsonOutput.contains("\"audioInformation\""))
        XCTAssertTrue(jsonOutput.contains("\"processingStats\""))
        XCTAssertTrue(jsonOutput.contains("\"segments\""))
    }

    func testCustomJSONOptionsIntegration() throws {
        let result = createTestTranscriptionResult()
        let formatter = OutputFormatter()

        let jsonOptions = JSONFormatter.JSONFormattingOptions(
            includeMetadata: true,
            includeProcessingStats: true,
            includeSegmentDetails: true,
            includeAudioInformation: true,
            includeWordTimings: false,
            includeConfidenceScores: false,
            prettyPrint: false,
            dateFormat: .timestamp
        )

        let jsonOutput = try formatter.format(result, as: .json, jsonOptions: jsonOptions)

        XCTAssertFalse(jsonOutput.isEmpty)
        XCTAssertTrue(jsonOutput.contains("\"transcription\""))
        XCTAssertFalse(jsonOutput.contains("  ")) // Should be compact
    }

    // MARK: - Quality Score Tests

    func testLosslessAudioQualityScore() throws {
        let losslessResult = TranscriptionResult(
            text: "Lossless audio transcription",
            language: "en-US",
            confidence: 0.95,
            duration: 1.0,
            segments: [
                TranscriptionSegment(
                    text: "Lossless audio transcription",
                    startTime: 0.0,
                    endTime: 1.0,
                    confidence: 0.95,
                    speakerID: "Speaker1",
                    words: nil,
                    segmentType: .speech,
                    pauseDuration: nil
                )
            ],
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 192000,
                channels: 2,
                bitRate: 1411000,
                duration: 1.0
            )
        )

        let formatter = JSONFormatter()
        let jsonString = try formatter.formatAsJSON(losslessResult)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let metadata = parsedData?["metadata"] as? [String: Any]
        let qualityScore = metadata?["qualityScore"] as? Double

        XCTAssertNotNil(qualityScore)
        // Should have high quality score: confidence(0.95 * 0.4) + audio(0.3) + completeness(0.3) = 0.98
        guard let score = qualityScore else {
            XCTFail("Quality score should not be nil")
            return
        }
        XCTAssertEqual(score, 0.98, accuracy: 0.01)
    }

    func testQualityScoreCalculation() throws {
        let highQualityResult = TranscriptionResult(
            text: "High quality transcription",
            language: "en-US",
            confidence: 0.95,
            duration: 1.0,
            segments: [
                TranscriptionSegment(
                    text: "High quality transcription",
                    startTime: 0.0,
                    endTime: 1.0,
                    confidence: 0.95,
                    speakerID: "Speaker1",
                    words: nil,
                    segmentType: .speech,
                    pauseDuration: nil
                )
            ],
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                codec: "wav",
                sampleRate: 96000,
                channels: 2,
                bitRate: 512000,
                duration: 1.0
            )
        )

        let formatter = JSONFormatter()
        let jsonString = try formatter.formatAsJSON(highQualityResult)
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to data")
            return
        }
        let parsedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        let metadata = parsedData?["metadata"] as? [String: Any]
        let qualityScore = metadata?["qualityScore"] as? Double

        XCTAssertNotNil(qualityScore)
        guard let score = qualityScore else {
            XCTFail("Quality score should not be nil")
            return
        }
        XCTAssertGreaterThan(score, 0.5)
    }
    
    // MARK: - Helper Methods
    
    private func createTestTranscriptionResult() -> TranscriptionResult {
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
}
