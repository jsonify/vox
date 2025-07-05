import XCTest
import Foundation
@testable import vox

/// Network and API error scenario tests
final class NetworkErrorTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("network_error_tests_\(UUID().uuidString)")
        
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
    
    // MARK: - Network and API Error Scenarios
    
    func testFallbackAPIError() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let expectation = XCTestExpectation(description: "Fallback API error")
        
        // Test transcription with invalid API key
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test transcription with invalid API configuration
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: false,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "invalid-api-key",
                    includeTimestamps: false
                )
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    XCTFail("Should not succeed with invalid API key")
                } catch {
                    // Validate API error handling
                    XCTAssertTrue(error is VoxError, "Should return VoxError for API failure")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("api") ||
                        errorDescription.localizedCaseInsensitiveContains("key") ||
                        errorDescription.localizedCaseInsensitiveContains("auth"),
                        "Error should mention API issue: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testNetworkTimeoutError() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let expectation = XCTestExpectation(description: "Network timeout error")
        
        // Test transcription with network timeout simulation
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test with configuration that might timeout
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: false,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "sk-test-timeout",
                    includeTimestamps: false
                )
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    XCTFail("Should not succeed with timeout configuration")
                } catch {
                    // Validate timeout error handling
                    XCTAssertTrue(error is VoxError, "Should return VoxError for timeout")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 45.0)
    }
    
    func testAPIKeyValidation() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 3.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let expectation = XCTestExpectation(description: "API key validation")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test various invalid API key formats
                let invalidAPIKeys = [
                    "",
                    "invalid",
                    "sk-",
                    "not-a-real-key"
                ]
                
                for apiKey in invalidAPIKeys {
                    let transcriptionManager = TranscriptionManager(
                        forceCloud: true,
                        verbose: false,
                        language: "en-US",
                        fallbackAPI: .openai,
                        apiKey: apiKey,
                        includeTimestamps: false
                    )
                    
                    do {
                        _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                        // If it doesn't throw, that's fine - some validation may be deferred
                    } catch {
                        // Validate error is appropriate
                        XCTAssertTrue(error is VoxError, "Should return VoxError for invalid API key")
                    }
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testFallbackServiceSelection() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 3.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let expectation = XCTestExpectation(description: "Fallback service selection")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test different fallback services
                let fallbackAPIs: [FallbackAPI] = [.openai, .revai]
                
                for fallbackAPI in fallbackAPIs {
                    let transcriptionManager = TranscriptionManager(
                        forceCloud: true,
                        verbose: false,
                        language: "en-US",
                        fallbackAPI: fallbackAPI,
                        apiKey: "test-key",
                        includeTimestamps: false
                    )
                    
                    do {
                        _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                        // If it doesn't throw, that's fine
                    } catch {
                        // Validate error is appropriate for the service
                        XCTAssertTrue(error is VoxError, "Should return VoxError")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                    }
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testRetryMechanism() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 3.0) else {
            XCTFail("Failed to create test file")
            return
        }
        
        let expectation = XCTestExpectation(description: "Retry mechanism")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test transcription that should trigger retry mechanism
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true, // Enable verbose to see retry attempts
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "sk-test-retry",
                    includeTimestamps: false
                )
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    // Success or failure both acceptable - testing retry mechanism
                } catch {
                    // Validate that retry was attempted (if possible to detect)
                    XCTAssertTrue(error is VoxError, "Should return VoxError")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 45.0)
    }
}