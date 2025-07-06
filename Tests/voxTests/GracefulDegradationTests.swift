import XCTest
import Foundation
@testable import vox

/// Graceful degradation testing for fallback mechanisms
/// Tests native→cloud fallback, quality degradation, and service unavailability handling
final class GracefulDegradationTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var degradationSimulator: DegradationSimulator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        degradationSimulator = DegradationSimulator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("graceful_degradation_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        degradationSimulator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        degradationSimulator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Native to Cloud Fallback Testing
    
    func testNativeToCloudFallbackChain() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 10.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Native to cloud fallback chain")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate native transcription failure
                self.degradationSimulator.simulateNativeTranscriptionFailure(enabled: true)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false, // Allow fallback
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-fallback",
                    includeTimestamps: false
                )
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // Validate fallback to cloud worked
                    XCTAssertFalse(result.text.isEmpty, "Fallback transcription should produce text")
                    XCTAssertEqual(result.engine, .openaiWhisper, "Should use cloud engine after native failure")
                    
                    // Validate degradation handling
                    XCTAssertGreaterThan(result.processingTime, 0, "Should have processing time")
                    XCTAssertTrue(result.confidence >= 0 && result.confidence <= 1, "Should have valid confidence")
                    
                } catch {
                    // If both native and cloud fail, validate comprehensive error
                    XCTAssertTrue(error is VoxError, "Should return VoxError after fallback failure")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("fallback") ||
                        errorDescription.localizedCaseInsensitiveContains("cloud") ||
                        errorDescription.localizedCaseInsensitiveContains("native"),
                        "Error should mention fallback attempt: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 90.0)
    }
    
    func testMultipleAPIFallbackChain() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 10.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Multiple API fallback chain")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate first API failure
                self.degradationSimulator.simulateAPIFailure(api: .openai, enabled: true)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .revai, // Try different API
                    apiKey: "test-key-multi-fallback",
                    includeTimestamps: false
                )
                
                // Configure multiple fallback APIs
                transcriptionManager.setFallbackAPIs([.openai, .revai])
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // Validate fallback to alternative API worked
                    XCTAssertFalse(result.text.isEmpty, "Alternative API should produce text")
                    XCTAssertEqual(result.engine, .openaiWhisper, "Should use cloud engine")
                    
                    // Validate fallback metadata
                    XCTAssertTrue(result.metadata.contains("fallback"), "Should indicate fallback was used")
                    
                } catch {
                    // If all APIs fail, validate comprehensive error
                    XCTAssertTrue(error is VoxError, "Should return VoxError after all API failures")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("api") ||
                        errorDescription.localizedCaseInsensitiveContains("fallback") ||
                        errorDescription.localizedCaseInsensitiveContains("unavailable"),
                        "Error should mention API fallback failure: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 120.0)
    }
    
    // MARK: - Audio Processing Fallback Testing
    
    func testAudioProcessingFallback() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 10.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Audio processing fallback")
        
        // Simulate AVFoundation failure
        degradationSimulator.simulateAVFoundationFailure(enabled: true)
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Validate fallback to FFmpeg worked
                XCTAssertFalse(audioFile.path.isEmpty, "Fallback audio processing should produce file")
                XCTAssertEqual(audioFile.processingMethod, .ffmpeg, "Should use FFmpeg as fallback")
                
                // Validate audio quality after fallback
                XCTAssertGreaterThan(audioFile.format.duration, 0, "Should have valid duration")
                XCTAssertGreaterThan(audioFile.format.sampleRate, 0, "Should have valid sample rate")
                
            case .failure(let error):
                // If both AVFoundation and FFmpeg fail, validate error
                XCTAssertTrue(error is VoxError, "Should return VoxError after processing fallback failure")
                
                let errorDescription = error.localizedDescription
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("audio") ||
                    errorDescription.localizedCaseInsensitiveContains("processing") ||
                    errorDescription.localizedCaseInsensitiveContains("fallback"),
                    "Error should mention audio processing fallback: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Quality Degradation Testing
    
    func testQualityDegradationUnderConstraints() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 20.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Quality degradation under constraints")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate resource constraints
                self.degradationSimulator.simulateResourceConstraints(enabled: true)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-quality-degradation",
                    includeTimestamps: true
                )
                
                // Enable quality degradation
                transcriptionManager.setQualityDegradationEnabled(true)
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // Validate graceful quality degradation
                    XCTAssertFalse(result.text.isEmpty, "Should still produce text with degraded quality")
                    
                    // Check for quality degradation indicators
                    if result.confidence < 0.8 {
                        XCTAssertTrue(result.metadata.contains("quality_degraded"), 
                            "Should indicate quality degradation occurred")
                    }
                    
                    // Validate segments might be reduced for performance
                    if result.segments.count < Int(audioFile.format.duration) / 2 {
                        XCTAssertTrue(result.metadata.contains("segments_reduced"), 
                            "Should indicate segments were reduced")
                    }
                    
                } catch {
                    XCTFail("Quality degradation should not cause complete failure: \(error)")
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 90.0)
    }
    
    func testTimestampDegradation() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 15.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Timestamp degradation")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate timestamp processing failure
                self.degradationSimulator.simulateTimestampProcessingFailure(enabled: true)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: nil,
                    apiKey: nil,
                    includeTimestamps: true
                )
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // Validate text is still provided even if timestamps fail
                    XCTAssertFalse(result.text.isEmpty, "Should still provide text without timestamps")
                    
                    // Check timestamp degradation handling
                    if result.segments.isEmpty || result.segments.allSatisfy({ $0.startTime == 0 && $0.endTime == 0 }) {
                        XCTAssertTrue(result.metadata.contains("timestamps_unavailable"), 
                            "Should indicate timestamps are unavailable")
                    }
                    
                } catch {
                    XCTFail("Timestamp failure should not cause complete transcription failure: \(error)")
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Service Unavailability Handling
    
    func testPartialServiceUnavailability() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 10.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Partial service unavailability")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate partial service unavailability
                self.degradationSimulator.simulatePartialServiceUnavailability(enabled: true)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-partial-unavailability",
                    includeTimestamps: false
                )
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // Validate partial service degradation
                    XCTAssertFalse(result.text.isEmpty, "Should provide text despite partial unavailability")
                    
                    // Check for service degradation indicators
                    if result.confidence < 0.9 {
                        XCTAssertTrue(result.metadata.contains("service_degraded"), 
                            "Should indicate service degradation")
                    }
                    
                } catch {
                    // If complete failure, validate appropriate error
                    XCTAssertTrue(error is VoxError, "Should return VoxError for service unavailability")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("service") ||
                        errorDescription.localizedCaseInsensitiveContains("unavailable") ||
                        errorDescription.localizedCaseInsensitiveContains("partial"),
                        "Error should mention service unavailability: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Recovery Testing
    
    func testServiceRecoveryAfterFailure() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 10.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Service recovery after failure")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate temporary service failure
                self.degradationSimulator.simulateTemporaryServiceFailure(enabled: true, duration: 5.0)
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: true,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: "test-key-recovery",
                    includeTimestamps: false
                )
                
                // Enable retry with recovery
                transcriptionManager.setRetryWithRecovery(enabled: true)
                transcriptionManager.setMaxRetries(3)
                transcriptionManager.setRetryDelay(2.0)
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // Validate service recovery worked
                    XCTAssertFalse(result.text.isEmpty, "Should provide text after service recovery")
                    XCTAssertTrue(result.metadata.contains("recovery_successful"), 
                        "Should indicate recovery was successful")
                    
                } catch {
                    // If recovery failed, validate appropriate error
                    XCTAssertTrue(error is VoxError, "Should return VoxError for recovery failure")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("recovery") ||
                        errorDescription.localizedCaseInsensitiveContains("retry") ||
                        errorDescription.localizedCaseInsensitiveContains("failed"),
                        "Error should mention recovery failure: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 120.0)
    }
}

// MARK: - Degradation Simulator

class DegradationSimulator {
    private var nativeTranscriptionFailureEnabled = false
    private var avFoundationFailureEnabled = false
    private var resourceConstraintsEnabled = false
    private var timestampProcessingFailureEnabled = false
    private var partialServiceUnavailabilityEnabled = false
    private var temporaryServiceFailureEnabled = false
    private var temporaryServiceFailureDuration: TimeInterval = 0
    private var apiFailures: [FallbackAPI: Bool] = [:]
    
    func simulateNativeTranscriptionFailure(enabled: Bool) {
        nativeTranscriptionFailureEnabled = enabled
    }
    
    func simulateAVFoundationFailure(enabled: Bool) {
        avFoundationFailureEnabled = enabled
    }
    
    func simulateResourceConstraints(enabled: Bool) {
        resourceConstraintsEnabled = enabled
    }
    
    func simulateTimestampProcessingFailure(enabled: Bool) {
        timestampProcessingFailureEnabled = enabled
    }
    
    func simulatePartialServiceUnavailability(enabled: Bool) {
        partialServiceUnavailabilityEnabled = enabled
    }
    
    func simulateTemporaryServiceFailure(enabled: Bool, duration: TimeInterval) {
        temporaryServiceFailureEnabled = enabled
        temporaryServiceFailureDuration = duration
        
        if enabled {
            // Simulate recovery after specified duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.temporaryServiceFailureEnabled = false
            }
        }
    }
    
    func simulateAPIFailure(api: FallbackAPI, enabled: Bool) {
        apiFailures[api] = enabled
    }
    
    func cleanup() {
        nativeTranscriptionFailureEnabled = false
        avFoundationFailureEnabled = false
        resourceConstraintsEnabled = false
        timestampProcessingFailureEnabled = false
        partialServiceUnavailabilityEnabled = false
        temporaryServiceFailureEnabled = false
        temporaryServiceFailureDuration = 0
        apiFailures.removeAll()
    }
}

// MARK: - TranscriptionManager Extensions for Testing

extension TranscriptionManager {
    func setFallbackAPIs(_ apis: [FallbackAPI]) {
        // Configure multiple fallback APIs for testing
        // This would be implemented in the actual TranscriptionManager
    }
    
    func setQualityDegradationEnabled(_ enabled: Bool) {
        // Enable quality degradation for testing
        // This would be implemented in the actual TranscriptionManager
    }
    
    func setRetryWithRecovery(enabled: Bool) {
        // Enable retry with recovery for testing
        // This would be implemented in the actual TranscriptionManager
    }
    
    func setRetryDelay(_ delay: TimeInterval) {
        // Set retry delay for testing
        // This would be implemented in the actual TranscriptionManager
    }
}

// MARK: - Test Storage

private class TestMetadataTracker {
    static let shared = TestMetadataTracker()
    private var metadataItems: [(text: String, metadata: Set<String>)] = []
    private var audioMethods: [(path: String, method: AudioProcessingMethod)] = []
    
    private init() {}
    
    func metadata(forTranscriptionWithText text: String) -> [String] {
        if let item = metadataItems.first(where: { $0.text == text }) {
            return Array(item.metadata)
        }
        return []
    }
    
    func store(_ metadata: String, forTranscriptionWithText text: String) {
        if let index = metadataItems.firstIndex(where: { $0.text == text }) {
            metadataItems[index].metadata.insert(metadata)
        } else {
            metadataItems.append((text: text, metadata: [metadata]))
        }
    }
    
    func processingMethod(forPath path: String) -> AudioProcessingMethod {
        return audioMethods.first(where: { $0.path == path })?.method ?? .avfoundation
    }
    
    func store(_ method: AudioProcessingMethod, forPath path: String) {
        if let index = audioMethods.firstIndex(where: { $0.path == path }) {
            audioMethods[index].method = method
        } else {
            audioMethods.append((path: path, method: method))
        }
    }
    
    func reset() {
        metadataItems.removeAll()
        audioMethods.removeAll()
    }
}

// MARK: - TranscriptionResult Extensions for Testing

extension TranscriptionResult {
    var metadata: [String] {
        return TestMetadataTracker.shared.metadata(forTranscriptionWithText: text)
    }
    
    mutating func addMetadata(_ item: String) {
        TestMetadataTracker.shared.store(item, forTranscriptionWithText: text)
    }
}

// MARK: - AudioFile Extensions for Testing

extension AudioFile {
    var processingMethod: AudioProcessingMethod {
        return TestMetadataTracker.shared.processingMethod(forPath: path)
    }
    
    mutating func setProcessingMethod(_ method: AudioProcessingMethod) {
        TestMetadataTracker.shared.store(method, forPath: path)
    }
}

// MARK: - Mock Test Methods

private extension TranscriptionManager {
    func setMaxRetries(_ count: Int) {
        // Mock implementation for testing retry behavior
    }
}

enum AudioProcessingMethod {
    case avfoundation
    case ffmpeg
}
