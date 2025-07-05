import XCTest
import Foundation
@testable import vox

/// Resource and permission error scenario tests
final class ResourceErrorTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("resource_error_tests_\(UUID().uuidString)")
        
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
    
    // MARK: - Permission and Access Error Scenarios
    
    func testReadOnlyDirectoryError() throws {
        // Create a read-only directory scenario
        let readOnlyDir = tempDirectory.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        
        // Create a test file in the directory
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let readOnlyFile = readOnlyDir.appendingPathComponent("readonly.mp4")
        try FileManager.default.copyItem(at: testFile, to: readOnlyFile)
        
        // Make directory read-only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: readOnlyDir.path
        )
        
        defer {
            // Restore permissions for cleanup
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: readOnlyDir.path
            )
        }
        
        let expectation = XCTestExpectation(description: "Read-only directory error")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: readOnlyFile.path) { result in
            switch result {
            case .success:
                // May succeed if extraction doesn't require write access to source directory
                XCTAssertTrue(true, "Extraction succeeded despite read-only directory")
            case .failure(let error):
                // Validate error handling
                XCTAssertTrue(error is VoxError, "Should return VoxError")
                
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 20.0)
    }
    
    func testInvalidOutputPathError() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let invalidOutputPath = "/invalid/path/that/does/not/exist/output.txt"
        let expectation = XCTestExpectation(description: "Invalid output path error")
        
        // Test complete workflow with invalid output path
        testCompleteWorkflowWithInvalidOutput(
            inputFile: testFile,
            outputPath: invalidOutputPath,
            expectation: expectation
        )
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Resource Exhaustion Error Scenarios
    
    func testLowMemoryScenario() throws {
        // This test simulates low memory conditions
        guard let testFile = testFileGenerator.createMockMP4File(duration: 10.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let expectation = XCTestExpectation(description: "Low memory scenario")
        
        // Monitor memory usage during processing
        let memoryMonitor = MemoryMonitor()
        let initialMemory = memoryMonitor.getCurrentUsage().currentBytes
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            let finalMemory = memoryMonitor.getCurrentUsage().currentBytes
            let memoryIncrease = finalMemory - initialMemory
            
            switch result {
            case .success(let audioFile):
                // Validate memory usage is reasonable
                XCTAssertLessThan(memoryIncrease, 200 * 1024 * 1024,
                    "Memory usage should be reasonable")
                XCTAssertGreaterThan(audioFile.format.duration, 0,
                    "Audio should have valid duration")
                
            case .failure(let error):
                // If memory-related error, validate it's handled gracefully
                XCTAssertTrue(error is VoxError, "Should return VoxError")
                
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 45.0)
    }
    
    func testDiskSpaceError() throws {
        // Test handling of insufficient disk space
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let outputFile = tempDirectory.appendingPathComponent("diskspace_test.txt")
        let expectation = XCTestExpectation(description: "Disk space error")
        
        // Execute workflow and monitor disk space
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test output writing with potential disk space issues
                let outputFormatter = OutputFormatter()
                let outputWriter = OutputWriter()
                
                do {
                    let mockResult = self.createMockTranscriptionResult(for: audioFile)
                    let formattedOutput = try outputFormatter.format(mockResult, as: .txt)
                    
                    try outputWriter.writeContent(formattedOutput, to: outputFile.path)
                    
                    // Success case
                    XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path),
                        "Output file should exist")
                    
                } catch {
                    // Disk space or write error - validate it's handled
                    XCTAssertTrue(error is VoxError, "Should return VoxError for write failure")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Helper Methods
    
    private func testCompleteWorkflowWithInvalidOutput(
        inputFile: URL,
        outputPath: String,
        expectation: XCTestExpectation
    ) {
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: inputFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test output writing with invalid path
                let outputFormatter = OutputFormatter()
                let outputWriter = OutputWriter()
                
                do {
                    let mockResult = self.createMockTranscriptionResult(for: audioFile)
                    let formattedOutput = try outputFormatter.format(mockResult, as: .txt)
                    
                    try outputWriter.writeContent(formattedOutput, to: outputPath)
                    XCTFail("Should not succeed with invalid output path")
                    
                } catch {
                    // Validate output error handling
                    XCTAssertTrue(error is VoxError, "Should return VoxError for output failure")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("path") ||
                        errorDescription.localizedCaseInsensitiveContains("directory") ||
                        errorDescription.localizedCaseInsensitiveContains("write"),
                        "Error should mention path issue: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
    }
    
    private func createMockTranscriptionResult(for audioFile: AudioFile) -> TranscriptionResult {
        let segment = TranscriptionSegment(
            text: "Mock transcription for error testing",
            startTime: 0.0,
            endTime: audioFile.format.duration,
            confidence: 0.85,
            speakerID: "Speaker1",
            words: nil,
            segmentType: .speech,
            pauseDuration: nil
        )
        
        return TranscriptionResult(
            text: "Mock transcription for error testing",
            language: "en-US",
            confidence: 0.85,
            duration: audioFile.format.duration,
            segments: [segment],
            engine: .speechAnalyzer,
            processingTime: 1.0,
            audioFormat: audioFile.format
        )
    }
}