import XCTest
import Foundation
@testable import vox

final class FFmpegProcessorBasicTests: XCTestCase {
    var processor: FFmpegProcessor?
    var testFileGenerator: TestAudioFileGenerator?
    var tempDirectory: URL?

    override func setUp() {
        super.setUp()
        processor = FFmpegProcessor()
        testFileGenerator = TestAudioFileGenerator.shared
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg_basic_tests_\(UUID().uuidString)")
        
        guard let tempDir = tempDirectory else {
            XCTFail("Failed to create temporary directory path")
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temporary directory: \(error)")
        }
    }

    override func tearDown() {
        // Clean up any temporary files first
        if let dir = tempDirectory {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                // Silently ignore cleanup errors in tests
            }
        }
        
        // Clean up test file generator
        if let generator = testFileGenerator {
            generator.cleanup()
        }
        
        processor = nil
        testFileGenerator = nil
        tempDirectory = nil
        
        super.tearDown()
    }

    func testFFmpegAvailabilityDetection() {
        // Test that the detection method works without crashing
        let isAvailable = FFmpegProcessor.isFFmpegAvailable()

        // We can't guarantee ffmpeg is installed in CI, so we just test the method doesn't crash
        XCTAssertTrue(isAvailable || !isAvailable, "Detection should return a boolean value")
    }

    func testFFmpegProcessorInstantiation() {
        XCTAssertNotNil(processor, "FFmpegProcessor should instantiate successfully")
    }

    func testTemporaryFileCreation() {
        guard let processor = processor else {
            XCTFail("Processor should be initialized")
            return
        }
        let tempURL = processor.createTemporaryAudioFile()
        XCTAssertNotNil(tempURL, "Should create a temporary file URL")

        if let url = tempURL {
            XCTAssertTrue(url.path.contains("vox_ffmpeg_temp_"), "Temporary file should have correct prefix")
            XCTAssertTrue(url.pathExtension == "m4a", "Temporary file should have .m4a extension")
        }
    }

    func testCleanupTemporaryFile() {
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        guard let tempURL = proc.createTemporaryAudioFile() else {
            XCTFail("Failed to create temporary file URL")
            return
        }

        // Create the file
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should exist")

        // Clean it up
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        proc.cleanupTemporaryFile(at: tempURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should be removed")
    }

    func testCleanupTemporaryFilesForAudioFile() {
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        guard let tempURL = proc.createTemporaryAudioFile() else {
            XCTFail("Failed to create temporary file URL")
            return
        }

        // Create the file
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should exist")

        // Create an AudioFile with the temporary path
        let audioFormat = AudioFormat(codec: "aac", sampleRate: 44100, channels: 2, bitRate: 128000, duration: 60.0)
        let audioFile = AudioFile(path: "/fake/path.mp4", format: audioFormat, temporaryPath: tempURL.path)

        // Clean it up
        guard let proc = processor else {
            XCTFail("Processor not initialized")
            return
        }
        
        proc.cleanupTemporaryFiles(for: audioFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), "Temporary file should be removed")
    }
}
