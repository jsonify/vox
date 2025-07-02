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
        
        let fileName = "test_video_\(UUID().uuidString).mp4"
        let outputURL = testDirectory.appendingPathComponent(fileName)
        
        // Create composition
        let composition = AVMutableComposition()
        
        if hasVideo {
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return nil }
            
            // Create simple video track with colored frames
            if let colorVideoAsset = createColorVideoAsset(duration: duration) {
                do {
                    let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
                    try videoTrack.insertTimeRange(timeRange, of: colorVideoAsset.tracks(withMediaType: .video)[0], at: .zero)
                } catch {
                    return nil
                }
            }
        }
        
        if hasAudio {
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return nil }
            
            // Create simple audio track
            if let toneAudioAsset = createToneAudioAsset(duration: duration, sampleRate: sampleRate, channels: channels) {
                do {
                    let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
                    try audioTrack.insertTimeRange(timeRange, of: toneAudioAsset.tracks(withMediaType: .audio)[0], at: .zero)
                } catch {
                    return nil
                }
            }
        }
        
        // Export composition
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetMediumQuality
        ) else { return nil }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        exportSession.exportAsynchronously {
            success = exportSession.status == .completed
            semaphore.signal()
        }
        
        semaphore.wait()
        
        return success ? outputURL : nil
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
        return createMockMP4File(duration: 300.0) // 5 minutes
    }
    
    func createSmallMP4File() -> URL? {
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
    
    // MARK: - Private Helpers
    
    private func createColorVideoAsset(duration: TimeInterval) -> AVAsset? {
        // Create a simple colored video asset programmatically
        let composition = AVMutableComposition()
        
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }
        
        // This is a simplified approach - in practice, creating video programmatically
        // is complex. For testing, we'll create a minimal asset.
        return composition
    }
    
    private func createToneAudioAsset(duration: TimeInterval, sampleRate: Int, channels: Int) -> AVAsset? {
        // Create a simple tone audio asset programmatically
        let composition = AVMutableComposition()
        
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }
        
        // This is a simplified approach - creating audio programmatically
        // would require more complex buffer manipulation
        return composition
    }
}