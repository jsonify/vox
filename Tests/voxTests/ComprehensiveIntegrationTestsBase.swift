import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Base class for comprehensive integration tests that provides shared infrastructure
/// and helper methods for testing the complete Vox workflow.
class ComprehensiveIntegrationTestsBase: XCTestCase {
    // MARK: - Test Infrastructure
    
    var testFileGenerator: TestAudioFileGenerator!
    var tempDirectory: URL!
    var testBundle: Bundle!
    var realSampleFiles: [String: URL] = [:]
    var generatedSampleFiles: [String: URL] = [:]
    
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
    
    // MARK: - Helper Methods
    
    func executeCompleteWorkflow(
        inputFile: URL,
        outputFormat: OutputFormat,
        expectedContentValidation: ((String) -> Bool)? = nil
    ) throws -> (output: String, processingTime: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create CLI command
        var voxCommand = Vox()
        voxCommand.inputFile = inputFile.path
        voxCommand.format = outputFormat
        voxCommand.verbose = true
        
        // Create output file
        let outputFile = tempDirectory.appendingPathComponent("test_output.\(outputFormat.rawValue)")
        voxCommand.output = outputFile.path
        
        // Execute the workflow
        try voxCommand.run()
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Validate output file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path), 
                     "Output file should exist at \(outputFile.path)")
        
        // Read and validate output content
        let outputContent = try String(contentsOf: outputFile)
        XCTAssertFalse(outputContent.isEmpty, "Output content should not be empty")
        
        // Optional content validation
        if let validator = expectedContentValidation {
            XCTAssertTrue(validator(outputContent), "Output content failed validation")
        }
        
        return (outputContent, processingTime)
    }
    
    func validateJSONOutput(_ content: String) -> Bool {
        guard let data = content.data(using: .utf8) else { return false }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = json as? [String: Any] else { return false }
            
            // Validate required JSON fields
            return dict["text"] != nil &&
                   dict["language"] != nil &&
                   dict["confidence"] != nil &&
                   dict["duration"] != nil &&
                   dict["segments"] != nil
        } catch {
            return false
        }
    }
    
    func validateSRTOutput(_ content: String) -> Bool {
        // Basic SRT validation: should contain timestamp patterns
        let srtPattern = "\\d{2}:\\d{2}:\\d{2},\\d{3} --> \\d{2}:\\d{2}:\\d{2},\\d{3}"
        return content.range(of: srtPattern, options: .regularExpression) != nil
    }
    
    func validateTextOutput(_ content: String) -> Bool {
        // Text output should contain actual words and not just whitespace
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func createMockTranscriptionResult(for audioFile: TestAudioFile) -> TranscriptionResult {
        let words = ["Hello", "world", "this", "is", "a", "test", "transcription", "sample"]
        let segments = words.enumerated().map { index, word in
            TranscriptionSegment(
                text: word,
                startTime: TimeInterval(index) * 0.5,
                endTime: TimeInterval(index + 1) * 0.5,
                confidence: 0.9 + Double.random(in: -0.1...0.1),
                speakerID: "speaker_1"
            )
        }
        
        let fullText = words.joined(separator: " ")
        
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