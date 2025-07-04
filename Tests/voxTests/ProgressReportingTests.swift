import XCTest
@testable import vox

final class ProgressReportingTests: XCTestCase {
    func testProgressReportCreation() {
        let startTime = Date()
        let progressReport = TranscriptionProgress(
            progress: 0.5,
            status: "Processing...",
            phase: .extracting,
            startTime: startTime,
            processingSpeed: 1.5
        )

        XCTAssertEqual(progressReport.currentProgress, 0.5)
        XCTAssertEqual(progressReport.currentStatus, "Processing...")
        XCTAssertEqual(progressReport.currentPhase, .extracting)
        XCTAssertEqual(progressReport.formattedProgress, "50.0%")
        XCTAssertFalse(progressReport.isComplete)
        XCTAssertNotNil(progressReport.estimatedTimeRemaining)
    }

    func testProgressReportCompletion() {
        let startTime = Date()
        let progressReport = TranscriptionProgress(
            progress: 1.0,
            status: "Complete",
            phase: .complete,
            startTime: startTime
        )

        XCTAssertEqual(progressReport.currentProgress, 1.0)
        XCTAssertTrue(progressReport.isComplete)
        XCTAssertEqual(progressReport.formattedProgress, "100.0%")
    }

    func testMemoryUsageCalculations() {
        let memoryUsage = MemoryUsage(
            currentBytes: 100 * 1024 * 1024, // 100 MB
            peakBytes: 150 * 1024 * 1024,    // 150 MB
            availableBytes: 400 * 1024 * 1024 // 400 MB
        )

        XCTAssertEqual(memoryUsage.currentMB, 100.0, accuracy: 0.1)
        XCTAssertEqual(memoryUsage.peakMB, 150.0, accuracy: 0.1)
        XCTAssertEqual(memoryUsage.availableMB, 400.0, accuracy: 0.1)

        // Memory percentage is now calculated using actual system memory
        // So we just verify it's a reasonable percentage (0-100%)
        XCTAssertGreaterThanOrEqual(memoryUsage.usagePercentage, 0.0)
        XCTAssertLessThanOrEqual(memoryUsage.usagePercentage, 100.0)
    }

    func testProcessingStatsTimeEstimation() {
        let stats = ProcessingStats(
            segmentsProcessed: 50,
            wordsProcessed: 200,
            averageConfidence: 0.85,
            processingRate: 2.0, // 2x real-time
            audioProcessed: 60.0, // 60 seconds
            audioRemaining: 30.0  // 30 seconds
        )

        XCTAssertEqual(stats.segmentsProcessed, 50)
        XCTAssertEqual(stats.wordsProcessed, 200)
        XCTAssertEqual(stats.averageConfidence, 0.85, accuracy: 0.01)
        XCTAssertEqual(stats.processingRate, 2.0, accuracy: 0.01)
        XCTAssertNotNil(stats.estimatedCompletion)
        guard let estimatedCompletion = stats.estimatedCompletion else {
            XCTFail("Estimated completion should not be nil")
            return
        }
        XCTAssertEqual(estimatedCompletion, 15.0, accuracy: 0.1) // 30/2 = 15 seconds
        XCTAssertEqual(stats.formattedProcessingRate, "2.0x")
    }

    func testEnhancedProgressReporter() {
        let reporter = EnhancedProgressReporter(totalAudioDuration: 120.0)

        // Test initial state
        XCTAssertEqual(reporter.currentSegmentIndex, 0)
        XCTAssertEqual(reporter.totalSegments, 0)
        XCTAssertNil(reporter.currentSegmentText)

        // Test progress update
        reporter.updateProgress(
            segmentIndex: 5,
            totalSegments: 100,
            segmentText: "Hello world",
            segmentConfidence: 0.9,
            audioTimeProcessed: 10.0
        )

        XCTAssertEqual(reporter.currentSegmentIndex, 5)
        XCTAssertEqual(reporter.totalSegments, 100)
        XCTAssertEqual(reporter.currentSegmentText, "Hello world")
        XCTAssertEqual(reporter.processingStats.segmentsProcessed, 6) // index + 1
        XCTAssertEqual(reporter.processingStats.wordsProcessed, 2) // "Hello world" = 2 words
        XCTAssertEqual(reporter.processingStats.audioProcessed, 10.0)
        XCTAssertEqual(reporter.processingStats.audioRemaining, 110.0) // 120 - 10
    }

    func testMemoryMonitor() {
        let monitor = MemoryMonitor()
        let usage = monitor.getCurrentUsage()

        // Memory usage should be positive values
        XCTAssertGreaterThan(usage.currentBytes, 0)
        XCTAssertGreaterThanOrEqual(usage.peakBytes, usage.currentBytes)
        XCTAssertGreaterThan(usage.availableBytes, 0)
        XCTAssertGreaterThan(usage.currentMB, 0)
        XCTAssertGreaterThanOrEqual(usage.usagePercentage, 0)
        XCTAssertLessThanOrEqual(usage.usagePercentage, 100)
    }

    func testProgressFormattingHelpers() {
        let startTime = Date().addingTimeInterval(-30) // 30 seconds ago

        // Test with time remaining
        let progressWithETA = TranscriptionProgress(
            progress: 0.6,
            status: "Processing",
            phase: .extracting,
            startTime: startTime,
            processingSpeed: 0.02 // 2% per second
        )

        XCTAssertFalse(progressWithETA.formattedTimeRemaining.isEmpty)
        XCTAssertFalse(progressWithETA.formattedElapsedTime.isEmpty)

        // Test without time remaining
        let progressWithoutETA = TranscriptionProgress(
            progress: 0.3,
            status: "Starting",
            phase: .initializing,
            startTime: startTime
        )

        XCTAssertEqual(progressWithoutETA.formattedTimeRemaining, "calculating...")
    }
}
