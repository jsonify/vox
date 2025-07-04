import XCTest
@testable import vox

final class LoggerTests: XCTestCase {
    private var originalVerboseSetting: Bool = false

    override func setUp() {
        super.setUp()
        originalVerboseSetting = Logger.shared.isVerbose
    }

    override func tearDown() {
        Logger.shared.configure(verbose: originalVerboseSetting)
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testLoggerSingleton() {
        let logger1 = Logger.shared
        let logger2 = Logger.shared
        XCTAssertIdentical(logger1, logger2)
    }

    func testLoggerConfiguration() {
        Logger.shared.configure(verbose: false)
        XCTAssertFalse(Logger.shared.isVerbose)

        Logger.shared.configure(verbose: true)
        XCTAssertTrue(Logger.shared.isVerbose)

        // Test multiple configurations
        Logger.shared.configure(verbose: false)
        XCTAssertFalse(Logger.shared.isVerbose)

        Logger.shared.configure(verbose: true)
        XCTAssertTrue(Logger.shared.isVerbose)
    }

    // MARK: - LogLevel Tests

    func testLogLevelDescriptions() {
        XCTAssertEqual(LogLevel.debug.description, "DEBUG")
        XCTAssertEqual(LogLevel.info.description, "INFO")
        XCTAssertEqual(LogLevel.warn.description, "WARN")
        XCTAssertEqual(LogLevel.error.description, "ERROR")
    }

    func testLogLevelRawValues() {
        XCTAssertEqual(LogLevel.debug.rawValue, 0)
        XCTAssertEqual(LogLevel.info.rawValue, 1)
        XCTAssertEqual(LogLevel.warn.rawValue, 2)
        XCTAssertEqual(LogLevel.error.rawValue, 3)
    }

    func testLogLevelComparison() {
        XCTAssertLessThan(LogLevel.debug.rawValue, LogLevel.info.rawValue)
        XCTAssertLessThan(LogLevel.info.rawValue, LogLevel.warn.rawValue)
        XCTAssertLessThan(LogLevel.warn.rawValue, LogLevel.error.rawValue)
    }

    // MARK: - Logging Method Tests

    func testDebugLogging() {
        Logger.shared.configure(verbose: true)

        // Test debug logging with component
        Logger.shared.debug("Debug message", component: "TestComponent")

        // Test debug logging without component
        Logger.shared.debug("Debug message without component")

        // These tests don't crash, which is the main verification
        XCTAssertTrue(Logger.shared.isVerbose)
    }

    func testInfoLogging() {
        Logger.shared.configure(verbose: false)

        // Test info logging with component
        Logger.shared.info("Info message", component: "TestComponent")

        // Test info logging without component
        Logger.shared.info("Info message without component")

        // Should work regardless of verbose setting
        XCTAssertFalse(Logger.shared.isVerbose)
    }

    func testWarnLogging() {
        Logger.shared.configure(verbose: true)

        // Test warn logging with component
        Logger.shared.warn("Warning message", component: "TestComponent")

        // Test warn logging without component
        Logger.shared.warn("Warning message without component")

        XCTAssertTrue(Logger.shared.isVerbose)
    }

    func testErrorLogging() {
        Logger.shared.configure(verbose: false)

        // Test error logging with component
        Logger.shared.error("Error message", component: "TestComponent")

        // Test error logging without component
        Logger.shared.error("Error message without component")

        // Error logging should work regardless of verbose setting
        XCTAssertFalse(Logger.shared.isVerbose)
    }

    // MARK: - Verbose Mode Tests

    func testVerboseModeEnabled() {
        Logger.shared.configure(verbose: true)
        XCTAssertTrue(Logger.shared.isVerbose)

        // All log levels should be available in verbose mode
        Logger.shared.debug("Debug in verbose mode", component: "Test")
        Logger.shared.info("Info in verbose mode", component: "Test")
        Logger.shared.warn("Warn in verbose mode", component: "Test")
        Logger.shared.error("Error in verbose mode", component: "Test")
    }

    func testVerboseModeDisabled() {
        Logger.shared.configure(verbose: false)
        XCTAssertFalse(Logger.shared.isVerbose)

        // Debug messages might be filtered in non-verbose mode, but shouldn't crash
        Logger.shared.debug("Debug in non-verbose mode", component: "Test")
        Logger.shared.info("Info in non-verbose mode", component: "Test")
        Logger.shared.warn("Warn in non-verbose mode", component: "Test")
        Logger.shared.error("Error in non-verbose mode", component: "Test")
    }

    // MARK: - Component Parameter Tests

    func testLoggingWithComponents() {
        let components = [
            "AudioProcessor",
            "CLI",
            "Transcription",
            "OutputWriter",
            "API",
            "FileProcessor"
        ]

        Logger.shared.configure(verbose: true)

        for component in components {
            Logger.shared.debug("Debug message", component: component)
            Logger.shared.info("Info message", component: component)
            Logger.shared.warn("Warning message", component: component)
            Logger.shared.error("Error message", component: component)
        }
    }

    func testLoggingWithoutComponents() {
        Logger.shared.configure(verbose: true)

        Logger.shared.debug("Debug without component")
        Logger.shared.info("Info without component")
        Logger.shared.warn("Warning without component")
        Logger.shared.error("Error without component")
    }

    func testLoggingWithEmptyComponent() {
        Logger.shared.configure(verbose: true)

        Logger.shared.debug("Debug with empty component", component: "")
        Logger.shared.info("Info with empty component", component: "")
        Logger.shared.warn("Warning with empty component", component: "")
        Logger.shared.error("Error with empty component", component: "")
    }

    // MARK: - Message Content Tests

    func testLoggingWithEmptyMessages() {
        Logger.shared.configure(verbose: true)

        Logger.shared.debug("", component: "Test")
        Logger.shared.info("", component: "Test")
        Logger.shared.warn("", component: "Test")
        Logger.shared.error("", component: "Test")
    }

    func testLoggingWithSpecialCharacters() {
        Logger.shared.configure(verbose: true)

        let specialMessages = [
            "Message with émojis 🎵🔊",
            "Message with\nnewlines\nand\ttabs",
            "Message with \"quotes\" and 'apostrophes'",
            "Message with special chars: !@#$%^&*()_+-={}[]|\\:;\"'<>?,./"
        ]

        for message in specialMessages {
            Logger.shared.debug(message, component: "SpecialChars")
            Logger.shared.info(message, component: "SpecialChars")
            Logger.shared.warn(message, component: "SpecialChars")
            Logger.shared.error(message, component: "SpecialChars")
        }
    }

    func testLoggingWithLongMessages() {
        Logger.shared.configure(verbose: true)

        let longMessage = String(repeating: "This is a very long message. ", count: 100)

        Logger.shared.debug(longMessage, component: "LongMessage")
        Logger.shared.info(longMessage, component: "LongMessage")
        Logger.shared.warn(longMessage, component: "LongMessage")
        Logger.shared.error(longMessage, component: "LongMessage")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentLogging() {
        Logger.shared.configure(verbose: true)

        let concurrentQueue = DispatchQueue(label: "test.logging", attributes: .concurrent)
        let group = DispatchGroup()

        for i in 0..<100 {
            group.enter()
            concurrentQueue.async {
                Logger.shared.info("Concurrent message \(i)", component: "ConcurrentTest")
                group.leave()
            }
        }

        let expectation = XCTestExpectation(description: "Concurrent logging")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testConcurrentConfiguration() {
        let concurrentQueue = DispatchQueue(label: "test.config", attributes: .concurrent)
        let group = DispatchGroup()

        for i in 0..<50 {
            group.enter()
            concurrentQueue.async {
                Logger.shared.configure(verbose: i % 2 == 0)
                Logger.shared.info("Config test \(i)", component: "ConfigTest")
                group.leave()
            }
        }

        let expectation = XCTestExpectation(description: "Concurrent configuration")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Performance Tests

    func testLoggingPerformance() {
        Logger.shared.configure(verbose: true)

        measure {
            for i in 0..<1000 {
                Logger.shared.info("Performance test message \(i)", component: "Performance")
            }
        }
    }

    func testVerboseLoggingPerformance() {
        Logger.shared.configure(verbose: true)

        measure {
            for i in 0..<1000 {
                Logger.shared.debug("Debug performance test \(i)", component: "Debug")
            }
        }
    }

    func testNonVerboseLoggingPerformance() {
        Logger.shared.configure(verbose: false)

        measure {
            for i in 0..<1000 {
                Logger.shared.debug("Debug message that might be filtered \(i)", component: "Debug")
            }
        }
    }

    // MARK: - Configuration State Tests

    func testConfigurationPersistence() {
        // Test that configuration persists across multiple calls
        Logger.shared.configure(verbose: true)
        XCTAssertTrue(Logger.shared.isVerbose)

        Logger.shared.info("Test message")
        XCTAssertTrue(Logger.shared.isVerbose)

        Logger.shared.configure(verbose: false)
        XCTAssertFalse(Logger.shared.isVerbose)

        Logger.shared.error("Error message")
        XCTAssertFalse(Logger.shared.isVerbose)
    }

    func testMultipleConfigurations() {
        let configurations = [true, false, true, false, true]

        for verbose in configurations {
            Logger.shared.configure(verbose: verbose)
            XCTAssertEqual(Logger.shared.isVerbose, verbose)
        }
    }
}
