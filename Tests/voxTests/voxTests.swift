import XCTest
@testable import vox

final class VoxTests: XCTestCase {
    func testBasicEnums() {
        XCTAssertEqual(OutputFormat.txt.rawValue, "txt")
        XCTAssertEqual(FallbackAPI.openai.rawValue, "openai")
        XCTAssertEqual(TranscriptionEngine.speechAnalyzer.rawValue, "apple-speechanalyzer")
    }
}