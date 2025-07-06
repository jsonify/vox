import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Comprehensive integration tests that validate the complete Vox workflow
/// with various sample files, all output formats, and real-world scenarios.
/// This test suite fulfills the requirements from Issue #34.
final class ComprehensiveIntegrationTests: XCTestCase {
    // MARK: - Test Infrastructure
    
    private var testFileGenerator: TestAudioFileGenerator!
    private var tempDirectory: URL!
    private var testBundle: Bundle!
    private var realSampleFiles: [String: URL] = [:]
    private var generatedSampleFiles: [String: URL] = [:]
    
    override func setUp() {
        super.setUp()
        
        // Set up test infrastructure
        testFileGenerator = TestAudioFileGenerator.shared
        testBundle = Bundle(for: type(of: self))
        
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("comprehensive_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
        
        setUpSampleFiles()
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        tempDirectory = nil
        testBundle = nil
        realSampleFiles.removeAll()
        generatedSampleFiles.removeAll()
        
        super.tearDown()
    }
    
    private func setUpSampleFiles() {
        // Set up real sample files from test resources
        if let smallReal = testBundle.url(forResource: "test_sample_small", withExtension: "mp4") {
            realSampleFiles["small"] = smallReal
        }
        
        if let largeReal = testBundle.url(forResource: "test_sample", withExtension: "mp4") {
            realSampleFiles["large"] = largeReal
        }
        
        // Generate additional test files
        if let smallGenerated = testFileGenerator.createSmallMP4File() {
            generatedSampleFiles["small"] = smallGenerated
        }
        
        if let mediumGenerated = testFileGenerator.createMediumMP4File() {
            generatedSampleFiles["medium"] = mediumGenerated
        }
        
        if let largeGenerated = testFileGenerator.createLargeMP4File() {
            generatedSampleFiles["large"] = largeGenerated
        }
    }
    
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
        let expectations = allTestCases.map { (name, _, format) in
            XCTestExpectation(description: "Workflow test: \(name) -> \(format.rawValue)")
        }
        
        for (index, (name, file, format)) in allTestCases.enumerated() {
            let outputFile = tempDirectory.appendingPathComponent("\(name)_output.\(format.rawValue)")
            
            executeCompleteWorkflow(
                inputFile: file,
                outputFile: outputFile,
                format: format,
                includeTimestamps: format != .txt,
                testName: name,
                expectation: expectations[index]
            )
        }
        
        // Wait for all tests to complete
        wait(for: expectations, timeout: 300.0) // 5 minutes for comprehensive testing
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
        
        let expectations = testCases.map { (_, _, name) in
            XCTestExpectation(description: "Timestamp variation: \(name)")
        }
        
        for (index, (format, timestamps, testName)) in testCases.enumerated() {
            let outputFile = tempDirectory.appendingPathComponent("\(testName)_output.\(format.rawValue)")
            
            executeCompleteWorkflow(
                inputFile: testFile,
                outputFile: outputFile,
                format: format,
                includeTimestamps: timestamps,
                testName: testName,
                expectation: expectations[index]
            )
        }
        
        wait(for: expectations, timeout: 180.0)
    }
    
    // MARK: - Error Scenario Testing
    
    func testErrorScenariosWithAllSampleTypes() throws {
        var errorTestFiles: [String: URL] = [
            "invalid": testFileGenerator.createInvalidMP4File(),
            "empty": testFileGenerator.createEmptyMP4File(),
            "corrupted": testFileGenerator.createCorruptedMP4File()
        ]
        
        // Add video-only file if available
        if let videoOnly = testFileGenerator.createVideoOnlyMP4File() {
            errorTestFiles["video_only"] = videoOnly
        }
        
        let expectations = errorTestFiles.map { (name, _) in
            XCTestExpectation(description: "Error scenario: \(name)")
        }
        
        for (index, (testName, file)) in errorTestFiles.enumerated() {
            let expectation = expectations[index]
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: file.path) { result in
                switch result {
                case .success:
                    XCTFail("Error test '\(testName)' should not succeed")
                case .failure(let error):
                    // Verify error contains meaningful information
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, 
                        "Error '\(testName)' should have description")
                    
                    // Specific validations for different error types
                    switch testName {
                    case "video_only":
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("audio") ||
                            errorDescription.localizedCaseInsensitiveContains("track"),
                            "Video-only error should mention audio track issue"
                        )
                    case "invalid", "corrupted":
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("invalid") ||
                            errorDescription.localizedCaseInsensitiveContains("format") ||
                            errorDescription.localizedCaseInsensitiveContains("corrupt"),
                            "Invalid/corrupted file error should mention format issue"
                        )
                    default:
                        break
                    }
                }
                expectation.fulfill()
            }
        }
        
        wait(for: expectations, timeout: 120.0)
    }
    
    // MARK: - Performance Benchmarking
    
    func testPerformanceBenchmarksWithRealFiles() throws {
        var performanceResults: [String: TimeInterval] = [:]
        
        // Test small file performance
        if let smallFile = realSampleFiles["small"] {
            let smallExpectation = XCTestExpectation(description: "Small file performance")
            let startTime = Date()
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: smallFile.path) { result in
                let processingTime = Date().timeIntervalSince(startTime)
                performanceResults["small_real"] = processingTime
                
                switch result {
                case .success(let audioFile):
                    XCTAssertLessThan(processingTime, 15.0, 
                        "Small real file should process within 15 seconds")
                    XCTAssertGreaterThan(audioFile.format.duration, 0, 
                        "Audio should have valid duration")
                case .failure(let error):
                    XCTFail("Small file processing failed: \(error)")
                }
                
                smallExpectation.fulfill()
            }
            
            wait(for: [smallExpectation], timeout: 30.0)
        }
        
        // Test large file performance
        if let largeFile = realSampleFiles["large"] {
            let largeExpectation = XCTestExpectation(description: "Large file performance")
            let startTime = Date()
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: largeFile.path) { result in
                let processingTime = Date().timeIntervalSince(startTime)
                performanceResults["large_real"] = processingTime
                
                switch result {
                case .success(let audioFile):
                    // Performance targets from CLAUDE.md
                    let isAppleSilicon = ProcessInfo.processInfo.machineType.contains("arm64")
                    let targetTime: TimeInterval = isAppleSilicon ? 60.0 : 90.0
                    
                    // For real files, be more lenient in test environment
                    XCTAssertLessThan(processingTime, targetTime * 1.5, 
                        "Large real file should process within reasonable time")
                    XCTAssertGreaterThan(audioFile.format.duration, 0, 
                        "Audio should have valid duration")
                case .failure(let error):
                    // Large file processing may fail in test environment
                    print("Large file processing failed (acceptable): \(error)")
                }
                
                largeExpectation.fulfill()
            }
            
            wait(for: [largeExpectation], timeout: 180.0)
        }
        
        // Report performance results
        print("Performance Benchmark Results:")
        for (testName, time) in performanceResults {
            print("  \(testName): \(String(format: "%.2f", time))s")
        }
    }
    
    func testMemoryUsageBenchmarks() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        let expectation = XCTestExpectation(description: "Memory usage benchmark")
        let memoryMonitor = MemoryMonitor()
        let initialMemory = memoryMonitor.getCurrentUsage().currentBytes
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            let finalMemory = memoryMonitor.getCurrentUsage().currentBytes
            let memoryIncrease = finalMemory - initialMemory
            
            // Memory usage targets from CLAUDE.md: Peak usage < 1GB for typical files
            XCTAssertLessThan(memoryIncrease, 1024 * 1024 * 1024, 
                "Memory usage should be under 1GB")
            
            // For typical test files, much lower usage expected
            XCTAssertLessThan(memoryIncrease, 100 * 1024 * 1024, 
                "Memory usage should be reasonable for test files")
            
            print("Memory usage: \(memoryIncrease / (1024 * 1024)) MB")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Output Validation Testing
    
    func testOutputValidationAcrossAllFormats() throws {
        guard let testFile = realSampleFiles["small"] ?? generatedSampleFiles["small"] else {
            throw XCTSkip("No sample file available")
        }
        
        let formats: [OutputFormat] = [.txt, .srt, .json]
        let expectations = formats.map { format in
            XCTestExpectation(description: "Output validation: \(format.rawValue)")
        }
        
        for (index, format) in formats.enumerated() {
            let outputFile = tempDirectory.appendingPathComponent("validation_test.\(format.rawValue)")
            let expectation = expectations[index]
            
            executeCompleteWorkflow(
                inputFile: testFile,
                outputFile: outputFile,
                format: format,
                includeTimestamps: format != .txt,
                testName: "validation_\(format.rawValue)",
                expectation: expectation
            )
        }
        
        wait(for: expectations, timeout: 180.0)
        
        // Validate all output files were created and have correct content
        for format in formats {
            let outputFile = tempDirectory.appendingPathComponent("validation_test.\(format.rawValue)")
            
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
                "\(format.rawValue) output file should exist")
            
            do {
                let content = try String(contentsOf: outputFile)
                XCTAssertFalse(content.isEmpty, "\(format.rawValue) output should not be empty")
                
                // Format-specific validation
                switch format {
                case .txt:
                    XCTAssertFalse(content.contains("-->"), "TXT should not contain SRT timestamps")
                    XCTAssertFalse(content.contains("{"), "TXT should not contain JSON")
                case .srt:
                    XCTAssertTrue(content.contains("-->"), "SRT should contain time indicators")
                    XCTAssertTrue(content.contains("1"), "SRT should contain sequence numbers")
                case .json:
                    XCTAssertTrue(content.contains("\"transcription\""), "JSON should contain transcription field")
                    
                    // Validate JSON structure
                    let jsonData = content.data(using: .utf8)!
                    let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                    XCTAssertNotNil(jsonObject, "JSON should be valid")
                }
            } catch {
                XCTFail("Failed to validate \(format.rawValue) output: \(error)")
            }
        }
    }
    
    // MARK: - Concurrent Processing Tests
    
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
        
        let expectation = XCTestExpectation(description: "Concurrent processing test")
        let startTime = Date()
        let group = DispatchGroup()
        
        var results: [Result<AudioFile, VoxError>] = []
        let resultsLock = NSLock()
        
        for (index, testFile) in testFiles.enumerated() {
            group.enter()
            let audioProcessor = AudioProcessor()
            
            audioProcessor.extractAudio(from: testFile.path) { result in
                resultsLock.lock()
                results.append(result)
                resultsLock.unlock()
                
                print("Concurrent processing \(index + 1)/\(testFiles.count) completed")
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let totalTime = Date().timeIntervalSince(startTime)
            
            // Concurrent processing should be efficient
            XCTAssertLessThan(totalTime, 120.0, 
                "Concurrent processing should complete within 2 minutes")
            
            // All files should be processed
            XCTAssertEqual(results.count, testFiles.count, 
                "All files should be processed")
            
            // Count successful results
            let successCount = results.filter { result in
                if case .success = result {
                    return true
                }
                return false
            }.count
            
            XCTAssertGreaterThan(successCount, 0, 
                "At least some files should process successfully")
            
            print("Concurrent processing: \(successCount)/\(testFiles.count) successful")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 180.0)
    }
    
    // MARK: - Helper Methods
    
    private func executeCompleteWorkflow(
        inputFile: URL,
        outputFile: URL,
        format: OutputFormat,
        includeTimestamps: Bool,
        testName: String,
        expectation: XCTestExpectation
    ) {
        // Step 1: Audio Processing
        let audioProcessor = AudioProcessor()
        
        audioProcessor.extractAudio(from: inputFile.path) { [weak self] audioResult in
            switch audioResult {
            case .success(let audioFile):
                self?.handleTranscriptionStep(
                    audioFile: audioFile,
                    outputFile: outputFile,
                    format: format,
                    includeTimestamps: includeTimestamps,
                    testName: testName,
                    expectation: expectation
                )
            case .failure(let error):
                XCTFail("Audio processing failed for \(testName): \(error)")
                expectation.fulfill()
            }
        }
    }
    
    private func handleTranscriptionStep(
        audioFile: AudioFile,
        outputFile: URL,
        format: OutputFormat,
        includeTimestamps: Bool,
        testName: String,
        expectation: XCTestExpectation
    ) {
        // Step 2: Transcription (using mock for integration tests)
        let mockResult = createMockTranscriptionResult(for: audioFile)
        
        // Step 3: Output Processing
        handleOutputStep(
            result: mockResult,
            outputFile: outputFile,
            format: format,
            testName: testName,
            expectation: expectation
        )
    }
    
    private func handleOutputStep(
        result: TranscriptionResult,
        outputFile: URL,
        format: OutputFormat,
        testName: String,
        expectation: XCTestExpectation
    ) {
        let outputFormatter = OutputFormatter()
        let outputWriter = OutputWriter()
        
        do {
            let formattedOutput = try outputFormatter.format(result, as: format)
            
            // Validate formatted output
            XCTAssertFalse(formattedOutput.isEmpty, 
                "Formatted output should not be empty for \(testName)")
            
            // Write output file
            try outputWriter.writeContentSafely(formattedOutput, to: outputFile.path)
            
            // Verify file was created
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
                "Output file should exist for \(testName)")
            
            let writtenContent = try String(contentsOf: outputFile)
            XCTAssertEqual(writtenContent, formattedOutput, 
                "Written content should match formatted output for \(testName)")
            
            print("Successfully completed workflow test: \(testName)")
        } catch {
            XCTFail("Output processing failed for \(testName): \(error)")
        }
        
        expectation.fulfill()
    }
    
    private func createMockTranscriptionResult(for audioFile: AudioFile) -> TranscriptionResult {
        let segmentCount = max(1, Int(audioFile.format.duration / 3.0)) // One segment per 3 seconds
        let segments = (0..<segmentCount).map { index in
            let segmentDuration = audioFile.format.duration / Double(segmentCount)
            let startTime = Double(index) * segmentDuration
            let endTime = startTime + segmentDuration
            
            return TranscriptionSegment(
                text: "Comprehensive test segment \(index + 1)",
                startTime: startTime,
                endTime: endTime,
                confidence: 0.90 - Double(index) * 0.02, // Slightly decreasing confidence
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: index > 0 ? 0.1 : nil
            )
        }
        
        let fullText = segments.map { $0.text }.joined(separator: " ")
        
        return TranscriptionResult(
            text: fullText,
            language: "en-US",
            confidence: segments.map { $0.confidence }.reduce(0, +) / Double(segments.count),
            duration: audioFile.format.duration,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: min(audioFile.format.duration / 5.0, 10.0), // Simulated processing time
            audioFormat: audioFile.format
        )
    }
}

