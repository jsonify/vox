import XCTest
@testable import vox

final class LoggerTests: XCTestCase {
    
    func testLoggerBasics() {
        let logger = Logger.shared
        XCTAssertNotNil(logger)
        
        Logger.shared.configure(verbose: false)
        XCTAssertFalse(Logger.shared.isVerbose)
        
        Logger.shared.configure(verbose: true)
        XCTAssertTrue(Logger.shared.isVerbose)
    }
    
    func testLogLevels() {
        XCTAssertEqual(LogLevel.debug.description, "DEBUG")
        XCTAssertEqual(LogLevel.info.description, "INFO")
        XCTAssertEqual(LogLevel.warn.description, "WARN")
        XCTAssertEqual(LogLevel.error.description, "ERROR")
    }
}