import XCTest
@testable import vox

final class VoxErrorOutputFormatTests: XCTestCase {
    // MARK: - VoxError Tests

    func testVoxErrorDescriptions() {
        let invalidFileError = VoxError.invalidInputFile("/nonexistent/file.mp4")
        XCTAssertEqual(invalidFileError.errorDescription, "Invalid input file: /nonexistent/file.mp4")

        let audioError = VoxError.audioExtractionFailed("Codec not supported")
        XCTAssertEqual(audioError.errorDescription, "Audio extraction failed: Codec not supported")

        let transcriptionError = VoxError.transcriptionFailed("Network timeout")
        XCTAssertEqual(transcriptionError.errorDescription, "Transcription failed: Network timeout")

        let outputError = VoxError.outputWriteFailed("Permission denied")
        XCTAssertEqual(outputError.errorDescription, "Failed to write output: Permission denied")

        let apiKeyError = VoxError.apiKeyMissing("OpenAI")
        XCTAssertEqual(apiKeyError.errorDescription, "API key missing for OpenAI")

        let formatError = VoxError.unsupportedFormat("avi")
        XCTAssertEqual(formatError.errorDescription, "Unsupported format: avi")
    }

    func testVoxErrorLocalizedDescription() {
        let error = VoxError.audioExtractionFailed("Test reason")
        XCTAssertEqual(error.localizedDescription, "Audio extraction failed: Test reason")
    }

    func testNewVoxErrorTypes() {
        let validationError = VoxError.audioFormatValidationFailed("Invalid sample rate")
        XCTAssertEqual(validationError.errorDescription, "Audio format validation failed: Invalid sample rate")

        let compatibilityError = VoxError.incompatibleAudioProperties("Unsupported channel configuration")
        XCTAssertEqual(compatibilityError.errorDescription, "Incompatible audio properties: Unsupported channel configuration")
    }

    func testVoxErrorEquality() {
        let error1 = VoxError.invalidInputFile("test.mp4")
        let error2 = VoxError.invalidInputFile("test.mp4")

        // Note: VoxError doesn't conform to Equatable, but we can test error descriptions
        XCTAssertEqual(error1.errorDescription, error2.errorDescription)
    }

    // MARK: - OutputFormat Tests

    func testOutputFormatValues() {
        XCTAssertEqual(OutputFormat.txt.rawValue, "txt")
        XCTAssertEqual(OutputFormat.srt.rawValue, "srt")
        XCTAssertEqual(OutputFormat.json.rawValue, "json")
    }

    func testOutputFormatAllCases() {
        let allCases = OutputFormat.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.txt))
        XCTAssertTrue(allCases.contains(.srt))
        XCTAssertTrue(allCases.contains(.json))
    }

    func testOutputFormatDefaultValue() {
        let format = OutputFormat.txt
        XCTAssertEqual(format.defaultValueDescription, "txt")
    }

    // MARK: - FallbackAPI Tests

    func testFallbackAPIValues() {
        XCTAssertEqual(FallbackAPI.openai.rawValue, "openai")
        XCTAssertEqual(FallbackAPI.revai.rawValue, "revai")
    }

    func testFallbackAPIAllCases() {
        let allCases = FallbackAPI.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.openai))
        XCTAssertTrue(allCases.contains(.revai))
    }
}
