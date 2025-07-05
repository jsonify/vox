import XCTest
import Foundation
@testable import vox

final class OptimizedPerformanceTests: XCTestCase {
    var benchmark: PerformanceBenchmark?
    var platformOptimizer: PlatformOptimizer?
    var memoryManager: OptimizedMemoryManager?
    var testFileGenerator: TestAudioFileGenerator?

    override func setUp() {
        super.setUp()
        benchmark = PerformanceBenchmark.shared
        platformOptimizer = PlatformOptimizer.shared
        memoryManager = OptimizedMemoryManager.shared
        testFileGenerator = TestAudioFileGenerator.shared

        // Log system configuration
        platformOptimizer?.logSystemInfo()
    }

    override func tearDown() {
        testFileGenerator?.cleanup()
        super.tearDown()
    }

    // MARK: - Platform Detection Tests

    func testPlatformDetection() {
        guard let optimizer = platformOptimizer else {
            XCTFail("Platform optimizer not available")
            return
        }
        
        Logger.shared.info("=== Platform Detection Test ===", component: "OptimizedPerformanceTests")

        XCTAssertNotEqual(optimizer.architecture, .unknown, "Should detect platform architecture")
        XCTAssertGreaterThan(optimizer.processorCount, 0, "Should detect processor count")
        XCTAssertGreaterThan(optimizer.physicalMemory, 0, "Should detect physical memory")

        Logger.shared.info("Architecture: \(optimizer.architecture.displayName)", component: "OptimizedPerformanceTests")
        Logger.shared.info("Processor Count: \(optimizer.processorCount)", component: "OptimizedPerformanceTests")
        Logger.shared.info("Physical Memory: \(optimizer.physicalMemory / 1024 / 1024 / 1024)GB", component: "OptimizedPerformanceTests")
    }

    // MARK: - Configuration Optimization Tests

    func testAudioProcessingConfiguration() {
        guard let optimizer = platformOptimizer else {
            XCTFail("Platform optimizer not available")
            return
        }
        
        let config = optimizer.getAudioProcessingConfig()

        XCTAssertGreaterThan(config.concurrentOperations, 0, "Should have concurrent operations")
        XCTAssertGreaterThan(config.bufferSize, 0, "Should have buffer size")

        Logger.shared.info("Audio Config - Concurrent: \(config.concurrentOperations), Buffer: \(config.bufferSize)", component: "OptimizedPerformanceTests")

        // Platform-specific assertions
        switch optimizer.architecture {
        case .appleSilicon:
            XCTAssertTrue(config.useHardwareAcceleration, "Apple Silicon should use hardware acceleration")
            XCTAssertGreaterThanOrEqual(config.bufferSize, 4096, "Apple Silicon should use larger buffers")

        case .intel:
            XCTAssertGreaterThanOrEqual(config.concurrentOperations, 1, "Intel should support concurrency")

        case .unknown:
            XCTAssertEqual(config.bufferSize, 2048, "Unknown architecture should use conservative buffer size")
        }
    }

    func testSpeechRecognitionConfiguration() {
        guard let optimizer = platformOptimizer else {
            XCTFail("Platform optimizer not available")
            return
        }
        
        let config = optimizer.getSpeechRecognitionConfig()

        XCTAssertTrue(config.useOnDeviceRecognition, "Should prefer on-device recognition")
        XCTAssertGreaterThan(config.segmentDuration, 0, "Should have segment duration")
        XCTAssertGreaterThan(config.memoryMonitoringInterval, 0, "Should have memory monitoring interval")

        Logger.shared.info("Speech Config - Segment: \(config.segmentDuration)s, Memory Interval: \(config.memoryMonitoringInterval)s", component: "OptimizedPerformanceTests")

        // Apple Silicon should have more optimistic settings
        if optimizer.architecture == .appleSilicon {
            XCTAssertLessThanOrEqual(config.progressReportingInterval, 0.5, "Apple Silicon should have frequent progress updates")
        }
    }

    func testMemoryConfiguration() {
        guard let optimizer = platformOptimizer else {
            XCTFail("Platform optimizer not available")
            return
        }
        
        let config = optimizer.getMemoryConfig()

        XCTAssertGreaterThan(config.maxMemoryUsage, 0, "Should have memory limit")
        XCTAssertGreaterThan(config.bufferPoolSize, 0, "Should have buffer pool")
        XCTAssertGreaterThan(config.garbageCollectionThreshold, 0, "Should have GC threshold")

        Logger.shared.info("Memory Config - Max: \(config.maxMemoryUsage / 1024 / 1024)MB, Pools: \(config.bufferPoolSize)", component: "OptimizedPerformanceTests")

        // Ensure memory usage is reasonable
        let memoryRatio = Double(config.maxMemoryUsage) / Double(optimizer.physicalMemory)
        XCTAssertLessThan(memoryRatio, 0.8, "Memory usage should be reasonable")
    }

    // MARK: - Memory Manager Tests

    func testMemoryPoolPerformance() {
        guard let manager = memoryManager else {
            XCTFail("Memory manager not available")
            return
        }
        
        let startTime = Date()
        let iterations = 1000
        var buffers: [UnsafeMutableRawPointer] = []

        // Test buffer allocation performance
        for _ in 0..<iterations {
            if let buffer = manager.borrowBuffer(size: 4096) {
                buffers.append(buffer)
            }
        }

        let allocationTime = Date().timeIntervalSince(startTime)

        // Test buffer deallocation performance
        let deallocStartTime = Date()
        for buffer in buffers {
            manager.returnBuffer(buffer, size: 4096)
        }
        let deallocationTime = Date().timeIntervalSince(deallocStartTime)

        Logger.shared.info("Memory Pool Performance:", component: "OptimizedPerformanceTests")
        Logger.shared.info("  Allocation: \(String(format: "%.3f", allocationTime))s for \(iterations) buffers", component: "OptimizedPerformanceTests")
        Logger.shared.info("  Deallocation: \(String(format: "%.3f", deallocationTime))s for \(iterations) buffers", component: "OptimizedPerformanceTests")

        XCTAssertLessThan(allocationTime, 0.1, "Buffer allocation should be fast")
        XCTAssertLessThan(deallocationTime, 0.1, "Buffer deallocation should be fast")
    }

    func testOptimizedMemoryOperations() {
        guard let manager = memoryManager else {
            XCTFail("Memory manager not available")
            return
        }
        
        let bufferSize = 64 * 1024 // 64KB
        let sourceData = Data(repeating: 0x42, count: bufferSize)

        guard let destBuffer = manager.borrowBuffer(size: bufferSize) else {
            XCTFail("Failed to allocate destination buffer")
            return
        }

        let startTime = Date()

        sourceData.withUnsafeBytes { sourcePtr in
            manager.optimizedMemcopy(
                destination: destBuffer,
                source: sourcePtr.bindMemory(to: UInt8.self).baseAddress!,
                byteCount: bufferSize
            )
        }

        let copyTime = Date().timeIntervalSince(startTime)

        Logger.shared.info("Optimized memcopy: \(String(format: "%.3f", copyTime))s for \(bufferSize) bytes", component: "OptimizedPerformanceTests")

        // Verify copy correctness
        let copiedData = Data(bytes: destBuffer, count: bufferSize)
        XCTAssertEqual(sourceData, copiedData, "Memory copy should be correct")

        manager.returnBuffer(destBuffer, size: bufferSize)

        // Performance should be reasonable
        let mbPerSecond = Double(bufferSize) / (1024 * 1024) / copyTime
        XCTAssertGreaterThan(mbPerSecond, 100, "Memory copy should achieve > 100MB/s")
    }

    // MARK: - Benchmark Framework Tests

    func testBenchmarkFramework() throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer,
              let _ = createTestAudioFile() else {
            throw XCTSkip("Unable to create test audio file or required components")
        }

        bench.startBenchmark("Framework_Test")

        // Simulate some work
        usleep(100000) // 100ms

        let result = bench.endBenchmark("Framework_Test", audioDuration: 1.0)

        XCTAssertEqual(result.testName, "Framework_Test")
        XCTAssertEqual(result.platform, optimizer.architecture)
        XCTAssertGreaterThan(result.processingTime, 0.09) // Should be > 90ms
        XCTAssertLessThan(result.processingTime, 0.2) // Should be < 200ms

        Logger.shared.info("Benchmark Framework Test:", component: "OptimizedPerformanceTests")
        Logger.shared.info(result.summary, component: "OptimizedPerformanceTests")

        bench.logBenchmarkResult(result)
    }

    // MARK: - Platform-Specific Performance Tests

    func testAppleSiliconOptimizations() throws {
        guard let optimizer = platformOptimizer,
              let bench = benchmark else {
            throw XCTSkip("Required components not available")
        }
        
        guard optimizer.architecture == .appleSilicon else {
            throw XCTSkip("Test requires Apple Silicon")
        }

        guard let testAudioFile = createTestAudioFile() else {
            throw XCTSkip("Unable to create test audio file")
        }

        Logger.shared.info("Testing Apple Silicon optimizations", component: "OptimizedPerformanceTests")

        bench.startBenchmark("Apple_Silicon_Test")

        // Test optimized transcription engine
        let engine = OptimizedTranscriptionEngine()
        let expectation = XCTestExpectation(description: "Apple Silicon transcription")

        engine.transcribeAudio(from: testAudioFile) { progress in
            // Progress updates should be frequent on Apple Silicon
            XCTAssertGreaterThanOrEqual(progress.currentProgress, 0.0)
            XCTAssertLessThanOrEqual(progress.currentProgress, 1.0)
        } completion: { result in
            let benchmarkResult = bench.endBenchmark("Apple_Silicon_Test", audioDuration: testAudioFile.format.duration)

            switch result {
            case .success(let transcriptionResult):
                XCTAssertGreaterThan(transcriptionResult.confidence, 0.5, "Should have reasonable confidence")

                // Apple Silicon should be efficient
                XCTAssertLessThan(benchmarkResult.processingRatio, 2.0, "Apple Silicon should process < 2x real-time")

            case .failure(let error):
                XCTFail("Transcription failed: \(error)")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testIntelOptimizations() throws {
        guard let optimizer = platformOptimizer,
              let bench = benchmark else {
            throw XCTSkip("Required components not available")
        }
        
        guard optimizer.architecture == .intel else {
            throw XCTSkip("Test requires Intel processor")
        }

        guard let testAudioFile = createTestAudioFile() else {
            throw XCTSkip("Unable to create test audio file")
        }

        Logger.shared.info("Testing Intel optimizations", component: "OptimizedPerformanceTests")

        bench.startBenchmark("Intel_Test")

        // Test with Intel-specific optimizations
        let audioConfig = optimizer.getAudioProcessingConfig()
        XCTAssertFalse(audioConfig.useHardwareAcceleration || audioConfig.concurrentOperations >= 8, "Intel should use appropriate settings")

        let engine = OptimizedTranscriptionEngine()
        let expectation = XCTestExpectation(description: "Intel transcription")

        engine.transcribeAudio(from: testAudioFile) { _ in
            // Monitor progress
        } completion: { result in
            let benchmarkResult = bench.endBenchmark("Intel_Test", audioDuration: testAudioFile.format.duration)

            switch result {
            case .success:
                // Intel should still perform reasonably
                XCTAssertLessThan(benchmarkResult.processingRatio, 3.0, "Intel should process < 3x real-time")

            case .failure(let error):
                XCTFail("Transcription failed: \(error)")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 45.0)
    }

    // MARK: - Performance Comparison Tests

    func testOptimizedVsStandardPerformance() async throws {
        guard let bench = benchmark,
              let testAudioFile = createTestAudioFile() else {
            throw XCTSkip("Unable to create test audio file or benchmark not available")
        }

        Logger.shared.info("Comparing optimized vs standard performance", component: "OptimizedPerformanceTests")

        // Test standard transcription
        bench.startBenchmark("Standard_Comparison")

        do {
            let standardTranscriber = try SpeechTranscriber()

            // Use the correct async method
            _ = try await standardTranscriber.transcribe(audioFile: testAudioFile) { progress in
                // Progress updates from standard transcriber
                Logger.shared.debug("Standard progress: \(progress.formattedProgress)", component: "OptimizedPerformanceTests")
            }

            let standardResult = bench.endBenchmark("Standard_Comparison", audioDuration: testAudioFile.format.duration)

            // Test optimized transcription
            bench.startBenchmark("Optimized_Comparison")

            let optimizedEngine = OptimizedTranscriptionEngine()

            // Use completion-based API with async wrapper
            let optimizedResult = try await withCheckedThrowingContinuation { continuation in
                optimizedEngine.transcribeAudio(from: testAudioFile) { progress in
                    // Progress updates from optimized engine
                    Logger.shared.debug("Optimized progress: \(String(format: "%.1f", progress.currentProgress * 100))%", component: "OptimizedPerformanceTests")
                } completion: { result in
                    continuation.resume(with: result)
                }
            }

            let optimizedBenchmarkResult = bench.endBenchmark("Optimized_Comparison", audioDuration: testAudioFile.format.duration)

            // Compare results
            Logger.shared.info("Performance Comparison:", component: "OptimizedPerformanceTests")
            Logger.shared.info("Standard: \(String(format: "%.2f", standardResult.processingTime))s", component: "OptimizedPerformanceTests")
            Logger.shared.info("Optimized: \(String(format: "%.2f", optimizedBenchmarkResult.processingTime))s", component: "OptimizedPerformanceTests")

            let improvement = (standardResult.processingTime - optimizedBenchmarkResult.processingTime) / standardResult.processingTime
            Logger.shared.info("Improvement: \(String(format: "%.1f", improvement * 100))%", component: "OptimizedPerformanceTests")

            // Verify both transcriptions succeeded
            XCTAssertFalse(optimizedResult.text.isEmpty, "Optimized transcription should produce text")
            XCTAssertGreaterThan(optimizedResult.confidence, 0.0, "Optimized transcription should have confidence")

            // Optimized should be at least as good as standard
            XCTAssertLessThanOrEqual(optimizedBenchmarkResult.processingTime, standardResult.processingTime * 1.1, "Optimized should not be significantly slower")

            // Log detailed comparison
            Logger.shared.info("=== Detailed Comparison ===", component: "OptimizedPerformanceTests")
            Logger.shared.info("Standard Result:", component: "OptimizedPerformanceTests")
            Logger.shared.info("  Processing Time: \(String(format: "%.2f", standardResult.processingTime))s", component: "OptimizedPerformanceTests")
            Logger.shared.info("  Memory Peak: \(String(format: "%.1f", standardResult.memoryUsage.peakMB))MB", component: "OptimizedPerformanceTests")
            Logger.shared.info("  Efficiency Score: \(String(format: "%.1f", standardResult.efficiency.overallScore * 100))%", component: "OptimizedPerformanceTests")

            Logger.shared.info("Optimized Result:", component: "OptimizedPerformanceTests")
            Logger.shared.info("  Processing Time: \(String(format: "%.2f", optimizedBenchmarkResult.processingTime))s", component: "OptimizedPerformanceTests")
            Logger.shared.info("  Memory Peak: \(String(format: "%.1f", optimizedBenchmarkResult.memoryUsage.peakMB))MB", component: "OptimizedPerformanceTests")
            Logger.shared.info("  Efficiency Score: \(String(format: "%.1f", optimizedBenchmarkResult.efficiency.overallScore * 100))%", component: "OptimizedPerformanceTests")
        } catch {
            XCTFail("Performance comparison failed: \(error)")
        }
    }

    // MARK: - Thermal Management Tests

    func testThermalAdaptation() {
        guard let optimizer = platformOptimizer else {
            XCTFail("Platform optimizer not available")
            return
        }
        
        let currentThermalState = ProcessInfo.processInfo.thermalState
        let adaptedOptimization = optimizer.adjustForThermalState()

        Logger.shared.info("Thermal State: \(currentThermalState), Adapted Optimization: \(adaptedOptimization.rawValue)", component: "OptimizedPerformanceTests")

        switch currentThermalState {
        case .nominal:
            // No adaptation needed for nominal state
            break
        case .fair:
            // Should reduce optimization level if originally maximum
            break
        case .serious, .critical:
            XCTAssertEqual(adaptedOptimization, .conservative, "Should use conservative optimization under thermal pressure")
        @unknown default:
            XCTAssertEqual(adaptedOptimization, .conservative, "Should default to conservative for unknown thermal states")
        }
    }

    // MARK: - Helper Methods

    private func createTestAudioFile() -> AudioFile? {
        guard let generator = testFileGenerator,
              let testURL = generator.createSmallMP4File() else {
            return nil
        }

        // Extract audio first
        let audioProcessor = AudioProcessor()
        let expectation = XCTestExpectation(description: "Audio extraction")
        var audioFile: AudioFile?

        audioProcessor.extractAudio(from: testURL.path) { _ in
            // Progress
        } completion: { result in
            switch result {
            case .success(let extractedAudio):
                audioFile = extractedAudio
            case .failure:
                break
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
        return audioFile
    }
}
