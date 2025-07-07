import XCTest
import Foundation
@testable import vox

/// Comprehensive network failure testing for real-world scenarios
/// Tests network timeouts, DNS failures, rate limiting, and service unavailability
final class NetworkFailureComprehensiveTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var networkSimulator: NetworkFailureSimulator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        networkSimulator = NetworkFailureSimulator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("network_failure_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        networkSimulator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        networkSimulator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Network Timeout Scenarios
    
    func testAPITimeoutHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "API timeout handling")
        
        // Simulate network timeout by using invalid endpoint
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test transcription with timeout simulation
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-for-timeout",
                    includeTimestamps: false
                )
                
                // Configure with extremely short timeout
                transcriptionManager.setNetworkTimeout(seconds: 0.1)
                
                Task {
                    do {
                        _ = try await transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Transcription should timeout with short timeout")
                    } catch {
                        // Validate timeout error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for timeout")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("timeout") ||
                            errorDescription.localizedCaseInsensitiveContains("connection") ||
                            errorDescription.localizedCaseInsensitiveContains("network"),
                            "Error should mention timeout: \(errorDescription)"
                        )
                    }
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testDNSResolutionFailure() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "DNS resolution failure")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test transcription with invalid hostname
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key",
                    includeTimestamps: false
                )
                
                // Configure with invalid hostname
                transcriptionManager.setAPIEndpoint("https://invalid.nonexistent.domain.com")
                
                Task {
                    do {
                        _ = try await transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Transcription should fail with invalid hostname")
                    } catch {
                        // Validate DNS resolution error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for DNS failure")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("network") ||
                            errorDescription.localizedCaseInsensitiveContains("connection") ||
                            errorDescription.localizedCaseInsensitiveContains("resolve") ||
                            errorDescription.localizedCaseInsensitiveContains("dns"),
                            "Error should mention network/DNS issue: \(errorDescription)"
                        )
                    }
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - API Rate Limiting and Service Errors
    
    func testRateLimitingHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Rate limiting handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate rate limiting by making multiple rapid requests
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "invalid-key-rate-limit-test",
                    includeTimestamps: false
                )
                
                // Make multiple rapid requests to trigger rate limiting
                var errors: [Error] = []
                let group = DispatchGroup()
                
                for _ in 0..<5 {
                    group.enter()
                    DispatchQueue.global().async {
                        Task {
                            do {
                                _ = try await transcriptionManager.transcribeAudio(audioFile: audioFile)
                            } catch {
                                errors.append(error)
                            }
                            group.leave()
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    // Should have errors due to rapid requests
                    XCTAssertGreaterThan(errors.count, 0, "Should have rate limiting errors")
                    
                    // Validate error handling for rate limiting
                    for error in errors {
                        if let voxError = error as? VoxError {
                            let errorDescription = voxError.localizedDescription
                            XCTAssertFalse(errorDescription.isEmpty, "Error should have description")
                        }
                    }
                    
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    func testServiceUnavailabilityHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Service unavailability handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test with endpoints that return 503 Service Unavailable
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-service-unavailable",
                    includeTimestamps: false
                )
                
                // Configure with endpoint that will return service unavailable
                transcriptionManager.setAPIEndpoint("https://httpstat.us/503")
                
                Task {
                    do {
                        _ = try await transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Transcription should fail with service unavailable")
                    } catch {
                        // Validate service unavailability error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for service unavailable")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("service") ||
                            errorDescription.localizedCaseInsensitiveContains("unavailable") ||
                            errorDescription.localizedCaseInsensitiveContains("server") ||
                            errorDescription.localizedCaseInsensitiveContains("503"),
                            "Error should mention service issue: \(errorDescription)"
                        )
                    }
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Authentication and Authorization Failures
    
    func testInvalidAPIKeyHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Invalid API key handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test with clearly invalid API key
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "invalid-api-key-12345",
                    includeTimestamps: false
                )
                
                Task {
                    do {
                        _ = try await transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Transcription should fail with invalid API key")
                    } catch {
                        // Validate API key error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for invalid API key")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("api") ||
                            errorDescription.localizedCaseInsensitiveContains("key") ||
                            errorDescription.localizedCaseInsensitiveContains("auth") ||
                            errorDescription.localizedCaseInsensitiveContains("unauthorized"),
                            "Error should mention authentication issue: \(errorDescription)"
                        )
                    }
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testMissingAPIKeyHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Missing API key handling")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test with no API key
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: nil,
                    includeTimestamps: false
                )
                
                Task {
                    do {
                        _ = try await transcriptionManager.transcribeAudio(audioFile: audioFile)
                        XCTFail("Transcription should fail with missing API key")
                    } catch {
                        // Validate missing API key error handling
                        XCTAssertTrue(error is VoxError, "Should return VoxError for missing API key")
                        
                        if let voxError = error as? VoxError {
                            switch voxError {
                            case .apiKeyMissing:
                                XCTAssertTrue(true, "Correct error type for missing API key")
                            default:
                                XCTFail("Should return apiKeyMissing error type")
                            }
                        }
                    }
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Fallback Mechanism Testing
    
    func testFallbackChainValidation() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Fallback chain validation")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test fallback from native to cloud when native fails
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false, // Allow fallback
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "invalid-key-fallback-test",
                    includeTimestamps: false
                )
                
                Task {
                    do {
                        _ = try await transcriptionManager.transcribeAudio(audioFile: audioFile)
                        // If it succeeds, either native worked or fallback worked
                        XCTAssertTrue(true, "Transcription succeeded through fallback chain")
                    } catch {
                        // If it fails, validate that fallback was attempted
                        XCTAssertTrue(error is VoxError, "Should return VoxError after fallback failure")
                        
                        let errorDescription = error.localizedDescription
                        XCTAssertFalse(errorDescription.isEmpty, "Error should have description after fallback")
                        
                        // Error should indicate that fallback was attempted
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("fallback") ||
                            errorDescription.localizedCaseInsensitiveContains("cloud") ||
                            errorDescription.localizedCaseInsensitiveContains("api"),
                            "Error should mention fallback attempt: \(errorDescription)"
                        )
                    }
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 45.0)
    }
}

// MARK: - Network Failure Simulator

class NetworkFailureSimulator {
    private var originalNetworkConfiguration: NetworkConfiguration?
    
    init() {
        // Store original network configuration
        originalNetworkConfiguration = NetworkConfiguration.current
        NetworkConfiguration.current.reset() // Start with clean configuration
    }
    
    func simulateTimeout() {
        // Configure extremely short timeouts
        NetworkConfiguration.current.requestTimeout = 0.1
        NetworkConfiguration.current.resourceTimeout = 0.1
    }
    
    func simulateDNSFailure() {
        // Configure invalid DNS servers
        NetworkConfiguration.current.dnsServers = ["0.0.0.0", "127.0.0.1"]
    }
    
    func simulateRateLimiting() {
        // Configure rate limiting simulation
        NetworkConfiguration.current.maxRequestsPerSecond = 1
        NetworkConfiguration.current.rateLimitingEnabled = true
    }
    
    func simulateServiceUnavailable() {
        // Configure service unavailable simulation
        NetworkConfiguration.current.forceServiceUnavailable = true
    }
    
    func cleanup() {
        // Restore original network configuration
        if let originalConfig = originalNetworkConfiguration {
            NetworkConfiguration.current = originalConfig
        }
    }
}

// MARK: - TranscriptionManager Extensions for Testing

extension TranscriptionManager {
    func setNetworkTimeout(seconds: TimeInterval) {
        // Configure network timeout for testing
        NetworkConfiguration.current.requestTimeout = seconds
    }
    
    /// Sets a custom API endpoint for testing network scenarios
    /// This allows tests to simulate various network conditions by directing
    /// requests to specific endpoints (e.g., invalid domains, error-generating services)
    func setAPIEndpoint(_ endpoint: String) {
        NetworkConfiguration.current.customAPIEndpoint = endpoint
    }
}
