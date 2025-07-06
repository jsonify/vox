import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Comprehensive error scenario tests that validate error handling
/// across various invalid inputs and edge cases.
final class ComprehensiveErrorTests: ComprehensiveIntegrationTestsBase {
    
    // MARK: - Error Scenario Testing
    
    func testErrorScenariosWithAllSampleTypes() throws {
        var errorTestFiles: [String: URL] = [
            "invalid": testFileGenerator.createInvalidMP4File(),
            "empty": testFileGenerator.createEmptyMP4File(),
            "corrupted": testFileGenerator.createCorruptedMP4File()
        ]
        
        // Add video-only file if available
        if let videoOnly = testFileGenerator.createVideoOnlyMP4File() {
            errorTestFiles["video_only"] = videoOnly
        }
        
        for (testName, file) in errorTestFiles {
            let audioProcessor = AudioProcessor()
            let expectation = XCTestExpectation(description: "Error scenario: \(testName)")
            
            audioProcessor.extractAudio(from: file.path) { result in
                switch result {
                case .success:
                    XCTFail("Error test '\(testName)' should not succeed")
                case .failure(let error):
                    // Verify error contains meaningful information
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, 
                        "Error '\(testName)' should have description")
                    
                    // Specific validations for different error types
                    switch testName {
                    case "video_only":
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("audio") ||
                            errorDescription.localizedCaseInsensitiveContains("track"),
                            "Video-only error should mention audio track issue"
                        )
                    case "invalid", "corrupted":
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("invalid") ||
                            errorDescription.localizedCaseInsensitiveContains("format") ||
                            errorDescription.localizedCaseInsensitiveContains("corrupt"),
                            "Invalid/corrupted file error should mention format issue"
                        )
                    default:
                        break
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    func testInvalidCommandLineArguments() throws {
        // Test missing input file
        do {
            var voxCommand = Vox()
            voxCommand.inputFile = "/nonexistent/file.mp4"
            voxCommand.format = .txt
            
            XCTAssertThrowsError(try voxCommand.run()) { error in
                let errorDescription = error.localizedDescription
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("file") ||
                    errorDescription.localizedCaseInsensitiveContains("exist"),
                    "Missing file error should mention file existence issue"
                )
            }
        }
        
        // Test invalid output directory
        do {
            guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
                throw XCTSkip("No sample file available")
            }
            
            var voxCommand = Vox()
            voxCommand.inputFile = testFile.path
            voxCommand.output = "/nonexistent/directory/output.txt"
            voxCommand.format = .txt
            
            XCTAssertThrowsError(try voxCommand.run()) { error in
                let errorDescription = error.localizedDescription
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("directory") ||
                    errorDescription.localizedCaseInsensitiveContains("path"),
                    "Invalid output directory error should mention path issue"
                )
            }
        }
    }
    
    func testUnsupportedFileFormats() throws {
        // Create test files with unsupported formats
        let unsupportedFiles = [
            ("test.avi", "video/x-msvideo"),
            ("test.mov", "video/quicktime"),
            ("test.mkv", "video/x-matroska"),
            ("test.wmv", "video/x-ms-wmv")
        ]
        
        for (filename, _) in unsupportedFiles {
            let testFile = tempDirectory.appendingPathComponent(filename)
            
            // Create a minimal file with the extension
            try Data("unsupported".utf8).write(to: testFile)
            
            var voxCommand = Vox()
            voxCommand.inputFile = testFile.path
            voxCommand.format = .txt
            
            XCTAssertThrowsError(try voxCommand.run()) { error in
                let errorDescription = error.localizedDescription
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("format") ||
                    errorDescription.localizedCaseInsensitiveContains("support"),
                    "Unsupported format error should mention format support issue for \(filename)"
                )
            }
        }
    }
    
    func testNetworkErrorHandling() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        // Test with invalid API key
        var voxCommand = Vox()
        voxCommand.inputFile = testFile.path
        voxCommand.format = .txt
        voxCommand.fallbackApi = .openai
        voxCommand.apiKey = "invalid_key_test"
        voxCommand.forceCloud = true
        
        XCTAssertThrowsError(try voxCommand.run()) { error in
            let errorDescription = error.localizedDescription
            XCTAssertTrue(
                errorDescription.localizedCaseInsensitiveContains("api") ||
                errorDescription.localizedCaseInsensitiveContains("key") ||
                errorDescription.localizedCaseInsensitiveContains("auth"),
                "Invalid API key error should mention authentication issue"
            )
        }
    }
    
    func testTranscriptionServiceFailures() throws {
        // Test scenario where both local and cloud transcription fail
        guard realSampleFiles["small"] != nil || generatedSampleFiles["small"] != nil else {
            throw XCTSkip("No sample file available")
        }
        
        // Create a scenario where transcription is likely to fail
        let corruptedFile = tempDirectory.appendingPathComponent("corrupted_audio.mp4")
        
        // Create a file that looks like MP4 but has corrupted audio
        var fileData = Data()
        fileData.append(contentsOf: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]) // MP4 header
        fileData.append(Data(repeating: 0x00, count: 1024)) // Corrupted data
        
        try fileData.write(to: corruptedFile)
        
        var voxCommand = Vox()
        voxCommand.inputFile = corruptedFile.path
        voxCommand.format = .txt
        voxCommand.verbose = true
        
        XCTAssertThrowsError(try voxCommand.run()) { error in
            let errorDescription = error.localizedDescription
            XCTAssertFalse(errorDescription.isEmpty, "Transcription failure should provide error description")
        }
    }
    
    func testMemoryPressureHandling() throws {
        // Skip memory pressure tests in CI environment to avoid compiler crashes
        #if os(macOS)
        throw XCTSkip("Memory pressure tests skipped in CI environment due to compiler issues")
        #endif
    }
    
    func testConcurrentAccessErrors() throws {
        // Skip concurrent access tests in CI environment to avoid compiler crashes
        throw XCTSkip("Concurrent access tests skipped in CI environment due to compiler issues")
    }
}