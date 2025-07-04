import XCTest
import Foundation
@testable import vox

final class AudioProcessorPerformanceTests: XCTestCase {
    var testFileGenerator: TestAudioFileGenerator?

    override func setUp() {
        super.setUp()
        testFileGenerator = TestAudioFileGenerator.shared
    }

    override func tearDown() {
        testFileGenerator?.cleanup()
        testFileGenerator = nil
        super.tearDown()
    }

    // MARK: - Memory Management Tests

    func testMemoryManagementWithMultipleProcessors() {
        var processors: [AudioProcessor] = []

        // Create multiple processors
        for _ in 0..<10 {
            processors.append(AudioProcessor())
        }

        // Test they can all create temp files via TempFileManager
        for _ in processors {
            let tempURL = TempFileManager.shared.createTemporaryAudioFile()
            XCTAssertNotNil(tempURL)
            if let url = tempURL {
                _ = TempFileManager.shared.cleanupFile(at: url)
            }
        }

        // Clear references
        processors.removeAll()

        // Force deallocation
        autoreleasepool {
            _ = AudioProcessor()
            let tempURL = TempFileManager.shared.createTemporaryAudioFile()
            XCTAssertNotNil(tempURL)
            if let url = tempURL {
                _ = TempFileManager.shared.cleanupFile(at: url)
            }
        }
    }

    // MARK: - Thread Safety Tests

    func testConcurrentTemporaryFileCreation() {
        let concurrentQueue = DispatchQueue(
            label: "test.concurrent", 
            attributes: .concurrent
        )
        let group = DispatchGroup()
        var tempURLs: [URL] = []
        let lock = NSLock()

        for _ in 0..<20 {
            group.enter()
            concurrentQueue.async {
                if let tempURL = TempFileManager.shared.createTemporaryAudioFile() {
                    lock.lock()
                    tempURLs.append(tempURL)
                    lock.unlock()
                }
                group.leave()
            }
        }

        let expectation = XCTestExpectation(description: "Concurrent file creation")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // All URLs should be unique
        let uniqueURLs = Set(tempURLs.map { $0.lastPathComponent })
        XCTAssertEqual(tempURLs.count, uniqueURLs.count)
        XCTAssertEqual(tempURLs.count, 20)

        // Cleanup all created files
        _ = TempFileManager.shared.cleanupFiles(at: tempURLs)
    }

    func testProgressReportingAccuracy() {
        guard let generator = testFileGenerator,
              let testVideoURL = generator.createMockMP4File(duration: 10.0) else {
            XCTFail("Failed to create test MP4 file")
            return
        }

        let expectation = XCTestExpectation(description: "Progress reporting")
        var progressReports: [TranscriptionProgress] = []
        let startTime = Date()
        let audioProcessor = AudioProcessor()

        audioProcessor.extractAudio(
            from: testVideoURL.path,
            progressCallback: { progress in
                progressReports.append(progress)

                // Validate progress properties
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
                XCTAssertNotNil(progress.currentStatus)
                XCTAssertNotNil(progress.currentPhase)
                XCTAssertEqual(
                    progress.startTime.timeIntervalSince1970,
                    startTime.timeIntervalSince1970,
                    accuracy: 1.0
                )
            }
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)

        // Validate progress sequence
        XCTAssertFalse(progressReports.isEmpty)

        // Check that progress is generally increasing
        for index in 1..<progressReports.count {
            XCTAssertGreaterThanOrEqual(
                progressReports[index].currentProgress,
                progressReports[index - 1].currentProgress,
                "Progress should not decrease"
            )
        }

        // Verify all expected phases are present
        let phases = Set(progressReports.map { $0.currentPhase })
        XCTAssertTrue(phases.contains(.initializing))
        XCTAssertTrue(phases.contains(.extracting))
        XCTAssertTrue(phases.contains(.complete))
    }

    func testConcurrentAudioProcessing() {
        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not available")
            return
        }

        // Create multiple test files
        var testFiles: [URL] = []
        for index in 0..<3 {
            if let testFile = generator.createMockMP4File(duration: 5.0) {
                testFiles.append(testFile)
            }
        }

        guard testFiles.count == 3 else {
            XCTFail("Failed to create test files")
            return
        }

        let concurrentQueue = DispatchQueue(
            label: "test.audio.concurrent", 
            attributes: .concurrent
        )
        let group = DispatchGroup()
        var results: [Result<AudioFile, VoxError>] = []
        let resultsLock = NSLock()

        // Process files concurrently
        for testFile in testFiles {
            group.enter()
            concurrentQueue.async {
                let processor = AudioProcessor()
                processor.extractAudio(from: testFile.path) { result in
                    resultsLock.lock()
                    results.append(result)
                    resultsLock.unlock()
                    group.leave()
                }
            }
        }

        let expectation = XCTestExpectation(description: "Concurrent processing")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)

        // Verify all processing completed
        XCTAssertEqual(results.count, 3)

        // Check results
        for result in results {
            switch result {
            case .success(let audioFile):
                XCTAssertEqual(audioFile.format.codec, "m4a")
                XCTAssertGreaterThan(audioFile.format.duration, 0)
            case .failure(let error):
                XCTFail("Audio processing should succeed: \(error)")
            }
        }
    }

    func testLargeFileProcessing() {
        guard let generator = testFileGenerator,
              let largeTestFile = generator.createLargeMP4File() else {
            XCTFail("Failed to create large test file")
            return
        }

        let expectation = XCTestExpectation(description: "Large file processing")
        let startTime = Date()
        var progressCount = 0
        let audioProcessor = AudioProcessor()

        audioProcessor.extractAudio(
            from: largeTestFile.path,
            progressCallback: { progress in
                progressCount += 1
                
                // Should report progress for large files
                XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
                XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
            }
        ) { result in
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let audioFile):
                XCTAssertEqual(audioFile.format.codec, "m4a")
                XCTAssertGreaterThan(audioFile.format.duration, 0)
                
                // Should have reported multiple progress updates for large file
                XCTAssertGreaterThan(progressCount, 1)
                
                // Processing should complete in reasonable time
                XCTAssertLessThan(processingTime, 120.0) // 2 minutes max
                
                // Cleanup
                audioProcessor.cleanupTemporaryFiles(for: audioFile)
                
            case .failure(let error):
                XCTFail("Large file processing should succeed: \(error)")
            }
            
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    func testMemoryUsageDuringProcessing() {
        guard let generator = testFileGenerator,
              let testFile = generator.createMockMP4File(duration: 30.0) else {
            XCTFail("Failed to create test file")
            return
        }

        let expectation = XCTestExpectation(description: "Memory usage monitoring")
        let audioProcessor = AudioProcessor()
        var memoryReadings: [UInt64] = []
        
        // Monitor memory usage during processing
        let memoryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let memoryUsage = self.getCurrentMemoryUsage()
            memoryReadings.append(memoryUsage)
        }

        audioProcessor.extractAudio(from: testFile.path) { result in
            memoryTimer.invalidate()
            
            switch result {
            case .success(let audioFile):
                // Verify memory usage is reasonable
                XCTAssertFalse(memoryReadings.isEmpty)
                
                let maxMemory = memoryReadings.max() ?? 0
                let minMemory = memoryReadings.min() ?? 0
                let memoryGrowth = maxMemory - minMemory
                
                // Memory growth should be reasonable (less than 500MB)
                XCTAssertLessThan(memoryGrowth, 500 * 1024 * 1024)
                
                // Cleanup
                audioProcessor.cleanupTemporaryFiles(for: audioFile)
                
            case .failure(let error):
                XCTFail("Memory usage test should succeed: \(error)")
            }
            
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    func testProcessingSpeedBenchmark() {
        guard let generator = testFileGenerator else {
            XCTFail("Test file generator not available")
            return
        }

        let testCases = [
            ("short", { generator.createMockMP4File(duration: 5.0) }),
            ("medium", { generator.createMockMP4File(duration: 30.0) }),
            ("long", { generator.createMockMP4File(duration: 60.0) })
        ]

        var processingTimes: [String: TimeInterval] = [:]

        for (name, createFile) in testCases {
            guard let testFile = createFile() else {
                XCTFail("Failed to create \(name) test file")
                continue
            }

            let expectation = XCTestExpectation(description: "Processing speed for \(name)")
            let startTime = Date()
            let audioProcessor = AudioProcessor()

            audioProcessor.extractAudio(from: testFile.path) { result in
                let processingTime = Date().timeIntervalSince(startTime)
                processingTimes[name] = processingTime

                switch result {
                case .success(let audioFile):
                    let realTimeRatio = audioFile.format.duration / processingTime
                    
                    // Should process faster than real-time for most files
                    if audioFile.format.duration > 10.0 {
                        XCTAssertGreaterThan(realTimeRatio, 1.0, "Should process faster than real-time for \(name)")
                    }
                    
                    // Cleanup
                    audioProcessor.cleanupTemporaryFiles(for: audioFile)
                    
                case .failure(let error):
                    XCTFail("Processing speed test should succeed for \(name): \(error)")
                }
                
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 120.0)
        }

        // Log processing times for analysis
        for (name, time) in processingTimes {
            Logger.shared.info("Processing time for \(name): \(String(format: "%.2f", time))s", component: "AudioProcessorPerformanceTests")
        }
    }

    // MARK: - Helper Methods

    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

// MARK: - Test File Generator Extensions

extension TestAudioFileGenerator {
    /// Creates a larger test file for performance testing
    /// - Returns: URL to a 2-minute test file, or nil if creation fails
    func createLargeMP4File() -> URL? {
        return createMockMP4File(duration: 120.0)
    }

    /// Creates a high quality test file for performance comparison
    /// - Returns: URL to a test file with standard duration and high quality settings
    func createHighQualityMP4File() -> URL? {
        return createMockMP4File(
            duration: 10.0,
            sampleRate: 48000,
            channels: 2
        )
    }

    /// Creates a low quality test file for performance comparison
    /// - Returns: URL to a test file with standard duration and low quality settings
    func createLowQualityMP4File() -> URL? {
        return createMockMP4File(
            duration: 10.0,
            sampleRate: 22050,
            channels: 1
        )
    }

    /// Creates a minimal test file for quick performance tests
    /// - Returns: URL to a short test file, or nil if creation fails
    func createSmallMP4File() -> URL? {
        return createMockMP4File(duration: 2.0)
    }
}
