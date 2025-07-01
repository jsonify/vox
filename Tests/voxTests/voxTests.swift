import XCTest
@testable import vox

final class VoxTests: XCTestCase {
    func testOutputFormatDefaults() {
        XCTAssertEqual(OutputFormat.txt.rawValue, "txt")
        XCTAssertEqual(OutputFormat.srt.rawValue, "srt")
        XCTAssertEqual(OutputFormat.json.rawValue, "json")
    }
    
    func testFallbackAPIOptions() {
        XCTAssertEqual(FallbackAPI.openai.rawValue, "openai")
        XCTAssertEqual(FallbackAPI.revai.rawValue, "revai")
    }
    
    func testTranscriptionEngineValues() {
        XCTAssertEqual(TranscriptionEngine.speechAnalyzer.rawValue, "apple-speechanalyzer")
        XCTAssertEqual(TranscriptionEngine.openaiWhisper.rawValue, "openai-whisper")
        XCTAssertEqual(TranscriptionEngine.revai.rawValue, "rev-ai")
    }
}