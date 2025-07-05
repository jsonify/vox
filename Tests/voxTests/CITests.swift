import XCTest
@testable import vox

/// Simplified tests for CI environment that avoid file system operations
final class CITests: XCTestCase {
    func testBasicModelCreation() {
        let format = AudioFormat(codec: "m4a", sampleRate: 44100, channels: 2, bitRate: 128000, duration: 10.0)
        XCTAssertEqual(format.codec, "m4a")
        XCTAssertEqual(format.sampleRate, 44100)
    }

    func testOutputFormatEnum() {
        XCTAssertEqual(OutputFormat.txt.rawValue, "txt")
        XCTAssertEqual(OutputFormat.srt.rawValue, "srt")
        XCTAssertEqual(OutputFormat.json.rawValue, "json")
    }

    func testVoxErrorCreation() {
        let error = VoxError.invalidInputFile("test.mp4")
        XCTAssertNotNil(error.errorDescription)
        
        guard let errorDescription = error.errorDescription else {
            XCTFail("Error description should not be nil")
            return
        }
        XCTAssertTrue(errorDescription.contains("test.mp4"))
    }

    func testCommandConfiguration() {
        let config = Vox.configuration
        XCTAssertEqual(config.commandName, "vox")
        XCTAssertEqual(config.abstract, "Audio transcription CLI for MP4 video files")
        XCTAssertEqual(config.version, "1.0.0")
    }
}
