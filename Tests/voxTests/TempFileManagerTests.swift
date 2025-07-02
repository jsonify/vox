import XCTest
import Foundation
@testable import vox

final class TempFileManagerTests: XCTestCase {
    
    var tempFileManager: TempFileManager!
    
    override func setUp() {
        super.setUp()
        tempFileManager = TempFileManager.shared
    }
    
    override func tearDown() {
        // Cleanup any remaining test files
        tempFileManager.cleanupAllFiles()
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testCreateTemporaryAudioFile() {
        // Given: A request to create temporary audio file
        
        // When: Creating temporary audio file
        guard let tempURL = tempFileManager.createTemporaryAudioFile() else {
            XCTFail("Should be able to create temporary audio file")
            return
        }
        
        // Then: File should exist and have correct properties
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        XCTAssertTrue(tempURL.pathExtension == "m4a")
        XCTAssertTrue(tempURL.lastPathComponent.hasPrefix("vox_audio_"))
        XCTAssertTrue(tempFileManager.managedFileCount > 0)
        
        // Cleanup
        XCTAssertTrue(tempFileManager.cleanupFile(at: tempURL))
    }
    
    func testCreateTemporaryFileWithCustomExtension() {
        // Given: Custom file extension and prefix
        let customExtension = "wav"
        let customPrefix = "test_"
        
        // When: Creating temporary file with custom parameters
        guard let tempURL = tempFileManager.createTemporaryFile(extension: customExtension, prefix: customPrefix) else {
            XCTFail("Should be able to create temporary file with custom parameters")
            return
        }
        
        // Then: File should have correct properties
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        XCTAssertEqual(tempURL.pathExtension, customExtension)
        XCTAssertTrue(tempURL.lastPathComponent.hasPrefix(customPrefix))
        
        // Cleanup
        XCTAssertTrue(tempFileManager.cleanupFile(at: tempURL))
    }
    
    func testFileRegistration() {
        // Given: A manually created temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("manual_test_file.txt")
        
        // Create file manually
        FileManager.default.createFile(atPath: testURL.path, contents: Data("test".utf8), attributes: nil)
        
        let initialCount = tempFileManager.managedFileCount
        
        // When: Registering the file
        tempFileManager.registerTemporaryFile(at: testURL)
        
        // Then: File should be tracked
        XCTAssertEqual(tempFileManager.managedFileCount, initialCount + 1)
        
        // Cleanup
        XCTAssertTrue(tempFileManager.cleanupFile(at: testURL))
        XCTAssertEqual(tempFileManager.managedFileCount, initialCount)
    }
    
    // MARK: - Security Tests
    
    func testSecureFilePermissions() {
        // Given: A newly created temporary file
        guard let tempURL = tempFileManager.createTemporaryAudioFile() else {
            XCTFail("Should be able to create temporary file")
            return
        }
        
        // When: Checking file permissions
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            let permissions = attributes[.posixPermissions] as? NSNumber
            
            // Then: File should have secure permissions (0o600 = owner read/write only)
            XCTAssertEqual(permissions?.uint16Value, 0o600)
        } catch {
            XCTFail("Should be able to read file attributes: \(error)")
        }
        
        // Cleanup
        XCTAssertTrue(tempFileManager.cleanupFile(at: tempURL))
    }
    
    func testUniqueFileNames() {
        // Given: Multiple temporary file creation requests
        var createdURLs: [URL] = []
        
        // When: Creating multiple temporary files
        for _ in 0..<10 {
            guard let tempURL = tempFileManager.createTemporaryAudioFile() else {
                XCTFail("Should be able to create temporary file")
                return
            }
            createdURLs.append(tempURL)
        }
        
        // Then: All filenames should be unique
        let filenames = createdURLs.map { $0.lastPathComponent }
        let uniqueFilenames = Set(filenames)
        XCTAssertEqual(filenames.count, uniqueFilenames.count, "All filenames should be unique")
        
        // Cleanup
        let failedCleanups = tempFileManager.cleanupFiles(at: createdURLs)
        XCTAssertTrue(failedCleanups.isEmpty, "All files should be cleaned up successfully")
    }
    
    // MARK: - Cleanup Tests
    
    func testSingleFileCleanup() {
        // Given: A temporary file
        guard let tempURL = tempFileManager.createTemporaryAudioFile() else {
            XCTFail("Should be able to create temporary file")
            return
        }
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        // When: Cleaning up the file
        let cleanupSuccess = tempFileManager.cleanupFile(at: tempURL)
        
        // Then: File should be removed and cleanup should succeed
        XCTAssertTrue(cleanupSuccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }
    
    func testMultipleFileCleanup() {
        // Given: Multiple temporary files
        var tempURLs: [URL] = []
        for _ in 0..<5 {
            guard let tempURL = tempFileManager.createTemporaryAudioFile() else {
                XCTFail("Should be able to create temporary file")
                return
            }
            tempURLs.append(tempURL)
        }
        
        // Verify all files exist
        for url in tempURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        
        // When: Cleaning up all files
        let failedCleanups = tempFileManager.cleanupFiles(at: tempURLs)
        
        // Then: All files should be removed
        XCTAssertTrue(failedCleanups.isEmpty)
        for url in tempURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    func testCleanupAllFiles() {
        // Given: Multiple temporary files of different types
        let initialCount = tempFileManager.managedFileCount
        
        guard let audioFile = tempFileManager.createTemporaryAudioFile(),
              let textFile = tempFileManager.createTemporaryFile(extension: "txt", prefix: "test_") else {
            XCTFail("Should be able to create temporary files")
            return
        }
        
        // Verify files exist and are tracked
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: textFile.path))
        XCTAssertEqual(tempFileManager.managedFileCount, initialCount + 2)
        
        // When: Cleaning up all files
        tempFileManager.cleanupAllFiles()
        
        // Then: All managed files should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: textFile.path))
        XCTAssertEqual(tempFileManager.managedFileCount, initialCount)
    }
    
    // MARK: - Error Handling Tests
    
    func testCleanupNonExistentFile() {
        // Given: A URL that doesn't exist
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_file.txt")
        
        // When: Attempting to clean up non-existent file
        let result = tempFileManager.cleanupFile(at: nonExistentURL)
        
        // Then: Should handle gracefully (return true for unmanaged files)
        XCTAssertTrue(result)
    }
    
    func testCleanupFailureHandling() throws {
        // Given: A temporary file
        guard let tempURL = tempFileManager.createTemporaryAudioFile() else {
            XCTFail("Should be able to create temporary file")
            return
        }
        
        // Make file immutable to simulate cleanup failure
        do {
            // Set file as immutable
            try (tempURL as NSURL).setResourceValue(true, forKey: .isUserImmutableKey)
            
            // Make parent directory immutable too
            let parentURL = tempURL.deletingLastPathComponent()
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: parentURL.path)
            
            defer {
                // Restore permissions for cleanup
                try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: parentURL.path)
                try? (tempURL as NSURL).setResourceValue(false, forKey: .isUserImmutableKey)
                _ = tempFileManager.cleanupFile(at: tempURL)
            }
            
            // When: Attempting cleanup
            let cleanupSuccess = tempFileManager.cleanupFile(at: tempURL)
            
            // Then: Should handle failure gracefully
            XCTAssertFalse(cleanupSuccess)
            XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
            
        } catch {
            // If we can't set up the test conditions, skip this test
            throw XCTSkip("Could not set up immutable file test conditions: \(error)")
        }
    }
    
    // MARK: - Convenience Method Tests
    
    func testWithTemporaryFileOperation() {
        // Given: An operation that needs a temporary file
        var operationExecuted = false
        var capturedURL: URL?
        
        // When: Using withTemporaryFile convenience method
        let result = tempFileManager.withTemporaryFile(extension: "txt", prefix: "test_") { url in
            operationExecuted = true
            capturedURL = url
            
            // Verify file exists during operation
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            
            return "operation_result"
        }
        
        // Then: Operation should execute and file should be cleaned up
        XCTAssertTrue(operationExecuted)
        XCTAssertEqual(result, "operation_result")
        
        if let url = capturedURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    func testWithTemporaryAudioFileOperation() {
        // Given: An operation that needs a temporary audio file
        var operationExecuted = false
        var capturedURL: URL?
        
        // When: Using withTemporaryAudioFile convenience method
        let result = tempFileManager.withTemporaryAudioFile { url in
            operationExecuted = true
            capturedURL = url
            
            // Verify it's an audio file
            XCTAssertEqual(url.pathExtension, "m4a")
            XCTAssertTrue(url.lastPathComponent.hasPrefix("vox_audio_"))
            
            return 42
        }
        
        // Then: Operation should execute and file should be cleaned up
        XCTAssertTrue(operationExecuted)
        XCTAssertEqual(result, 42)
        
        if let url = capturedURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    func testWithTemporaryFileOperationThrowsError() {
        // Given: An operation that throws an error
        enum TestError: Error {
            case intentional
        }
        
        var operationExecuted = false
        var capturedURL: URL?
        
        // When: Using withTemporaryFile with throwing operation
        do {
            _ = try tempFileManager.withTemporaryFile(extension: "txt") { url in
                operationExecuted = true
                capturedURL = url
                throw TestError.intentional
            }
            XCTFail("Should have thrown an error")
        } catch TestError.intentional {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Then: File should still be cleaned up despite error
        XCTAssertTrue(operationExecuted)
        if let url = capturedURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentFileCreation() {
        // Given: Multiple concurrent file creation requests
        let expectation = XCTestExpectation(description: "Concurrent file creation")
        expectation.expectedFulfillmentCount = 10
        
        var createdURLs: [URL] = []
        let urlsLock = NSLock()
        
        // When: Creating files concurrently
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            if let url = tempFileManager.createTemporaryAudioFile() {
                urlsLock.lock()
                createdURLs.append(url)
                urlsLock.unlock()
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Then: All files should be created successfully and be unique
        XCTAssertEqual(createdURLs.count, 10)
        let uniqueURLs = Set(createdURLs.map { $0.lastPathComponent })
        XCTAssertEqual(uniqueURLs.count, 10)
        
        // Cleanup
        let failedCleanups = tempFileManager.cleanupFiles(at: createdURLs)
        XCTAssertTrue(failedCleanups.isEmpty)
    }
}