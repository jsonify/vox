import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Tests to validate that all sample files (real and generated) meet quality standards
/// and can be used reliably for integration testing.
final class SampleFileValidationTests: XCTestCase {
    // MARK: - Test Infrastructure
    
    private var testFileGenerator: TestAudioFileGenerator!
    private var testBundle: Bundle!
    
    override func setUp() {
        super.setUp()
        testFileGenerator = TestAudioFileGenerator.shared
        testBundle = Bundle(for: type(of: self))
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        testFileGenerator = nil
        testBundle = nil
        super.tearDown()
    }
    
    // MARK: - Real Sample File Validation
    
    func testRealSampleFilesExistAndAreValid() throws {
        let sampleFiles = [
            "test_sample.mp4",
            "test_sample_small.mp4"
        ]
        
        for fileName in sampleFiles {
            let fileNameWithoutExt = String(fileName.dropLast(4))
            
            guard let fileURL = testBundle.url(forResource: fileNameWithoutExt, withExtension: "mp4") else {
                XCTFail("Real sample file \(fileName) not found in test bundle")
                continue
            }
            
            // Test file existence and basic properties
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), 
                "Sample file \(fileName) should exist at path")
            
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            XCTAssertGreaterThan(fileSize, 1000, "Sample file \(fileName) should be larger than 1KB")
            
            // Test MP4 structure using AVFoundation
            try validateMP4Structure(fileURL, fileName: fileName)
            
            // Test audio content
            try validateAudioContent(fileURL, fileName: fileName)
            
            print("✅ Real sample file \(fileName) validation passed")
        }
    }
    
    func testRealSampleFileProperties() throws {
        let testCases: [(String, TimeInterval, TimeInterval)] = [
            ("test_sample_small.mp4", 2.0, 15.0),  // Expected range for small file
            ("test_sample.mp4", 10.0, 120.0)      // Expected range for large file
        ]
        
        for (fileName, minDuration, maxDuration) in testCases {
            let fileNameWithoutExt = String(fileName.dropLast(4))
            
            guard let fileURL = testBundle.url(forResource: fileNameWithoutExt, withExtension: "mp4") else {
                XCTFail("Sample file \(fileName) not found")
                continue
            }
            
            let asset = AVAsset(url: fileURL)
            let duration = asset.duration.seconds
            
            XCTAssertGreaterThan(duration, minDuration, 
                "\(fileName) duration should be greater than \(minDuration) seconds")
            XCTAssertLessThan(duration, maxDuration, 
                "\(fileName) duration should be less than \(maxDuration) seconds")
            
            // Check audio track properties
            let audioTracks = asset.tracks(withMediaType: .audio)
            XCTAssertFalse(audioTracks.isEmpty, "\(fileName) should have audio tracks")
            
            if let audioTrack = audioTracks.first {
                let sampleRate = audioTrack.naturalTimeScale
                XCTAssertGreaterThan(sampleRate, 0, "\(fileName) should have valid sample rate")
                
                // Check for reasonable audio track duration
                let audioTrackDuration = audioTrack.timeRange.duration.seconds
                XCTAssertEqual(audioTrackDuration, duration, accuracy: 0.1, 
                    "\(fileName) audio track duration should match asset duration")
            }
            
            print("✅ \(fileName) properties validation passed (duration: \(String(format: "%.2f", duration))s)")
        }
    }
    
    // MARK: - Generated Sample File Validation
    
    func testGeneratedSampleFileCreation() throws {
        let testCases: [(String, () -> URL?, TimeInterval)] = [
            ("Small", { self.testFileGenerator.createSmallMP4File() }, 3.0),
            ("Medium", { self.testFileGenerator.createMediumMP4File() }, 10.0),
            ("Large", { self.testFileGenerator.createLargeMP4File() }, 60.0)
        ]
        
        for (name, createFile, expectedDuration) in testCases {
            guard let fileURL = createFile() else {
                XCTFail("Failed to create \(name) test file")
                continue
            }
            
            // Validate file was created
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), 
                "\(name) test file should exist")
            
            // Validate file is not empty
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            XCTAssertGreaterThan(fileSize, 0, "\(name) test file should not be empty")
            
            // Validate MP4 structure
            try validateMP4Structure(fileURL, fileName: "\(name) generated file")
            
            // Validate duration is approximately correct
            let asset = AVAsset(url: fileURL)
            let actualDuration = asset.duration.seconds
            XCTAssertEqual(actualDuration, expectedDuration, accuracy: 1.0, 
                "\(name) file duration should be approximately \(expectedDuration) seconds")
            
            print("✅ Generated \(name) file validation passed (duration: \(String(format: "%.2f", actualDuration))s)")
        }
    }
    
    func testErrorTestFileGeneration() throws {
        let errorTestCases: [(String, () -> URL)] = [
            ("Invalid", { self.testFileGenerator.createInvalidMP4File() }),
            ("Empty", { self.testFileGenerator.createEmptyMP4File() }),
            ("Corrupted", { self.testFileGenerator.createCorruptedMP4File() })
        ]
        
        for (name, createFile) in errorTestCases {
            let fileURL = createFile()
            
            // Validate file was created
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), 
                "\(name) error test file should exist")
            
            // These files should be invalid MP4s (test that they fail validation)
            do {
                try validateMP4Structure(fileURL, fileName: "\(name) error file")
                XCTFail("\(name) error file should fail MP4 validation")
            } catch {
                // Expected to fail - this is correct behavior
                print("✅ \(name) error file correctly fails validation: \(error)")
            }
        }
    }
    
    func testVideoOnlyFileGeneration() throws {
        guard let videoOnlyFile = testFileGenerator.createVideoOnlyMP4File() else {
            XCTFail("Failed to create video-only test file")
            return
        }
        
        // Validate file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoOnlyFile.path), 
            "Video-only file should exist")
        
        // Validate it has video but no audio
        let asset = AVAsset(url: videoOnlyFile)
        
        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        
        XCTAssertFalse(videoTracks.isEmpty, "Video-only file should have video tracks")
        XCTAssertTrue(audioTracks.isEmpty, "Video-only file should not have audio tracks")
        
        print("✅ Video-only file validation passed")
    }
    
    // MARK: - Sample File Quality Assessment
    
    func testSampleFileAudioQuality() throws {
        var testFiles: [(String, URL)] = []
        
        // Add real sample files
        if let smallReal = testBundle.url(forResource: "test_sample_small", withExtension: "mp4") {
            testFiles.append(("Real Small", smallReal))
        }
        
        if let largeReal = testBundle.url(forResource: "test_sample", withExtension: "mp4") {
            testFiles.append(("Real Large", largeReal))
        }
        
        // Add generated sample files
        if let smallGenerated = testFileGenerator.createSmallMP4File() {
            testFiles.append(("Generated Small", smallGenerated))
        }
        
        for (name, fileURL) in testFiles {
            let asset = AVAsset(url: fileURL)
            let audioTracks = asset.tracks(withMediaType: .audio)
            
            guard let audioTrack = audioTracks.first else {
                XCTFail("\(name) should have at least one audio track")
                continue
            }
            
            // Check basic audio properties
            let naturalTimeScale = audioTrack.naturalTimeScale
            XCTAssertGreaterThan(naturalTimeScale, 8000, 
                "\(name) should have reasonable sample rate (>8kHz)")
            XCTAssertLessThan(naturalTimeScale, 192000, 
                "\(name) should have reasonable sample rate (<192kHz)")
            
            // Check estimated data rate
            let estimatedDataRate = audioTrack.estimatedDataRate
            XCTAssertGreaterThan(estimatedDataRate, 32000, 
                "\(name) should have reasonable bit rate (>32kbps)")
            
            print("✅ \(name) audio quality assessment passed (sample rate: \(naturalTimeScale)Hz, bit rate: \(Int(estimatedDataRate))bps)")
        }
    }
    
    // MARK: - Cross-Platform Compatibility Testing
    
    func testSampleFileCompatibilityWithAudioProcessor() throws {
        var testFiles: [(String, URL)] = []
        
        // Collect all available test files
        if let smallReal = testBundle.url(forResource: "test_sample_small", withExtension: "mp4") {
            testFiles.append(("Real Small", smallReal))
        }
        
        if let largeReal = testBundle.url(forResource: "test_sample", withExtension: "mp4") {
            testFiles.append(("Real Large", largeReal))
        }
        
        if let smallGenerated = testFileGenerator.createSmallMP4File() {
            testFiles.append(("Generated Small", smallGenerated))
        }
        
        guard !testFiles.isEmpty else {
            throw XCTSkip("No test files available for compatibility testing")
        }
        
        let expectations = testFiles.map { (name, _) in
            XCTestExpectation(description: "Compatibility test: \(name)")
        }
        
        for (index, (name, fileURL)) in testFiles.enumerated() {
            let expectation = expectations[index]
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: fileURL.path) { result in
                switch result {
                case .success(let audioFile):
                    // Validate extracted audio properties
                    XCTAssertGreaterThan(audioFile.format.duration, 0, 
                        "\(name) should extract audio with valid duration")
                    XCTAssertGreaterThan(audioFile.format.sampleRate, 0, 
                        "\(name) should extract audio with valid sample rate")
                    XCTAssertGreaterThan(audioFile.format.channels, 0, 
                        "\(name) should extract audio with valid channel count")
                    XCTAssertTrue(audioFile.format.isValid, 
                        "\(name) should extract valid audio format")
                    
                    print("✅ \(name) AudioProcessor compatibility passed")
                    
                case .failure(let error):
                    XCTFail("\(name) failed AudioProcessor compatibility test: \(error)")
                }
                
                expectation.fulfill()
            }
        }
        
        wait(for: expectations, timeout: 120.0)
    }
    
    // MARK: - Sample File Documentation
    
    func testGenerateSampleFileDocumentation() throws {
        var documentation = """
        # Sample File Documentation
        Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))
        
        ## Real Sample Files (Test Resources)
        
        """
        
        let realFiles = ["test_sample_small.mp4", "test_sample.mp4"]
        
        for fileName in realFiles {
            let fileNameWithoutExt = String(fileName.dropLast(4))
            
            if let fileURL = testBundle.url(forResource: fileNameWithoutExt, withExtension: "mp4") {
                let asset = AVAsset(url: fileURL)
                let duration = asset.duration.seconds
                
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                let audioTracks = asset.tracks(withMediaType: .audio)
                let videoTracks = asset.tracks(withMediaType: .video)
                
                documentation += """
                ### \(fileName)
                - Duration: \(String(format: "%.2f", duration)) seconds
                - File Size: \(fileSize / 1024) KB
                - Audio Tracks: \(audioTracks.count)
                - Video Tracks: \(videoTracks.count)
                
                """
                
                if let audioTrack = audioTracks.first {
                    documentation += """
                - Sample Rate: \(audioTrack.naturalTimeScale) Hz
                - Estimated Bit Rate: \(Int(audioTrack.estimatedDataRate)) bps
                
                """
                }
            }
        }
        
        documentation += """
        ## Generated Sample Files (TestAudioFileGenerator)
        
        ### Small MP4 (createSmallMP4File)
        - Target Duration: 3.0 seconds
        - Channels: 1 (mono)
        - Sample Rate: 44,100 Hz
        - Purpose: Quick testing, unit tests
        
        ### Medium MP4 (createMediumMP4File)
        - Target Duration: 10.0 seconds
        - Channels: 2 (stereo)
        - Sample Rate: 44,100 Hz
        - Purpose: Standard integration testing
        
        ### Large MP4 (createLargeMP4File)
        - Target Duration: 60.0 seconds
        - Channels: 2 (stereo)
        - Sample Rate: 44,100 Hz
        - Purpose: Performance testing, stress testing
        
        ## Error Test Files
        
        ### Invalid MP4 (createInvalidMP4File)
        - Contains: Plain text instead of MP4 data
        - Purpose: Test error handling for invalid file formats
        
        ### Empty MP4 (createEmptyMP4File)
        - Contains: Zero bytes
        - Purpose: Test error handling for empty files
        
        ### Corrupted MP4 (createCorruptedMP4File)
        - Contains: Partial MP4 header with truncated data
        - Purpose: Test error handling for corrupted files
        
        ### Video-Only MP4 (createVideoOnlyMP4File)
        - Contains: Video track without audio
        - Purpose: Test error handling for files without audio content
        
        ## Usage Guidelines
        
        1. Use real sample files for realistic integration testing
        2. Use small generated files for quick unit tests
        3. Use large generated files for performance testing
        4. Use error test files for comprehensive error handling validation
        
        """
        
        print(documentation)
        
        // This test always passes - it's for documentation generation
        XCTAssertTrue(true, "Sample file documentation generated successfully")
    }
    
    // MARK: - Helper Methods
    
    private func validateMP4Structure(_ fileURL: URL, fileName: String) throws {
        let asset = AVAsset(url: fileURL)
        
        // Test basic asset properties
        XCTAssertTrue(asset.isPlayable, "\(fileName) should be playable")
        
        let duration = asset.duration
        XCTAssertFalse(duration.isIndefinite, "\(fileName) should have definite duration")
        XCTAssertGreaterThan(duration.seconds, 0, "\(fileName) should have positive duration")
        
        // Test that it has tracks
        let tracks = asset.tracks
        XCTAssertFalse(tracks.isEmpty, "\(fileName) should have at least one track")
    }
    
    private func validateAudioContent(_ fileURL: URL, fileName: String) throws {
        let asset = AVAsset(url: fileURL)
        let audioTracks = asset.tracks(withMediaType: .audio)
        
        XCTAssertFalse(audioTracks.isEmpty, "\(fileName) should have audio tracks")
        
        guard let audioTrack = audioTracks.first else {
            XCTFail("\(fileName) should have at least one audio track")
            return
        }
        
        // Validate audio track properties
        XCTAssertTrue(audioTrack.isEnabled, "\(fileName) audio track should be enabled")
        XCTAssertTrue(audioTrack.isSelfContained, "\(fileName) audio track should be self-contained")
        
        let timeRange = audioTrack.timeRange
        XCTAssertGreaterThan(timeRange.duration.seconds, 0, 
            "\(fileName) audio track should have positive duration")
    }
}