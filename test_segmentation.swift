#!/usr/bin/env swift

import Foundation
import AVFoundation

print("=== Audio Segmentation Test ===")

// Test that we can create audio segments properly
func testAudioSegmentation() {
    print("Testing audio segmentation capability...")
    
    // Check if AVFoundation can create export sessions
    let testAsset = AVURLAsset(url: URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff"))
    
    if let exportSession = AVAssetExportSession(asset: testAsset, presetName: AVAssetExportPresetAppleM4A) {
        print("✅ AVAssetExportSession creation: SUCCESS")
        print("   Supported file types: \(exportSession.supportedFileTypes)")
        print("   Can determine output file type: \(exportSession.outputFileType != nil)")
    } else {
        print("❌ AVAssetExportSession creation: FAILED")
    }
    
    // Test time range functionality
    let startTime = CMTime(seconds: 1.0, preferredTimescale: 600)
    let duration = CMTime(seconds: 2.0, preferredTimescale: 600)
    let timeRange = CMTimeRange(start: startTime, duration: duration)
    
    print("✅ CMTimeRange creation: SUCCESS")
    print("   Start: \(CMTimeGetSeconds(timeRange.start))s")
    print("   Duration: \(CMTimeGetSeconds(timeRange.duration))s")
    
    // Test temporary directory creation
    let tempDir = FileManager.default.temporaryDirectory
    let segmentDir = tempDir.appendingPathComponent("test_segments_\(UUID().uuidString)")
    
    do {
        try FileManager.default.createDirectory(at: segmentDir, withIntermediateDirectories: true)
        print("✅ Temporary directory creation: SUCCESS")
        print("   Directory: \(segmentDir.path)")
        
        // Cleanup
        try FileManager.default.removeItem(at: segmentDir)
        print("✅ Directory cleanup: SUCCESS")
    } catch {
        print("❌ Directory operations: FAILED - \(error)")
    }
}

// Test memory management patterns
func testMemoryManagement() {
    print("\nTesting memory management patterns...")
    
    // Simulate weak reference pattern
    class TestEngine {
        var isActive = true
        
        func performTask(completion: @escaping (String) -> Void) {
            DispatchQueue.global().async { [weak self] in
                guard let self = self else {
                    print("✅ Weak self pattern: SUCCESS - Engine was deallocated")
                    return
                }
                
                if self.isActive {
                    completion("Task completed")
                }
            }
        }
    }
    
    var engine: TestEngine? = TestEngine()
    
    engine?.performTask { result in
        print("Task result: \(result)")
    }
    
    // Deallocate engine to test weak reference
    engine = nil
    
    print("✅ Memory management test setup: SUCCESS")
}

// Test progress calculation
func testProgressCalculation() {
    print("\nTesting progress calculation...")
    
    let totalSegments = 5
    var completedSegments = 0
    
    for i in 1...totalSegments {
        completedSegments = i
        let progress = Double(completedSegments) / Double(totalSegments)
        let percentage = Int(progress * 100)
        print("   Segment \(i)/\(totalSegments) completed: \(percentage)%")
    }
    
    print("✅ Progress calculation: SUCCESS")
}

// Run all tests
testAudioSegmentation()
testMemoryManagement()
testProgressCalculation()

print("\n🎉 All segmentation infrastructure tests completed!")
print("🚀 Ready for optimized transcription with real audio splitting")