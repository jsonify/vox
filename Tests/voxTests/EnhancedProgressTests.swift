import XCTest
@testable import vox

final class EnhancedProgressTests: XCTestCase {
    func testProgressReporterInitialization() {
        let duration: TimeInterval = 60.0
        let reporter = EnhancedProgressReporter(totalAudioDuration: duration)

        // Test initial state
        XCTAssertEqual(reporter.currentSegmentIndex, 0)
        XCTAssertEqual(reporter.totalSegments, 0)
        XCTAssertNil(reporter.currentSegmentText)

        // Test memory usage initialization
        let memoryUsage = reporter.memoryUsage
        XCTAssertGreaterThan(memoryUsage.currentBytes, 0)
        XCTAssertGreaterThanOrEqual(memoryUsage.peakBytes, memoryUsage.currentBytes)
        XCTAssertGreaterThan(memoryUsage.availableBytes, 0)

        // Test initial processing stats
        let stats = reporter.processingStats
        XCTAssertEqual(stats.segmentsProcessed, 0)
        XCTAssertEqual(stats.wordsProcessed, 0)
        XCTAssertEqual(stats.averageConfidence, 0.0)
        XCTAssertEqual(stats.processingRate, 0.0)
        XCTAssertEqual(stats.audioProcessed, 0.0)
        XCTAssertEqual(stats.audioRemaining, duration)
    }

    func testProgressUpdates() {
        let duration: TimeInterval = 60.0
        let reporter = EnhancedProgressReporter(totalAudioDuration: duration)

        // Test progress update
        reporter.updateProgress(
            segmentIndex: 1,
            totalSegments: 10,
            segmentText: "Test segment",
            segmentConfidence: 0.9,
            audioTimeProcessed: 6.0
        )

        XCTAssertEqual(reporter.currentSegmentIndex, 1)
        XCTAssertEqual(reporter.totalSegments, 10)
        XCTAssertEqual(reporter.currentSegmentText, "Test segment")

        let stats = reporter.processingStats
        XCTAssertEqual(stats.segmentsProcessed, 2) // Index + 1
        XCTAssertEqual(stats.audioProcessed, 6.0)
        XCTAssertEqual(stats.audioRemaining, 54.0)

        // Test progress report generation
        let report = reporter.generateDetailedProgressReport()
        XCTAssertEqual(report.currentProgress, 0.1) // 1/10
        XCTAssertEqual(report.currentPhase, .extracting)
        XCTAssertNotNil(report.startTime)
        XCTAssertNotNil(report.processingSpeed)
    }

    func testMemoryUsageCalculation() {
        let monitor = MemoryMonitor()
        let usage = monitor.getCurrentUsage()

        XCTAssertGreaterThan(usage.currentBytes, 0)
        XCTAssertGreaterThan(usage.peakBytes, 0)
        XCTAssertGreaterThan(usage.availableBytes, 0)

        let percentage = usage.usagePercentage
        XCTAssertGreaterThanOrEqual(percentage, 0.0)
        XCTAssertLessThanOrEqual(percentage, 100.0)

        // Test memory metrics
        XCTAssertGreaterThan(usage.currentMB, 0.0)
        XCTAssertGreaterThan(usage.peakMB, 0.0)
        XCTAssertGreaterThan(usage.availableMB, 0.0)
    }
}
