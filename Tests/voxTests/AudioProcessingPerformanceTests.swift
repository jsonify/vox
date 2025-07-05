import XCTest
import Foundation
import AVFoundation
@testable import vox

final class AudioProcessingPerformanceTests: XCTestCase {
    var audioProcessor: AudioProcessor?
    var ffmpegProcessor: FFmpegProcessor?
    var testFileGenerator: TestAudioFileGenerator?
    var tempDirectory: URL?

    override func setUp() {
        super.setUp()
        audioProcessor = AudioProcessor()
        ffmpegProcessor = FFmpegProcessor()
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("perf_tests_\(UUID().uuidString)")
        if let tempDir = tempDirectory {
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        audioProcessor = nil
        ffmpegProcessor = nil
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        testFileGenerator?.cleanup()
        testFileGenerator = nil
        super.tearDown()
    }

    // MARK: - Basic Performance Tests

    func testAudioProcessorInstantiation() {
        measure {
            for _ in 0..<100 {
                _ = AudioProcessor()
            }
        }
    }

    func testFFmpegProcessorInstantiation() {
        measure {
            for _ in 0..<100 {
                _ = FFmpegProcessor()
            }
        }
    }

    func testTemporaryFileCreation() {
        measure {
            var tempURLs: [URL] = []

            for _ in 0..<50 {
                if let tempURL = TempFileManager.shared.createTemporaryAudioFile() {
                    tempURLs.append(tempURL)
                }
            }

            // Cleanup
            _ = TempFileManager.shared.cleanupFiles(at: tempURLs)
        }
    }

    func testMemoryMonitorPerformance() {
        let monitor = MemoryMonitor()

        measure {
            for _ in 0..<1000 {
                _ = monitor.getCurrentUsage()
            }
        }
    }

    // MARK: - Simple Processing Tests

    func testBasicAudioProcessing() throws {
        guard let generator = testFileGenerator,
              let testVideoURL = generator.createSmallMP4File() else {
            throw XCTSkip("Unable to create test file")
        }

        let expectation = XCTestExpectation(description: "Basic audio processing")
        let startTime = Date()

        audioProcessor?.extractAudio(from: testVideoURL.path) { result in
            let processingTime = Date().timeIntervalSince(startTime)

            switch result {
            case .success(let audioFile):
                // Basic performance check - should complete in reasonable time
                XCTAssertLessThan(processingTime, 10.0, "Processing should complete within 10 seconds")
                XCTAssertGreaterThan(audioFile.format.duration, 0, "Should have valid duration")

            case .failure(let error):
                XCTFail("Processing failed: \(error)")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15.0)
    }

    func testProgressReportingPerformance() throws {
        guard let generator = testFileGenerator,
              let testVideoURL = generator.createSmallMP4File() else {
            throw XCTSkip("Unable to create test file")
        }

        let expectation = XCTestExpectation(description: "Progress reporting performance")
        var progressReports: [TranscriptionProgress] = []

        audioProcessor?.extractAudio(
            from: testVideoURL.path,
            progressCallback: { progress in
                progressReports.append(progress)
            },
            completion: { result in
                switch result {
                case .success:
                    // Should have received progress updates
                    XCTAssertGreaterThan(progressReports.count, 0, "Should receive progress updates")

                    // Progress should be monotonic
                    for i in 1..<progressReports.count {
                        XCTAssertGreaterThanOrEqual(
                            progressReports[i].currentProgress,
                            progressReports[i - 1].currentProgress,
                            "Progress should be monotonic"
                        )
                    }

                case .failure(let error):
                    XCTFail("Processing failed: \(error)")
                }

                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 15.0)
    }
}
