import XCTest
import Foundation
@testable import vox

final class AudioProcessorTests: XCTestCase {
    
    var audioProcessor: AudioProcessor!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        audioProcessor = AudioProcessor()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("vox_tests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        audioProcessor = nil
        try? FileManager.default.removeItem(at: tempDirectory)
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
                // Should fail during validation or audio extraction
                XCTAssertTrue(error is VoxError)
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
                XCTAssertGreaterThanOrEqual(progress, 0.0)
                XCTAssertLessThanOrEqual(progress, 1.0)
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
                    XCTAssertTrue(error is VoxError)
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
            let newProcessor = AudioProcessor()
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
}

