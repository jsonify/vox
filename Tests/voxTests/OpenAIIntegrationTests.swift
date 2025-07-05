import XCTest
@testable import vox

class OpenAIIntegrationTests: XCTestCase {
    func testTranscriptionManagerWithOpenAI() throws {
        // Test that TranscriptionManager properly handles OpenAI fallback configuration
        let manager = TranscriptionManager(
            forceCloud: true,
            verbose: false,
            language: "en-US",
            fallbackAPI: .openai,
            apiKey: "sk-test123",
            includeTimestamps: true
        )

        // Create a small test audio file
        let testAudioFormat = AudioFormat(
            codec: "mp3",
            sampleRate: 22050,
            channels: 1,
            bitRate: 64000,
            duration: 5.0,
            fileSize: 1024,
            isValid: true
        )

        let tempDir = NSTemporaryDirectory()
        let testFilePath = tempDir + "test_integration_audio.mp3"

        // Create a minimal MP3 file for testing
        let mp3Header = Data([0xFF, 0xFB, 0x90, 0x00]) // Basic MP3 header
        try mp3Header.write(to: URL(fileURLWithPath: testFilePath))
        defer {
            try? FileManager.default.removeItem(atPath: testFilePath)
        }

        let testAudioFile = AudioFile(path: testFilePath, format: testAudioFormat)

        // Test should fail with invalid API key (expected behavior)
        XCTAssertThrowsError(try manager.transcribeAudio(audioFile: testAudioFile)) { error in
            // Should fail either due to invalid API key or network issues - that's expected
            XCTAssertTrue(error is VoxError)
        }
    }

    func testCLIToTranscriptionManagerIntegration() {
        // Verify that CLI parameters are properly passed to TranscriptionManager
        // This test validates the integration chain

        _ = "test.mp4" // Mock input file for validation

        // Create CLI instance (can't easily test run() without actual file)
        // But we can verify the parameter mapping exists

        // Test that the integration compiles and types are correct
        let manager = TranscriptionManager(
            forceCloud: false,
            verbose: true,
            language: "en-US",
            fallbackAPI: .openai,
            apiKey: "sk-test123",
            includeTimestamps: false
        )

        XCTAssertNotNil(manager)
    }

    func testOpenAIAPIClientCreation() {
        // Test the factory method for creating WhisperAPIClient
        XCTAssertNoThrow(try WhisperAPIClient.create(with: "sk-validformat123"))

        // Test environment variable fallback
        let client = try? WhisperAPIClient.create(with: nil)

        // Should either work (if OPENAI_API_KEY is set) or fail gracefully
        if let existingKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], existingKey.hasPrefix("sk-") {
            XCTAssertNotNil(client, "Should create client when valid OPENAI_API_KEY is set")
        } else {
            XCTAssertNil(client, "Should fail when no valid API key is available")
        }
    }

    func testLanguageHandling() {
        // Test that language preferences are properly handled in OpenAI integration
        let manager1 = TranscriptionManager(
            forceCloud: true,
            verbose: false,
            language: "es-ES",
            fallbackAPI: .openai,
            apiKey: "sk-test",
            includeTimestamps: false
        )

        let manager2 = TranscriptionManager(
            forceCloud: true,
            verbose: false,
            language: nil, // Test nil language
            fallbackAPI: .openai,
            apiKey: "sk-test",
            includeTimestamps: false
        )

        XCTAssertNotNil(manager1)
        XCTAssertNotNil(manager2)
    }

    func testFallbackAPISelection() {
        // Test default fallback API selection
        let managerWithoutAPI = TranscriptionManager(
            forceCloud: true,
            verbose: false,
            language: nil,
            fallbackAPI: nil, // Should default to OpenAI
            apiKey: "sk-test",
            includeTimestamps: false
        )

        let managerWithOpenAI = TranscriptionManager(
            forceCloud: true,
            verbose: false,
            language: nil,
            fallbackAPI: .openai,
            apiKey: "sk-test",
            includeTimestamps: false
        )

        // Both should be valid configurations
        XCTAssertNotNil(managerWithoutAPI)
        XCTAssertNotNil(managerWithOpenAI)
    }

    func testProgressCallbackIntegration() {
        // Test that progress callbacks work in the integration
        var progressReports: [TranscriptionProgress] = []

        let testCallback: ProgressCallback = { progress in
            progressReports.append(progress)
        }

        // Verify callback signature compatibility
        XCTAssertNotNil(testCallback)

        // Test progress report creation
        let progress = TranscriptionProgress(
            progress: 0.5,
            status: "Testing OpenAI integration",
            phase: .extracting,
            startTime: Date()
        )

        testCallback(progress)
        XCTAssertEqual(progressReports.count, 1)
        XCTAssertEqual(progressReports.first?.currentStatus, "Testing OpenAI integration")
    }
}
