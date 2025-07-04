import XCTest
import Foundation
import AVFoundation
@testable import vox

final class AudioProcessingErrorTests: XCTestCase {
    var audioProcessor: AudioProcessor?
    var ffmpegProcessor: FFmpegProcessor?
    var testFileGenerator: TestAudioFileGenerator?
    var tempDirectory: URL?

    override func setUp() {
        super.setUp()
        audioProcessor = AudioProcessor()
        ffmpegProcessor = FFmpegProcessor()
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("error_tests_\(UUID().uuidString)")
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

    // MARK: - File System Error Tests

    func testExtractionWithNonexistentFile() {
        let nonexistentPath = "/this/path/absolutely/does/not/exist/video.mp4"
        let expectation = XCTestExpectation(description: "Nonexistent file error")

        audioProcessor?.extractAudio(from: nonexistentPath) { result in
            switch result {
            case .success:
                XCTFail("Should fail with nonexistent file")
            case .failure(let error):
                if case .invalidInputFile(let message) = error {
                    XCTAssertTrue(message.contains(nonexistentPath))
                    XCTAssertTrue(message.contains("does not exist"))
                } else {
                    XCTFail("Expected invalidInputFile error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testExtractionWithEmptyPath() {
        let expectation = XCTestExpectation(description: "Empty path error")

        audioProcessor?.extractAudio(from: "") { result in
            switch result {
            case .success:
                XCTFail("Should fail with empty path")
            case .failure(let error):
                if case .invalidInputFile = error {
                    // Expected error case
                } else {
                    XCTFail("Expected invalidInputFile error for empty path, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testExtractionWithDirectoryPath() {
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        let directoryPath = tempDir.path
        let expectation = XCTestExpectation(description: "Directory path error")

        audioProcessor?.extractAudio(from: directoryPath) { result in
            switch result {
            case .success:
                XCTFail("Should fail with directory path")
            case .failure(let error):
                if case .invalidInputFile = error {
                    // Expected error case
                } else {
                    XCTFail("Expected invalidInputFile error for directory path, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testExtractionWithInvalidExtension() {
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        let textFile = tempDir.appendingPathComponent("not_a_video.txt")
        guard let testData = "This is just text, not a video file".data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }
        FileManager.default.createFile(atPath: textFile.path, contents: testData)

        let expectation = XCTestExpectation(description: "Invalid extension error")

        audioProcessor?.extractAudio(from: textFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should fail with invalid extension")
            case .failure(let error):
                if case .unsupportedFormat(let message) = error {
                    XCTAssertTrue(message.contains("not a valid MP4"))
                } else {
                    XCTFail("Expected unsupportedFormat error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Invalid File Content Tests

    func testExtractionWithInvalidMP4Content() {
        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not available")
            return
        }
        let invalidMP4 = generator.createInvalidMP4File()
        let expectation = XCTestExpectation(description: "Invalid MP4 content error")

        audioProcessor?.extractAudio(from: invalidMP4.path) { result in
            switch result {
            case .success:
                XCTFail("Should fail with invalid MP4 content")
            case .failure(let error):
                // Should be either unsupportedFormat or audioExtractionFailed
                switch error {
                case .unsupportedFormat, .audioExtractionFailed:
                    // Expected error cases
                    break
                default:
                    XCTFail("Expected unsupportedFormat or audioExtractionFailed error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testExtractionWithEmptyMP4File() {
        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not available")
            return
        }
        let emptyMP4 = generator.createEmptyMP4File()
        let expectation = XCTestExpectation(description: "Empty MP4 file error")

        audioProcessor?.extractAudio(from: emptyMP4.path) { result in
            switch result {
            case .success:
                XCTFail("Should fail with empty MP4 file")
            case .failure(let error):
                if case .audioExtractionFailed = error {
                    // Expected error case
                } else {
                    XCTFail("Expected audioExtractionFailed error for empty MP4 file, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testExtractionWithCorruptedMP4File() {
        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not available")
            return
        }
        let corruptedMP4 = generator.createCorruptedMP4File()
        let expectation = XCTestExpectation(description: "Corrupted MP4 file error")

        audioProcessor?.extractAudio(from: corruptedMP4.path) { result in
            switch result {
            case .success:
                XCTFail("Should fail with corrupted MP4 file")
            case .failure(let error):
                if case .audioExtractionFailed = error {
                    // Expected error case
                } else {
                    XCTFail("Expected audioExtractionFailed error for corrupted MP4 file, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testExtractionWithVideoOnlyMP4File() {
        guard let generator = testFileGenerator,
              let videoOnlyMP4 = generator.createVideoOnlyMP4File() else {
            XCTFail("Failed to create video-only MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Video-only MP4 file error")

        audioProcessor?.extractAudio(from: videoOnlyMP4.path) { result in
            switch result {
            case .success:
                XCTFail("Should fail with video-only MP4 file")
            case .failure(let error):
                switch error {
                case .audioExtractionFailed, .unsupportedFormat:
                    // Expected error cases for video-only MP4 files
                    break
                default:
                    XCTFail("Expected audioExtractionFailed or unsupportedFormat error for video-only MP4 file, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15.0)
    }

    // MARK: - FFmpeg-Specific Error Tests

    func testFFmpegUnavailableError() {
        // Create a processor and test when ffmpeg is not available
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        let testFile = tempDir.appendingPathComponent("test.mp4")
        guard let testData = "fake mp4 data".data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }
        FileManager.default.createFile(atPath: testFile.path, contents: testData)

        let expectation = XCTestExpectation(description: "FFmpeg unavailable error")

        ffmpegProcessor?.extractAudio(from: testFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should fail with invalid MP4 or missing ffmpeg")
            case .failure(let error):
                if case .audioExtractionFailed(let message) = error {
                    XCTAssertTrue(
                        message.contains("ffmpeg") || message.contains("extraction failed"),
                        "Error message should mention ffmpeg or extraction failure"
                    )
                } else {
                    XCTFail("Expected audioExtractionFailed error for ffmpeg unavailable, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15.0)
    }
}
