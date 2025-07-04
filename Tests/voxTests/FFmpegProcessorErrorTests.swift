import XCTest
import Foundation
@testable import vox

final class FFmpegProcessorErrorTests: XCTestCase {
    var processor: FFmpegProcessor?
    var testFileGenerator: TestAudioFileGenerator?
    var tempDirectory: URL?

    override func setUp() {
        super.setUp()
        processor = FFmpegProcessor()
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg_error_tests_\(UUID().uuidString)")
        
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

    func testExtractAudioWithNonexistentFile() {
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let expectation = XCTestExpectation(description: "Extraction should fail with nonexistent file")
        let nonexistentPath = "/nonexistent/file.mp4"

        proc.extractAudio(from: nonexistentPath) { result in
            switch result {
            case .success:
                XCTFail("Extraction should fail with nonexistent file")
            case .failure(let error):
                if case .invalidInputFile(let path) = error {
                    XCTAssertEqual(path, "File does not exist: \(nonexistentPath)")
                } else {
                    XCTFail("Should return invalidInputFile error")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testExtractAudioWithoutFFmpeg() {
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        // Create a mock input file that exists
        let tempDir = FileManager.default.temporaryDirectory
        let testInputFile = tempDir.appendingPathComponent("test_input.mp4")

        // Create a dummy file
        FileManager.default.createFile(atPath: testInputFile.path, contents: Data("dummy".utf8), attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: testInputFile)
        }

        // If ffmpeg is not available, this should fail appropriately
        let expectation = XCTestExpectation(description: "Extraction behavior with/without ffmpeg")

        proc.extractAudio(from: testInputFile.path) { result in
            // We can't predict if ffmpeg is available, so we just test that we get some result
            switch result {
            case .success:
                // If ffmpeg is available and somehow processes our dummy file
                break
            case .failure(let error):
                // Expected if ffmpeg is not available or file is invalid
                XCTAssertTrue(error.localizedDescription.contains("ffmpeg") ||
                                error.localizedDescription.contains("extraction failed"),
                              "Error should be related to ffmpeg or extraction: \(error.localizedDescription)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testFFmpegErrorHandlingWithInvalidFiles() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }

        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not initialized")
            return
        }
        
        let invalidFiles = [
            generator.createInvalidMP4File(),
            generator.createEmptyMP4File(),
            generator.createCorruptedMP4File()
        ]

        for invalidFile in invalidFiles {
            let expectation = XCTestExpectation(
                description: "FFmpeg error handling for \(invalidFile.lastPathComponent)"
            )

            guard let proc = processor else {
                XCTFail("Processor not initialized")
                continue
            }
            
            proc.extractAudio(from: invalidFile.path) { result in
                switch result {
                case .success:
                    XCTFail("FFmpeg should fail with invalid file: \(invalidFile.lastPathComponent)")
                case .failure(let error):
                    // Verify it's an audio extraction failure with proper message
                    XCTAssertTrue(
                        error.localizedDescription.contains("extraction failed") ||
                        error.localizedDescription.contains("invalid") ||
                        error.localizedDescription.contains("ffmpeg"),
                        "Error should indicate extraction failure: \(error.localizedDescription)"
                    )
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 30.0)
        }
    }
}
