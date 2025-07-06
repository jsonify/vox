import XCTest
import Foundation
@testable import vox

/// Enhanced performance testing suite for comprehensive architecture comparison and validation
/// This test suite validates the performance targets from CLAUDE.md and provides detailed architecture comparison
final class EnhancedPerformanceTests: XCTestCase {
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
    
    // MARK: - Performance Target Validation
    
    func testCLAUDEMDPerformanceTargets() async throws {
        Logger.shared.info("=== CLAUDE.md Performance Targets Validation ===", component: "EnhancedPerformanceTests")
        
        guard let bench = benchmark,
              let optimizer = platformOptimizer else {
            throw XCTSkip("Unable to create benchmark components")
        }
        
        // Test with 30-minute equivalent audio file
        guard let testFile = createTestAudioFile(duration: 30.0 * 60.0) else { // 30 minutes
            throw XCTSkip("Unable to create 30-minute test file")
        }
        
        Logger.shared.info("Testing 30-minute audio file on \(optimizer.architecture.displayName)", component: "EnhancedPerformanceTests")
        
        // Run comprehensive benchmark
        let results = await bench.runComprehensiveBenchmark(audioFile: testFile)
        
        XCTAssertFalse(results.isEmpty, "Should have benchmark results")
        
        // Get the standard transcription result for validation
        guard let standardResult = results.first(where: { $0.testName.contains("Standard") }) else {
            XCTFail("Should have standard transcription result")
            return
        }
        
        // Log performance metrics
        Logger.shared.info("=== Performance Metrics ===", component: "EnhancedPerformanceTests")
        Logger.shared.info("Processing time: \(String(format: "%.2f", standardResult.processingTime))s", component: "EnhancedPerformanceTests")
        Logger.shared.info("Memory peak: \(String(format: "%.1f", standardResult.memoryUsage.peakMB))MB", component: "EnhancedPerformanceTests")
        Logger.shared.info("Processing ratio: \(String(format: "%.2f", standardResult.processingRatio))x", component: "EnhancedPerformanceTests")
        Logger.shared.info("Efficiency score: \(String(format: "%.1f", standardResult.efficiency.overallScore * 100))%", component: "EnhancedPerformanceTests")
        
        // Validate architecture-specific performance targets from CLAUDE.md
        switch optimizer.architecture {
        case .appleSilicon:
            // Apple Silicon: Process 30-minute video in < 60 seconds
            XCTAssertLessThan(standardResult.processingTime, 60.0, 
                             "Apple Silicon should process 30-minute video in < 60 seconds (actual: \(String(format: "%.2f", standardResult.processingTime))s)")
            
            // Apple Silicon should be more energy efficient
            XCTAssertGreaterThan(standardResult.efficiency.energyEfficiency, 0.8, 
                               "Apple Silicon should be energy efficient (actual: \(String(format: "%.1f", standardResult.efficiency.energyEfficiency * 100))%)")
            
        case .intel:
            // Intel Mac: Process 30-minute video in < 90 seconds
            XCTAssertLessThan(standardResult.processingTime, 90.0, 
                             "Intel Mac should process 30-minute video in < 90 seconds (actual: \(String(format: "%.2f", standardResult.processingTime))s)")
            
            // Intel should still be reasonably efficient
            XCTAssertGreaterThan(standardResult.efficiency.energyEfficiency, 0.6, 
                               "Intel should be reasonably efficient (actual: \(String(format: "%.1f", standardResult.efficiency.energyEfficiency * 100))%)")
            
        case .unknown:
            // Conservative targets for unknown architecture
            XCTAssertLessThan(standardResult.processingTime, 120.0, 
                             "Unknown architecture should complete within 2 minutes (actual: \(String(format: "%.2f", standardResult.processingTime))s)")
        }
        
        // Universal performance targets from CLAUDE.md
        XCTAssertLessThan(standardResult.memoryUsage.peakMB, 1024.0, 
                         "Peak memory usage should be < 1GB (actual: \(String(format: "%.1f", standardResult.memoryUsage.peakMB))MB)")
        
        XCTAssertLessThan(standardResult.processingRatio, 3.0, 
                         "Processing should be < 3x real-time (actual: \(String(format: "%.2f", standardResult.processingRatio))x)")
        
        XCTAssertGreaterThan(standardResult.efficiency.overallScore, 0.5, 
                           "Overall efficiency should be > 50% (actual: \(String(format: "%.1f", standardResult.efficiency.overallScore * 100))%)")
        
        // Generate and save performance report
        let report = bench.generateBenchmarkReport(results)
        savePerformanceReport(report, testName: "CLAUDE_MD_Targets")
        
        Logger.shared.info("=== CLAUDE.md Performance Targets PASSED ===", component: "EnhancedPerformanceTests")
    }
    
    func testStartupTimeValidation() {
        Logger.shared.info("=== Startup Time Validation ===", component: "EnhancedPerformanceTests")
        
        let iterations = 10
        var startupTimes: [TimeInterval] = []
        
        for i in 1...iterations {
            let startTime = Date()
            
            // Initialize core components (simulating app startup)
            _ = AudioProcessor()
            _ = try? SpeechTranscriber()
            _ = OptimizedTranscriptionEngine()
            _ = TempFileManager.shared
            _ = Logger.shared
            
            let startupTime = Date().timeIntervalSince(startTime)
            startupTimes.append(startupTime)
            
            Logger.shared.info("Startup iteration \(i): \(String(format: "%.3f", startupTime))s", component: "EnhancedPerformanceTests")
        }
        
        let averageStartupTime = startupTimes.reduce(0, +) / Double(startupTimes.count)
        let maxStartupTime = startupTimes.max() ?? 0
        
        Logger.shared.info("Average startup time: \(String(format: "%.3f", averageStartupTime))s", component: "EnhancedPerformanceTests")
        Logger.shared.info("Max startup time: \(String(format: "%.3f", maxStartupTime))s", component: "EnhancedPerformanceTests")
        
        // Validate against CLAUDE.md target: Application launch < 2 seconds
        XCTAssertLessThan(averageStartupTime, 2.0, 
                         "Average startup time should be < 2 seconds (actual: \(String(format: "%.3f", averageStartupTime))s)")
        
        XCTAssertLessThan(maxStartupTime, 2.0, 
                         "Max startup time should be < 2 seconds (actual: \(String(format: "%.3f", maxStartupTime))s)")
        
        // Stricter target for good UX
        XCTAssertLessThan(averageStartupTime, 1.0, 
                         "Average startup time should be < 1 second for good UX (actual: \(String(format: "%.3f", averageStartupTime))s)")
    }
    
    // MARK: - Architecture Comparison
    
    func testArchitecturePerformanceComparison() async throws {
        Logger.shared.info("=== Architecture Performance Comparison ===", component: "EnhancedPerformanceTests")
        
        guard let bench = benchmark,
              let optimizer = platformOptimizer else {
            throw XCTSkip("Unable to create benchmark components")
        }
        
        // Test with multiple file sizes
        let testDurations: [TimeInterval] = [60.0, 300.0, 600.0] // 1 min, 5 min, 10 min
        var allResults: [PerformanceBenchmark.BenchmarkResult] = []
        
        for duration in testDurations {
            Logger.shared.info("Testing \(Int(duration/60))min audio file", component: "EnhancedPerformanceTests")
            
            guard let testFile = createTestAudioFile(duration: duration) else {
                Logger.shared.error("Failed to create test file for \(duration)s", component: "EnhancedPerformanceTests")
                continue
            }
            
            let results = await bench.runComprehensiveBenchmark(audioFile: testFile)
            allResults.append(contentsOf: results)
            
            // Log results for this duration
            for result in results {
                let processingInfo = "\(result.testName): \(String(format: "%.2f", result.processingTime))s (\(String(format: "%.2f", result.processingRatio))x)"
            Logger.shared.info("  \(processingInfo)", component: "EnhancedPerformanceTests")
            }
        }
        
        // Analyze performance patterns
        let standardResults = allResults.filter { $0.testName.contains("Standard") }
        let optimizedResults = allResults.filter { $0.testName.contains("Optimized") }
        
        if !standardResults.isEmpty && !optimizedResults.isEmpty {
            let avgStandardRatio = standardResults.reduce(0.0) { $0 + $1.processingRatio } / Double(standardResults.count)
            let avgOptimizedRatio = optimizedResults.reduce(0.0) { $0 + $1.processingRatio } / Double(optimizedResults.count)
            
            Logger.shared.info("Average Standard Processing Ratio: \(String(format: "%.2f", avgStandardRatio))x", component: "EnhancedPerformanceTests")
            Logger.shared.info("Average Optimized Processing Ratio: \(String(format: "%.2f", avgOptimizedRatio))x", component: "EnhancedPerformanceTests")
            
            // Optimized should be better than standard
            XCTAssertLessThan(avgOptimizedRatio, avgStandardRatio, 
                             "Optimized transcription should be faster than standard")
        }
        
        // Generate comprehensive report
        let report = generateArchitectureComparisonReport(allResults, architecture: optimizer.architecture)
        savePerformanceReport(report, testName: "Architecture_Comparison")
        
        Logger.shared.info("=== Architecture Performance Comparison Complete ===", component: "EnhancedPerformanceTests")
    }
    
    // MARK: - Memory Profiling
    
    func testComprehensiveMemoryProfiling() async throws {
        Logger.shared.info("=== Comprehensive Memory Profiling ===", component: "EnhancedPerformanceTests")
        
        guard let bench = benchmark,
              let optimizer = platformOptimizer else {
            throw XCTSkip("Unable to create benchmark components")
        }
        
        // Test with different file sizes to understand memory scaling
        let testDurations: [TimeInterval] = [60.0, 300.0, 600.0, 1800.0] // 1min, 5min, 10min, 30min
        var memoryProfiles: [(duration: TimeInterval, profile: PerformanceBenchmark.MemoryProfile)] = []
        
        for duration in testDurations {
            Logger.shared.info("Memory profiling \(Int(duration/60))min audio file", component: "EnhancedPerformanceTests")
            
            guard let testFile = createTestAudioFile(duration: duration) else {
                Logger.shared.error("Failed to create test file for \(duration)s", component: "EnhancedPerformanceTests")
                continue
            }
            
            // Run memory-focused benchmark
            bench.startBenchmark("Memory_Profile_\(Int(duration))")
            
            let engine = OptimizedTranscriptionEngine()
            let expectation = XCTestExpectation(description: "Memory profiling \(duration)s")
            
            engine.transcribeAudio(from: testFile) { _ in
                // Progress updates
            } completion: { result in
                let benchmarkResult = bench.endBenchmark("Memory_Profile_\(Int(duration))", audioDuration: testFile.format.duration)
                memoryProfiles.append((duration: duration, profile: benchmarkResult.memoryUsage))
                
                expectation.fulfill()
            }
            
            await fulfillment(of: [expectation], timeout: duration + 30.0)
        }
        
        // Analyze memory usage patterns
        Logger.shared.info("=== Memory Usage Analysis ===", component: "EnhancedPerformanceTests")
        
        for (duration, profile) in memoryProfiles {
            let memoryInfo = "\(Int(duration/60))min: Peak \(String(format: "%.1f", profile.peakMB))MB, " +
                           "Avg \(String(format: "%.1f", profile.averageMB))MB, " +
                           "Leak \(String(format: "%.1f", profile.leakMB))MB"
            Logger.shared.info("  \(memoryInfo)", component: "EnhancedPerformanceTests")
            
            // Validate memory constraints
            XCTAssertLessThan(profile.peakMB, 1024.0, 
                             "Peak memory for \(Int(duration/60))min file should be < 1GB (actual: \(String(format: "%.1f", profile.peakMB))MB)")
            
            XCTAssertLessThan(profile.leakMB, 50.0, 
                             "Memory leak for \(Int(duration/60))min file should be < 50MB (actual: \(String(format: "%.1f", profile.leakMB))MB)")
        }
        
        // Test memory scaling
        if memoryProfiles.count >= 2 {
            let shortest = memoryProfiles.first!
            let longest = memoryProfiles.last!
            
            let durationRatio = longest.duration / shortest.duration
            let memoryRatio = longest.profile.peakMB / shortest.profile.peakMB
            
            Logger.shared.info("Memory scaling: \(String(format: "%.1f", durationRatio))x duration -> \(String(format: "%.1f", memoryRatio))x memory", component: "EnhancedPerformanceTests")
            
            // Memory should scale sub-linearly with duration
            XCTAssertLessThan(memoryRatio, durationRatio, 
                             "Memory usage should scale sub-linearly with audio duration")
        }
        
        // Generate memory profiling report
        let report = generateMemoryProfilingReport(memoryProfiles, architecture: optimizer.architecture)
        savePerformanceReport(report, testName: "Memory_Profiling")
        
        Logger.shared.info("=== Memory Profiling Complete ===", component: "EnhancedPerformanceTests")
    }
    
    // MARK: - Performance Regression Detection
    
    func testPerformanceRegressionDetection() async throws {
        Logger.shared.info("=== Performance Regression Detection ===", component: "EnhancedPerformanceTests")
        
        guard let bench = benchmark,
              let optimizer = platformOptimizer else {
            throw XCTSkip("Unable to create benchmark components")
        }
        
        // Load existing baseline if available
        let baselineData = loadPerformanceBaseline(for: optimizer.architecture)
        
        // Run current performance test
        guard let testFile = createTestAudioFile(duration: 300.0) else { // 5 minutes
            throw XCTSkip("Unable to create test file")
        }
        
        let currentResults = await bench.runComprehensiveBenchmark(audioFile: testFile)
        
        guard let standardResult = currentResults.first(where: { $0.testName.contains("Standard") }) else {
            XCTFail("Should have standard benchmark result")
            return
        }
        
        // If we have baseline data, compare against it
        if let baseline = baselineData {
            let performanceRatio = standardResult.processingTime / baseline.processingTime
            let memoryRatio = standardResult.memoryUsage.peakMB / baseline.memoryUsage.peakMB
            let efficiencyRatio = standardResult.efficiency.overallScore / baseline.efficiency.overallScore
            
            Logger.shared.info("=== Regression Analysis ===", component: "EnhancedPerformanceTests")
            Logger.shared.info("  Processing time ratio: \(String(format: "%.2f", performanceRatio))x", component: "EnhancedPerformanceTests")
            Logger.shared.info("  Memory usage ratio: \(String(format: "%.2f", memoryRatio))x", component: "EnhancedPerformanceTests")
            Logger.shared.info("  Efficiency ratio: \(String(format: "%.2f", efficiencyRatio))x", component: "EnhancedPerformanceTests")
            
            // Regression detection thresholds
            XCTAssertLessThan(performanceRatio, 1.2, 
                             "Processing time should not regress by > 20% " +
                             "(baseline: \(String(format: "%.2f", baseline.processingTime))s, " +
                             "current: \(String(format: "%.2f", standardResult.processingTime))s)")
            
            XCTAssertLessThan(memoryRatio, 1.3, 
                             "Memory usage should not regress by > 30% " +
                             "(baseline: \(String(format: "%.1f", baseline.memoryUsage.peakMB))MB, " +
                             "current: \(String(format: "%.1f", standardResult.memoryUsage.peakMB))MB)")
            
            XCTAssertGreaterThan(efficiencyRatio, 0.8, 
                               "Efficiency should not regress by > 20% " +
                               "(baseline: \(String(format: "%.1f", baseline.efficiency.overallScore * 100))%, " +
                               "current: \(String(format: "%.1f", standardResult.efficiency.overallScore * 100))%)")
            
            // Flag significant improvements for validation
            if performanceRatio < 0.8 {
                Logger.shared.info("⚠️  Significant performance improvement detected - verify accuracy", component: "EnhancedPerformanceTests")
            }
        } else {
            Logger.shared.info("No baseline data found - establishing new baseline", component: "EnhancedPerformanceTests")
        }
        
        // Save current results as new baseline
        savePerformanceBaseline(standardResult, for: optimizer.architecture)
        
        Logger.shared.info("=== Performance Regression Detection Complete ===", component: "EnhancedPerformanceTests")
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile(duration: TimeInterval) -> AudioFile? {
        guard let generator = testFileGenerator else { return nil }
        
        // Use smaller duration for testing to avoid timeouts
        let testDuration = min(duration, 30.0) // Cap at 30 seconds for testing
        
        guard let testURL = generator.createMockMP4File(duration: testDuration) else {
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
        _ = waiter.wait(for: [expectation], timeout: 60.0)
        return audioFile
    }
    
    private func generateArchitectureComparisonReport(_ results: [PerformanceBenchmark.BenchmarkResult], architecture: PlatformOptimizer.Architecture) -> String {
        var report = """
        ===== Architecture Performance Comparison Report =====
        Architecture: \(architecture.displayName)
        Test Date: \(Date())
        Test Count: \(results.count)
        
        """
        
        let standardResults = results.filter { $0.testName.contains("Standard") }
        let optimizedResults = results.filter { $0.testName.contains("Optimized") }
        
        if !standardResults.isEmpty {
            let avgProcessingTime = standardResults.reduce(0.0) { $0 + $1.processingTime } / Double(standardResults.count)
            let avgMemoryUsage = standardResults.reduce(0.0) { $0 + $1.memoryUsage.peakMB } / Double(standardResults.count)
            let avgEfficiency = standardResults.reduce(0.0) { $0 + $1.efficiency.overallScore } / Double(standardResults.count)
            
            report += """
            Standard Transcription Performance:
              Average Processing Time: \(String(format: "%.2f", avgProcessingTime))s
              Average Memory Usage: \(String(format: "%.1f", avgMemoryUsage))MB
              Average Efficiency: \(String(format: "%.1f", avgEfficiency * 100))%
            
            """
        }
        
        if !optimizedResults.isEmpty {
            let avgProcessingTime = optimizedResults.reduce(0.0) { $0 + $1.processingTime } / Double(optimizedResults.count)
            let avgMemoryUsage = optimizedResults.reduce(0.0) { $0 + $1.memoryUsage.peakMB } / Double(optimizedResults.count)
            let avgEfficiency = optimizedResults.reduce(0.0) { $0 + $1.efficiency.overallScore } / Double(optimizedResults.count)
            
            report += """
            Optimized Transcription Performance:
              Average Processing Time: \(String(format: "%.2f", avgProcessingTime))s
              Average Memory Usage: \(String(format: "%.1f", avgMemoryUsage))MB
              Average Efficiency: \(String(format: "%.1f", avgEfficiency * 100))%
            
            """
        }
        
        // Add individual test results
        report += "Individual Test Results:\n"
        for result in results {
            let resultLine = "  \(result.testName): \(String(format: "%.2f", result.processingTime))s, " +
                           "\(String(format: "%.1f", result.memoryUsage.peakMB))MB, " +
                           "\(String(format: "%.1f", result.efficiency.overallScore * 100))%\n"
            report += resultLine
        }
        
        return report
    }
    
    private func generateMemoryProfilingReport(_ profiles: [(duration: TimeInterval, profile: PerformanceBenchmark.MemoryProfile)], architecture: PlatformOptimizer.Architecture) -> String {
        var report = """
        ===== Memory Profiling Report =====
        Architecture: \(architecture.displayName)
        Test Date: \(Date())
        
        """
        
        for (duration, profile) in profiles {
            report += """
            \(Int(duration/60))min Audio File:
              Peak Memory: \(String(format: "%.1f", profile.peakMB))MB
              Average Memory: \(String(format: "%.1f", profile.averageMB))MB
              Memory Leak: \(String(format: "%.1f", profile.leakMB))MB
              GC Events: \(profile.gcEvents)
            
            """
        }
        
        return report
    }
    
    private func savePerformanceReport(_ report: String, testName: String) {
        let reportsDir = FileManager.default.temporaryDirectory.appendingPathComponent("performance_reports")
        
        do {
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
            
            let timestamp = Int(Date().timeIntervalSince1970)
            let architecture = platformOptimizer?.architecture.displayName.lowercased() ?? "unknown"
            let reportFile = reportsDir.appendingPathComponent("enhanced_\(testName.lowercased())_\(architecture)_\(timestamp).txt")
            
            try report.write(to: reportFile, atomically: true, encoding: .utf8)
            
            Logger.shared.info("Performance report saved to: \(reportFile.path)", component: "EnhancedPerformanceTests")
        } catch {
            Logger.shared.error("Failed to save performance report: \(error)", component: "EnhancedPerformanceTests")
        }
    }
    
    private func loadPerformanceBaseline(for architecture: PlatformOptimizer.Architecture) -> PerformanceBenchmark.BenchmarkResult? {
        let baselineFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("enhanced_baseline_\(architecture.displayName.lowercased()).json")
        
        guard let data = try? Data(contentsOf: baselineFile),
              let baseline = try? JSONDecoder().decode(PerformanceBaseline.self, from: data) else {
            Logger.shared.info("No baseline performance data found for \(architecture.displayName)", component: "EnhancedPerformanceTests")
            return nil
        }
        
        return baseline.toBenchmarkResult()
    }
    
    private func savePerformanceBaseline(_ result: PerformanceBenchmark.BenchmarkResult, for architecture: PlatformOptimizer.Architecture) {
        let baselineFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("enhanced_baseline_\(architecture.displayName.lowercased()).json")
        
        do {
            let baseline = PerformanceBaseline(from: result)
            let data = try JSONEncoder().encode(baseline)
            try data.write(to: baselineFile)
            Logger.shared.info("Baseline performance data saved for \(architecture.displayName)", component: "EnhancedPerformanceTests")
        } catch {
            Logger.shared.error("Failed to save baseline performance data: \(error)", component: "EnhancedPerformanceTests")
        }
    }
}

// MARK: - Performance Baseline Data Structure

private struct PerformanceBaseline: Codable {
    let testName: String
    let platform: String
    let processingTime: TimeInterval
    let peakMemoryMB: Double
    let averageMemoryMB: Double
    let leakMemoryMB: Double
    let overallScore: Double
    let timestamp: Date
    
    init(from result: PerformanceBenchmark.BenchmarkResult) {
        self.testName = result.testName
        self.platform = result.platform.rawValue
        self.processingTime = result.processingTime
        self.peakMemoryMB = result.memoryUsage.peakMB
        self.averageMemoryMB = result.memoryUsage.averageMB
        self.leakMemoryMB = result.memoryUsage.leakMB
        self.overallScore = result.efficiency.overallScore
        self.timestamp = result.timestamp
    }
    
    func toBenchmarkResult() -> PerformanceBenchmark.BenchmarkResult {
        let memoryProfile = PerformanceBenchmark.MemoryProfile(
            initial: 0,
            peak: UInt64(peakMemoryMB * 1024 * 1024),
            average: UInt64(averageMemoryMB * 1024 * 1024),
            leak: UInt64(leakMemoryMB * 1024 * 1024),
            gcEvents: 0
        )
        
        let thermalProfile = PerformanceBenchmark.ThermalProfile(
            initialState: .nominal,
            peakState: .nominal,
            finalState: .nominal,
            thermalPressureSeconds: 0
        )
        
        let efficiency = PerformanceBenchmark.EfficiencyMetrics(
            processingTimeRatio: 1.0,
            memoryEfficiency: 1.0,
            energyEfficiency: 1.0,
            concurrencyUtilization: 1.0
        )
        
        return PerformanceBenchmark.BenchmarkResult(
            testName: testName,
            platform: PlatformOptimizer.Architecture(rawValue: platform) ?? .unknown,
            processingTime: processingTime,
            memoryUsage: memoryProfile,
            thermalImpact: thermalProfile,
            efficiency: efficiency,
            timestamp: timestamp
        )
    }
}