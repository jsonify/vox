import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Integration tests using real-world sample files to validate complete workflow functionality
/// with actual MP4 files containing audio and video content.
final class RealWorldSampleTests: XCTestCase {
    // MARK: - Test Infrastructure
    
    private var tempDirectory: URL!
    private var testBundle: Bundle!
    private var testSampleFile: URL!
    private var testSampleSmallFile: URL!
    
    override func setUp() {
        super.setUp()
        
        // Set up test infrastructure
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("realworld_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
        
        // Get test bundle and sample files
        testBundle = Bundle(for: type(of: self))
        setUpSampleFiles()
    }
    
    override func tearDown() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        tempDirectory = nil
        testBundle = nil
        testSampleFile = nil
        testSampleSmallFile = nil
        
        super.tearDown()
    }
    
    private func setUpSampleFiles() {
        // Locate the real sample files in the test bundle
        testSampleFile = testBundle.url(forResource: "test_sample", withExtension: "mp4")
        testSampleSmallFile = testBundle.url(forResource: "test_sample_small", withExtension: "mp4")
        
        // Validate that the sample files exist
        XCTAssertNotNil(testSampleFile, "test_sample.mp4 should exist in test resources")
        XCTAssertNotNil(testSampleSmallFile, "test_sample_small.mp4 should exist in test resources")
        
        if let sampleFile = testSampleFile {
            XCTAssertTrue(FileManager.default.fileExists(atPath: sampleFile.path), 
                "test_sample.mp4 should exist at path")
        }
        
        if let smallFile = testSampleSmallFile {
            XCTAssertTrue(FileManager.default.fileExists(atPath: smallFile.path), 
                "test_sample_small.mp4 should exist at path")
        }
    }
    
    // MARK: - Complete Workflow Tests with Real Files
    
    func testCompleteWorkflowWithSmallSampleFile() throws {
        guard let inputFile = testSampleSmallFile else {
            throw XCTSkip("test_sample_small.mp4 not available")
        }
        
        try validateSampleFile(inputFile)
        
        let outputFile = tempDirectory.appendingPathComponent("small_sample_output.txt")
        let expectation = XCTestExpectation(description: "Complete workflow - small sample")
        
        executeCompleteWorkflow(
            inputFile: inputFile,
            outputFile: outputFile,
            format: .txt,
            includeTimestamps: false,
            expectation: expectation
        )
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    func testCompleteWorkflowWithLargeSampleFile() throws {
        guard let inputFile = testSampleFile else {
            throw XCTSkip("test_sample.mp4 not available")
        }
        
        try validateSampleFile(inputFile)
        
        let outputFile = tempDirectory.appendingPathComponent("large_sample_output.txt")
        let expectation = XCTestExpectation(description: "Complete workflow - large sample")
        
        executeCompleteWorkflow(
            inputFile: inputFile,
            outputFile: outputFile,
            format: .txt,
            includeTimestamps: false,
            expectation: expectation
        )
        
        wait(for: [expectation], timeout: 120.0)
    }
    
    func testAllOutputFormatsWithRealFiles() throws {
        guard let inputFile = testSampleSmallFile else {
            throw XCTSkip("test_sample_small.mp4 not available")
        }
        
        let formats: [OutputFormat] = [.txt, .srt, .json]
        let expectation = XCTestExpectation(description: "All formats with real file")
        var completedFormats = 0
        
        for format in formats {
            let outputFile = tempDirectory.appendingPathComponent("sample_output.\(format.rawValue)")
            
            let formatExpectation = XCTestExpectation(description: "Format \(format.rawValue)")
            
            executeCompleteWorkflow(
                inputFile: inputFile,
                outputFile: outputFile,
                format: format,
                includeTimestamps: format != .txt,
                expectation: formatExpectation
            )
            
            // Wait for each format individually
            wait(for: [formatExpectation], timeout: 60.0)
            
            completedFormats += 1
            if completedFormats == formats.count {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Audio Processing Tests with Real Files
    
    func testAudioExtractionFromRealFiles() throws {
        guard let smallFile = testSampleSmallFile,
              let largeFile = testSampleFile else {
            throw XCTSkip("Sample files not available")
        }
        
        let testFiles = [
            ("small", smallFile),
            ("large", largeFile)
        ]
        
        for (name, file) in testFiles {
            let expectation = XCTestExpectation(description: "Audio extraction - \(name)")
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: file.path) { result in
                switch result {
                case .success(let audioFile):
                    // Validate extracted audio properties
                    XCTAssertGreaterThan(audioFile.format.duration, 0, 
                        "Audio duration should be positive for \(name)")
                    XCTAssertGreaterThan(audioFile.format.sampleRate, 0, 
                        "Sample rate should be positive for \(name)")
                    XCTAssertGreaterThan(audioFile.format.channels, 0, 
                        "Channels should be positive for \(name)")
                    XCTAssertTrue(audioFile.format.isValid, 
                        "Audio format should be valid for \(name)")
                    
                    // Validate temporary file was created
                    if let tempPath = audioFile.temporaryPath {
                        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), 
                            "Temporary audio file should exist for \(name)")
                    }
                    
                case .failure(let error):
                    XCTFail("Audio extraction failed for \(name): \(error)")
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 60.0)
        }
    }
    
    // MARK: - Performance Tests with Real Files
    
    func testPerformanceWithRealSmallFile() throws {
        guard let inputFile = testSampleSmallFile else {
            throw XCTSkip("test_sample_small.mp4 not available")
        }
        
        let expectation = XCTestExpectation(description: "Performance with real small file")
        let startTime = Date()
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: inputFile.path) { result in
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let audioFile):
                // Small real files should process quickly
                XCTAssertLessThan(processingTime, 15.0, 
                    "Small real file should process within 15 seconds")
                
                // Validate audio properties
                XCTAssertGreaterThan(audioFile.format.duration, 0, 
                    "Audio should have valid duration")
                
                // Calculate processing efficiency
                let efficiency = audioFile.format.duration / processingTime
                XCTAssertGreaterThan(efficiency, 0.1, 
                    "Processing should be reasonably efficient")
                
            case .failure(let error):
                XCTFail("Processing failed: \(error)")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testPerformanceWithRealLargeFile() throws {
        guard let inputFile = testSampleFile else {
            throw XCTSkip("test_sample.mp4 not available")
        }
        
        let expectation = XCTestExpectation(description: "Performance with real large file")
        let startTime = Date()
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: inputFile.path) { result in
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let audioFile):
                // Large real files should meet performance targets
                XCTAssertLessThan(processingTime, 45.0, 
                    "Large real file should process within 45 seconds")
                
                // Validate audio properties
                XCTAssertGreaterThan(audioFile.format.duration, 0, 
                    "Audio should have valid duration")
                
                // Calculate processing efficiency
                let efficiency = audioFile.format.duration / processingTime
                XCTAssertGreaterThan(efficiency, 0.2, 
                    "Processing should be reasonably efficient")
                
            case .failure(let error):
                XCTFail("Processing failed: \(error)")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Output Format Validation with Real Files
    
    func testTXTOutputWithRealFile() throws {
        guard let inputFile = testSampleSmallFile else {
            throw XCTSkip("test_sample_small.mp4 not available")
        }
        
        let outputFile = tempDirectory.appendingPathComponent("real_output.txt")
        let expectation = XCTestExpectation(description: "TXT output with real file")
        
        executeCompleteWorkflow(
            inputFile: inputFile,
            outputFile: outputFile,
            format: .txt,
            includeTimestamps: false,
            expectation: expectation
        )
        
        wait(for: [expectation], timeout: 60.0)
        
        // Validate output file
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
            "TXT output file should exist")
        
        do {
            let content = try String(contentsOf: outputFile)
            XCTAssertFalse(content.isEmpty, "TXT output should not be empty")
            XCTAssertFalse(content.contains("-->"), "TXT output should not contain SRT timestamps")
            XCTAssertFalse(content.contains("{"), "TXT output should not contain JSON formatting")
        } catch {
            XCTFail("Failed to read TXT output: \(error)")
        }
    }
    
    func testSRTOutputWithRealFile() throws {
        guard let inputFile = testSampleSmallFile else {
            throw XCTSkip("test_sample_small.mp4 not available")
        }
        
        let outputFile = tempDirectory.appendingPathComponent("real_output.srt")
        let expectation = XCTestExpectation(description: "SRT output with real file")
        
        executeCompleteWorkflow(
            inputFile: inputFile,
            outputFile: outputFile,
            format: .srt,
            includeTimestamps: true,
            expectation: expectation
        )
        
        wait(for: [expectation], timeout: 60.0)
        
        // Validate output file
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
            "SRT output file should exist")
        
        do {
            let content = try String(contentsOf: outputFile)
            XCTAssertFalse(content.isEmpty, "SRT output should not be empty")
            XCTAssertTrue(content.contains("-->"), "SRT output should contain time indicators")
            XCTAssertTrue(content.contains("1"), "SRT output should contain sequence numbers")
        } catch {
            XCTFail("Failed to read SRT output: \(error)")
        }
    }
    
    func testJSONOutputWithRealFile() throws {
        guard let inputFile = testSampleSmallFile else {
            throw XCTSkip("test_sample_small.mp4 not available")
        }
        
        let outputFile = tempDirectory.appendingPathComponent("real_output.json")
        let expectation = XCTestExpectation(description: "JSON output with real file")
        
        executeCompleteWorkflow(
            inputFile: inputFile,
            outputFile: outputFile,
            format: .json,
            includeTimestamps: true,
            expectation: expectation
        )
        
        wait(for: [expectation], timeout: 60.0)
        
        // Validate output file
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
            "JSON output file should exist")
        
        do {
            let content = try String(contentsOf: outputFile)
            XCTAssertFalse(content.isEmpty, "JSON output should not be empty")
            XCTAssertTrue(content.contains("\"transcription\""), "JSON should contain transcription field")
            XCTAssertTrue(content.contains("\"metadata\""), "JSON should contain metadata field")
            
            // Validate JSON structure
            let jsonData = content.data(using: .utf8)!
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            XCTAssertNotNil(jsonObject, "JSON should be valid")
        } catch {
            XCTFail("Failed to read or parse JSON output: \(error)")
        }
    }
    
    // MARK: - Error Handling Tests with Real Files
    
    func testRobustnessWithRealFiles() throws {
        guard let smallFile = testSampleSmallFile,
              let largeFile = testSampleFile else {
            throw XCTSkip("Sample files not available")
        }
        
        let testFiles = [smallFile, largeFile]
        
        for (index, file) in testFiles.enumerated() {
            let expectation = XCTestExpectation(description: "Robustness test \(index)")
            let outputFile = tempDirectory.appendingPathComponent("robust_output_\(index).txt")
            
            // Test with various configurations
            // Note: In integration tests, we test individual components
            // rather than the full CLI command structure
            
            // Execute workflow with error handling
            executeCompleteWorkflow(
                inputFile: file,
                outputFile: outputFile,
                format: .txt,
                includeTimestamps: false,
                expectation: expectation
            )
            
            wait(for: [expectation], timeout: 60.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func executeCompleteWorkflow(
        inputFile: URL,
        outputFile: URL,
        format: OutputFormat,
        includeTimestamps: Bool,
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
                    expectation: expectation
                )
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                expectation.fulfill()
            }
        }
    }
    
    private func handleTranscriptionStep(
        audioFile: AudioFile,
        outputFile: URL,
        format: OutputFormat,
        includeTimestamps: Bool,
        expectation: XCTestExpectation
    ) {
        // Step 2: Transcription (using mock for now since native may not be available)
        let mockResult = createMockTranscriptionResult(for: audioFile)
        
        // Step 3: Output Processing
        handleOutputStep(
            result: mockResult,
            outputFile: outputFile,
            format: format,
            expectation: expectation
        )
    }
    
    private func handleOutputStep(
        result: TranscriptionResult,
        outputFile: URL,
        format: OutputFormat,
        expectation: XCTestExpectation
    ) {
        let outputFormatter = OutputFormatter()
        let outputWriter = OutputWriter()
        
        do {
            let formattedOutput = try outputFormatter.format(result, as: format)
            
            // Validate formatted output
            XCTAssertFalse(formattedOutput.isEmpty, "Formatted output should not be empty")
            
            // Write output file
            try outputWriter.writeContentSafely(formattedOutput, to: outputFile.path)
            
            // Verify file was created
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
                "Output file should exist")
            
            let writtenContent = try String(contentsOf: outputFile)
            XCTAssertEqual(writtenContent, formattedOutput, 
                "Written content should match formatted output")
        } catch {
            XCTFail("Output processing failed: \(error)")
        }
        
        expectation.fulfill()
    }
    
    private func validateSampleFile(_ file: URL) throws {
        // Validate file exists and is not empty
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), 
            "Sample file should exist")
        
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Sample file should not be empty")
        
        // Validate file is a valid MP4 using AVAsset
        let asset = AVAsset(url: file)
        let duration = asset.duration
        XCTAssertGreaterThan(duration.seconds, 0, "Sample file should have valid duration")
        
        // Check for audio tracks
        let audioTracks = asset.tracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty, "Sample file should have audio tracks")
    }
    
    private func createMockTranscriptionResult(for audioFile: AudioFile) -> TranscriptionResult {
        let segments = [
            TranscriptionSegment(
                text: "This is a real world test sample",
                startTime: 0.0,
                endTime: audioFile.format.duration / 2,
                confidence: 0.90,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            ),
            TranscriptionSegment(
                text: "Testing transcription with actual MP4 file",
                startTime: audioFile.format.duration / 2,
                endTime: audioFile.format.duration,
                confidence: 0.88,
                speakerID: "Speaker1",
                words: nil,
                segmentType: .speech,
                pauseDuration: 0.2
            )
        ]
        
        return TranscriptionResult(
            text: "This is a real world test sample Testing transcription with actual MP4 file",
            language: "en-US",
            confidence: 0.89,
            duration: audioFile.format.duration,
            segments: segments,
            engine: .speechAnalyzer,
            processingTime: 2.0,
            audioFormat: audioFile.format
        )
    }
}
