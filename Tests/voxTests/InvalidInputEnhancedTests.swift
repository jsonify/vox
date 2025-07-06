import XCTest
import Foundation
@testable import vox

/// Enhanced invalid input testing with security and malicious content validation
/// Tests comprehensive edge cases for file input handling and security validation
final class InvalidInputEnhancedTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var tempDirectory: URL!
    private var maliciousFileGenerator: MaliciousFileGenerator!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        maliciousFileGenerator = MaliciousFileGenerator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid_input_enhanced_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        maliciousFileGenerator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        maliciousFileGenerator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Security Edge Case Testing
    
    func testPathTraversalAttackPrevention() throws {
        // Test various path traversal attempts
        let pathTraversalAttempts = [
            "../../../etc/passwd",
            "..\\..\\..\\windows\\system32\\config\\sam",
            "....//....//....//etc//passwd",
            "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
            "..%252f..%252f..%252fetc%252fpasswd"
        ]
        
        for maliciousPath in pathTraversalAttempts {
            let expectation = XCTestExpectation(description: "Path traversal prevention: \(maliciousPath)")
            
            var voxCommand = Vox()
            voxCommand.inputFile = maliciousPath
            voxCommand.format = .txt
            
            do {
                try voxCommand.run()
                XCTFail("Path traversal should be prevented: \(maliciousPath)")
            } catch {
                // Validate that error is properly handled
                XCTAssertTrue(error is VoxError, "Should return VoxError for path traversal")
                
                if let voxError = error as? VoxError {
                    let errorDescription = voxError.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("invalid") ||
                        errorDescription.localizedCaseInsensitiveContains("file") ||
                        errorDescription.localizedCaseInsensitiveContains("path"),
                        "Error should indicate invalid path: \(errorDescription)"
                    )
                }
            }
            
            expectation.fulfill()
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testUnicodeAndSpecialCharacterHandling() throws {
        // Test files with various Unicode and special characters
        let specialCharacterFilenames = [
            "test_file_with_émojis_🎵.mp4",
            "test_file_with_中文.mp4",
            "test_file_with_русский.mp4",
            "test_file_with_العربية.mp4",
            "test_file_with_🎵🎶🎹.mp4",
            "test file with spaces.mp4",
            "test\tfile\twith\ttabs.mp4",
            "test\nfile\nwith\nnewlines.mp4"
        ]
        
        for filename in specialCharacterFilenames {
            let testFile = tempDirectory.appendingPathComponent(filename)
            
            // Create a minimal valid MP4 file
            let minimalMP4Data = Data([
                0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // ftyp header
                0x6D, 0x70, 0x34, 0x31, 0x00, 0x00, 0x00, 0x00, // mp41 brand
                0x6D, 0x70, 0x34, 0x31, 0x69, 0x73, 0x6F, 0x6D  // compatible brands
            ])
            
            do {
                try minimalMP4Data.write(to: testFile)
            } catch {
                XCTFail("Failed to create test file with special characters: \(filename)")
                continue
            }
            
            let expectation = XCTestExpectation(description: "Unicode handling: \(filename)")
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: testFile.path) { result in
                switch result {
                case .success:
                    // Some files might succeed if they're valid
                    XCTAssertTrue(true, "Unicode filename handled successfully: \(filename)")
                case .failure(let error):
                    // Validate proper error handling for Unicode filenames
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, "Error should have description for Unicode filename")
                    XCTAssertFalse(errorDescription.contains("�"), "Error should not contain replacement characters")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 15.0)
        }
    }
    
    func testOversizedFileHandling() throws {
        // Test extremely large file handling
        let oversizedFile = tempDirectory.appendingPathComponent("oversized_test.mp4")
        
        // Create a file that's larger than reasonable for testing (simulated)
        let largeSize = 100 * 1024 * 1024 // 100MB for testing (would be larger in real scenario)
        let largeData = Data(repeating: 0x00, count: largeSize)
        
        do {
            try largeData.write(to: oversizedFile)
        } catch {
            throw XCTSkip("Cannot create large test file for oversized testing")
        }
        
        let expectation = XCTestExpectation(description: "Oversized file handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: oversizedFile.path) { result in
            switch result {
            case .success:
                XCTFail("Oversized file processing should fail or be handled gracefully")
            case .failure(let error):
                // Validate proper error handling for oversized files
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description for oversized file")
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("size") ||
                    errorDescription.localizedCaseInsensitiveContains("large") ||
                    errorDescription.localizedCaseInsensitiveContains("memory") ||
                    errorDescription.localizedCaseInsensitiveContains("space"),
                    "Error should mention size issue: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - File Format Edge Cases
    
    func testMaliciousMetadataHandling() throws {
        // Test files with potentially malicious metadata
        let maliciousMetadataFile = tempDirectory.appendingPathComponent("malicious_metadata.mp4")
        
        // Create a file with oversized metadata fields
        var maliciousData = Data()
        
        // MP4 header
        maliciousData.append(contentsOf: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])
        
        // Add extremely long metadata strings that could cause buffer issues
        let longMetadata = String(repeating: "A", count: 65536)
        maliciousData.append(longMetadata.data(using: .utf8) ?? Data())
        
        do {
            try maliciousData.write(to: maliciousMetadataFile)
        } catch {
            XCTFail("Failed to create malicious metadata file")
            return
        }
        
        let expectation = XCTestExpectation(description: "Malicious metadata handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: maliciousMetadataFile.path) { result in
            switch result {
            case .success:
                XCTFail("Malicious metadata file should not succeed")
            case .failure(let error):
                // Validate proper error handling for malicious metadata
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description for malicious metadata")
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("invalid") ||
                    errorDescription.localizedCaseInsensitiveContains("corrupt") ||
                    errorDescription.localizedCaseInsensitiveContains("format"),
                    "Error should mention format issue: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testZeroByteFileHandling() throws {
        // Test completely empty file
        let zeroByteFile = tempDirectory.appendingPathComponent("zero_byte.mp4")
        
        // Create truly empty file
        FileManager.default.createFile(atPath: zeroByteFile.path, contents: Data(), attributes: nil)
        
        let expectation = XCTestExpectation(description: "Zero byte file handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: zeroByteFile.path) { result in
            switch result {
            case .success:
                XCTFail("Zero byte file should not succeed")
            case .failure(let error):
                // Validate proper error handling for zero byte files
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description for zero byte file")
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
    
    // MARK: - System Resource Edge Cases
    
    func testConcurrentMaliciousFileProcessing() throws {
        // Test multiple malicious files processed concurrently
        let maliciousFiles = [
            maliciousFileGenerator.createPathTraversalFile(),
            maliciousFileGenerator.createOversizedMetadataFile(),
            maliciousFileGenerator.createCorruptedHeaderFile()
        ]
        
        let expectation = XCTestExpectation(description: "Concurrent malicious file processing")
        let group = DispatchGroup()
        
        var results: [Result<AudioFile, VoxError>] = []
        let resultsLock = NSLock()
        
        for maliciousFile in maliciousFiles {
            group.enter()
            let audioProcessor = AudioProcessor()
            
            audioProcessor.extractAudio(from: maliciousFile.path) { result in
                resultsLock.lock()
                results.append(result)
                resultsLock.unlock()
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // All processing should complete with failures
            XCTAssertEqual(results.count, maliciousFiles.count, "All files should be processed")
            
            // All should fail
            let failureCount = results.filter { result in
                if case .failure = result {
                    return true
                }
                return false
            }.count
            
            XCTAssertEqual(failureCount, maliciousFiles.count, "All malicious files should fail")
            
            // Validate error handling
            for result in results {
                if case .failure(let error) = result {
                    XCTAssertFalse(error.localizedDescription.isEmpty, "Error should have description")
                }
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 90.0)
    }
}

// MARK: - Malicious File Generator

class MaliciousFileGenerator {
    private var tempDirectory: URL
    private var createdFiles: [URL] = []
    
    init() {
        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("malicious_files_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create malicious file directory: \(error)")
        }
    }
    
    func createPathTraversalFile() -> URL {
        let file = tempDirectory.appendingPathComponent("path_traversal.mp4")
        
        // Create a file with path traversal in its content
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])
        data.append("../../../etc/passwd".data(using: .utf8) ?? Data())
        
        try? data.write(to: file)
        createdFiles.append(file)
        return file
    }
    
    func createOversizedMetadataFile() -> URL {
        let file = tempDirectory.appendingPathComponent("oversized_metadata.mp4")
        
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])
        
        // Add extremely long metadata
        let longString = String(repeating: "X", count: 32768)
        data.append(longString.data(using: .utf8) ?? Data())
        
        try? data.write(to: file)
        createdFiles.append(file)
        return file
    }
    
    func createCorruptedHeaderFile() -> URL {
        let file = tempDirectory.appendingPathComponent("corrupted_header.mp4")
        
        // Create file with corrupted MP4 header
        var data = Data()
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        data.append(Data(repeating: 0x00, count: 1024))
        
        try? data.write(to: file)
        createdFiles.append(file)
        return file
    }
    
    func cleanup() {
        for file in createdFiles {
            try? FileManager.default.removeItem(at: file)
        }
        try? FileManager.default.removeItem(at: tempDirectory)
        createdFiles.removeAll()
    }
}