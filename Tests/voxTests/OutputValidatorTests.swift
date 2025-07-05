import XCTest
@testable import vox

class OutputValidatorTests: XCTestCase {
    var outputValidator: OutputValidator!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for tests
        let tempPath = "vox-validator-tests-\(UUID().uuidString)"
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tempPath)
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temp directory: \(error)")
        }
        
        outputValidator = OutputValidator()
    }
    
    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Test Helpers
    
    private func createTestTranscriptionResult() -> TranscriptionResult {
        return TranscriptionResult(
            text: "Hello world, this is a test transcription.",
            language: "en-US",
            confidence: 0.95,
            duration: 10.0,
            segments: [
                TranscriptionSegment(
                    text: "Hello world",
                    startTime: 0.0,
                    endTime: 2.0,
                    confidence: 0.98
                ),
                TranscriptionSegment(
                    text: "this is a test transcription",
                    startTime: 2.0,
                    endTime: 10.0,
                    confidence: 0.92
                )
            ],
            engine: .speechAnalyzer,
            processingTime: 5.0,
            audioFormat: AudioFormat(
                codec: "PCM",
                sampleRate: 44100,
                channels: 2,
                bitRate: 1411,
                duration: 10.0
            )
        )
    }
    
    private func writeTestFile(content: String, filename: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    // MARK: - Format Validation Tests
    
    func testValidateTextFormat() throws {
        let content = "Hello world\nThis is a test\nWith multiple lines"
        let result = try outputValidator.validateFormat(content, format: .txt)
        
        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(result.format, .txt)
        XCTAssertTrue(result.isCompliant)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.details["lineCount"], "3")
        XCTAssertEqual(result.details["characterCount"], "\(content.count)")
    }
    
    func testValidateEmptyTextFormat() throws {
        let content = ""
        let result = try outputValidator.validateFormat(content, format: .txt)
        
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.format, .txt)
        XCTAssertFalse(result.isCompliant)
        XCTAssertTrue(result.issues.contains("Text content is empty"))
    }
    
    func testValidateTextFormatWithLongLines() throws {
        let longLine = String(repeating: "A", count: 1500)
        let content = "Short line\n\(longLine)\nAnother short line"
        let result = try outputValidator.validateFormat(content, format: .txt)
        
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.format, .txt)
        XCTAssertFalse(result.isCompliant)
        XCTAssertTrue(result.issues.contains("Found 1 extremely long lines"))
    }
    
    func testValidateSRTFormat() throws {
        let content = """
        1
        00:00:01,000 --> 00:00:05,000
        Hello world
        
        2
        00:00:05,000 --> 00:00:10,000
        This is a test transcription
        """
        let result = try outputValidator.validateFormat(content, format: .srt)
        
        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(result.format, .srt)
        XCTAssertTrue(result.isCompliant)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.details["totalBlocks"], "2")
        XCTAssertEqual(result.details["validBlocks"], "2")
    }
    
    func testValidateInvalidSRTFormat() throws {
        let content = """
        1
        invalid timestamp
        Hello world
        
        2
        00:00:05,000 --> 00:00:10,000
        This is a test transcription
        """
        let result = try outputValidator.validateFormat(content, format: .srt)
        
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.format, .srt)
        XCTAssertFalse(result.isCompliant)
        XCTAssertTrue(result.issues.contains("Block 1 has invalid timestamp format"))
    }
    
    func testValidateJSONFormat() throws {
        let content = """
        {
            "text": "Hello world",
            "language": "en-US",
            "confidence": 0.95,
            "duration": 10.0,
            "segments": [],
            "engine": "apple-speechanalyzer",
            "processingTime": 5.0,
            "audioFormat": {
                "sampleRate": 44100,
                "channels": 2,
                "bitDepth": 16,
                "format": "PCM"
            }
        }
        """
        let result = try outputValidator.validateFormat(content, format: .json)
        
        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(result.format, .json)
        XCTAssertTrue(result.isCompliant)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.details["hasExpectedStructure"], "true")
    }
    
    func testValidateInvalidJSONFormat() throws {
        let content = "{ invalid json"
        let result = try outputValidator.validateFormat(content, format: .json)
        
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.format, .json)
        XCTAssertFalse(result.isCompliant)
        XCTAssertTrue(result.issues.first?.contains("Invalid JSON format") == true)
    }
    
    func testValidateJSONWithMissingKeys() throws {
        let content = """
        {
            "text": "Hello world",
            "language": "en-US"
        }
        """
        let result = try outputValidator.validateFormat(content, format: .json)
        
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.format, .json)
        XCTAssertFalse(result.isCompliant)
        XCTAssertTrue(result.issues.first?.contains("Missing expected keys") == true)
    }
    
    // MARK: - Encoding Validation Tests
    
    func testValidateValidUTF8Encoding() throws {
        let content = "Hello world with émojis 🌍 and spécial characters"
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let result = try outputValidator.validateEncoding(url)
        
        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(result.encoding, "UTF-8")
        XCTAssertTrue(result.isValidUTF8)
        XCTAssertFalse(result.hasInvalidCharacters)
        XCTAssertTrue(result.issues.isEmpty)
    }
    
    func testValidateEncodingWithInvalidCharacters() throws {
        let content = "Hello world\u{0008}with control characters"
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let result = try outputValidator.validateEncoding(url)
        
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.encoding, "UTF-8")
        XCTAssertTrue(result.hasInvalidCharacters)
        XCTAssertTrue(result.issues.contains("Invalid control characters detected"))
    }
    
    // MARK: - Integrity Validation Tests
    
    func testValidateIntegrityWithValidContent() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = "Hello world, this is a test transcription."
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let result = try outputValidator.validateIntegrity(transcriptionResult, writtenContent: content, path: url)
        
        XCTAssertEqual(result.status, .passed)
        XCTAssertFalse(result.isCorrupted)
        XCTAssertTrue(result.checksumMatches)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertGreaterThan(result.fileSizeBytes, 0)
        XCTAssertFalse(result.contentHash.isEmpty)
    }
    
    func testValidateIntegrityWithCorruptedContent() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = "Completely different content"
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let result = try outputValidator.validateIntegrity(transcriptionResult, writtenContent: content, path: url)
        
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.isCorrupted)
        XCTAssertTrue(result.issues.contains("Content appears corrupted - original text not found"))
    }
    
    func testValidateIntegrityWithEmptyFile() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = ""
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let result = try outputValidator.validateIntegrity(transcriptionResult, writtenContent: content, path: url)
        
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.issues.contains("File is empty"))
    }
    
    func testValidateIntegrityWithSmallFile() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = "Hi"
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let result = try outputValidator.validateIntegrity(transcriptionResult, writtenContent: content, path: url)
        
        XCTAssertEqual(result.status, .warning)
        XCTAssertTrue(result.issues.contains("File size is suspiciously small: 2 bytes"))
    }
    
    // MARK: - Complete Output Validation Tests
    
    func testValidateCompleteOutputSuccess() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = "Hello world, this is a test transcription."
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let report = try outputValidator.validateOutput(transcriptionResult, writtenTo: url, format: .txt)
        
        XCTAssertEqual(report.overallStatus, .passed)
        XCTAssertEqual(report.formatValidation.status, .passed)
        XCTAssertEqual(report.integrityValidation.status, .passed)
        XCTAssertEqual(report.encodingValidation.status, .passed)
        XCTAssertGreaterThan(report.validationTime, 0)
    }
    
    func testValidateCompleteOutputWithWarnings() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = "Hello world, this is a test transcription.\u{0008}"
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let report = try outputValidator.validateOutput(transcriptionResult, writtenTo: url, format: .txt)
        
        XCTAssertEqual(report.overallStatus, .warning)
        XCTAssertEqual(report.formatValidation.status, .passed)
        XCTAssertEqual(report.integrityValidation.status, .passed)
        XCTAssertEqual(report.encodingValidation.status, .warning)
    }
    
    func testValidateCompleteOutputWithFailures() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = ""
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let report = try outputValidator.validateOutput(transcriptionResult, writtenTo: url, format: .txt)
        
        XCTAssertEqual(report.overallStatus, .failed)
        XCTAssertEqual(report.formatValidation.status, .failed)
        XCTAssertEqual(report.integrityValidation.status, .failed)
        XCTAssertEqual(report.encodingValidation.status, .passed)
    }
    
    // MARK: - Success Confirmation Tests
    
    func testSuccessConfirmationCreation() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = "Hello world, this is a test transcription."
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let report = try outputValidator.validateOutput(transcriptionResult, writtenTo: url, format: .txt)
        
        let successConfirmation = SuccessConfirmation(
            filePath: url,
            fileSize: Int64(content.count),
            format: .txt,
            validationReport: report,
            processingTime: 0.5
        )
        
        XCTAssertEqual(successConfirmation.filePath, url)
        XCTAssertEqual(successConfirmation.fileSize, Int64(content.count))
        XCTAssertEqual(successConfirmation.format, .txt)
        XCTAssertEqual(successConfirmation.validationReport.overallStatus, .passed)
        XCTAssertEqual(successConfirmation.processingTime, 0.5)
        XCTAssertTrue(successConfirmation.message.contains("successfully written and validated"))
    }
    
    func testSuccessConfirmationWithWarnings() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = "Hello world, this is a test transcription.\u{0008}"
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let report = try outputValidator.validateOutput(transcriptionResult, writtenTo: url, format: .txt)
        
        let successConfirmation = SuccessConfirmation(
            filePath: url,
            fileSize: Int64(content.count),
            format: .txt,
            validationReport: report,
            processingTime: 0.5
        )
        
        XCTAssertEqual(successConfirmation.validationReport.overallStatus, .warning)
        XCTAssertTrue(successConfirmation.message.contains("written with warnings"))
    }
    
    func testSuccessConfirmationWithFailures() throws {
        let transcriptionResult = createTestTranscriptionResult()
        let content = ""
        let url = try writeTestFile(content: content, filename: "test.txt")
        
        let report = try outputValidator.validateOutput(transcriptionResult, writtenTo: url, format: .txt)
        
        let successConfirmation = SuccessConfirmation(
            filePath: url,
            fileSize: Int64(content.count),
            format: .txt,
            validationReport: report,
            processingTime: 0.5
        )
        
        XCTAssertEqual(successConfirmation.validationReport.overallStatus, .failed)
        XCTAssertTrue(successConfirmation.message.contains("validation failed"))
    }
}