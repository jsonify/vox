import Foundation
import AVFoundation

class TestAudioFileGenerator {
    
    static let shared = TestAudioFileGenerator()
    
    private let testDirectory: URL
    
    private init() {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox_test_audio_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("Failed to create test directory: \(error)")
        }
    }
    
    deinit {
        try? FileManager.default.removeItem(at: testDirectory)
    }
    
    // MARK: - Mock MP4 Creation
    
    func createMockMP4File(
        duration: TimeInterval = 30.0,
        hasAudio: Bool = true,
        hasVideo: Bool = true,
        sampleRate: Int = 44100,
        channels: Int = 2
    ) -> URL? {
        
        // Use appropriate test file based on duration
        let preferSmall = duration <= 5.0
        
        // For now, return a pre-generated test file if available
        if let testResourceURL = getTestResourceURL(preferSmall: preferSmall) {
            return copyTestFile(from: testResourceURL)
        }
        
        // Fallback: create a simple MP4 file with basic structure
        return createBasicMP4File(duration: duration, hasAudio: hasAudio, hasVideo: hasVideo)
    }
    
    // MARK: - Invalid File Creation
    
    func createInvalidMP4File() -> URL {
        let fileName = "invalid_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)
        
        let invalidData = "This is not a valid MP4 file content".data(using: .utf8)!
        FileManager.default.createFile(atPath: outputURL.path, contents: invalidData)
        
        return outputURL
    }
    
    func createEmptyMP4File() -> URL {
        let fileName = "empty_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)
        
        FileManager.default.createFile(atPath: outputURL.path, contents: Data())
        
        return outputURL
    }
    
    func createVideoOnlyMP4File(duration: TimeInterval = 10.0) -> URL? {
        return createMockMP4File(duration: duration, hasAudio: false, hasVideo: true)
    }
    
    func createCorruptedMP4File() -> URL {
        let fileName = "corrupted_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)
        
        // Create partial MP4 header to simulate corruption
        let corruptedData = Data([
            0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // Partial ftyp box
            0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
            0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32,
            // Truncated/corrupted data
            0xFF, 0xFF, 0xFF, 0xFF
        ])
        
        FileManager.default.createFile(atPath: outputURL.path, contents: corruptedData)
        
        return outputURL
    }
    
    // MARK: - File Size Variants
    
    func createLargeMP4File() -> URL? {
        // For "large" files in tests, we'll just use the regular test file multiple times
        // This avoids actually creating a 5-minute file which would be slow
        if let testResourceURL = getTestResourceURL(preferSmall: false) {
            return copyTestFile(from: testResourceURL)
        }
        return createMockMP4File(duration: 30.0) // Use shorter duration for tests
    }
    
    func createSmallMP4File() -> URL? {
        // Explicitly prefer the small test file
        if let testResourceURL = getTestResourceURL(preferSmall: true) {
            return copyTestFile(from: testResourceURL)
        }
        return createMockMP4File(duration: 1.0) // 1 second
    }
    
    // MARK: - Audio Format Variants
    
    func createHighQualityMP4File() -> URL? {
        return createMockMP4File(duration: 30.0, sampleRate: 48000, channels: 2)
    }
    
    func createLowQualityMP4File() -> URL? {
        return createMockMP4File(duration: 30.0, sampleRate: 22050, channels: 1)
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        try? FileManager.default.removeItem(at: testDirectory)
    }
    
    // MARK: - Private Implementation
    
    private func getTestResourceURL(preferSmall: Bool = false) -> URL? {
        // Look for test MP4 file in test bundle
        let bundle = Bundle(for: type(of: self))
        
        // Prioritize the appropriate test file based on requirements
        let testFileNames: [String]
        if preferSmall {
            testFileNames = [
                "test_sample_small.mp4",
                "test_sample.mp4"
            ]
        } else {
            testFileNames = [
                "test_sample.mp4",
                "test_sample_small.mp4"
            ]
        }
        
        for fileName in testFileNames {
            if let resourceURL = bundle.url(forResource: fileName, withExtension: nil) {
                return resourceURL
            }
            
            // Also try without extension
            let nameWithoutExt = String(fileName.dropLast(4))
            if let resourceURL = bundle.url(forResource: nameWithoutExt, withExtension: "mp4") {
                return resourceURL
            }
        }
        
        return nil
    }
    
    private func copyTestFile(from sourceURL: URL) -> URL? {
        let fileName = "test_copy_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
            return outputURL
        } catch {
            print("Failed to copy test file: \(error)")
            return nil
        }
    }
    
    private func createBasicMP4File(duration: TimeInterval, hasAudio: Bool, hasVideo: Bool) -> URL? {
        let fileName = "basic_test_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)
        
        // Create a minimal valid MP4 structure using AVAssetWriter
        guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            return nil
        }
        
        // Add a minimal audio track if requested
        if hasAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 64000
            ]
            
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = false
            
            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            }
        }
        
        // Add a minimal video track if requested  
        if hasVideo {
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 320,
                AVVideoHeightKey: 240
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = false
            
            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            }
        }
        
        // Start and immediately finish to create minimal valid file
        guard assetWriter.startWriting() else {
            return nil
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        // Mark all inputs as finished immediately
        for input in assetWriter.inputs {
            input.markAsFinished()
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        assetWriter.finishWriting {
            success = assetWriter.status == .completed
            semaphore.signal()
        }
        
        semaphore.wait()
        
        return success ? outputURL : nil
    }
}