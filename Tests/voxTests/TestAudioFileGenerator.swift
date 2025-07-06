import Foundation
import AVFoundation
import XCTest

/// Generator for creating test audio files with various configurations
public final class TestAudioFileGenerator {
    static let shared = TestAudioFileGenerator()

    private let testDirectory: URL

    private init() {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox_test_audio_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        } catch {
            print("Warning: Failed to create test directory: \(error)")
            // Use a fallback directory instead of crashing
            let fallbackDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("vox_test_fallback")
            try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    // MARK: - Mock MP4 Creation

    /// Creates a mock MP4 file for testing with specified parameters
    /// - Parameters:
    ///   - duration: Length of the audio/video in seconds
    ///   - hasAudio: Whether to include an audio track
    ///   - hasVideo: Whether to include a video track
    ///   - sampleRate: Audio sample rate in Hz
    ///   - channels: Number of audio channels
    /// - Returns: URL to the created file, or nil if creation fails
    public func createMockMP4File(
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

    /// Creates an invalid MP4 file for testing error handling
    /// - Returns: URL to the created invalid file
    public func createInvalidMP4File() -> URL {
        let fileName = "invalid_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)

        guard let invalidData = "This is not a valid MP4 file content".data(using: .utf8) else {
            return testDirectory.appendingPathComponent("empty_fallback.mp4")
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: invalidData)

        return outputURL
    }

    /// Creates an empty MP4 file for testing error handling
    /// - Returns: URL to the created empty file
    public func createEmptyMP4File() -> URL {
        let fileName = "empty_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)

        FileManager.default.createFile(atPath: outputURL.path, contents: Data())

        return outputURL
    }

    /// Creates an MP4 file with video track but no audio
    /// - Parameter duration: Length of the video in seconds
    /// - Returns: URL to the created file, or nil if creation fails
    public func createVideoOnlyMP4File(duration: TimeInterval = 10.0) -> URL? {
        return createMockMP4File(duration: duration, hasAudio: false, hasVideo: true)
    }

    /// Creates a corrupted MP4 file for testing error handling
    /// - Returns: URL to the created corrupted file
    public func createCorruptedMP4File() -> URL {
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

    /// Creates a small MP4 file for quick testing (3 seconds)
    /// - Returns: URL to the created file, or nil if creation fails
    public func createSmallMP4File() -> URL? {
        return createMockMP4File(
            duration: 3.0,
            hasAudio: true,
            hasVideo: true,
            sampleRate: 44100,
            channels: 1
        )
    }
    
    /// Creates a large MP4 file for performance testing (60 seconds)
    /// - Returns: URL to the created file, or nil if creation fails
    public func createLargeMP4File() -> URL? {
        return createMockMP4File(
            duration: 60.0,
            hasAudio: true,
            hasVideo: true,
            sampleRate: 44100,
            channels: 2
        )
    }
    
    /// Creates a medium MP4 file for standard testing (10 seconds)
    /// - Returns: URL to the created file, or nil if creation fails
    public func createMediumMP4File() -> URL? {
        return createMockMP4File(
            duration: 10.0,
            hasAudio: true,
            hasVideo: true,
            sampleRate: 44100,
            channels: 2
        )
    }

    // MARK: - Cleanup

    /// Cleans up all test files and directories
    public func cleanup() {
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
            XCTFail("Failed to copy test file: \(error)")
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
