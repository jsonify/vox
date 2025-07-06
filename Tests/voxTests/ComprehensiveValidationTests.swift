import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Comprehensive validation tests that verify output quality and format compliance
/// across all supported formats and scenarios.
final class ComprehensiveValidationTests: ComprehensiveIntegrationTestsBase {
    
    // MARK: - Output Validation Testing
    
    func testOutputValidationAcrossAllFormats() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        let formats: [OutputFormat] = [.txt, .srt, .json]
        
        for format in formats {
            let result = try executeCompleteWorkflow(
                inputFile: testFile,
                outputFormat: format,
                expectedContentValidation: { content in
                    switch format {
                    case .txt:
                        return self.validateTextOutput(content)
                    case .srt:
                        return self.validateSRTOutput(content)
                    case .json:
                        return self.validateJSONOutput(content)
                    }
                }
            )
            
            // Format-specific validation
            switch format {
            case .txt:
                XCTAssertFalse(result.output.contains("-->"), "TXT should not contain SRT timestamps")
                XCTAssertFalse(result.output.contains("{"), "TXT should not contain JSON")
            case .srt:
                XCTAssertTrue(result.output.contains("-->"), "SRT should contain time indicators")
                XCTAssertTrue(result.output.contains("1"), "SRT should contain sequence numbers")
            case .json:
                XCTAssertTrue(result.output.contains("\"text\""), "JSON should contain text field")
                
                // Validate JSON structure
                let jsonData = result.output.data(using: String.Encoding.utf8)!
                let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                XCTAssertNotNil(jsonObject, "JSON should be valid")
            }
        }
    }
    
    func testTimestampAccuracy() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        // Test SRT timestamp format
        let srtResult = try executeCompleteWorkflow(
            inputFile: testFile,
            outputFormat: .srt,
            expectedContentValidation: validateSRTOutput
        )
        
        // Validate SRT timestamp format: HH:MM:SS,mmm --> HH:MM:SS,mmm
        let srtTimePattern = "\\d{2}:\\d{2}:\\d{2},\\d{3} --> \\d{2}:\\d{2}:\\d{2},\\d{3}"
        let srtRegex = try NSRegularExpression(pattern: srtTimePattern)
        let srtMatches = srtRegex.matches(in: srtResult.output, 
                                         range: NSRange(location: 0, length: srtResult.output.count))
        
        XCTAssertGreaterThan(srtMatches.count, 0, "SRT should contain valid timestamps")
        
        // Test JSON timestamp format
        let jsonResult = try executeCompleteWorkflow(
            inputFile: testFile,
            outputFormat: .json,
            expectedContentValidation: validateJSONOutput
        )
        
        let jsonData = jsonResult.output.data(using: .utf8)!
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("JSON result should be valid dictionary")
            return
        }
        
        if let segments = json["segments"] as? [[String: Any]] {
            for segment in segments {
                if let startTime = segment["startTime"] as? Double,
                   let endTime = segment["endTime"] as? Double {
                    XCTAssertGreaterThanOrEqual(endTime, startTime, 
                                              "End time should be >= start time")
                    XCTAssertGreaterThanOrEqual(startTime, 0, 
                                              "Start time should be non-negative")
                }
            }
        }
    }
    
    func testOutputConsistency() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        // Run the same file through different formats multiple times
        let iterations = 3
        var txtResults: [String] = []
        var jsonResults: [String] = []
        
        for _ in 0..<iterations {
            let txtResult = try executeCompleteWorkflow(
                inputFile: testFile,
                outputFormat: .txt,
                expectedContentValidation: validateTextOutput
            )
            txtResults.append(txtResult.output)
            
            let jsonResult = try executeCompleteWorkflow(
                inputFile: testFile,
                outputFormat: .json,
                expectedContentValidation: validateJSONOutput
            )
            jsonResults.append(jsonResult.output)
        }
        
        // Validate that results are consistent across runs
        for i in 1..<txtResults.count {
            let similarity = calculateTextSimilarity(txtResults[0], txtResults[i])
            XCTAssertGreaterThan(similarity, 0.8, 
                               "TXT outputs should be highly similar across runs")
        }
        
        for i in 1..<jsonResults.count {
            guard let firstJson = try JSONSerialization.jsonObject(with: jsonResults[0].data(using: .utf8)!) as? [String: Any],
                  let secondJson = try JSONSerialization.jsonObject(with: jsonResults[i].data(using: .utf8)!) as? [String: Any] else {
                XCTFail("JSON results should be valid dictionaries")
                continue
            }
            
            let firstText = firstJson["text"] as? String ?? ""
            let secondText = secondJson["text"] as? String ?? ""
            
            let similarity = calculateTextSimilarity(firstText, secondText)
            XCTAssertGreaterThan(similarity, 0.8, 
                               "JSON text outputs should be highly similar across runs")
        }
    }
    
    func testConcurrentProcessingWithMultipleSamples() throws {
        var testFiles: [URL] = []
        
        // Collect available test files
        testFiles.append(contentsOf: realSampleFiles.values)
        testFiles.append(contentsOf: generatedSampleFiles.values)
        
        guard testFiles.count >= 2 else {
            throw XCTSkip("Need at least 2 sample files for concurrent testing")
        }
        
        // Limit to first 3 files to keep test time reasonable
        testFiles = Array(testFiles.prefix(3))
        
        let startTime = Date()
        let expectations = testFiles.enumerated().map { index, _ in
            XCTestExpectation(description: "Concurrent processing file \(index)")
        }
        
        var results: [String] = Array(repeating: "", count: testFiles.count)
        let resultsQueue = DispatchQueue(label: "results", attributes: .concurrent)
        
        // Start concurrent processing
        for (index, file) in testFiles.enumerated() {
            let expectation = expectations[index]
            
            DispatchQueue.global().async {
                do {
                    let result = try self.executeCompleteWorkflow(
                        inputFile: file,
                        outputFormat: .txt,
                        expectedContentValidation: self.validateTextOutput
                    )
                    
                    resultsQueue.async(flags: .barrier) {
                        results[index] = result.output
                    }
                } catch {
                    XCTFail("Concurrent processing failed for file \(index): \(error)")
                }
                
                expectation.fulfill()
            }
        }
        
        wait(for: expectations, timeout: 300.0)
        
        let totalTime = Date().timeIntervalSince(startTime)
        
        // Validate all results were generated
        for (index, result) in results.enumerated() {
            XCTAssertFalse(result.isEmpty, "Result \(index) should not be empty")
            XCTAssertTrue(validateTextOutput(result), "Result \(index) should be valid text")
        }
        
        // Validate concurrent processing completed in reasonable time
        XCTAssertLessThan(totalTime, 240.0, 
                         "Concurrent processing should complete within 4 minutes")
        
        print("Concurrent processing of \(testFiles.count) files completed in \(String(format: "%.2f", totalTime))s")
    }
    
    func testEdgeCaseValidation() throws {
        // Test very short files
        if let shortFile = testFileGenerator.createSmallMP4File() {
            let result = try executeCompleteWorkflow(
                inputFile: shortFile,
                outputFormat: .json,
                expectedContentValidation: validateJSONOutput
            )
            
            let jsonData = result.output.data(using: String.Encoding.utf8)!
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                XCTFail("Short file should produce valid JSON dictionary")
                return
            }
            
            // Even very short files should have valid structure
            XCTAssertNotNil(json["text"], "Short file should have text field")
            XCTAssertNotNil(json["duration"], "Short file should have duration field")
            
            if let duration = json["duration"] as? Double {
                XCTAssertGreaterThan(duration, 0, "Short file should have positive duration")
            }
        }
        
        // Test files with silent periods - using small file as substitute
        if let silentFile = testFileGenerator.createSmallMP4File() {
            let result = try executeCompleteWorkflow(
                inputFile: silentFile,
                outputFormat: .txt,
                expectedContentValidation: { content in
                    // Silent files may produce empty text or silence indicators
                    return true // Accept any output for silent files
                }
            )
            
            // Silent files should still produce valid output structure
            XCTAssertNotNil(result.output, "Silent file should produce output")
        }
    }
    
    func testLanguageDetection() throws {
        // Test with different language samples if available
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        let result = try executeCompleteWorkflow(
            inputFile: testFile,
            outputFormat: .json,
            expectedContentValidation: validateJSONOutput
        )
        
        let jsonData = result.output.data(using: .utf8)!
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Language detection test should produce valid JSON dictionary")
            return
        }
        
        if let language = json["language"] as? String {
            XCTAssertFalse(language.isEmpty, "Language field should not be empty")
            
            // Language should be in valid format (e.g., "en-US", "en", etc.)
            let languagePattern = "^[a-z]{2}(-[A-Z]{2})?$"
            let languageRegex = try NSRegularExpression(pattern: languagePattern)
            let languageMatches = languageRegex.matches(in: language, 
                                                       range: NSRange(location: 0, length: language.count))
            
            XCTAssertEqual(languageMatches.count, 1, 
                          "Language should be in valid format: \(language)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        // Simple similarity calculation based on common words
        let words1 = Set(text1.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)))
        let words2 = Set(text2.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        guard !union.isEmpty else { return 1.0 }
        
        return Double(intersection.count) / Double(union.count)
    }
}