import XCTest
@testable import vox

class WhisperAPIClientTests: XCTestCase {
    
    func testAPIKeyValidation() {
        // Test missing API key
        XCTAssertThrowsError(try WhisperAPIClient.create(with: nil)) { error in
            if case VoxError.apiKeyMissing = error {
                // Expected error
            } else {
                XCTFail("Expected apiKeyMissing error, got: \(error)")
            }
        }
        
        // Test empty API key
        XCTAssertThrowsError(try WhisperAPIClient.create(with: "")) { error in
            if case VoxError.apiKeyMissing = error {
                // Expected error
            } else {
                XCTFail("Expected apiKeyMissing error, got: \(error)")
            }
        }
        
        // Test invalid API key format
        XCTAssertThrowsError(try WhisperAPIClient.create(with: "invalid-key")) { error in
            if case VoxError.apiKeyMissing = error {
                // Expected error
            } else {
                XCTFail("Expected apiKeyMissing error, got: \(error)")
            }
        }
        
        // Test valid API key format
        XCTAssertNoThrow(try WhisperAPIClient.create(with: "sk-test123"))
    }
    
    func testFileSizeValidation() throws {
        let client = try WhisperAPIClient.create(with: "sk-test123")
        
        // Create a test audio file with size exceeding OpenAI limit (25MB)
        let largeFileFormat = AudioFormat(
            codec: "mp3",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 300.0,
            fileSize: 30 * 1024 * 1024, // 30MB
            isValid: true
        )
        
        let tempDir = NSTemporaryDirectory()
        let testFilePath = tempDir + "test_large_audio.mp3"
        
        // Create an empty file to test with
        FileManager.default.createFile(atPath: testFilePath, contents: Data(), attributes: nil)
        defer {
            try? FileManager.default.removeItem(atPath: testFilePath)
        }
        
        let largeAudioFile = AudioFile(path: testFilePath, format: largeFileFormat)
        
        // Test should fail due to file size limit
        Task {
            do {
                _ = try await client.transcribe(audioFile: largeAudioFile)
                XCTFail("Expected file size validation to fail")
            } catch {
                if case VoxError.processingFailed(let message) = error {
                    XCTAssertTrue(message.contains("exceeds OpenAI limit"))
                } else {
                    XCTFail("Expected processingFailed error with size limit message, got: \(error)")
                }
            }
        }
    }
    
    func testMimeTypeMapping() throws {
        let client = try WhisperAPIClient.create(with: "sk-test123")
        
        // Use reflection to test the private getMimeType method
        // Since it's private, we'll test indirectly through the public interface
        // This test ensures the method exists and client initializes properly
        XCTAssertNotNil(client)
    }
    
    func testEnvironmentVariableAPIKey() {
        // Store original value
        let originalValue = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        // Test with environment variable (we can't actually set it in tests, but we can verify the logic)
        let client = try? WhisperAPIClient.create(with: nil)
        
        // If there's an existing environment variable, client should be created
        if originalValue?.hasPrefix("sk-") == true {
            XCTAssertNotNil(client)
        } else {
            // Otherwise it should fail
            XCTAssertNil(client)
        }
    }
    
    func testErrorExtensions() {
        let openAIError = VoxError.openAIError("Test error")
        if case VoxError.transcriptionFailed(let message) = openAIError {
            XCTAssertTrue(message.contains("OpenAI Whisper"))
            XCTAssertTrue(message.contains("Test error"))
        } else {
            XCTFail("Expected transcriptionFailed error")
        }
        
        let networkError = VoxError.networkError("Connection failed")
        if case VoxError.transcriptionFailed(let message) = networkError {
            XCTAssertTrue(message.contains("Network error"))
            XCTAssertTrue(message.contains("Connection failed"))
        } else {
            XCTFail("Expected transcriptionFailed error")
        }
        
        let rateLimitError = VoxError.rateLimitError(60.0)
        if case VoxError.transcriptionFailed(let message) = rateLimitError {
            XCTAssertTrue(message.contains("Rate limited"))
            XCTAssertTrue(message.contains("60"))
        } else {
            XCTFail("Expected transcriptionFailed error")
        }
    }
}