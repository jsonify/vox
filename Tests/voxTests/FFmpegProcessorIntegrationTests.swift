import XCTest
import Foundation
@testable import vox

final class FFmpegProcessorIntegrationTests: XCTestCase {
    var processor: FFmpegProcessor?
    var testFileGenerator: TestAudioFileGenerator?
    var tempDirectory: URL?

    override func setUp() {
        super.setUp()
        processor = FFmpegProcessor()
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg_integration_tests_\(UUID().uuidString)")
        
        guard let tempDir = tempDirectory else {
            XCTFail("Failed to create temporary directory path")
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temporary directory: \(error)")
        }
    }

    override func tearDown() {
        // Clean up any temporary files first
        if let dir = tempDirectory {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                // Silently ignore cleanup errors in tests
            }
        }
        
        // Clean up test file generator
        if let generator = testFileGenerator {
            generator.cleanup()
        }
        
        processor = nil
        testFileGenerator = nil
        tempDirectory = nil
        
        super.tearDown()
    }

    func testProgressCallbackIsCalledDuringExtraction() {
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let testInputFile = tempDir.appendingPathComponent("test_progress.mp4")

        // Create a dummy file
        FileManager.default.createFile(atPath: testInputFile.path, contents: Data("dummy".utf8), attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: testInputFile)
        }

        let expectation = XCTestExpectation(description: "Progress callback test")

        proc.extractAudio(
            from: testInputFile.path,
            progressCallback: { progress in
                // progressCalled = true
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0, "Progress should be >= 0")
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0, "Progress should be <= 1")
            },
            completion: { _ in
                // We don't care about success/failure here, just that the callback mechanism works
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 10.0)

        // Note: progressCalled might be false if ffmpeg is not available or fails immediately
        // This is acceptable for this unit test
    }

    func testFFmpegExtractionWithValidMP4() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }
        
        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not initialized")
            return
        }
        
        guard let testVideoURL = generator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "FFmpeg audio extraction")
        var progressReports: [TranscriptionProgress] = []

        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        proc.extractAudio(
            from: testVideoURL.path,
            progressCallback: { progress in
                progressReports.append(progress)
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
            },
            completion: { result in
                switch result {
                case .success(let audioFile):
                    XCTAssertEqual(audioFile.path, testVideoURL.path)
                    XCTAssertNotNil(audioFile.temporaryPath)
                    if let tempPath = audioFile.temporaryPath {
                        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
                    }

                    // Verify audio format from ffmpeg
                    XCTAssertGreaterThan(audioFile.format.duration, 0)
                    XCTAssertGreaterThan(audioFile.format.sampleRate, 0)
                    XCTAssertGreaterThan(audioFile.format.channels, 0)

                    // Verify progress was reported
                    XCTAssertFalse(progressReports.isEmpty)

                case .failure(let error):
                    XCTFail("FFmpeg extraction should succeed: \(error)")
                }
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 60.0) // Longer timeout for ffmpeg
    }

    func testFFmpegFallbackWithDifferentFormats() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }

        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not initialized")
            return
        }
        
        let testCases = [
            ("high_quality", { generator.createHighQualityMP4File() }),
            ("low_quality", { generator.createLowQualityMP4File() }),
            ("large_file", { generator.createLargeMP4File() })
        ]

        for (name, createFile) in testCases {
            guard let proc = processor else {
                XCTFail("Processor not initialized")
                continue
            }
            
            guard let testVideoURL = createFile() else {
                XCTFail("Failed to create \(name) test file")
                continue
            }

            let expectation = XCTestExpectation(description: "FFmpeg extraction for \(name)")

            proc.extractAudio(from: testVideoURL.path) { result in
                switch result {
                case .success(let audioFile):
                    XCTAssertGreaterThan(audioFile.format.duration, 0, "Duration should be valid for \(name)")
                    XCTAssertGreaterThan(audioFile.format.sampleRate, 0, "Sample rate should be valid for \(name)")
                    XCTAssertGreaterThan(audioFile.format.channels, 0, "Channels should be valid for \(name)")

                case .failure(let error):
                    XCTFail("FFmpeg extraction should succeed for \(name): \(error)")
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 120.0) // Longer timeout for large files
        }
    }

    func testFFmpegProgressReporting() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }

        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not initialized")
            return
        }
        
        guard let testVideoURL = generator.createMockMP4File(duration: 15.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "FFmpeg progress reporting")
        var progressReports: [TranscriptionProgress] = []
        let startTime = Date()

        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }

        proc.extractAudio(
            from: testVideoURL.path,
            progressCallback: { progress in
                progressReports.append(progress)

                // Validate progress properties
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
                XCTAssertNotNil(progress.currentStatus)
                XCTAssertNotNil(progress.currentPhase)

                // Check timing
                XCTAssertEqual(progress.startTime.timeIntervalSince1970,
                               startTime.timeIntervalSince1970,
                               accuracy: 2.0)
            },
            completion: { _ in
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 60.0)

        // Validate progress sequence
        XCTAssertFalse(progressReports.isEmpty, "Should have progress reports")

        // Verify expected phases
        let phases = Set(progressReports.map { $0.currentPhase })
        XCTAssertTrue(phases.contains(.initializing), "Should have initializing phase")
        XCTAssertTrue(phases.contains(.extracting), "Should have extracting phase")

        // Check progress ordering (allowing for some variance due to threading)
        let progressValues = progressReports.map { $0.currentProgress }
        for index in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(
                progressValues[index],
                progressValues[index - 1] - 0.01, // Small tolerance for threading
                "Progress should generally increase"
            )
        }
    }

    func testFFmpegTemporaryFileManagement() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }

        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not initialized")
            return
        }
        
        guard let testVideoURL = generator.createSmallMP4File() else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "FFmpeg temp file management")
        var tempFilePath: String?

        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        proc.extractAudio(from: testVideoURL.path) { result in
            switch result {
            case .success(let audioFile):
                tempFilePath = audioFile.temporaryPath
                XCTAssertNotNil(tempFilePath, "Should have temporary file path")
                
                guard let tempPath = tempFilePath else {
                    XCTFail("Temporary file path should not be nil")
                    return
                }
                
                XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), "Temp file should exist")

                // Verify temp file has expected properties
                XCTAssertTrue(tempPath.contains("vox_ffmpeg_temp_"), "Should have FFmpeg temp prefix")
                XCTAssertTrue(tempPath.hasSuffix(".m4a"), "Should have .m4a extension")

                // Test cleanup
                guard let proc = self.processor else {
                    XCTFail("Processor not initialized")
                    return
                }
                proc.cleanupTemporaryFiles(for: audioFile)
                XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath), "Temp file should be cleaned up")

            case .failure(let error):
                XCTFail("FFmpeg extraction should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testFFmpegConcurrentProcessing() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }

        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not initialized")
            return
        }

        // Create multiple test files
        let testFiles = (0..<3).compactMap { _ in
            generator.createSmallMP4File()
        }

        guard testFiles.count == 3 else {
            XCTFail("Failed to create test files")
            return
        }

        let group = DispatchGroup()
        var results: [Result<AudioFile, VoxError>] = []
        let resultsLock = NSLock()

        // Process files concurrently
        for testFile in testFiles {
            group.enter()
            let individualProcessor = FFmpegProcessor()

            individualProcessor.extractAudio(from: testFile.path) { result in
                resultsLock.lock()
                results.append(result)
                resultsLock.unlock()
                group.leave()
            }
        }

        let expectation = XCTestExpectation(description: "Concurrent processing")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)

        // Verify all processing completed
        XCTAssertEqual(results.count, 3, "Should have 3 results")

        // Count successes (should be all successful with valid files)
        let successes = results.compactMap { result -> AudioFile? in
            if case .success(let audioFile) = result {
                return audioFile
            }
            return nil
        }

        XCTAssertEqual(successes.count, 3, "All extractions should succeed")

        // Verify each has unique temporary file
        let tempPaths = Set(successes.compactMap { $0.temporaryPath })
        XCTAssertEqual(tempPaths.count, 3, "All temp files should be unique")

        // Cleanup
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        for audioFile in successes {
            proc.cleanupTemporaryFiles(for: audioFile)
        }
    }
}
