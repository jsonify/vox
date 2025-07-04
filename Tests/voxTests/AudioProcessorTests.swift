import XCTest
import Foundation
import AVFoundation
@testable import vox

final class AudioProcessorTests: XCTestCase {
    var audioProcessor: AudioProcessor!
    var tempDirectory: URL!
    var testFileGenerator: TestAudioFileGenerator!

    override func setUp() {
        super.setUp()
        audioProcessor = AudioProcessor()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("vox_tests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testFileGenerator = TestAudioFileGenerator.shared
    }

    override func tearDown() {
        audioProcessor = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        testFileGenerator?.cleanup()
        testFileGenerator = nil
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testAudioProcessorCreation() {
        let processor = AudioProcessor()
        XCTAssertNotNil(processor)
    }

    // MARK: - Temporary File Management Tests

    func testTemporaryFileCreation() {
        let tempURL = TempFileManager.shared.createTemporaryAudioFile()

        XCTAssertNotNil(tempURL)
        XCTAssertEqual(tempURL?.pathExtension, "m4a")
        XCTAssertTrue(tempURL?.lastPathComponent.hasPrefix("vox_audio_") == true)

        // Cleanup
        if let url = tempURL {
            _ = TempFileManager.shared.cleanupFile(at: url)
        }
    }

    func testMultipleTemporaryFileCreationUniqueness() {
        let tempURL1 = TempFileManager.shared.createTemporaryAudioFile()
        let tempURL2 = TempFileManager.shared.createTemporaryAudioFile()

        XCTAssertNotNil(tempURL1)
        XCTAssertNotNil(tempURL2)
        XCTAssertNotEqual(tempURL1, tempURL2)
        XCTAssertNotEqual(tempURL1?.lastPathComponent, tempURL2?.lastPathComponent)

        // Cleanup
        if let url1 = tempURL1 { _ = TempFileManager.shared.cleanupFile(at: url1) }
        if let url2 = tempURL2 { _ = TempFileManager.shared.cleanupFile(at: url2) }
    }

    func testCleanupTemporaryFile() {
        let tempFileURL = tempDirectory.appendingPathComponent("test_cleanup.m4a")

        // Create test file
        let testData = "test audio data".data(using: .utf8)!
        XCTAssertTrue(FileManager.default.createFile(atPath: tempFileURL.path, contents: testData))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        // Register and test cleanup
        TempFileManager.shared.registerTemporaryFile(at: tempFileURL)
        XCTAssertTrue(TempFileManager.shared.cleanupFile(at: tempFileURL))

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func testCleanupNonexistentTemporaryFile() {
        let nonexistentURL = tempDirectory.appendingPathComponent("nonexistent.m4a")

        XCTAssertFalse(FileManager.default.fileExists(atPath: nonexistentURL.path))

        // Should not crash when trying to cleanup non-existent file
        XCTAssertTrue(TempFileManager.shared.cleanupFile(at: nonexistentURL))

        XCTAssertFalse(FileManager.default.fileExists(atPath: nonexistentURL.path))
    }

    func testCleanupTemporaryFilesForAudioFile() {
        let tempFileURL = tempDirectory.appendingPathComponent("audio_file_cleanup.m4a")
        let testData = "test audio data".data(using: .utf8)!
        XCTAssertTrue(FileManager.default.createFile(atPath: tempFileURL.path, contents: testData))

        let audioFormat = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 60.0
        )

        let audioFile = AudioFile(
            path: "/input/path.mp4",
            format: audioFormat,
            temporaryPath: tempFileURL.path
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        audioProcessor.cleanupTemporaryFiles(for: audioFile)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func testCleanupTemporaryFilesForAudioFileWithoutTempPath() {
        let audioFormat = AudioFormat(
            codec: "wav",
            sampleRate: 44100,
            channels: 1,
            bitRate: nil,
            duration: 30.0
        )

        let audioFile = AudioFile(
            path: "/input/path.wav",
            format: audioFormat,
            temporaryPath: nil
        )

        // Should not crash when there's no temporary path
        audioProcessor.cleanupTemporaryFiles(for: audioFile)
    }

    // MARK: - File Validation Tests

    func testExtractAudioFromNonexistentFile() {
        let nonexistentPath = "/nonexistent/path/video.mp4"
        let expectation = XCTestExpectation(description: "Extract audio completion")

        audioProcessor.extractAudio(from: nonexistentPath) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with nonexistent file")
            case .failure(let error):
                if case .invalidInputFile(let path) = error {
                    XCTAssertTrue(path.contains(nonexistentPath))
                } else {
                    XCTFail("Expected invalidInputFile error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testExtractAudioFromInvalidExtension() {
        let invalidFile = tempDirectory.appendingPathComponent("test.txt")
        let testData = "not a video file".data(using: .utf8)!
        XCTAssertTrue(FileManager.default.createFile(atPath: invalidFile.path, contents: testData))

        let expectation = XCTestExpectation(description: "Extract audio completion")

        audioProcessor.extractAudio(from: invalidFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with invalid file extension")
            case .failure(let error):
                if case .unsupportedFormat(let format) = error {
                    XCTAssertTrue(format.contains("test.txt"))
                } else {
                    XCTFail("Expected unsupportedFormat error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testExtractAudioFromFileWithValidExtensionButInvalidContent() {
        let invalidMP4File = tempDirectory.appendingPathComponent("fake.mp4")
        let testData = "not actually an mp4 file".data(using: .utf8)!
        XCTAssertTrue(FileManager.default.createFile(atPath: invalidMP4File.path, contents: testData))

        let expectation = XCTestExpectation(description: "Extract audio completion")

        audioProcessor.extractAudio(from: invalidMP4File.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with invalid MP4 content")
            case .failure(let error):
                switch error {
                case .unsupportedFormat, .audioExtractionFailed:
                    // Expected error cases for invalid MP4 content
                    break
                default:
                    XCTFail("Expected unsupportedFormat or audioExtractionFailed error for invalid MP4 content, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Progress Callback Tests

    func testProgressCallbackWithNonexistentFile() {
        let nonexistentPath = "/nonexistent/video.mp4"
        let expectation = XCTestExpectation(description: "Extract audio completion")
        var progressCallbackInvoked = false

        audioProcessor.extractAudio(
            from: nonexistentPath,
            progressCallback: { progress in
                progressCallbackInvoked = true
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
            }
        ) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed")
            case .failure:
                // Progress callback should not be invoked for immediate failures
                XCTAssertFalse(progressCallbackInvoked)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Error Handling Tests

    func testExtractAudioErrorHandling() {
        let paths = [
            "/dev/null",
            "/tmp",
            "",
            "/this/path/definitely/does/not/exist/video.mp4"
        ]

        let group = DispatchGroup()

        for path in paths {
            group.enter()
            audioProcessor.extractAudio(from: path) { result in
                switch result {
                case .success:
                    if !path.isEmpty {
                        XCTFail("Should not succeed with invalid path: \(path)")
                    }
                case .failure(let error):
                    switch error {
                    case .invalidInputFile, .unsupportedFormat:
                        // These are the expected error types for invalid paths
                        break
                    default:
                        XCTFail("Expected invalidInputFile or unsupportedFormat error for invalid path, got \(error)")
                    }
                }
                group.leave()
            }
        }

        let expectation = XCTestExpectation(description: "All extractions complete")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Memory Management Tests

    func testMemoryManagementWithMultipleProcessors() {
        var processors: [AudioProcessor] = []

        // Create multiple processors
        for _ in 0..<10 {
            processors.append(AudioProcessor())
        }

        // Test they can all create temp files via TempFileManager
        for _ in processors {
            let tempURL = TempFileManager.shared.createTemporaryAudioFile()
            XCTAssertNotNil(tempURL)
            if let url = tempURL {
                _ = TempFileManager.shared.cleanupFile(at: url)
            }
        }

        // Clear references
        processors.removeAll()

        // Force deallocation
        autoreleasepool {
            _ = AudioProcessor()
            let tempURL = TempFileManager.shared.createTemporaryAudioFile()
            XCTAssertNotNil(tempURL)
            if let url = tempURL {
                _ = TempFileManager.shared.cleanupFile(at: url)
            }
        }
    }

    // MARK: - Thread Safety Tests

    func testConcurrentTemporaryFileCreation() {
        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        var tempURLs: [URL] = []
        let lock = NSLock()

        for _ in 0..<20 {
            group.enter()
            concurrentQueue.async {
                if let tempURL = TempFileManager.shared.createTemporaryAudioFile() {
                    lock.lock()
                    tempURLs.append(tempURL)
                    lock.unlock()
                }
                group.leave()
            }
        }

        let expectation = XCTestExpectation(description: "Concurrent file creation")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // All URLs should be unique
        let uniqueURLs = Set(tempURLs.map { $0.lastPathComponent })
        XCTAssertEqual(tempURLs.count, uniqueURLs.count)
        XCTAssertEqual(tempURLs.count, 20)

        // Cleanup all created files
        _ = TempFileManager.shared.cleanupFiles(at: tempURLs)
    }

    // MARK: - AVFoundation Processing Tests

    func testSuccessfulAudioExtractionFromValidMP4() {
        guard let testVideoURL = testFileGenerator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Audio extraction completion")
        var progressReports: [TranscriptionProgress] = []

        audioProcessor.extractAudio(
            from: testVideoURL.path,
            progressCallback: { progress in
                progressReports.append(progress)
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
            }
        ) { result in
            switch result {
            case .success(let audioFile):
                XCTAssertEqual(audioFile.path, testVideoURL.path)
                XCTAssertNotNil(audioFile.temporaryPath)
                XCTAssertTrue(FileManager.default.fileExists(atPath: audioFile.temporaryPath!))
                XCTAssertEqual(audioFile.format.codec, "m4a")
                XCTAssertGreaterThan(audioFile.format.duration, 0)

                // Verify progress was reported
                XCTAssertFalse(progressReports.isEmpty)
                XCTAssertEqual(progressReports.last?.currentProgress, 1.0)

            case .failure(let error):
                XCTFail("Audio extraction should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testAudioExtractionWithDifferentFormats() {
        let testCases = [
            ("high_quality", { self.testFileGenerator.createHighQualityMP4File() }),
            ("low_quality", { self.testFileGenerator.createLowQualityMP4File() }),
            ("small_file", { self.testFileGenerator.createSmallMP4File() })
        ]

        for (name, createFile) in testCases {
            guard let testVideoURL = createFile() else {
                XCTFail("Failed to create \(name) test file")
                continue
            }

            let expectation = XCTestExpectation(description: "Audio extraction for \(name)")

            audioProcessor.extractAudio(from: testVideoURL.path) { result in
                switch result {
                case .success(let audioFile):
                    XCTAssertEqual(audioFile.format.codec, "m4a", "Failed for \(name)")
                    XCTAssertGreaterThan(audioFile.format.duration, 0, "Failed for \(name)")
                    XCTAssertTrue(audioFile.format.isValid, "Audio format should be valid for \(name)")

                case .failure(let error):
                    XCTFail("Audio extraction should succeed for \(name): \(error)")
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 30.0)
        }
    }

    func testProgressReportingAccuracy() {
        guard let testVideoURL = testFileGenerator.createMockMP4File(duration: 10.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Progress reporting")
        var progressReports: [TranscriptionProgress] = []
        let startTime = Date()

        audioProcessor.extractAudio(
            from: testVideoURL.path,
            progressCallback: { progress in
                progressReports.append(progress)

                // Validate progress properties
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
                XCTAssertNotNil(progress.currentStatus)
                XCTAssertNotNil(progress.currentPhase)
                XCTAssertEqual(progress.startTime.timeIntervalSince1970,
                               startTime.timeIntervalSince1970,
                               accuracy: 1.0)
            }
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)

        // Validate progress sequence
        XCTAssertFalse(progressReports.isEmpty)

        // Check that progress is generally increasing
        for i in 1..<progressReports.count {
            XCTAssertGreaterThanOrEqual(
                progressReports[i].currentProgress,
                progressReports[i - 1].currentProgress,
                "Progress should not decrease"
            )
        }

        // Verify all expected phases are present
        let phases = Set(progressReports.map { $0.currentPhase })
        XCTAssertTrue(phases.contains(.initializing))
        XCTAssertTrue(phases.contains(.extracting))
        XCTAssertTrue(phases.contains(.complete))
    }

    func testAudioFormatValidation() {
        guard let testVideoURL = testFileGenerator.createMockMP4File() else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Format validation")

        audioProcessor.extractAudio(from: testVideoURL.path) { result in
            switch result {
            case .success(let audioFile):
                let format = audioFile.format

                // Validate basic format properties
                XCTAssertFalse(format.codec.isEmpty)
                XCTAssertGreaterThan(format.sampleRate, 0)
                XCTAssertGreaterThan(format.channels, 0)
                XCTAssertGreaterThan(format.duration, 0)

                // Validate format compatibility
                XCTAssertTrue(format.isValid)
                XCTAssertNil(format.validationError)

                // Check reasonable values
                XCTAssertLessThanOrEqual(format.channels, 8) // Reasonable channel count
                XCTAssertGreaterThan(format.sampleRate, 8000) // Minimum acceptable sample rate
                XCTAssertLessThan(format.sampleRate, 192000) // Maximum reasonable sample rate

            case .failure(let error):
                XCTFail("Audio extraction should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testTemporaryFileCleanup() {
        guard let testVideoURL = testFileGenerator.createMockMP4File() else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Temporary file cleanup")
        var tempFilePath: String?

        audioProcessor.extractAudio(from: testVideoURL.path) { result in
            switch result {
            case .success(let audioFile):
                tempFilePath = audioFile.temporaryPath
                XCTAssertNotNil(tempFilePath)
                XCTAssertTrue(FileManager.default.fileExists(atPath: tempFilePath!))

                // Test cleanup
                self.audioProcessor.cleanupTemporaryFiles(for: audioFile)
                XCTAssertFalse(FileManager.default.fileExists(atPath: tempFilePath!))

            case .failure(let error):
                XCTFail("Audio extraction should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }
}
