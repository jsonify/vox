import XCTest
import Foundation
@testable import vox

/// Performance regression detection tests that validate against established baselines
final class PerformanceRegressionTests: XCTestCase {
    var benchmark: PerformanceBenchmark?
    var platformOptimizer: PlatformOptimizer?
    var testFileGenerator: TestAudioFileGenerator?
    
    override func setUp() {
        super.setUp()
        benchmark = PerformanceBenchmark.shared
        platformOptimizer = PlatformOptimizer.shared  
        testFileGenerator = TestAudioFileGenerator.shared
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        super.tearDown()
    }
    
    // MARK: - Core Performance Regression Tests
    
    func testStartupTimeRegression() {
        Logger.shared.info("=== Startup Time Regression Test ===", component: "PerformanceRegressionTests")
        
        let startTime = Date()
        
        // Measure time to initialize core components
        _ = AudioProcessor()
        _ = try? SpeechTranscriber()
        _ = OptimizedTranscriptionEngine()
        _ = TempFileManager.shared
        
        let initializationTime = Date().timeIntervalSince(startTime)
        
        Logger.shared.info("Startup time: \(String(format: "%.3f", initializationTime))s", component: "PerformanceRegressionTests")
        
        // Startup time should be < 2 seconds (from CLAUDE.md)
        XCTAssertLessThan(initializationTime, 2.0, "Application startup should be < 2 seconds")
        
        // Additional regression threshold
        XCTAssertLessThan(initializationTime, 1.0, "Startup time should be < 1 second for good UX")
    }
    
    func testMemoryLeakRegression() async throws {
        guard let bench = benchmark,
              let testFile = createTestAudioFile(duration: 5.0) else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== Memory Leak Regression Test ===", component: "PerformanceRegressionTests")
        
        let initialMemory = getCurrentMemoryUsage()
        let iterations = 5
        
        // Run multiple transcription cycles
        for i in 0..<iterations {
            bench.startBenchmark("Memory_Leak_Test_\(i)")
            
            let engine = OptimizedTranscriptionEngine()
            let expectation = XCTestExpectation(description: "Memory leak test \(i)")
            
            engine.transcribeAudio(from: testFile) { _ in
                // Progress
            } completion: { _ in
                let _ = bench.endBenchmark("Memory_Leak_Test_\(i)", audioDuration: testFile.format.duration)
                expectation.fulfill()
            }
            
            await fulfillment(of: [expectation], timeout: 15.0)
            
            // Force garbage collection
            autoreleasepool {
                // Empty pool to trigger cleanup
            }
            
            // Brief pause to allow cleanup
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryGrowth = finalMemory - initialMemory
        let memoryGrowthMB = Double(memoryGrowth) / (1024 * 1024)
        
        Logger.shared.info("Memory growth after \(iterations) iterations: \(String(format: "%.1f", memoryGrowthMB))MB", component: "PerformanceRegressionTests")
        
        // Memory growth should be minimal (< 50MB for 5 iterations)
        XCTAssertLessThan(memoryGrowthMB, 50.0, "Memory growth should be < 50MB after multiple iterations")
        
        // Stricter check for CI
        if ProcessInfo.processInfo.environment["CI"] != nil {
            XCTAssertLessThan(memoryGrowthMB, 25.0, "Memory growth should be < 25MB in CI environment")
        }
    }
    
    func testProcessingSpeedRegression() async throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer,
              let testFile = createTestAudioFile(duration: 30.0) else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== Processing Speed Regression Test ===", component: "PerformanceRegressionTests")
        
        // Load baseline performance data
        let baselineKey = "processing_speed_baseline_\(optimizer.architecture.rawValue)"
        let baseline = loadPerformanceBaseline(key: baselineKey)
        
        // Run current performance test
        let results = await bench.runComprehensiveBenchmark(audioFile: testFile)
        
        guard let currentResult = results.first(where: { $0.testName.contains("Standard") }) else {
            XCTFail("Should have standard benchmark result")
            return
        }
        
        Logger.shared.info("Current processing time: \(String(format: "%.2f", currentResult.processingTime))s", component: "PerformanceRegressionTests")
        
        if let baseline = baseline {
            let performanceRatio = currentResult.processingTime / baseline
            Logger.shared.info("Performance ratio vs baseline: \(String(format: "%.2f", performanceRatio))x", component: "PerformanceRegressionTests")
            
            // Should not regress by more than 20%
            XCTAssertLessThan(performanceRatio, 1.2, "Processing speed should not regress by > 20%")
            
            // Flag significant improvements for validation
            if performanceRatio < 0.8 {
                Logger.shared.info("⚠️  Significant performance improvement detected (\(String(format: "%.1f", (1.0 - performanceRatio) * 100))% faster)", component: "PerformanceRegressionTests")
            }
        }
        
        // Validate against absolute targets
        switch optimizer.architecture {
        case .appleSilicon:
            XCTAssertLessThan(currentResult.processingTime, 60.0, "Apple Silicon should process 30-min video in < 60s")
        case .intel:
            XCTAssertLessThan(currentResult.processingTime, 90.0, "Intel should process 30-min video in < 90s")
        case .unknown:
            XCTAssertLessThan(currentResult.processingTime, 120.0, "Unknown architecture should complete within 2 minutes")
        }
        
        // Save current result as new baseline
        savePerformanceBaseline(currentResult.processingTime, key: baselineKey)
    }
    
    func testConcurrentProcessingRegression() async throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== Concurrent Processing Regression Test ===", component: "PerformanceRegressionTests")
        
        // Create multiple test files
        var testFiles: [AudioFile] = []
        for _ in 0..<3 {
            if let file = createTestAudioFile(duration: 5.0) {
                testFiles.append(file)
            }
        }
        
        guard testFiles.count == 3 else {
            throw XCTSkip("Unable to create required test files")
        }
        
        bench.startBenchmark("Concurrent_Regression_Test")
        
        let startTime = Date()
        
        // Process files concurrently
        await withTaskGroup(of: Void.self) { group in
            for (index, testFile) in testFiles.enumerated() {
                group.addTask {
                    let engine = OptimizedTranscriptionEngine()
                    let expectation = XCTestExpectation(description: "Concurrent processing \(index)")
                    
                    engine.transcribeAudio(from: testFile) { _ in
                        // Progress
                    } completion: { _ in
                        expectation.fulfill()
                    }
                    
                    await self.fulfillment(of: [expectation], timeout: 30.0)
                }
            }
        }
        
        let concurrentTime = Date().timeIntervalSince(startTime)
        let benchmarkResult = bench.endBenchmark("Concurrent_Regression_Test", audioDuration: 15.0) // 3 x 5-second files
        
        Logger.shared.info("Concurrent processing time: \(String(format: "%.2f", concurrentTime))s", component: "PerformanceRegressionTests")
        Logger.shared.info("Concurrency efficiency: \(String(format: "%.1f", benchmarkResult.efficiency.concurrencyUtilization * 100))%", component: "PerformanceRegressionTests")
        
        // Concurrent processing should be faster than sequential
        let sequentialEstimate = 15.0 * 2.0 // Assume 2x real-time for sequential
        XCTAssertLessThan(concurrentTime, sequentialEstimate, "Concurrent processing should be faster than sequential")
        
        // Should utilize multiple cores effectively
        XCTAssertGreaterThan(benchmarkResult.efficiency.concurrencyUtilization, 0.5, "Should utilize concurrency effectively")
        
        // Architecture-specific expectations
        switch optimizer.architecture {
        case .appleSilicon:
            XCTAssertGreaterThan(benchmarkResult.efficiency.concurrencyUtilization, 0.7, "Apple Silicon should excel at concurrent processing")
        case .intel:
            XCTAssertGreaterThan(benchmarkResult.efficiency.concurrencyUtilization, 0.5, "Intel should handle concurrent processing well")
        case .unknown:
            XCTAssertGreaterThan(benchmarkResult.efficiency.concurrencyUtilization, 0.3, "Unknown architecture should show some concurrency")
        }
    }
    
    func testThermalImpactRegression() async throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer,
              let testFile = createTestAudioFile(duration: 15.0) else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== Thermal Impact Regression Test ===", component: "PerformanceRegressionTests")
        
        let initialThermalState = ProcessInfo.processInfo.thermalState
        Logger.shared.info("Initial thermal state: \(initialThermalState)", component: "PerformanceRegressionTests")
        
        // Run intensive processing
        let results = await bench.runComprehensiveBenchmark(audioFile: testFile)
        
        let finalThermalState = ProcessInfo.processInfo.thermalState
        Logger.shared.info("Final thermal state: \(finalThermalState)", component: "PerformanceRegressionTests")
        
        // Check thermal impact from results
        if let thermalResult = results.first {
            Logger.shared.info("Thermal impact: \(thermalResult.thermalImpact.thermalImpact)", component: "PerformanceRegressionTests")
            Logger.shared.info("Thermal pressure time: \(String(format: "%.1f", thermalResult.thermalImpact.thermalPressureSeconds))s", component: "PerformanceRegressionTests")
            
            // Should not cause significant thermal pressure
            XCTAssertLessThan(thermalResult.thermalImpact.thermalPressureSeconds, 5.0, "Should not cause > 5s of thermal pressure")
            
            // Should not increase thermal state significantly
            XCTAssertLessThanOrEqual(thermalResult.thermalImpact.finalState.rawValue, initialThermalState.rawValue + 1, "Should not increase thermal state significantly")
        }
        
        // Architecture-specific thermal expectations
        switch optimizer.architecture {
        case .appleSilicon:
            // Apple Silicon should be more thermally efficient
            XCTAssertLessThanOrEqual(finalThermalState.rawValue, ProcessInfo.ThermalState.fair.rawValue, "Apple Silicon should maintain good thermal state")
        case .intel:
            // Intel may run warmer but should still be manageable
            XCTAssertLessThanOrEqual(finalThermalState.rawValue, ProcessInfo.ThermalState.serious.rawValue, "Intel should not reach critical thermal state")
        case .unknown:
            // Conservative check for unknown architectures
            XCTAssertLessThan(finalThermalState.rawValue, ProcessInfo.ThermalState.critical.rawValue, "Should not reach critical thermal state")
        }
    }
    
    // MARK: - CI-Specific Regression Tests
    
    func testCIPerformanceBaseline() async throws {
        // Only run in CI environment
        guard ProcessInfo.processInfo.environment["CI"] != nil else {
            throw XCTSkip("CI-specific test - skipping in local environment")
        }
        
        guard let bench = benchmark,
              let optimizer = platformOptimizer,
              let testFile = createTestAudioFile(duration: 10.0) else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== CI Performance Baseline Test ===", component: "PerformanceRegressionTests")
        Logger.shared.info("CI Environment: \(ProcessInfo.processInfo.environment["CI"] ?? "unknown")", component: "PerformanceRegressionTests")
        Logger.shared.info("GitHub Actions: \(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] ?? "false")", component: "PerformanceRegressionTests")
        
        // Run standard benchmark
        let results = await bench.runComprehensiveBenchmark(audioFile: testFile)
        
        guard let result = results.first else {
            XCTFail("Should have benchmark result")
            return
        }
        
        // CI-specific performance expectations (more lenient due to virtualization)
        let ciProcessingTimeLimit = optimizer.architecture == .appleSilicon ? 30.0 : 45.0
        XCTAssertLessThan(result.processingTime, ciProcessingTimeLimit, "CI processing time should be within expected limits")
        
        // Memory usage should be reasonable in CI
        XCTAssertLessThan(result.memoryUsage.peakMB, 2048.0, "CI memory usage should be < 2GB")
        
        // Log CI-specific metrics
        Logger.shared.info("CI Performance Metrics:", component: "PerformanceRegressionTests")
        Logger.shared.info("  Processing Time: \(String(format: "%.2f", result.processingTime))s", component: "PerformanceRegressionTests")
        Logger.shared.info("  Memory Peak: \(String(format: "%.1f", result.memoryUsage.peakMB))MB", component: "PerformanceRegressionTests")
        Logger.shared.info("  Efficiency Score: \(String(format: "%.1f", result.efficiency.overallScore * 100))%", component: "PerformanceRegressionTests")
        
        // Export metrics for CI analysis
        exportCIMetrics(result, architecture: optimizer.architecture)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile(duration: TimeInterval) -> AudioFile? {
        guard let generator = testFileGenerator,
              let testURL = generator.createMockMP4File(duration: duration) else {
            return nil
        }
        
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
        
        let waiter = XCTWaiter()
        _ = waiter.wait(for: [expectation], timeout: 30.0)
        return audioFile
    }
    
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
    
    private func loadPerformanceBaseline(key: String) -> TimeInterval? {
        let baselineFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("baselines")
            .appendingPathComponent("\(key).json")
        
        guard let data = try? Data(contentsOf: baselineFile),
              let baseline = try? JSONDecoder().decode(TimeInterval.self, from: data) else {
            Logger.shared.info("No baseline found for key: \(key)", component: "PerformanceRegressionTests")
            return nil
        }
        
        return baseline
    }
    
    private func savePerformanceBaseline(_ value: TimeInterval, key: String) {
        let baselinesDir = FileManager.default.temporaryDirectory.appendingPathComponent("baselines")
        let baselineFile = baselinesDir.appendingPathComponent("\(key).json")
        
        do {
            try FileManager.default.createDirectory(at: baselinesDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: baselineFile)
            Logger.shared.info("Saved baseline for key: \(key) = \(String(format: "%.2f", value))s", component: "PerformanceRegressionTests")
        } catch {
            Logger.shared.error("Failed to save baseline for key \(key): \(error)", component: "PerformanceRegressionTests")
        }
    }
    
    private func exportCIMetrics(_ result: PerformanceBenchmark.BenchmarkResult, architecture: PlatformOptimizer.Architecture) {
        let metrics = [
            "architecture": architecture.rawValue,
            "processing_time": String(format: "%.2f", result.processingTime),
            "memory_peak_mb": String(format: "%.1f", result.memoryUsage.peakMB),
            "efficiency_score": String(format: "%.3f", result.efficiency.overallScore),
            "processing_ratio": String(format: "%.2f", result.processingRatio),
            "timestamp": ISO8601DateFormatter().string(from: result.timestamp)
        ]
        
        // Export as JSON for CI analysis
        let ciMetricsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ci_performance_metrics.json")
        
        do {
            let data = try JSONSerialization.data(withJSONObject: metrics, options: .prettyPrinted)
            try data.write(to: ciMetricsFile)
            Logger.shared.info("CI metrics exported to: \(ciMetricsFile.path)", component: "PerformanceRegressionTests")
        } catch {
            Logger.shared.error("Failed to export CI metrics: \(error)", component: "PerformanceRegressionTests")
        }
        
        // Also export as environment variables for GitHub Actions
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            let githubEnvFile = ProcessInfo.processInfo.environment["GITHUB_ENV"]
            if let envFile = githubEnvFile {
                let envContent = """
                VOX_PROCESSING_TIME=\(String(format: "%.2f", result.processingTime))
                VOX_MEMORY_PEAK_MB=\(String(format: "%.1f", result.memoryUsage.peakMB))
                VOX_EFFICIENCY_SCORE=\(String(format: "%.3f", result.efficiency.overallScore))
                VOX_ARCHITECTURE=\(architecture.rawValue)
                """
                
                do {
                    try envContent.write(toFile: envFile, atomically: true, encoding: .utf8)
                    Logger.shared.info("GitHub Actions environment variables exported", component: "PerformanceRegressionTests")
                } catch {
                    Logger.shared.error("Failed to export GitHub Actions environment: \(error)", component: "PerformanceRegressionTests")
                }
            }
        }
    }
}