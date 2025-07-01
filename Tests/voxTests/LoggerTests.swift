import XCTest
@testable import vox

final class LoggerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        Logger.shared.configure(verbose: false)
    }
    
    func testLoggerSingleton() {
        let logger1 = Logger.shared
        let logger2 = Logger.shared
        XCTAssertTrue(logger1 === logger2, "Logger should be a singleton")
    }
    
    func testVerboseConfiguration() {
        Logger.shared.configure(verbose: false)
        XCTAssertFalse(Logger.shared.isVerbose)
        XCTAssertEqual(Logger.shared.minimumLevel, .info)
        
        Logger.shared.configure(verbose: true)
        XCTAssertTrue(Logger.shared.isVerbose)
        XCTAssertEqual(Logger.shared.minimumLevel, .debug)
    }
    
    func testLogLevelComparison() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warn)
        XCTAssertTrue(LogLevel.warn < LogLevel.error)
        XCTAssertFalse(LogLevel.error < LogLevel.debug)
    }
    
    func testLogLevelDescriptions() {
        XCTAssertEqual(LogLevel.debug.description, "DEBUG")
        XCTAssertEqual(LogLevel.info.description, "INFO")
        XCTAssertEqual(LogLevel.warn.description, "WARN")
        XCTAssertEqual(LogLevel.error.description, "ERROR")
    }
    
    func testLoggingMethods() {
        let expectation = XCTestExpectation(description: "Logging methods should not crash")
        
        Logger.shared.configure(verbose: true)
        
        Logger.shared.debug("Debug message")
        Logger.shared.info("Info message")
        Logger.shared.warn("Warning message")
        Logger.shared.error("Error message")
        
        Logger.shared.debug("Debug with component", component: "TestComponent")
        Logger.shared.info("Info with component", component: "TestComponent")
        Logger.shared.warn("Warning with component", component: "TestComponent")
        Logger.shared.error("Error with component", component: "TestComponent")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testComponentSpecificLogging() {
        let expectation = XCTestExpectation(description: "Component-specific logging should work")
        
        Logger.shared.configure(verbose: true)
        
        Logger.shared.logAudioProcessing("Audio processing message")
        Logger.shared.logTranscription("Transcription message")
        Logger.shared.logAPI("API message")
        
        let testError = VoxError.invalidInputFile("test.mp4")
        Logger.shared.logError(testError)
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testVoxErrorLogging() {
        let errors: [VoxError] = [
            .invalidInputFile("test.mp4"),
            .audioExtractionFailed("Test reason"),
            .transcriptionFailed("Test reason"),
            .outputWriteFailed("Test reason"),
            .apiKeyMissing("OpenAI"),
            .unsupportedFormat("mp3")
        ]
        
        for error in errors {
            XCTAssertNoThrow(error.log())
            XCTAssertNotNil(error.errorDescription)
        }
    }
    
    func testThreadSafety() {
        let expectation = XCTestExpectation(description: "Thread safety test")
        expectation.expectedFulfillmentCount = 10
        
        Logger.shared.configure(verbose: true)
        
        let queue = DispatchQueue.global(qos: .default)
        
        for i in 0..<10 {
            queue.async {
                Logger.shared.info("Thread safety test message \(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testMinimumLogLevel() {
        Logger.shared.configure(verbose: false)
        XCTAssertEqual(Logger.shared.minimumLevel, .info)
        
        Logger.shared.configure(verbose: true)
        XCTAssertEqual(Logger.shared.minimumLevel, .debug)
    }
    
    func testLogLevelFiltering() {
        Logger.shared.configure(verbose: false)
        
        Logger.shared.debug("This debug message should be filtered out")
        Logger.shared.info("This info message should appear")
        Logger.shared.warn("This warning message should appear")
        Logger.shared.error("This error message should appear")
    }
}