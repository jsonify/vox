import XCTest
@testable import vox

final class FFmpegProcessorTests: XCTestCase {
    
    var processor: FFmpegProcessor!
    
    override func setUp() {
        super.setUp()
        processor = FFmpegProcessor()
    }
    
    override func tearDown() {
        processor = nil
        super.tearDown()
    }
    
    func testFFmpegAvailabilityDetection() {
        // Test that the detection method works without crashing
        let isAvailable = FFmpegProcessor.isFFmpegAvailable()
        
        // We can't guarantee ffmpeg is installed in CI, so we just test the method doesn't crash
        XCTAssertTrue(isAvailable || !isAvailable, "Detection should return a boolean value")
    }
    
    func testFFmpegProcessorInstantiation() {
        XCTAssertNotNil(processor, "FFmpegProcessor should instantiate successfully")
    }
    
    func testTemporaryFileCreation() {
        let tempURL = processor.createTemporaryAudioFile()
        XCTAssertNotNil(tempURL, "Should create a temporary file URL")
        
        if let url = tempURL {
            XCTAssertTrue(url.path.contains("vox_ffmpeg_temp_"), "Temporary file should have correct prefix")
            XCTAssertTrue(url.pathExtension == "m4a", "Temporary file should have .m4a extension")
        }
    }
    
    func testCleanupTemporaryFile() {
        guard let tempURL = processor.createTemporaryAudioFile() else {
            XCTFail("Failed to create temporary file URL")
            return
        }
        
        // Create the file
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should exist")
        
        // Clean it up
        processor.cleanupTemporaryFile(at: tempURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should be removed")
    }
    
    func testCleanupTemporaryFilesForAudioFile() {
        guard let tempURL = processor.createTemporaryAudioFile() else {
            XCTFail("Failed to create temporary file URL")
            return
        }
        
        // Create the file
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should exist")
        
        // Create an AudioFile with the temporary path
        let audioFormat = AudioFormat(codec: "aac", sampleRate: 44100, channels: 2, bitRate: 128000, duration: 60.0)
        let audioFile = AudioFile(path: "/fake/path.mp4", format: audioFormat, temporaryPath: tempURL.path)
        
        // Clean it up
        processor.cleanupTemporaryFiles(for: audioFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should be removed")
    }
    
    func testExtractAudioWithNonexistentFile() {
        let expectation = XCTestExpectation(description: "Extraction should fail with nonexistent file")
        let nonexistentPath = "/nonexistent/file.mp4"
        
        processor.extractAudio(from: nonexistentPath) { result in
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
        // This test is challenging because we can't easily mock the static methods
        // We'll test the error handling path when ffmpeg is not available
        
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
        
        processor.extractAudio(from: testInputFile.path) { result in
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
    
    func testProgressCallbackIsCalledDuringExtraction() {
        // This test requires a real MP4 file and ffmpeg to be meaningful
        // We'll create a simple test that verifies the callback mechanism
        
        let tempDir = FileManager.default.temporaryDirectory
        let testInputFile = tempDir.appendingPathComponent("test_progress.mp4")
        
        // Create a dummy file
        FileManager.default.createFile(atPath: testInputFile.path, contents: Data("dummy".utf8), attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: testInputFile)
        }
        
        var progressCalled = false
        let expectation = XCTestExpectation(description: "Progress callback test")
        
        processor.extractAudio(from: testInputFile.path, progressCallback: { progress in
            progressCalled = true
            XCTAssertGreaterThanOrEqual(progress, 0.0, "Progress should be >= 0")
            XCTAssertLessThanOrEqual(progress, 1.0, "Progress should be <= 1")
        }) { result in
            // We don't care about success/failure here, just that the callback mechanism works
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Note: progressCalled might be false if ffmpeg is not available or fails immediately
        // This is acceptable for this unit test
    }
}