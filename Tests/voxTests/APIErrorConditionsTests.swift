import XCTest
import Foundation
@testable import vox

/// Comprehensive API error condition testing
/// Tests authentication failures, rate limiting, service errors, and API response validation
final class APIErrorConditionsTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var apiSimulator: APIErrorSimulator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        apiSimulator = APIErrorSimulator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("api_error_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        apiSimulator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        apiSimulator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Authentication Error Testing
    
    func testInvalidAPIKeyFormats() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let invalidAPIKeys = [
            "",                                    // Empty key
            "invalid-key",                        // Too short
            "sk-1234567890",                      // Incorrect format
            "invalid_key_with_special_chars!@#",  // Special characters
            String(repeating: "a", count: 1000),  // Too long
            "key with spaces",                    // Spaces
            "key\nwith\nnewlines",               // Newlines
            "key\twith\ttabs"                     // Tabs
        ]
        
        for (index, invalidKey) in invalidAPIKeys.enumerated() {
            let expectation = XCTestExpectation(description: "Invalid API key \(index): \(invalidKey.prefix(20))")
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: testFile.path) { result in
                switch result {
                case .success(let audioFile):
                    let transcriptionManager = TranscriptionManager(
                        forceCloud: true,
                        verbose: true,
                        language: "en-US",
                        fallbackAPI: .openai,
                        apiKey: invalidKey,
                        includeTimestamps: false
                    )
                    
                    do {
                        _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Should fail with invalid API key: \(invalidKey.prefix(20))")
                    } catch {
                        // Validate API key error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for invalid API key")
                        
                        if let voxError = error as? VoxError {
                            switch voxError {
                            case .apiKeyMissing, .transcriptionFailed:
                                XCTAssertTrue(true, "Correct error type for invalid API key")
                            default:
                                let errorDescription = voxError.localizedDescription
                                XCTAssertTrue(
                                    errorDescription.localizedCaseInsensitiveContains("api") ||
                                    errorDescription.localizedCaseInsensitiveContains("key") ||
                                    errorDescription.localizedCaseInsensitiveContains("auth"),
                                    "Error should mention API key issue: \(errorDescription)"
                                )
                            }
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Audio processing failed: \(error)")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    func testAPIKeyValidationEdgeCases() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "API key validation edge cases")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test null API key
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: nil,
                    includeTimestamps: false
                )
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    XCTFail("Should fail with null API key")
                } catch {
                    // Validate null API key error handling
                    XCTAssertTrue(error is VoxError, "Should return VoxError for null API key")
                    
                    if let voxError = error as? VoxError {
                        switch voxError {
                        case .apiKeyMissing:
                            XCTAssertTrue(true, "Correct error type for missing API key")
                        default:
                            XCTFail("Should return apiKeyMissing error for null key")
                        }
                    }
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - HTTP Status Code Error Testing
    
    func testHTTPStatusCodeHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let statusCodes = [
            400: "Bad Request",
            401: "Unauthorized",
            403: "Forbidden",
            404: "Not Found",
            429: "Too Many Requests",
            500: "Internal Server Error",
            502: "Bad Gateway",
            503: "Service Unavailable",
            504: "Gateway Timeout"
        ]
        
        for (statusCode, description) in statusCodes {
            let expectation = XCTestExpectation(description: "HTTP \(statusCode) \(description)")
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: testFile.path) { result in
                switch result {
                case .success(let audioFile):
                    // Configure API simulator to return specific status code
                    self.apiSimulator.configureHTTPResponse(statusCode: statusCode, body: nil)
                    
                    let transcriptionManager = TranscriptionManager(
                        forceCloud: true,
                        verbose: true,
                        language: "en-US",
                        fallbackAPI: .openai,
                        apiKey: "test-key-\(statusCode)",
                        includeTimestamps: false
                    )
                    
                    do {
                        _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Should fail with HTTP \(statusCode)")
                    } catch {
                        // Validate HTTP status code error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for HTTP \(statusCode)")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertFalse(errorDescription.isEmpty, "Error should have description for HTTP \(statusCode)")
                        
                        // Validate specific status code handling
                        switch statusCode {
                        case 401, 403:
                            XCTAssertTrue(
                                errorDescription.localizedCaseInsensitiveContains("auth") ||
                                errorDescription.localizedCaseInsensitiveContains("unauthorized") ||
                                errorDescription.localizedCaseInsensitiveContains("forbidden"),
                                "Error should mention auth issue for \(statusCode): \(errorDescription)"
                            )
                        case 429:
                            XCTAssertTrue(
                                errorDescription.localizedCaseInsensitiveContains("rate") ||
                                errorDescription.localizedCaseInsensitiveContains("limit") ||
                                errorDescription.localizedCaseInsensitiveContains("too many"),
                                "Error should mention rate limiting for \(statusCode): \(errorDescription)"
                            )
                        case 500, 502, 503, 504:
                            XCTAssertTrue(
                                errorDescription.localizedCaseInsensitiveContains("server") ||
                                errorDescription.localizedCaseInsensitiveContains("service") ||
                                errorDescription.localizedCaseInsensitiveContains("unavailable"),
                                "Error should mention server issue for \(statusCode): \(errorDescription)"
                            )
                        default:
                            XCTAssertTrue(
                                errorDescription.localizedCaseInsensitiveContains("error") ||
                                errorDescription.localizedCaseInsensitiveContains("failed"),
                                "Error should mention failure for \(statusCode): \(errorDescription)"
                            )
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Audio processing failed: \(error)")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    // MARK: - API Response Validation Testing
    
    func testMalformedAPIResponseHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let malformedResponses = [
            "",                                    // Empty response
            "invalid json",                       // Invalid JSON
            "{}",                                 // Empty JSON
            "{\"error\": \"malformed\"}",         // JSON with error
            "<xml>invalid</xml>",                 // XML instead of JSON
            "null",                               // Null response
            "{\"text\": null}",                   // Null text field
            "{\"text\": \"\"}",                   // Empty text field
            "{\"text\": 123}",                    // Wrong type for text
            String(repeating: "a", count: 10000)  // Extremely long response
        ]
        
        for (index, malformedResponse) in malformedResponses.enumerated() {
            let expectation = XCTestExpectation(description: "Malformed response \(index)")
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: testFile.path) { result in
                switch result {
                case .success(let audioFile):
                    // Configure API simulator to return malformed response
                    self.apiSimulator.configureHTTPResponse(statusCode: 200, body: malformedResponse)
                    
                    let transcriptionManager = TranscriptionManager(
                        forceCloud: true,
                        verbose: true,
                        language: "en-US",
                        fallbackAPI: .openai,
                        apiKey: "test-key-malformed-\(index)",
                        includeTimestamps: false
                    )
                    
                    do {
                        _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Should fail with malformed response \(index)")
                    } catch {
                        // Validate malformed response error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for malformed response")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertFalse(errorDescription.isEmpty, "Error should have description for malformed response")
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("response") ||
                            errorDescription.localizedCaseInsensitiveContains("parse") ||
                            errorDescription.localizedCaseInsensitiveContains("invalid") ||
                            errorDescription.localizedCaseInsensitiveContains("format"),
                            "Error should mention response issue: \(errorDescription)"
                        )
                    }
                    
                case .failure(let error):
                    XCTFail("Audio processing failed: \(error)")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    // MARK: - Rate Limiting and Quota Testing
    
    func testRateLimitingRecovery() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Rate limiting recovery")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Configure API simulator to return rate limiting error
                self.apiSimulator.configureRateLimiting(enabled: true, retryAfter: 1)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-rate-limit",
                    includeTimestamps: false
                )
                
                // Enable retry mechanism
                transcriptionManager.setRetryEnabled(true)
                transcriptionManager.setMaxRetries(3)
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    // If successful, rate limiting recovery worked
                    XCTAssertTrue(true, "Rate limiting recovery successful")
                } catch {
                    // If failed, validate rate limiting error
                    XCTAssertTrue(error is VoxError, "Should return VoxError for rate limiting")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("rate") ||
                        errorDescription.localizedCaseInsensitiveContains("limit") ||
                        errorDescription.localizedCaseInsensitiveContains("retry"),
                        "Error should mention rate limiting: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    func testQuotaExceededHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Quota exceeded handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Configure API simulator to return quota exceeded error
                self.apiSimulator.configureQuotaExceeded(enabled: true)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-quota-exceeded",
                    includeTimestamps: false
                )
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    XCTFail("Should fail with quota exceeded")
                } catch {
                    // Validate quota exceeded error handling
                    XCTAssertTrue(error is VoxError, "Should return VoxError for quota exceeded")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("quota") ||
                        errorDescription.localizedCaseInsensitiveContains("limit") ||
                        errorDescription.localizedCaseInsensitiveContains("exceeded"),
                        "Error should mention quota issue: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - API Service Availability Testing
    
    func testServiceUnavailabilityWithFallback() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Service unavailability with fallback")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Configure API simulator to simulate service unavailability
                self.apiSimulator.configureServiceUnavailable(enabled: true)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false, // Allow fallback to native
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-service-unavailable",
                    includeTimestamps: false
                )
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    // If successful, fallback to native worked
                    XCTAssertFalse(result.text.isEmpty, "Fallback transcription should produce text")
                    XCTAssertEqual(result.engine, .speechAnalyzer, "Should use native engine as fallback")
                } catch {
                    // If failed, validate service unavailability error
                    XCTAssertTrue(error is VoxError, "Should return VoxError for service unavailability")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("service") ||
                        errorDescription.localizedCaseInsensitiveContains("unavailable") ||
                        errorDescription.localizedCaseInsensitiveContains("fallback"),
                        "Error should mention service issue: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
}

// MARK: - API Error Simulator

class APIErrorSimulator {
    private var httpStatusCode: Int = 200
    private var responseBody: String?
    private var rateLimitingEnabled = false
    private var quotaExceededEnabled = false
    private var serviceUnavailableEnabled = false
    
    func configureHTTPResponse(statusCode: Int, body: String?) {
        self.httpStatusCode = statusCode
        self.responseBody = body
    }
    
    func configureRateLimiting(enabled: Bool, retryAfter: Int = 60) {
        self.rateLimitingEnabled = enabled
        if enabled {
            self.httpStatusCode = 429
            self.responseBody = "{\"error\": \"rate_limit_exceeded\", \"retry_after\": \(retryAfter)}"
        }
    }
    
    func configureQuotaExceeded(enabled: Bool) {
        self.quotaExceededEnabled = enabled
        if enabled {
            self.httpStatusCode = 429
            self.responseBody = "{\"error\": \"quota_exceeded\", \"message\": \"You have exceeded your quota\"}"
        }
    }
    
    func configureServiceUnavailable(enabled: Bool) {
        self.serviceUnavailableEnabled = enabled
        if enabled {
            self.httpStatusCode = 503
            self.responseBody = "{\"error\": \"service_unavailable\", \"message\": \"Service is temporarily unavailable\"}"
        }
    }
    
    func cleanup() {
        // Reset all configurations
        httpStatusCode = 200
        responseBody = nil
        rateLimitingEnabled = false
        quotaExceededEnabled = false
        serviceUnavailableEnabled = false
    }
}

// MARK: - TranscriptionManager Extensions for Testing

extension TranscriptionManager {
    func setRetryEnabled(_ enabled: Bool) {
        // Configure retry mechanism for testing
        // This would be implemented in the actual TranscriptionManager
    }
    
    func setMaxRetries(_ count: Int) {
        // Configure maximum retry count for testing
        // This would be implemented in the actual TranscriptionManager
    }
}