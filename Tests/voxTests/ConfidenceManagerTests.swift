import XCTest
@testable import vox

final class ConfidenceManagerTests: XCTestCase {
    var confidenceManager: ConfidenceManager?

    override func setUp() {
        super.setUp()
        confidenceManager = ConfidenceManager()
    }

    override func tearDown() {
        confidenceManager = nil
        super.tearDown()
    }

    // MARK: - Quality Level Tests

    func testQualityLevelDetermination() {
        // Test excellent quality (>80%)
        let excellentResult = createMockTranscriptionResult(confidence: 0.9)
        let excellentAssessment = confidenceManager!.assessQuality(result: excellentResult)
        XCTAssertEqual(excellentAssessment.qualityLevel, .excellent)

        // Test good quality (60-80%)
        let goodResult = createMockTranscriptionResult(confidence: 0.7)
        let goodAssessment = confidenceManager!.assessQuality(result: goodResult)
        XCTAssertEqual(goodAssessment.qualityLevel, .good)

        // Test acceptable quality (40-60%)
        let acceptableResult = createMockTranscriptionResult(confidence: 0.5)
        let acceptableAssessment = confidenceManager!.assessQuality(result: acceptableResult)
        XCTAssertEqual(acceptableAssessment.qualityLevel, .acceptable)

        // Test poor quality (20-40%)
        let poorResult = createMockTranscriptionResult(confidence: 0.3)
        let poorAssessment = confidenceManager!.assessQuality(result: poorResult)
        XCTAssertEqual(poorAssessment.qualityLevel, .poor)

        // Test unacceptable quality (<20%)
        let unacceptableResult = createMockTranscriptionResult(confidence: 0.1)
        let unacceptableAssessment = confidenceManager!.assessQuality(result: unacceptableResult)
        XCTAssertEqual(unacceptableAssessment.qualityLevel, .unacceptable)
    }

    // MARK: - Low Confidence Segment Tests

    func testLowConfidenceSegmentIdentification() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let segments = [
            TranscriptionSegment(text: "Good segment", startTime: 0.0, endTime: 5.0, confidence: 0.8, speakerID: nil),
            TranscriptionSegment(text: "Bad segment", startTime: 5.0, endTime: 10.0, confidence: 0.2, speakerID: nil),
            TranscriptionSegment(text: "Another good segment", startTime: 10.0, endTime: 15.0, confidence: 0.7, speakerID: nil),
            TranscriptionSegment(text: "Very bad segment", startTime: 15.0, endTime: 20.0, confidence: 0.1, speakerID: nil)
        ]

        let result = createMockTranscriptionResult(segments: segments)
        let assessment = manager.assessQuality(result: result)

        // Should identify 2 low-confidence segments (confidence < 0.4)
        XCTAssertEqual(assessment.lowConfidenceSegments.count, 2)
        XCTAssertEqual(assessment.lowConfidencePercentage, 0.5) // 2 out of 4 segments

        // Verify the correct segments were identified
        XCTAssertEqual(assessment.lowConfidenceSegments[0].segment.text, "Bad segment")
        XCTAssertEqual(assessment.lowConfidenceSegments[1].segment.text, "Very bad segment")
    }

    func testEmptySegmentsHandling() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let result = createMockTranscriptionResult(segments: [])
        let assessment = manager.assessQuality(result: result)

        XCTAssertTrue(assessment.lowConfidenceSegments.isEmpty)
        XCTAssertEqual(assessment.lowConfidencePercentage, 0.0)
    }

    // MARK: - Fallback Trigger Tests

    func testShouldUseFallbackBasedOnOverallConfidence() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        // Test low overall confidence should trigger fallback
        let lowConfidenceResult = createMockTranscriptionResult(confidence: 0.2)
        let lowAssessment = manager.assessQuality(result: lowConfidenceResult)
        XCTAssertTrue(lowAssessment.shouldUseFallback)

        // Test high overall confidence should not trigger fallback
        let highConfidenceResult = createMockTranscriptionResult(confidence: 0.8)
        let highAssessment = manager.assessQuality(result: highConfidenceResult)
        XCTAssertFalse(highAssessment.shouldUseFallback)
    }

    func testShouldUseFallbackBasedOnLowConfidenceSegmentPercentage() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        // Create result with high overall confidence but many low-confidence segments
        let segments = [
            TranscriptionSegment(text: "Segment 1", startTime: 0.0, endTime: 5.0, confidence: 0.2, speakerID: nil),
            TranscriptionSegment(text: "Segment 2", startTime: 5.0, endTime: 10.0, confidence: 0.2, speakerID: nil),
            TranscriptionSegment(text: "Segment 3", startTime: 10.0, endTime: 15.0, confidence: 0.2, speakerID: nil),
            TranscriptionSegment(text: "Segment 4", startTime: 15.0, endTime: 20.0, confidence: 0.9, speakerID: nil)
        ]

        let result = createMockTranscriptionResult(confidence: 0.375, segments: segments) // Average confidence is acceptable
        let assessment = manager.assessQuality(result: result)

        // Should trigger fallback due to high percentage of low-confidence segments (75% > 30%)
        XCTAssertTrue(assessment.shouldUseFallback)
    }

    // MARK: - Quality Standards Tests

    func testMeetsQualityStandards() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        // Test result that meets standards
        let goodSegments = [
            TranscriptionSegment(text: "Good segment 1", startTime: 0.0, endTime: 5.0, confidence: 0.8, speakerID: nil),
            TranscriptionSegment(text: "Good segment 2", startTime: 5.0, endTime: 10.0, confidence: 0.7, speakerID: nil)
        ]
        let goodResult = createMockTranscriptionResult(confidence: 0.75, segments: goodSegments)
        XCTAssertTrue(manager.meetsQualityStandards(result: goodResult))

        // Test result that doesn't meet standards (low overall confidence)
        let badResult = createMockTranscriptionResult(confidence: 0.2)
        XCTAssertFalse(manager.meetsQualityStandards(result: badResult))
    }

    // MARK: - Warning Generation Tests

    func testWarningGeneration() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        // Test poor quality generates warnings
        let poorResult = createMockTranscriptionResult(confidence: 0.25)
        let poorAssessment = manager.assessQuality(result: poorResult)
        XCTAssertFalse(poorAssessment.warnings.isEmpty)
        XCTAssertTrue(poorAssessment.warnings.contains { $0.contains("poor") })

        // Test high quality generates no warnings
        let goodResult = createMockTranscriptionResult(confidence: 0.85)
        let goodAssessment = manager.assessQuality(result: goodResult)
        XCTAssertTrue(goodAssessment.warnings.isEmpty)
    }

    func testWarningForHighLowConfidenceSegmentPercentage() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let segments = Array(repeating:
                                TranscriptionSegment(text: "Low confidence", startTime: 0.0, endTime: 5.0, confidence: 0.2, speakerID: nil),
                             count: 8
        ) + Array(repeating:
                    TranscriptionSegment(text: "High confidence", startTime: 0.0, endTime: 5.0, confidence: 0.8, speakerID: nil),
                  count: 2
        )

        let result = createMockTranscriptionResult(segments: segments)
        let assessment = manager.assessQuality(result: result)

        // Should generate warning for high percentage of low-confidence segments
        XCTAssertTrue(assessment.warnings.contains { $0.contains("80.0% of segments have low confidence") })
    }

    // MARK: - Recommendation Tests

    func testRecommendationGeneration() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        // Test poor quality generates fallback recommendation
        let poorResult = createMockTranscriptionResult(confidence: 0.15)
        let poorAssessment = manager.assessQuality(result: poorResult)

        let fallbackRecommendations = poorAssessment.recommendations.filter { $0.type == .fallback }
        XCTAssertFalse(fallbackRecommendations.isEmpty)
        XCTAssertTrue(fallbackRecommendations.first?.message.contains("cloud transcription") ?? false)
    }

    func testAudioQualityRecommendation() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let mediumResult = createMockTranscriptionResult(confidence: 0.45)
        let assessment = manager.assessQuality(result: mediumResult)

        let audioRecommendations = assessment.recommendations.filter { $0.type == .audioquality }
        XCTAssertFalse(audioRecommendations.isEmpty)
        XCTAssertTrue(audioRecommendations.first?.message.contains("higher quality audio") ?? false)
    }

    // MARK: - Quality Report Tests

    func testQualityReportGeneration() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let result = createMockTranscriptionResult(confidence: 0.75)
        let assessment = manager.assessQuality(result: result)
        let report = manager.generateQualityReport(assessment: assessment)

        XCTAssertTrue(report.contains("📊 Quality Assessment"))
        XCTAssertTrue(report.contains("75.0%"))
        XCTAssertTrue(report.contains("Good transcription quality"))
    }

    func testQualityReportWithWarnings() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let poorResult = createMockTranscriptionResult(confidence: 0.2)
        let poorAssessment = manager.assessQuality(result: poorResult)
        let report = manager.generateQualityReport(assessment: poorAssessment)

        XCTAssertTrue(report.contains("⚠️  Quality Warnings"))
        XCTAssertTrue(report.contains("🔄 Fallback recommended"))
    }

    // MARK: - Configuration Tests

    func testCustomConfiguration() {
        let customConfig = ConfidenceConfig(
            minAcceptableConfidence: 0.5,
            warningThreshold: 0.7,
            fallbackThreshold: 0.4,
            segmentConfidenceThreshold: 0.6,
            maxLowConfidenceSegmentPercentage: 0.2
        )

        let customManager = ConfidenceManager(config: customConfig)

        // Test that custom thresholds are applied
        let result = createMockTranscriptionResult(confidence: 0.45)
        XCTAssertFalse(customManager.meetsQualityStandards(result: result)) // Below custom min threshold

        let assessment = customManager.assessQuality(result: result)
        XCTAssertTrue(assessment.shouldUseFallback) // Above custom fallback threshold
    }

    // MARK: - Edge Cases

    func testZeroConfidenceHandling() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let zeroResult = createMockTranscriptionResult(confidence: 0.0)
        let assessment = manager.assessQuality(result: zeroResult)

        XCTAssertEqual(assessment.qualityLevel, .unacceptable)
        XCTAssertTrue(assessment.shouldUseFallback)
        XCTAssertFalse(assessment.warnings.isEmpty)
    }

    func testPerfectConfidenceHandling() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let perfectResult = createMockTranscriptionResult(confidence: 1.0)
        let assessment = manager.assessQuality(result: perfectResult)

        XCTAssertEqual(assessment.qualityLevel, .excellent)
        XCTAssertFalse(assessment.shouldUseFallback)
        XCTAssertTrue(assessment.warnings.isEmpty)
    }

    // MARK: - Helper Methods

    private func createMockTranscriptionResult(
        confidence: Double = 0.5,
        segments: [TranscriptionSegment]? = nil
    ) -> TranscriptionResult {
        let defaultSegments = [
            TranscriptionSegment(text: "Test segment", startTime: 0.0, endTime: 5.0, confidence: confidence, speakerID: nil)
        ]

        return TranscriptionResult(
            text: "Test transcription",
            language: "en-US",
            confidence: confidence,
            duration: 10.0,
            segments: segments ?? defaultSegments,
            engine: .speechAnalyzer,
            processingTime: 2.0,
            audioFormat: AudioFormat(codec: "mp3", sampleRate: 44100, channels: 2, bitRate: 128000, duration: 10.0)
        )
    }
}

// MARK: - Quality Level Tests

extension ConfidenceManagerTests {
    func testQualityLevelDescriptions() {
        XCTAssertEqual(QualityLevel.excellent.description, "Excellent transcription quality")
        XCTAssertEqual(QualityLevel.good.description, "Good transcription quality")
        XCTAssertEqual(QualityLevel.acceptable.description, "Acceptable transcription quality")
        XCTAssertEqual(QualityLevel.poor.description, "Poor transcription quality - consider using fallback")
        XCTAssertEqual(QualityLevel.unacceptable.description, "Unacceptable transcription quality - fallback recommended")
    }

    func testQualityLevelEmojis() {
        XCTAssertEqual(QualityLevel.excellent.emoji, "🟢")
        XCTAssertEqual(QualityLevel.good.emoji, "🟡")
        XCTAssertEqual(QualityLevel.acceptable.emoji, "🟠")
        XCTAssertEqual(QualityLevel.poor.emoji, "🔴")
        XCTAssertEqual(QualityLevel.unacceptable.emoji, "⚫")
    }
}

// MARK: - Low Confidence Segment Tests

extension ConfidenceManagerTests {
    func testSegmentIssueReasonDetermination() {
        guard let manager = confidenceManager else {
            XCTFail("Confidence manager not available")
            return
        }
        
        let segments = [
            TranscriptionSegment(text: "Short", startTime: 0.0, endTime: 0.3, confidence: 0.6, speakerID: nil),
            TranscriptionSegment(text: "", startTime: 1.0, endTime: 2.0, confidence: 0.3, speakerID: nil),
            TranscriptionSegment(text: "Very low confidence", startTime: 2.0, endTime: 7.0, confidence: 0.05, speakerID: nil)
        ]

        let result = createMockTranscriptionResult(segments: segments)
        let assessment = manager.assessQuality(result: result)

        XCTAssertEqual(assessment.lowConfidenceSegments.count, 2) // Empty text and very low confidence

        // Find the very low confidence segment
        let veryLowConfidenceSegment = assessment.lowConfidenceSegments.first { $0.segment.confidence < 0.1 }
        XCTAssertNotNil(veryLowConfidenceSegment)
        XCTAssertEqual(veryLowConfidenceSegment?.reason, "Very low confidence score")
    }
}
