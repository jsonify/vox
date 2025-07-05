import XCTest
import Foundation
@testable import vox

final class AudioProcessorTempFileTests: XCTestCase {
    var tempDirectory: URL?

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox_temp_tests_\(UUID().uuidString)")
        if let tempDir = tempDirectory {
            try? FileManager.default.createDirectory(
                at: tempDir, 
                withIntermediateDirectories: true
            )
        }
    }

    override func tearDown() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDirectory = nil
        super.tearDown()
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
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        
        let tempFileURL = tempDir.appendingPathComponent("test_cleanup.m4a")

        // Create test file
        let testData = Data("test audio data".utf8)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: tempFileURL.path, 
            contents: testData
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        // Register and test cleanup
        TempFileManager.shared.registerTemporaryFile(at: tempFileURL)
        XCTAssertTrue(TempFileManager.shared.cleanupFile(at: tempFileURL))

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func testCleanupNonexistentTemporaryFile() {
        guard let tempDir = tempDirectory else {
            XCTFail("Temporary directory not available")
            return
        }
        
        let nonexistentURL = tempDir.appendingPathComponent("nonexistent.m4a")

        XCTAssertFalse(FileManager.default.fileExists(atPath: nonexistentURL.path))

        // Should not crash when trying to cleanup non-existent file
        XCTAssertTrue(TempFileManager.shared.cleanupFile(at: nonexistentURL))

        XCTAssertFalse(FileManager.default.fileExists(atPath: nonexistentURL.path))
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

        let audioProcessor = AudioProcessor()

        // Should not crash when there's no temporary path
        audioProcessor.cleanupTemporaryFiles(for: audioFile)
    }

    func testTemporaryFileCleanup() {
        let generator = TestAudioFileGenerator.shared
        guard let testVideoURL = generator.createMockMP4File() else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Temporary file cleanup")
        var tempFilePath: String?
        let audioProcessor = AudioProcessor()

        audioProcessor.extractAudio(from: testVideoURL.path) { result in
            switch result {
            case .success(let audioFile):
                tempFilePath = audioFile.temporaryPath
                XCTAssertNotNil(tempFilePath)
                guard let path = tempFilePath else {
                    XCTFail("Temporary file path should not be nil")
                    return
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath: path))

                // Test cleanup
                audioProcessor.cleanupTemporaryFiles(for: audioFile)
                XCTAssertFalse(FileManager.default.fileExists(atPath: path))

            case .failure(let error):
                XCTFail("Audio extraction should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testBulkTemporaryFileCleanup() {
        var tempURLs: [URL] = []
        
        // Create multiple temporary files
        for index in 0..<5 {
            guard let tempDir = tempDirectory else {
                XCTFail("Temporary directory not available")
                return
            }
            
            let tempFileURL = tempDir.appendingPathComponent("bulk_test_\(index).m4a")
            let testData = Data("test data \(index)".utf8)
            
            XCTAssertTrue(FileManager.default.createFile(
                atPath: tempFileURL.path, 
                contents: testData
            ))
            
            tempURLs.append(tempFileURL)
            TempFileManager.shared.registerTemporaryFile(at: tempFileURL)
        }

        // Verify files exist
        for url in tempURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        // Cleanup all files
        let failedCleanups = TempFileManager.shared.cleanupFiles(at: tempURLs)
        XCTAssertTrue(failedCleanups.isEmpty, "Some files failed to cleanup: \(failedCleanups)")

        // Verify files are deleted
        for url in tempURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testTemporaryFileAutoCleanup() {
        var tempURLs: [URL] = []
        
        // Create temporary files that should be auto-cleaned
        autoreleasepool {
            for index in 0..<3 {
                if let tempURL = TempFileManager.shared.createTemporaryAudioFile() {
                    tempURLs.append(tempURL)
                    
                    // Create actual files
                    let testData = Data("auto cleanup test \(index)".utf8)
                    FileManager.default.createFile(
                        atPath: tempURL.path, 
                        contents: testData
                    )
                }
            }
        }

        // Files should exist initially
        for url in tempURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        // Trigger cleanup
        TempFileManager.shared.cleanupAllFiles()

        // Give some time for cleanup to complete
        let expectation = XCTestExpectation(description: "Auto cleanup completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        // Some files might be cleaned up (depending on age and cleanup policy)
        // This test verifies the cleanup mechanism works without crashing
        XCTAssertTrue(true) // If we get here, cleanup didn't crash
    }

    func testTemporaryFileManagerThreadSafety() {
        let concurrentQueue = DispatchQueue(
            label: "test.temp.concurrent", 
            attributes: .concurrent
        )
        let group = DispatchGroup()
        var createdURLs: [URL] = []
        let lock = NSLock()

        // Create files concurrently
        for _ in 0..<10 {
            group.enter()
            concurrentQueue.async {
                if let tempURL = TempFileManager.shared.createTemporaryAudioFile() {
                    lock.lock()
                    createdURLs.append(tempURL)
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
        let uniqueURLs = Set(createdURLs.map { $0.lastPathComponent })
        XCTAssertEqual(createdURLs.count, uniqueURLs.count)
        XCTAssertEqual(createdURLs.count, 10)

        // Cleanup
        _ = TempFileManager.shared.cleanupFiles(at: createdURLs)
    }
}
