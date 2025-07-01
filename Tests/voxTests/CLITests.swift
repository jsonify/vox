import XCTest
import ArgumentParser
@testable import vox

final class CLITests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func parseVoxCommand(_ arguments: [String]) throws -> Vox {
        return try Vox.parseAsRoot(arguments) as! Vox
    }
    
    // MARK: - Command Configuration Tests
    
    func testCommandConfiguration() {
        let config = Vox.configuration
        XCTAssertEqual(config.commandName, "vox")
        XCTAssertEqual(config.abstract, "Audio transcription CLI for MP4 video files")
        XCTAssertEqual(config.version, "1.0.0")
    }
    
    // MARK: - Argument Parsing Tests
    
    func testBasicArgumentParsing() throws {
        let command = try parseVoxCommand(["input.mp4"])
        
        XCTAssertEqual(command.inputFile, "input.mp4")
        XCTAssertNil(command.output)
        XCTAssertEqual(command.format, .txt)
        XCTAssertNil(command.language)
        XCTAssertNil(command.fallbackApi)
        XCTAssertNil(command.apiKey)
        XCTAssertFalse(command.verbose)
        XCTAssertFalse(command.forceCloud)
        XCTAssertFalse(command.timestamps)
    }
    
    func testOutputArgumentParsing() throws {
        let shortFormCommand = try parseVoxCommand(["input.mp4", "-o", "output.txt"])
        XCTAssertEqual(shortFormCommand.inputFile, "input.mp4")
        XCTAssertEqual(shortFormCommand.output, "output.txt")
        
        let longFormCommand = try parseVoxCommand(["input.mp4", "--output", "transcript.txt"])
        XCTAssertEqual(longFormCommand.inputFile, "input.mp4")
        XCTAssertEqual(longFormCommand.output, "transcript.txt")
    }
    
    func testFormatArgumentParsing() throws {
        let txtCommand = try parseVoxCommand(["input.mp4", "-f", "txt"])
        XCTAssertEqual(txtCommand.format, .txt)
        
        let srtCommand = try parseVoxCommand(["input.mp4", "--format", "srt"])
        XCTAssertEqual(srtCommand.format, .srt)
        
        let jsonCommand = try parseVoxCommand(["input.mp4", "-f", "json"])
        XCTAssertEqual(jsonCommand.format, .json)
    }
    
    func testLanguageArgumentParsing() throws {
        let shortFormCommand = try parseVoxCommand(["input.mp4", "-l", "en-US"])
        XCTAssertEqual(shortFormCommand.language, "en-US")
        
        let longFormCommand = try parseVoxCommand(["input.mp4", "--language", "es-ES"])
        XCTAssertEqual(longFormCommand.language, "es-ES")
    }
    
    func testFallbackApiArgumentParsing() throws {
        let openaiCommand = try parseVoxCommand(["input.mp4", "--fallback-api", "openai"])
        XCTAssertEqual(openaiCommand.fallbackApi, .openai)
        
        let revaiCommand = try parseVoxCommand(["input.mp4", "--fallback-api", "revai"])
        XCTAssertEqual(revaiCommand.fallbackApi, .revai)
    }
    
    func testApiKeyArgumentParsing() throws {
        let command = try parseVoxCommand(["input.mp4", "--api-key", "sk-test123"])
        XCTAssertEqual(command.apiKey, "sk-test123")
    }
    
    func testVerboseFlagParsing() throws {
        let shortFormCommand = try parseVoxCommand(["input.mp4", "-v"])
        XCTAssertTrue(shortFormCommand.verbose)
        
        let longFormCommand = try parseVoxCommand(["input.mp4", "--verbose"])
        XCTAssertTrue(longFormCommand.verbose)
    }
    
    func testForceCloudFlagParsing() throws {
        let command = try parseVoxCommand(["input.mp4", "--force-cloud"])
        XCTAssertTrue(command.forceCloud)
    }
    
    func testTimestampsFlagParsing() throws {
        let command = try parseVoxCommand(["input.mp4", "--timestamps"])
        XCTAssertTrue(command.timestamps)
    }
    
    // MARK: - Complex Argument Combinations Tests
    
    func testComplexArgumentCombination() throws {
        let command = try parseVoxCommand([
            "video.mp4",
            "-o", "transcript.srt",
            "--format", "srt",
            "-l", "en-US",
            "--fallback-api", "openai",
            "--api-key", "sk-abc123",
            "--verbose",
            "--force-cloud",
            "--timestamps"
        ])
        
        XCTAssertEqual(command.inputFile, "video.mp4")
        XCTAssertEqual(command.output, "transcript.srt")
        XCTAssertEqual(command.format, .srt)
        XCTAssertEqual(command.language, "en-US")
        XCTAssertEqual(command.fallbackApi, .openai)
        XCTAssertEqual(command.apiKey, "sk-abc123")
        XCTAssertTrue(command.verbose)
        XCTAssertTrue(command.forceCloud)
        XCTAssertTrue(command.timestamps)
    }
    
    func testMinimalArgumentCombination() throws {
        let command = try parseVoxCommand(["minimal.mp4"])
        
        XCTAssertEqual(command.inputFile, "minimal.mp4")
        XCTAssertNil(command.output)
        XCTAssertEqual(command.format, .txt)
        XCTAssertNil(command.language)
        XCTAssertNil(command.fallbackApi)
        XCTAssertNil(command.apiKey)
        XCTAssertFalse(command.verbose)
        XCTAssertFalse(command.forceCloud)
        XCTAssertFalse(command.timestamps)
    }
    
    // MARK: - Error Handling Tests
    
    func testMissingInputFileArgument() {
        XCTAssertThrowsError(try parseVoxCommand([])) { error in
            // Argument parsing errors are thrown by ArgumentParser
            XCTAssertNotNil(error)
        }
    }
    
    func testInvalidFormatArgument() {
        XCTAssertThrowsError(try parseVoxCommand(["input.mp4", "--format", "invalid"])) { error in
            XCTAssertNotNil(error)
        }
    }
    
    func testInvalidFallbackApiArgument() {
        XCTAssertThrowsError(try parseVoxCommand(["input.mp4", "--fallback-api", "invalid"])) { error in
            XCTAssertNotNil(error)
        }
    }
    
    func testUnknownFlag() {
        XCTAssertThrowsError(try parseVoxCommand(["input.mp4", "--unknown-flag"])) { error in
            XCTAssertNotNil(error)
        }
    }
    
    func testMissingValueForOption() {
        XCTAssertThrowsError(try parseVoxCommand(["input.mp4", "--output"])) { error in
            XCTAssertNotNil(error)
        }
        
        XCTAssertThrowsError(try parseVoxCommand(["input.mp4", "--format"])) { error in
            XCTAssertNotNil(error)
        }
        
        XCTAssertThrowsError(try parseVoxCommand(["input.mp4", "--language"])) { error in
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testFilePathsWithSpaces() throws {
        let command = try parseVoxCommand([
            "file with spaces.mp4",
            "--output", "output with spaces.txt"
        ])
        
        XCTAssertEqual(command.inputFile, "file with spaces.mp4")
        XCTAssertEqual(command.output, "output with spaces.txt")
    }
    
    func testFilePathsWithSpecialCharacters() throws {
        let command = try parseVoxCommand([
            "file-with_special@chars.mp4",
            "--output", "output#file$with%special&chars.txt"
        ])
        
        XCTAssertEqual(command.inputFile, "file-with_special@chars.mp4")
        XCTAssertEqual(command.output, "output#file$with%special&chars.txt")
    }
    
    func testAbsolutePaths() throws {
        let command = try parseVoxCommand([
            "/absolute/path/to/video.mp4",
            "--output", "/absolute/path/to/output.txt"
        ])
        
        XCTAssertEqual(command.inputFile, "/absolute/path/to/video.mp4")
        XCTAssertEqual(command.output, "/absolute/path/to/output.txt")
    }
    
    func testRelativePaths() throws {
        let command = try parseVoxCommand([
            "./relative/path/video.mp4",
            "--output", "../output/transcript.txt"
        ])
        
        XCTAssertEqual(command.inputFile, "./relative/path/video.mp4")
        XCTAssertEqual(command.output, "../output/transcript.txt")
    }
    
    func testEmptyStringArguments() throws {
        let command = try parseVoxCommand([
            "",
            "--output", "",
            "--language", "",
            "--api-key", ""
        ])
        
        XCTAssertEqual(command.inputFile, "")
        XCTAssertEqual(command.output, "")
        XCTAssertEqual(command.language, "")
        XCTAssertEqual(command.apiKey, "")
    }
    
    // MARK: - Flag Combination Tests
    
    func testAllFlagsCombination() throws {
        let command = try parseVoxCommand([
            "input.mp4",
            "--verbose",
            "--force-cloud",
            "--timestamps"
        ])
        
        XCTAssertTrue(command.verbose)
        XCTAssertTrue(command.forceCloud)
        XCTAssertTrue(command.timestamps)
    }
    
    func testConflictingFormatAndOutput() throws {
        // This is not actually conflicting, but tests that both can be specified
        let command = try parseVoxCommand([
            "input.mp4",
            "--format", "json",
            "--output", "output.txt"
        ])
        
        XCTAssertEqual(command.format, .json)
        XCTAssertEqual(command.output, "output.txt")
    }
    
    // MARK: - Help and Version Tests
    
    func testHelpFlag() {
        XCTAssertThrowsError(try Vox.parseAsRoot(["--help"])) { error in
            // Help flag should throw ExitCode.success
            if let exitCode = error as? ExitCode {
                XCTAssertEqual(exitCode, .success)
            } else {
                XCTFail("Expected ExitCode.success for help flag")
            }
        }
    }
    
    func testVersionFlag() {
        XCTAssertThrowsError(try Vox.parseAsRoot(["--version"])) { error in
            // Version flag should throw ExitCode.success
            if let exitCode = error as? ExitCode {
                XCTAssertEqual(exitCode, .success)
            } else {
                XCTFail("Expected ExitCode.success for version flag")
            }
        }
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultValues() throws {
        let command = try parseVoxCommand(["test.mp4"])
        
        XCTAssertEqual(command.format, .txt)
        XCTAssertFalse(command.verbose)
        XCTAssertFalse(command.forceCloud)
        XCTAssertFalse(command.timestamps)
    }
    
    func testOutputFormatDefaultValue() {
        let format = OutputFormat.txt
        XCTAssertEqual(format.defaultValueDescription, "txt")
    }
    
    // MARK: - Argument Order Independence Tests
    
    func testArgumentOrderIndependence() throws {
        let command1 = try parseVoxCommand([
            "input.mp4",
            "--format", "srt",
            "--verbose",
            "--output", "out.srt"
        ])
        
        let command2 = try parseVoxCommand([
            "--verbose",
            "--output", "out.srt",
            "input.mp4",
            "--format", "srt"
        ])
        
        XCTAssertEqual(command1.inputFile, command2.inputFile)
        XCTAssertEqual(command1.output, command2.output)
        XCTAssertEqual(command1.format, command2.format)
        XCTAssertEqual(command1.verbose, command2.verbose)
    }
    
    // MARK: - Language Code Validation Tests
    
    func testValidLanguageCodes() throws {
        let validLanguages = ["en-US", "es-ES", "fr-FR", "de-DE", "ja-JP", "zh-CN"]
        
        for language in validLanguages {
            let command = try parseVoxCommand(["input.mp4", "--language", language])
            XCTAssertEqual(command.language, language)
        }
    }
    
    func testLanguageCodeCaseSensitivity() throws {
        let command1 = try parseVoxCommand(["input.mp4", "--language", "en-US"])
        let command2 = try parseVoxCommand(["input.mp4", "--language", "en-us"])
        let command3 = try parseVoxCommand(["input.mp4", "--language", "EN-US"])
        
        XCTAssertEqual(command1.language, "en-US")
        XCTAssertEqual(command2.language, "en-us")
        XCTAssertEqual(command3.language, "EN-US")
    }
    
    // MARK: - API Key Security Tests
    
    func testApiKeyHandling() throws {
        let apiKeys = [
            "sk-1234567890abcdef",
            "very-long-api-key-with-many-characters-and-numbers-123456789",
            "short",
            "key-with-special-chars!@#$%^&*()"
        ]
        
        for apiKey in apiKeys {
            let command = try parseVoxCommand(["input.mp4", "--api-key", apiKey])
            XCTAssertEqual(command.apiKey, apiKey)
        }
    }
    
    // MARK: - File Extension Validation Tests
    
    func testInputFileExtensions() throws {
        let validExtensions = ["video.mp4", "movie.m4v", "clip.mov"]
        
        for filename in validExtensions {
            let command = try parseVoxCommand([filename])
            XCTAssertEqual(command.inputFile, filename)
        }
    }
    
    func testOutputFileExtensions() throws {
        let outputFiles = [
            "transcript.txt",
            "subtitles.srt", 
            "metadata.json",
            "output_without_extension"
        ]
        
        for filename in outputFiles {
            let command = try parseVoxCommand(["input.mp4", "--output", filename])
            XCTAssertEqual(command.output, filename)
        }
    }
}