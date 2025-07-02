import XCTest
@testable import vox

final class AudioFormatTests: XCTestCase {
    
    // MARK: - AudioFormat Tests
    
    func testAudioFormatCreation() {
        let format = AudioFormat(
            codec: "mp4",
            sampleRate: 48000,
            channels: 2,
            bitRate: 256000,
            duration: 180.5
        )
        
        XCTAssertEqual(format.codec, "mp4")
        XCTAssertEqual(format.sampleRate, 48000)
        XCTAssertEqual(format.channels, 2)
        XCTAssertEqual(format.bitRate, 256000)
        XCTAssertEqual(format.duration, 180.5)
        XCTAssertTrue(format.isValid)
        XCTAssertNil(format.validationError)
        XCTAssertEqual(format.quality, .high)
    }
    
    func testAudioFormatWithoutBitRate() {
        let format = AudioFormat(
            codec: "wav",
            sampleRate: 44100,
            channels: 1,
            bitRate: nil,
            duration: 60.0
        )
        
        XCTAssertEqual(format.codec, "wav")
        XCTAssertEqual(format.channels, 1)
        XCTAssertNil(format.bitRate)
        XCTAssertEqual(format.quality, .medium)
    }
    
    func testAudioFormatWithFileSize() {
        let format = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 120.0,
            fileSize: 1920000 // 1.92MB
        )
        
        XCTAssertEqual(format.fileSize, 1920000)
        XCTAssertTrue(format.description.contains("1.9 MB"))
    }
    
    func testAudioFormatValidationFailed() {
        let format = AudioFormat(
            codec: "unsupported",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 60.0,
            isValid: false,
            validationError: "Unsupported codec: unsupported"
        )
        
        XCTAssertFalse(format.isValid)
        XCTAssertEqual(format.validationError, "Unsupported codec: unsupported")
        XCTAssertFalse(format.isCompatible)
    }
    
    func testAudioFormatDescription() {
        let format = AudioFormat(
            codec: "aac",
            sampleRate: 48000,
            channels: 2,
            bitRate: 256000,
            duration: 123.45,
            fileSize: 4000000
        )
        
        let description = format.description
        XCTAssertTrue(description.contains("AAC"))
        XCTAssertTrue(description.contains("48000Hz"))
        XCTAssertTrue(description.contains("2ch"))
        XCTAssertTrue(description.contains("256 kbps"))
        XCTAssertTrue(description.contains("123.5s"))
        XCTAssertTrue(description.contains("MB"))
    }
    
    func testAudioFormatWithZeroDuration() {
        let format = AudioFormat(
            codec: "silence",
            sampleRate: 44100,
            channels: 1,
            bitRate: 0,
            duration: 0.0
        )
        
        XCTAssertEqual(format.duration, 0.0)
        XCTAssertEqual(format.bitRate, 0)
    }
    
    // MARK: - AudioFile Tests
    
    func testAudioFileCreation() {
        let format = AudioFormat(
            codec: "m4a",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 300.0
        )
        
        let audioFile = AudioFile(
            path: "/path/to/input.mp4",
            format: format,
            temporaryPath: "/tmp/temp_audio.m4a"
        )
        
        XCTAssertEqual(audioFile.path, "/path/to/input.mp4")
        XCTAssertEqual(audioFile.format.codec, "m4a")
        XCTAssertEqual(audioFile.temporaryPath, "/tmp/temp_audio.m4a")
    }
    
    func testAudioFileWithoutTempPath() {
        let format = AudioFormat(
            codec: "wav",
            sampleRate: 22050,
            channels: 1,
            bitRate: 64000,
            duration: 120.0
        )
        
        let audioFile = AudioFile(
            path: "/path/to/audio.wav",
            format: format,
            temporaryPath: nil
        )
        
        XCTAssertEqual(audioFile.path, "/path/to/audio.wav")
        XCTAssertNil(audioFile.temporaryPath)
    }
    
    // MARK: - Enhanced Audio Format Tests
    
    func testAudioFormatTranscriptionCompatibility() {
        // Test transcription-ready formats
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "aac"))
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "m4a"))
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "wav"))
        XCTAssertTrue(AudioFormatValidator.isTranscriptionCompatible(codec: "mp3"))
        
        // Test non-transcription-ready formats  
        XCTAssertFalse(AudioFormatValidator.isTranscriptionCompatible(codec: "opus"))
        XCTAssertFalse(AudioFormatValidator.isTranscriptionCompatible(codec: "vorbis"))
        XCTAssertFalse(AudioFormatValidator.isTranscriptionCompatible(codec: "unknown"))
    }
    
    func testAudioFormatIsTranscriptionReady() {
        // Valid and transcription-compatible format
        let readyFormat = AudioFormat(
            codec: "aac",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 60.0
        )
        XCTAssertTrue(readyFormat.isTranscriptionReady)
        
        // Valid but not transcription-compatible format
        let notReadyFormat = AudioFormat(
            codec: "opus", 
            sampleRate: 48000,
            channels: 2,
            bitRate: 128000,
            duration: 60.0,
            isValid: true
        )
        XCTAssertFalse(notReadyFormat.isTranscriptionReady)
        
        // Invalid format
        let invalidFormat = AudioFormat(
            codec: "aac",
            sampleRate: 44100,
            channels: 2,
            bitRate: 128000,
            duration: 60.0,
            isValid: false
        )
        XCTAssertFalse(invalidFormat.isTranscriptionReady)
    }
}