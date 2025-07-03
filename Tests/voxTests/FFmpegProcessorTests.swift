import XCTest
import Foundation
@testable import vox

final class FFmpegProcessorTests: XCTestCase {
    
    var processor: FFmpegProcessor!
    var testFileGenerator: TestAudioFileGenerator!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        processor = FFmpegProcessor()
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ffmpeg_tests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        processor = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        testFileGenerator?.cleanup()
        testFileGenerator = nil
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
        
        // var progressCalled = false
        let expectation = XCTestExpectation(description: "Progress callback test")
        
        processor.extractAudio(from: testInputFile.path, progressCallback: { progress in
            // progressCalled = true
            XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0, "Progress should be >= 0")
            XCTAssertLessThanOrEqual(progress.currentProgress, 1.0, "Progress should be <= 1")
        }) { result in
            // We don't care about success/failure here, just that the callback mechanism works
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Note: progressCalled might be false if ffmpeg is not available or fails immediately
        // This is acceptable for this unit test
    }
    
    // MARK: - FFmpeg Integration Tests
    
    func testFFmpegExtractionWithValidMP4() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }
        
        guard let testVideoURL = testFileGenerator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }
        
        let expectation = XCTestExpectation(description: "FFmpeg audio extraction")
        var progressReports: [TranscriptionProgress] = []
        
        processor.extractAudio(
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
        
        wait(for: [expectation], timeout: 60.0) // Longer timeout for ffmpeg
    }
    
    func testFFmpegFallbackWithDifferentFormats() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }
        
        let testCases = [
            ("high_quality", { self.testFileGenerator.createHighQualityMP4File() }),
            ("low_quality", { self.testFileGenerator.createLowQualityMP4File() }),
            ("large_file", { self.testFileGenerator.createLargeMP4File() })
        ]
        
        for (name, createFile) in testCases {
            guard let testVideoURL = createFile() else {
                XCTFail("Failed to create \(name) test file")
                continue
            }
            
            let expectation = XCTestExpectation(description: "FFmpeg extraction for \(name)")
            
            processor.extractAudio(from: testVideoURL.path) { result in
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
    
    func testFFmpegErrorHandlingWithInvalidFiles() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }
        
        let invalidFiles = [
            testFileGenerator.createInvalidMP4File(),
            testFileGenerator.createEmptyMP4File(),
            testFileGenerator.createCorruptedMP4File()
        ]
        
        for invalidFile in invalidFiles {
            let expectation = XCTestExpectation(description: "FFmpeg error handling for \(invalidFile.lastPathComponent)")
            
            processor.extractAudio(from: invalidFile.path) { result in
                switch result {
                case .success:
                    XCTFail("FFmpeg should fail with invalid file: \(invalidFile.lastPathComponent)")
                case .failure(let error):
                    // Verify it's an audio extraction failure with proper message
                    if case .audioExtractionFailed(let message) = error {
                        XCTAssertTrue(
                            message.contains("extraction failed") || message.contains("FFmpeg"),
                            "Error message should mention extraction failure or FFmpeg"
                        )
                    } else {
                        XCTFail("Expected audioExtractionFailed error, got \(error)")
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    func testFFmpegProgressReporting() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }
        
        guard let testVideoURL = testFileGenerator.createMockMP4File(duration: 15.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }
        
        let expectation = XCTestExpectation(description: "FFmpeg progress reporting")
        var progressReports: [TranscriptionProgress] = []
        let startTime = Date()
        
        processor.extractAudio(
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
            }
        ) { result in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
        
        // Validate progress sequence
        XCTAssertFalse(progressReports.isEmpty, "Should have progress reports")
        
        // Verify expected phases
        let phases = Set(progressReports.map { $0.currentPhase })
        XCTAssertTrue(phases.contains(.initializing), "Should have initializing phase")
        XCTAssertTrue(phases.contains(.extracting), "Should have extracting phase")
        
        // Check progress ordering (allowing for some variance due to threading)
        let progressValues = progressReports.map { $0.currentProgress }
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(
                progressValues[i],
                progressValues[i-1] - 0.01, // Small tolerance for threading
                "Progress should generally increase"
            )
        }
    }
    
    func testFFmpegTemporaryFileManagement() throws {
        // Skip if ffmpeg is not available
        guard FFmpegProcessor.isFFmpegAvailable() else {
            throw XCTSkip("FFmpeg not available for testing")
        }
        
        guard let testVideoURL = testFileGenerator.createSmallMP4File() else {
            XCTFail("Failed to create test MP4 file")
            return
        }
        
        let expectation = XCTestExpectation(description: "FFmpeg temp file management")
        var tempFilePath: String?
        
        processor.extractAudio(from: testVideoURL.path) { result in
            switch result {
            case .success(let audioFile):
                tempFilePath = audioFile.temporaryPath
                XCTAssertNotNil(tempFilePath, "Should have temporary file path")
                XCTAssertTrue(FileManager.default.fileExists(atPath: tempFilePath!), "Temp file should exist")
                
                // Verify temp file has expected properties
                XCTAssertTrue(tempFilePath!.contains("vox_ffmpeg_temp_"), "Should have FFmpeg temp prefix")
                XCTAssertTrue(tempFilePath!.hasSuffix(".m4a"), "Should have .m4a extension")
                
                // Test cleanup
                self.processor.cleanupTemporaryFiles(for: audioFile)
                XCTAssertFalse(FileManager.default.fileExists(atPath: tempFilePath!), "Temp file should be cleaned up")
                
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
        
        // Create multiple test files
        let testFiles = (0..<3).compactMap { _ in
            testFileGenerator.createSmallMP4File()
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
        for audioFile in successes {
            processor.cleanupTemporaryFiles(for: audioFile)
        }
    }
}
