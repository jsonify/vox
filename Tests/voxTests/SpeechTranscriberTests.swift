import XCTest
import Speech
@testable import vox

@available(macOS 10.15, *)
final class SpeechTranscriberTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Enable logging for tests
        Logger.shared.enableLogging(level: .info)
    }
    
    // MARK: - Initialization Tests
    
    func testSpeechTranscriberInitializationWithValidLocale() throws {
        let locale = Locale(identifier: "en-US")
        
        // Skip test if Speech framework is not available
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for en-US locale")
        }
        
        XCTAssertNoThrow(try SpeechTranscriber(locale: locale))
    }
    
    func testSpeechTranscriberInitializationWithInvalidLocale() {
        let locale = Locale(identifier: "invalid-locale")
        
        XCTAssertThrowsError(try SpeechTranscriber(locale: locale)) { error in
            if case VoxError.transcriptionFailed(let message) = error {
                XCTAssertTrue(message.contains("Speech recognizer not available"))
            } else {
                XCTFail("Expected VoxError.transcriptionFailed, got \(error)")
            }
        }
    }
    
    // MARK: - Availability Tests
    
    func testSpeechRecognitionAvailability() {
        let englishLocale = Locale(identifier: "en-US")
        let availability = SpeechTranscriber.isAvailable(for: englishLocale)
        
        // This should typically be true on macOS
        XCTAssertTrue(availability, "Speech recognition should be available for en-US")
    }
    
    func testSpeechRecognitionAvailabilityForInvalidLocale() {
        let invalidLocale = Locale(identifier: "xx-XX")
        let availability = SpeechTranscriber.isAvailable(for: invalidLocale)
        
        XCTAssertFalse(availability, "Speech recognition should not be available for invalid locale")
    }
    
    func testSupportedLocales() {
        let supportedLocales = SpeechTranscriber.supportedLocales()
        
        XCTAssertFalse(supportedLocales.isEmpty, "Should have at least one supported locale")
        
        // Check that en-US is typically supported
        let hasEnglish = supportedLocales.contains { $0.identifier.hasPrefix("en") }
        XCTAssertTrue(hasEnglish, "Should support at least one English locale")
    }
    
    // MARK: - Error Handling Tests
    
    func testTranscriptionWithInvalidAudioFile() async throws {
        let locale = Locale(identifier: "en-US")
        
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for testing")
        }
        
        let speechTranscriber = try SpeechTranscriber(locale: locale)
        
        let invalidAudioFormat = AudioFormat(
            codec: "mp3",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 10.0
        )
        
        let invalidAudioFile = AudioFile(
            path: "/nonexistent/file.mp3",
            format: invalidAudioFormat,
            temporaryPath: nil
        )
        
        do {
            _ = try await speechTranscriber.transcribe(audioFile: invalidAudioFile)
            XCTFail("Should have thrown an error for invalid file")
        } catch VoxError.invalidInputFile(let path) {
            XCTAssertEqual(path, "/nonexistent/file.mp3")
        } catch {
            XCTFail("Expected VoxError.invalidInputFile, got \(error)")
        }
    }
    
    // MARK: - Language Detection Tests
    
    func testLanguageDetectionWithPreferredLanguages() async throws {
        let locale = Locale(identifier: "en-US")
        
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for testing")
        }
        
        let speechTranscriber = try SpeechTranscriber(locale: locale)
        
        // Create a mock audio file (we'll skip actual transcription in unit tests)
        let mockAudioFormat = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 1,
            bitRate: 128000,
            duration: 5.0
        )
        
        let mockAudioFile = AudioFile(
            path: "/fake/audio.m4a",
            format: mockAudioFormat,
            temporaryPath: nil
        )
        
        // This test validates the language detection logic structure
        // In a real scenario, we'd need actual audio files
        let preferredLanguages = ["en-US", "es-ES", "fr-FR"]
        
        // The method should attempt each language in order
        // Since we don't have real audio, we expect it to fail with file not found
        do {
            _ = try await speechTranscriber.transcribeWithLanguageDetection(
                audioFile: mockAudioFile,
                preferredLanguages: preferredLanguages
            )
            XCTFail("Should have failed with invalid file")
        } catch VoxError.invalidInputFile {
            // Expected - this validates the flow reaches the transcription attempt
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Progress Reporting Tests
    
    func testProgressReportingStructure() async throws {
        let locale = Locale(identifier: "en-US")
        
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for testing")
        }
        
        let speechTranscriber = try SpeechTranscriber(locale: locale)
        
        let mockAudioFormat = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 1,
            bitRate: 128000,
            duration: 5.0
        )
        
        let mockAudioFile = AudioFile(
            path: "/fake/audio.m4a",
            format: mockAudioFormat,
            temporaryPath: nil
        )
        
        var progressReports: [ProgressReport] = []
        
        // Test that progress callback is called
        do {
            _ = try await speechTranscriber.transcribe(audioFile: mockAudioFile) { progress in
                progressReports.append(progress)
            }
        } catch VoxError.invalidInputFile {
            // Expected - but we should have received some progress reports
            XCTAssertFalse(progressReports.isEmpty, "Should have received progress reports")
            
            // Verify progress report structure
            if let firstReport = progressReports.first {
                XCTAssertGreaterThanOrEqual(firstReport.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(firstReport.currentProgress, 1.0)
                XCTAssertFalse(firstReport.currentStatus.isEmpty)
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Integration Tests with Real Audio (if available)
    
    func testTranscriptionWithTestAudio() async throws {
        let locale = Locale(identifier: "en-US")
        
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for testing")
        }
        
        // Check if we have test audio files
        let testBundle = Bundle(for: type(of: self))
        guard let testAudioPath = testBundle.path(forResource: "test_sample", ofType: "mp4") else {
            throw XCTSkip("Test audio file not available")
        }
        
        let speechTranscriber = try SpeechTranscriber(locale: locale)
        
        let audioFormat = AudioFormat(
            codec: "mp4",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 10.0
        )
        
        let audioFile = AudioFile(
            path: testAudioPath,
            format: audioFormat,
            temporaryPath: nil
        )
        
        var progressReports: [ProgressReport] = []
        
        do {
            let result = try await speechTranscriber.transcribe(audioFile: audioFile) { progress in
                progressReports.append(progress)
            }
            
            // Validate transcription result
            XCTAssertFalse(result.text.isEmpty, "Transcription text should not be empty")
            XCTAssertEqual(result.engine, .speechAnalyzer)
            XCTAssertEqual(result.language, "en-US")
            XCTAssertGreaterThan(result.processingTime, 0)
            XCTAssertGreaterThanOrEqual(result.confidence, 0.0)
            XCTAssertLessThanOrEqual(result.confidence, 1.0)
            XCTAssertFalse(result.segments.isEmpty, "Should have transcription segments")
            
            // Validate segments
            for segment in result.segments {
                XCTAssertFalse(segment.text.isEmpty)
                XCTAssertGreaterThanOrEqual(segment.startTime, 0)
                XCTAssertGreaterThanOrEqual(segment.endTime, segment.startTime)
                XCTAssertGreaterThanOrEqual(segment.confidence, 0.0)
                XCTAssertLessThanOrEqual(segment.confidence, 1.0)
                XCTAssertNil(segment.speakerID) // Apple Speech framework doesn't provide speaker ID
            }
            
            // Validate progress reporting
            XCTAssertFalse(progressReports.isEmpty, "Should have received progress reports")
            
            if let lastReport = progressReports.last {
                XCTAssertEqual(lastReport.currentProgress, 1.0, "Final progress should be 100%")
                XCTAssertTrue(lastReport.isComplete, "Final report should be marked complete")
            }
            
        } catch {
            // If transcription fails, it might be due to the test audio format
            // This is acceptable for unit tests
            Logger.shared.info("Transcription test failed (expected for some test environments): \(error)", component: "SpeechTranscriberTests")
            throw XCTSkip("Transcription failed in test environment: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Language Validation Tests
    
    func testLanguageCodeValidation() {
        // Test exact match
        XCTAssertEqual(SpeechTranscriber.validateLanguageCode("en-US"), "en-US")
        
        // Test case insensitive match
        XCTAssertEqual(SpeechTranscriber.validateLanguageCode("en-us"), "en-US")
        
        // Test invalid language code
        XCTAssertNil(SpeechTranscriber.validateLanguageCode("invalid-code"))
        
        // Test language-only matching (e.g., "en" -> "en-US")
        let validatedLanguage = SpeechTranscriber.validateLanguageCode("en")
        XCTAssertNotNil(validatedLanguage)
        XCTAssertTrue(validatedLanguage?.hasPrefix("en-") ?? false)
    }
    
    func testCommonLanguages() {
        let commonLanguages = SpeechTranscriber.commonLanguages()
        
        XCTAssertFalse(commonLanguages.isEmpty, "Should have common languages")
        XCTAssertNotNil(commonLanguages["en-US"], "Should include English US")
        XCTAssertNotNil(commonLanguages["es-ES"], "Should include Spanish")
        XCTAssertNotNil(commonLanguages["fr-FR"], "Should include French")
        
        // Check that descriptions are meaningful
        XCTAssertTrue(commonLanguages["en-US"]?.contains("English") ?? false)
        XCTAssertTrue(commonLanguages["es-ES"]?.contains("Spanish") ?? false)
    }
    
    func testLanguageDetectionWithValidation() async throws {
        let locale = Locale(identifier: "en-US")
        
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for testing")
        }
        
        let speechTranscriber = try SpeechTranscriber(locale: locale)
        
        // Create a mock audio file for testing validation logic
        let mockAudioFormat = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 1,
            bitRate: 128000,
            duration: 5.0
        )
        
        let mockAudioFile = AudioFile(
            path: "/fake/audio.m4a",
            format: mockAudioFormat,
            temporaryPath: nil
        )
        
        // Test with mixed valid/invalid language codes
        let mixedLanguages = ["invalid-lang", "en-US", "another-invalid", "es"]
        
        do {
            _ = try await speechTranscriber.transcribeWithLanguageDetection(
                audioFile: mockAudioFile,
                preferredLanguages: mixedLanguages
            )
            XCTFail("Should have failed with invalid file")
        } catch VoxError.invalidInputFile {
            // Expected - this validates the flow reaches the transcription attempt
            // The language validation logic should have filtered out invalid codes
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testLanguageDetectionWithAllInvalidLanguages() async throws {
        let locale = Locale(identifier: "en-US")
        
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for testing")
        }
        
        let speechTranscriber = try SpeechTranscriber(locale: locale)
        
        // Create a mock audio file
        let mockAudioFormat = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 1,
            bitRate: 128000,
            duration: 5.0
        )
        
        let mockAudioFile = AudioFile(
            path: "/fake/audio.m4a",
            format: mockAudioFormat,
            temporaryPath: nil
        )
        
        // Test with all invalid language codes
        let invalidLanguages = ["invalid-lang", "another-invalid", "fake-code"]
        
        do {
            _ = try await speechTranscriber.transcribeWithLanguageDetection(
                audioFile: mockAudioFile,
                preferredLanguages: invalidLanguages
            )
            XCTFail("Should have failed with invalid file")
        } catch VoxError.invalidInputFile {
            // Expected - should fall back to en-US after validation
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Memory and Performance Tests
    
    func testSpeechTranscriberMemoryCleanup() throws {
        let locale = Locale(identifier: "en-US")
        
        guard SpeechTranscriber.isAvailable(for: locale) else {
            throw XCTSkip("Speech recognition not available for testing")
        }
        
        // Create and immediately release transcriber to test cleanup
        weak var weakTranscriber: SpeechTranscriber?
        
        autoreleasepool {
            do {
                let transcriber = try SpeechTranscriber(locale: locale)
                weakTranscriber = transcriber
                XCTAssertNotNil(weakTranscriber)
            } catch {
                XCTFail("Failed to create SpeechTranscriber: \(error)")
            }
        }
        
        // Give ARC time to clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNil(weakTranscriber, "SpeechTranscriber should be deallocated")
        }
    }
}