import XCTest
import Foundation
import AVFoundation
@testable import vox

final class AudioProcessorTests: XCTestCase {
    var audioProcessor: AudioProcessor?
    var tempDirectory: URL?
    var testFileGenerator: TestAudioFileGenerator?

    override func setUp() {
        super.setUp()
        audioProcessor = AudioProcessor()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox_tests_\(UUID().uuidString)")
        if let tempDir = tempDirectory {
            try? FileManager.default.createDirectory(
                at: tempDir, 
                withIntermediateDirectories: true
            )
        }
        testFileGenerator = TestAudioFileGenerator.shared
    }

    override func tearDown() {
        audioProcessor = nil
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        testFileGenerator?.cleanup()
        testFileGenerator = nil
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testAudioProcessorCreation() {
        let processor = AudioProcessor()
        XCTAssertNotNil(processor)
    }

    // MARK: - File Validation Tests

    func testExtractAudioFromNonexistentFile() {
        let nonexistentPath = "/nonexistent/path/video.mp4"
        let expectation = XCTestExpectation(description: "Extract audio completion")

        audioProcessor?.extractAudio(from: nonexistentPath) { result in
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
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        
        let invalidFile = tempDir.appendingPathComponent("test.txt")
        let testData = Data("not a video file".utf8)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: invalidFile.path, 
            contents: testData
        ))

        let expectation = XCTestExpectation(description: "Extract audio completion")

        audioProcessor?.extractAudio(from: invalidFile.path) { result in
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
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        
        let invalidMP4File = tempDir.appendingPathComponent("fake.mp4")
        let testData = Data("not actually an mp4 file".utf8)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: invalidMP4File.path, 
            contents: testData
        ))

        let expectation = XCTestExpectation(description: "Extract audio completion")

        audioProcessor?.extractAudio(from: invalidMP4File.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with invalid MP4 content")
            case .failure(let error):
                switch error {
                case .unsupportedFormat, .audioExtractionFailed:
                    // Expected error cases for invalid MP4 content
                    break
                default:
                    XCTFail("Expected unsupportedFormat or audioExtractionFailed error, got \(error)")
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

        audioProcessor?.extractAudio(
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
            audioProcessor?.extractAudio(from: path) { result in
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
                        XCTFail("Expected invalidInputFile or unsupportedFormat error, got \(error)")
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

    // MARK: - AVFoundation Processing Tests

    func testSuccessfulAudioExtractionFromValidMP4() {
        guard let generator = testFileGenerator,
              let testVideoURL = generator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Audio extraction completion")
        var progressReports: [TranscriptionProgress] = []

        audioProcessor?.extractAudio(
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
                    guard let temporaryPath = audioFile.temporaryPath else {
                        XCTFail("Temporary path should not be nil")
                        return
                    }
                    XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryPath))
                    XCTAssertEqual(audioFile.format.codec, "m4a")
                    XCTAssertGreaterThan(audioFile.format.duration, 0)

                    // Verify progress was reported
                    XCTAssertFalse(progressReports.isEmpty)
                    XCTAssertEqual(progressReports.last?.currentProgress, 1.0)

                case .failure(let error):
                    XCTFail("Audio extraction should succeed: \(error)")
                }
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 30.0)
    }

    func testAudioExtractionWithDifferentFormats() {
        let testCases = [
            ("high_quality", { self.testFileGenerator?.createHighQualityMP4File() }),
            ("low_quality", { self.testFileGenerator?.createLowQualityMP4File() }),
            ("small_file", { self.testFileGenerator?.createSmallMP4File() })
        ]

        for (name, createFile) in testCases {
            guard let testVideoURL = createFile() else {
                XCTFail("Failed to create \(name) test file")
                continue
            }

            let expectation = XCTestExpectation(description: "Audio extraction for \(name)")

            audioProcessor?.extractAudio(from: testVideoURL.path) { result in
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

    func testAudioFormatValidation() {
        guard let generator = testFileGenerator,
              let testVideoURL = generator.createMockMP4File() else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Format validation")

        audioProcessor?.extractAudio(from: testVideoURL.path) { result in
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

    func testCleanupTemporaryFilesForAudioFile() {
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        
        let tempFileURL = tempDir.appendingPathComponent("audio_file_cleanup.m4a")
        let testData = Data("test audio data".utf8)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: tempFileURL.path, 
            contents: testData
        ))

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

        audioProcessor?.cleanupTemporaryFiles(for: audioFile)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }
}
