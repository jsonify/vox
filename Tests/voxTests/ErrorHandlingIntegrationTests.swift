import XCTest
import Foundation
@testable import vox

/// Core error handling integration tests for file input scenarios
final class ErrorHandlingIntegrationTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("error_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - File Input Error Scenarios
    
    func testNonExistentFileError() throws {
        let nonExistentFile = "/path/that/does/not/exist.mp4"
        let expectation = XCTestExpectation(description: "Non-existent file error")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: nonExistentFile) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with non-existent file")
            case .failure(let error):
                // Validate error type and message
                XCTAssertTrue(error is VoxError, "Should return VoxError")
                
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("file") ||
                    errorDescription.localizedCaseInsensitiveContains("not found") ||
                    errorDescription.localizedCaseInsensitiveContains("exist"),
                    "Error should mention file not found: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testInvalidMP4FileError() throws {
        let invalidFile = testFileGenerator.createInvalidMP4File()
        let expectation = XCTestExpectation(description: "Invalid MP4 file error")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: invalidFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with invalid MP4 file")
            case .failure(let error):
                // Validate error handling
                XCTAssertTrue(error is VoxError, "Should return VoxError")
                
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                
                // Error should provide useful information
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("invalid") ||
                    errorDescription.localizedCaseInsensitiveContains("format") ||
                    errorDescription.localizedCaseInsensitiveContains("corrupt"),
                    "Error should mention invalid format: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    func testEmptyFileError() throws {
        let emptyFile = testFileGenerator.createEmptyMP4File()
        let expectation = XCTestExpectation(description: "Empty file error")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: emptyFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with empty file")
            case .failure(let error):
                // Validate error handling
                XCTAssertTrue(error is VoxError, "Should return VoxError")
                
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("empty") ||
                    errorDescription.localizedCaseInsensitiveContains("invalid") ||
                    errorDescription.localizedCaseInsensitiveContains("size"),
                    "Error should mention empty file: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testCorruptedFileError() throws {
        let corruptedFile = testFileGenerator.createCorruptedMP4File()
        let expectation = XCTestExpectation(description: "Corrupted file error")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: corruptedFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with corrupted file")
            case .failure(let error):
                // Validate error handling
                XCTAssertTrue(error is VoxError, "Should return VoxError")
                
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("corrupt") ||
                    errorDescription.localizedCaseInsensitiveContains("invalid") ||
                    errorDescription.localizedCaseInsensitiveContains("damaged"),
                    "Error should mention corruption: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    func testVideoOnlyFileError() throws {
        guard let videoOnlyFile = testFileGenerator.createVideoOnlyMP4File() else {
            XCTFail("Failed to create video-only file")
            return
        }
        
        let expectation = XCTestExpectation(description: "Video-only file error")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: videoOnlyFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with video-only file")
            case .failure(let error):
                // Validate error handling
                XCTAssertTrue(error is VoxError, "Should return VoxError")
                
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("audio") ||
                    errorDescription.localizedCaseInsensitiveContains("track") ||
                    errorDescription.localizedCaseInsensitiveContains("sound"),
                    "Error should mention missing audio: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    // MARK: - Concurrent Processing Error Scenarios
    
    func testConcurrentProcessingErrors() throws {
        // Test error handling in concurrent processing scenarios
        let invalidFiles = [
            testFileGenerator.createInvalidMP4File(),
            testFileGenerator.createEmptyMP4File(),
            testFileGenerator.createCorruptedMP4File()
        ]
        
        let expectation = XCTestExpectation(description: "Concurrent processing errors")
        let group = DispatchGroup()
        
        var results: [Result<AudioFile, VoxError>] = []
        let resultsLock = NSLock()
        
        for invalidFile in invalidFiles {
            group.enter()
            let audioProcessor = AudioProcessor()
            
            audioProcessor.extractAudio(from: invalidFile.path) { result in
                resultsLock.lock()
                results.append(result)
                resultsLock.unlock()
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // All processing should complete (with failures)
            XCTAssertEqual(results.count, invalidFiles.count,
                "All files should be processed")
            
            // All should fail
            let failureCount = results.filter { result in
                if case .failure = result {
                    return true
                }
                return false
            }.count
            
            XCTAssertEqual(failureCount, invalidFiles.count,
                "All invalid files should fail")
            
            // Validate error types
            for result in results {
                if case .failure(let error) = result {
                    XCTAssertTrue(error is VoxError, "Should return VoxError")
                    XCTAssertFalse(error.localizedDescription.isEmpty,
                        "Error should have description")
                }
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Recovery and Cleanup Error Scenarios
    
    func testTempFileCleanupAfterErrors() throws {
        let invalidFile = testFileGenerator.createInvalidMP4File()
        let expectation = XCTestExpectation(description: "Temp file cleanup after error")
        
        // Monitor temp directory before processing
        let tempFileCount = countTempFiles()
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: invalidFile.path) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with invalid file")
            case .failure:
                // Validate temp files are cleaned up even after errors
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let finalTempFileCount = self.countTempFiles()
                    XCTAssertEqual(finalTempFileCount, tempFileCount,
                        "Temp files should be cleaned up after errors")
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    // MARK: - Helper Methods
    
    private func countTempFiles() -> Int {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            return files.filter { $0.contains("vox_") }.count
        } catch {
            return 0
        }
    }
}