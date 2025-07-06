import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Comprehensive workflow tests that validate the complete Vox workflow
/// with various sample files and output formats.
final class ComprehensiveWorkflowTests: ComprehensiveIntegrationTestsBase {
    
    // MARK: - Comprehensive Workflow Tests
    
    func testAllSampleFilesWithAllFormats() throws {
        let formats: [OutputFormat] = [.txt, .srt, .json]
        var allTestCases: [(String, URL, OutputFormat)] = []
        
        // Build test cases from real files
        for (name, file) in realSampleFiles {
            for format in formats {
                allTestCases.append(("real_\(name)", file, format))
            }
        }
        
        // Build test cases from generated files
        for (name, file) in generatedSampleFiles {
            for format in formats {
                allTestCases.append(("gen_\(name)", file, format))
            }
        }
        
        guard !allTestCases.isEmpty else {
            throw XCTSkip("No sample files available for testing")
        }
        
        // Execute all test cases
        for (name, file, format) in allTestCases {
            let expectedValidator: ((String) -> Bool)? = {
                switch format {
                case .txt:
                    return self.validateTextOutput
                case .srt:
                    return self.validateSRTOutput
                case .json:
                    return self.validateJSONOutput
                }
            }()
            
            let result = try executeCompleteWorkflow(
                inputFile: file,
                outputFormat: format,
                expectedContentValidation: expectedValidator
            )
            
            // Validate processing time is reasonable
            XCTAssertLessThan(result.processingTime, 120.0, 
                            "Processing time for \(name) should be under 2 minutes")
            
            // Validate output content based on format
            switch format {
            case .txt:
                XCTAssertTrue(validateTextOutput(result.output), 
                            "Text output validation failed for \(name)")
            case .srt:
                XCTAssertTrue(validateSRTOutput(result.output), 
                            "SRT output validation failed for \(name)")
            case .json:
                XCTAssertTrue(validateJSONOutput(result.output), 
                            "JSON output validation failed for \(name)")
            }
        }
    }
    
    func testWorkflowWithTimestampVariations() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        let testCases: [(OutputFormat, Bool, String)] = [
            (.txt, false, "txt_no_timestamps"),
            (.txt, true, "txt_with_timestamps"),
            (.srt, true, "srt_with_timestamps"),
            (.json, false, "json_no_timestamps"),
            (.json, true, "json_with_timestamps")
        ]
        
        for (format, includeTimestamps, testName) in testCases {
            // Create CLI command
            var voxCommand = Vox()
            voxCommand.inputFile = testFile.path
            voxCommand.format = format
            voxCommand.timestamps = includeTimestamps
            voxCommand.verbose = true
            
            // Create output file
            let outputFile = tempDirectory.appendingPathComponent("\(testName)_output.\(format.rawValue)")
            voxCommand.output = outputFile.path
            
            // Execute the workflow
            try voxCommand.run()
            
            // Validate output exists and is correct
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
                         "Output file should exist for \(testName)")
            
            let outputContent = try String(contentsOf: outputFile)
            XCTAssertFalse(outputContent.isEmpty, "Output content should not be empty for \(testName)")
            
            // Validate timestamp inclusion based on format and setting
            if includeTimestamps {
                switch format {
                case .srt:
                    XCTAssertTrue(validateSRTOutput(outputContent), 
                                "SRT should include timestamps for \(testName)")
                case .json:
                    XCTAssertTrue(outputContent.contains("startTime"), 
                                "JSON should include timestamps for \(testName)")
                case .txt:
                    // TXT with timestamps should include time markers
                    XCTAssertTrue(outputContent.contains("[") && outputContent.contains("]"), 
                                "TXT with timestamps should include time markers for \(testName)")
                }
            }
        }
    }
    
    func testOutputFormatSpecificValidation() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        // Test TXT format
        let txtResult = try executeCompleteWorkflow(
            inputFile: testFile,
            outputFormat: .txt,
            expectedContentValidation: validateTextOutput
        )
        
        // TXT should be plain text
        XCTAssertFalse(txtResult.output.contains("{"), "TXT output should not contain JSON")
        XCTAssertFalse(txtResult.output.contains("-->"), "TXT output should not contain SRT timestamps")
        
        // Test SRT format
        let srtResult = try executeCompleteWorkflow(
            inputFile: testFile,
            outputFormat: .srt,
            expectedContentValidation: validateSRTOutput
        )
        
        // SRT should contain numbered entries and timestamps
        XCTAssertTrue(srtResult.output.contains("1\n"), "SRT should contain numbered entries")
        XCTAssertTrue(srtResult.output.contains("-->"), "SRT should contain timestamp separators")
        
        // Test JSON format
        let jsonResult = try executeCompleteWorkflow(
            inputFile: testFile,
            outputFormat: .json,
            expectedContentValidation: validateJSONOutput
        )
        
        // JSON should be valid JSON with expected structure
        let jsonData = jsonResult.output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(json, "JSON should be valid dictionary")
        
        XCTAssertNotNil(json?["text"], "JSON should contain text field")
        XCTAssertNotNil(json?["language"], "JSON should contain language field")
        XCTAssertNotNil(json?["confidence"], "JSON should contain confidence field")
        XCTAssertNotNil(json?["duration"], "JSON should contain duration field")
        XCTAssertNotNil(json?["segments"], "JSON should contain segments field")
    }
    
    func testLargeFileHandling() throws {
        guard let largeFile = realSampleFiles["large"] ?? generatedSampleFiles["large"] else {
            throw XCTSkip("No large sample file available")
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let result = try executeCompleteWorkflow(
            inputFile: largeFile,
            outputFormat: .json,
            expectedContentValidation: validateJSONOutput
        )
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Validate reasonable processing time for large files
        XCTAssertLessThan(totalTime, 300.0, "Large file processing should complete within 5 minutes")
        
        // Validate output quality
        XCTAssertFalse(result.output.isEmpty, "Large file should produce non-empty output")
        XCTAssertTrue(validateJSONOutput(result.output), "Large file should produce valid JSON")
        
        // Parse JSON and validate segments
        let jsonData = result.output.data(using: .utf8)!
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let segments = json["segments"] as? [[String: Any]] else {
            XCTFail("Large file should produce valid JSON with segments array")
            return
        }
        
        XCTAssertGreaterThan(segments.count, 0, "Large file should produce multiple segments")
        
        // Validate segment structure
        for segment in segments {
            XCTAssertNotNil(segment["text"], "Each segment should have text")
            XCTAssertNotNil(segment["startTime"], "Each segment should have startTime")
            XCTAssertNotNil(segment["endTime"], "Each segment should have endTime")
            XCTAssertNotNil(segment["confidence"], "Each segment should have confidence")
        }
    }
}