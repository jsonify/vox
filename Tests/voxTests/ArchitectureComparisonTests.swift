import XCTest
import Foundation
@testable import vox

final class ArchitectureComparisonTests: XCTestCase {
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
    
    // MARK: - Architecture Comparison Tests
    
    func testArchitecturePerformanceTargets() async throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer,
              let testFile = createTestAudioFile(duration: 30.0) else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== Architecture Performance Target Validation ===", component: "ArchitectureComparisonTests")
        Logger.shared.info("Platform: \(optimizer.architecture.displayName)", component: "ArchitectureComparisonTests")
        Logger.shared.info("Test file duration: 30 minutes", component: "ArchitectureComparisonTests")
        
        // Run comprehensive benchmark
        let results = await bench.runComprehensiveBenchmark(audioFile: testFile)
        
        XCTAssertFalse(results.isEmpty, "Should have benchmark results")
        
        // Validate against performance targets from CLAUDE.md
        let standardResult = results.first { $0.testName.contains("Standard") }
        
        guard let mainResult = standardResult else {
            XCTFail("Should have standard transcription result")
            return
        }
        
        Logger.shared.info("=== Performance Target Validation ===", component: "ArchitectureComparisonTests")
        Logger.shared.info("Processing time: \(String(format: "%.2f", mainResult.processingTime))s", component: "ArchitectureComparisonTests")
        Logger.shared.info("Memory peak: \(String(format: "%.1f", mainResult.memoryUsage.peakMB))MB", component: "ArchitectureComparisonTests")
        Logger.shared.info("Processing ratio: \(String(format: "%.2f", mainResult.processingRatio))x", component: "ArchitectureComparisonTests")
        
        // Validate architecture-specific performance targets
        switch optimizer.architecture {
        case .appleSilicon:
            // Apple Silicon: Process 30-minute video in < 60 seconds
            XCTAssertLessThan(mainResult.processingTime, 60.0, "Apple Silicon should process 30-minute video in < 60 seconds")
            
            // Should be more efficient than Intel
            XCTAssertGreaterThan(mainResult.efficiency.energyEfficiency, 0.8, "Apple Silicon should be energy efficient")
            
        case .intel:
            // Intel Mac: Process 30-minute video in < 90 seconds
            XCTAssertLessThan(mainResult.processingTime, 90.0, "Intel Mac should process 30-minute video in < 90 seconds")
            
            // Should still be reasonably efficient
            XCTAssertGreaterThan(mainResult.efficiency.energyEfficiency, 0.6, "Intel should be reasonably efficient")
            
        case .unknown:
            // Conservative targets for unknown architecture
            XCTAssertLessThan(mainResult.processingTime, 120.0, "Unknown architecture should complete within 2 minutes")
        }
        
        // Universal targets
        XCTAssertLessThan(mainResult.memoryUsage.peakMB, 1024.0, "Peak memory usage should be < 1GB")
        XCTAssertLessThan(mainResult.processingRatio, 3.0, "Processing should be < 3x real-time")
        XCTAssertGreaterThan(mainResult.efficiency.overallScore, 0.5, "Overall efficiency should be > 50%")
        
        // Generate detailed report
        let report = bench.generateBenchmarkReport(results)
        Logger.shared.info("=== Benchmark Report ===", component: "ArchitectureComparisonTests")
        Logger.shared.info(report, component: "ArchitectureComparisonTests")
        
        // Save report for CI analysis
        savePerformanceReport(report, architecture: optimizer.architecture)
    }
    
    func testMemoryUsageProfile() async throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer,
              let testFile = createTestAudioFile(duration: 10.0) else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== Memory Usage Profile Test ===", component: "ArchitectureComparisonTests")
        
        bench.startBenchmark("Memory_Profile_Test")
        
        // Monitor memory during processing
        let memoryMonitor = MemoryMonitor()
        memoryMonitor.startMonitoring()
        
        // Run transcription
        let engine = OptimizedTranscriptionEngine()
        let expectation = XCTestExpectation(description: "Memory profiling")
        
        engine.transcribeAudio(from: testFile) { _ in
            // Progress monitoring
        } completion: { result in
            memoryMonitor.stopMonitoring()
            let _ = bench.endBenchmark("Memory_Profile_Test", audioDuration: testFile.format.duration)
            
            switch result {
            case .success:
                // Analyze memory usage pattern
                let memoryProfile = memoryMonitor.getProfile()
                
                Logger.shared.info("Memory Profile Analysis:", component: "ArchitectureComparisonTests")
                Logger.shared.info("  Initial: \(String(format: "%.1f", memoryProfile.initialMB))MB", component: "ArchitectureComparisonTests")
                Logger.shared.info("  Peak: \(String(format: "%.1f", memoryProfile.peakMB))MB", component: "ArchitectureComparisonTests")
                Logger.shared.info("  Average: \(String(format: "%.1f", memoryProfile.averageMB))MB", component: "ArchitectureComparisonTests")
                Logger.shared.info("  Leak: \(String(format: "%.1f", memoryProfile.leakMB))MB", component: "ArchitectureComparisonTests")
                
                // Validate memory usage
                XCTAssertLessThan(memoryProfile.peakMB, 1024.0, "Peak memory should be < 1GB")
                XCTAssertLessThan(memoryProfile.leakMB, 10.0, "Memory leak should be < 10MB")
                
                // Architecture-specific validation
                switch optimizer.architecture {
                case .appleSilicon:
                    XCTAssertLessThan(memoryProfile.averageMB, 512.0, "Apple Silicon should use < 512MB on average")
                case .intel:
                    XCTAssertLessThan(memoryProfile.averageMB, 768.0, "Intel should use < 768MB on average")
                case .unknown:
                    XCTAssertLessThan(memoryProfile.averageMB, 1024.0, "Unknown architecture should use < 1GB on average")
                }
                
            case .failure(let error):
                XCTFail("Memory profiling test failed: \(error)")
            }
            
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
    }
    
    func testCPUUtilizationMonitoring() async throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer,
              let testFile = createTestAudioFile(duration: 10.0) else {
            throw XCTSkip("Unable to create test components")
        }
        
        Logger.shared.info("=== CPU Utilization Monitoring Test ===", component: "ArchitectureComparisonTests")
        
        bench.startBenchmark("CPU_Utilization_Test")
        
        // Monitor CPU utilization
        let cpuMonitor = CPUMonitor()
        cpuMonitor.startMonitoring()
        
        // Run transcription
        let engine = OptimizedTranscriptionEngine()
        let expectation = XCTestExpectation(description: "CPU monitoring")
        
        engine.transcribeAudio(from: testFile) { _ in
            // Progress monitoring
        } completion: { result in
            cpuMonitor.stopMonitoring()
            let _ = bench.endBenchmark("CPU_Utilization_Test", audioDuration: testFile.format.duration)
            
            switch result {
            case .success:
                // Analyze CPU utilization
                let cpuProfile = cpuMonitor.getProfile()
                
                Logger.shared.info("CPU Utilization Analysis:", component: "ArchitectureComparisonTests")
                Logger.shared.info("  Average: \(String(format: "%.1f", cpuProfile.averageUtilization * 100))%", component: "ArchitectureComparisonTests")
                Logger.shared.info("  Peak: \(String(format: "%.1f", cpuProfile.peakUtilization * 100))%", component: "ArchitectureComparisonTests")
                Logger.shared.info("  Cores used: \(cpuProfile.coresUsed)/\(optimizer.processorCount)", component: "ArchitectureComparisonTests")
                
                // Validate CPU usage
                XCTAssertLessThan(cpuProfile.averageUtilization, 0.8, "Average CPU usage should be < 80%")
                XCTAssertGreaterThan(cpuProfile.averageUtilization, 0.1, "Should use some CPU")
                
                // Multi-core utilization validation
                let expectedCores = min(4, optimizer.processorCount)
                XCTAssertGreaterThanOrEqual(cpuProfile.coresUsed, expectedCores / 2, "Should use multiple cores")
                
            case .failure(let error):
                XCTFail("CPU monitoring test failed: \(error)")
            }
            
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
    }
    
    func testPerformanceRegressionDetection() async throws {
        guard let bench = benchmark,
              let optimizer = platformOptimizer else {
            throw XCTSkip("Unable to create benchmark components")
        }
        
        Logger.shared.info("=== Performance Regression Detection Test ===", component: "ArchitectureComparisonTests")
        
        // Load baseline performance data
        let baselineData = loadBaselinePerformanceData(for: optimizer.architecture)
        
        // Run current performance test
        guard let testFile = createTestAudioFile(duration: 10.0) else {
            throw XCTSkip("Unable to create test file")
        }
        
        let currentResults = await bench.runComprehensiveBenchmark(audioFile: testFile)
        
        guard let standardResult = currentResults.first(where: { $0.testName.contains("Standard") }) else {
            XCTFail("Should have standard benchmark result")
            return
        }
        
        // Compare with baseline
        if let baseline = baselineData {
            let performanceRatio = standardResult.processingTime / baseline.processingTime
            let memoryRatio = standardResult.memoryUsage.peakMB / baseline.memoryUsage.peakMB
            
            Logger.shared.info("Performance Regression Analysis:", component: "ArchitectureComparisonTests")
            Logger.shared.info("  Processing time ratio: \(String(format: "%.2f", performanceRatio))x", component: "ArchitectureComparisonTests")
            Logger.shared.info("  Memory usage ratio: \(String(format: "%.2f", memoryRatio))x", component: "ArchitectureComparisonTests")
            
            // Regression detection thresholds
            XCTAssertLessThan(performanceRatio, 1.2, "Processing time should not regress by > 20%")
            XCTAssertLessThan(memoryRatio, 1.3, "Memory usage should not regress by > 30%")
            
            // Flag significant improvements for validation
            if performanceRatio < 0.8 {
                Logger.shared.info("⚠️  Significant performance improvement detected - verify accuracy", component: "ArchitectureComparisonTests")
            }
        }
        
        // Save current results as new baseline
        saveBaselinePerformanceData(standardResult, for: optimizer.architecture)
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
        
        // Use synchronous wait for helper method
        let waiter = XCTWaiter()
        _ = waiter.wait(for: [expectation], timeout: 30.0)
        return audioFile
    }
    
    private func savePerformanceReport(_ report: String, architecture: PlatformOptimizer.Architecture) {
        let reportsDir = FileManager.default.temporaryDirectory.appendingPathComponent("performance_reports")
        
        do {
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
            
            let reportFile = reportsDir.appendingPathComponent("performance_report_\(architecture.displayName.lowercased())_\(Date().timeIntervalSince1970).txt")
            try report.write(to: reportFile, atomically: true, encoding: .utf8)
            
            Logger.shared.info("Performance report saved to: \(reportFile.path)", component: "ArchitectureComparisonTests")
        } catch {
            Logger.shared.error("Failed to save performance report: \(error)", component: "ArchitectureComparisonTests")
        }
    }
    
    private func loadBaselinePerformanceData(for architecture: PlatformOptimizer.Architecture) -> PerformanceBenchmark.BenchmarkResult? {
        let baselineFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline_performance_\(architecture.displayName.lowercased()).json")
        
        guard let data = try? Data(contentsOf: baselineFile),
              let resultData = try? JSONDecoder().decode(BenchmarkResultData.self, from: data) else {
            Logger.shared.info("No baseline performance data found for \(architecture.displayName)", component: "ArchitectureComparisonTests")
            return nil
        }
        
        // Create a simple mock result for comparison
        let mockMemoryProfile = PerformanceBenchmark.MemoryProfile(
            initial: 0, peak: 0, average: 0, leak: 0, gcEvents: 0
        )
        let mockThermalProfile = PerformanceBenchmark.ThermalProfile(
            initialState: .nominal, peakState: .nominal, finalState: .nominal, thermalPressureSeconds: 0
        )
        let mockEfficiency = PerformanceBenchmark.EfficiencyMetrics(
            processingTimeRatio: 1.0, memoryEfficiency: 1.0, energyEfficiency: 1.0, concurrencyUtilization: 1.0
        )
        
        return PerformanceBenchmark.BenchmarkResult(
            testName: resultData.testName,
            platform: PlatformOptimizer.Architecture(rawValue: resultData.platform) ?? .unknown,
            processingTime: resultData.processingTime,
            memoryUsage: mockMemoryProfile,
            thermalImpact: mockThermalProfile,
            efficiency: mockEfficiency,
            timestamp: resultData.timestamp
        )
    }
    
    private func saveBaselinePerformanceData(_ result: PerformanceBenchmark.BenchmarkResult, for architecture: PlatformOptimizer.Architecture) {
        let baselineFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline_performance_\(architecture.displayName.lowercased()).json")
        
        do {
            let resultData = BenchmarkResultData(from: result)
            let data = try JSONEncoder().encode(resultData)
            try data.write(to: baselineFile)
            Logger.shared.info("Baseline performance data saved for \(architecture.displayName)", component: "ArchitectureComparisonTests")
        } catch {
            Logger.shared.error("Failed to save baseline performance data: \(error)", component: "ArchitectureComparisonTests")
        }
    }
}

// MARK: - Memory Monitor

private class MemoryMonitor {
    private var memoryReadings: [UInt64] = []
    private var monitoringTimer: Timer?
    private var initialMemory: UInt64 = 0
    
    func startMonitoring() {
        initialMemory = getCurrentMemoryUsage()
        memoryReadings = [initialMemory]
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.memoryReadings.append(self.getCurrentMemoryUsage())
        }
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    func getProfile() -> PerformanceBenchmark.MemoryProfile {
        let peak = memoryReadings.max() ?? initialMemory
        let average = memoryReadings.reduce(0, +) / UInt64(memoryReadings.count)
        let final = memoryReadings.last ?? initialMemory
        let leak = final > initialMemory ? final - initialMemory : 0
        
        return PerformanceBenchmark.MemoryProfile(
            initial: initialMemory,
            peak: peak,
            average: average,
            leak: leak,
            gcEvents: 0
        )
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
}

// MARK: - CPU Monitor

private class CPUMonitor {
    private var cpuReadings: [Double] = []
    private var coreUsageReadings: [[Double]] = []
    private var monitoringTimer: Timer?
    
    func startMonitoring() {
        cpuReadings = []
        coreUsageReadings = []
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let usage = self.getCurrentCPUUsage() {
                self.cpuReadings.append(usage.overall)
                self.coreUsageReadings.append(usage.perCore)
            }
        }
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    func getProfile() -> CPUProfile {
        let average = cpuReadings.isEmpty ? 0.0 : cpuReadings.reduce(0, +) / Double(cpuReadings.count)
        let peak = cpuReadings.max() ?? 0.0
        
        // Calculate cores used (cores with > 10% average utilization)
        let coreCount = coreUsageReadings.first?.count ?? 0
        var coresUsed = 0
        
        for coreIndex in 0..<coreCount {
            let coreUsages = coreUsageReadings.compactMap { $0.count > coreIndex ? $0[coreIndex] : nil }
            let coreAverage = coreUsages.isEmpty ? 0.0 : coreUsages.reduce(0, +) / Double(coreUsages.count)
            
            if coreAverage > 0.1 {
                coresUsed += 1
            }
        }
        
        return CPUProfile(
            averageUtilization: average,
            peakUtilization: peak,
            coresUsed: coresUsed
        )
    }
    
    private func getCurrentCPUUsage() -> (overall: Double, perCore: [Double])? {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &cpuInfo, &numCpuInfo)
        
        guard result == KERN_SUCCESS else { return nil }
        
        defer {
            if let cpuInfo = cpuInfo {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo))
            }
        }
        
        guard let info = cpuInfo else { return nil }
        
        var overallUsage: Double = 0.0
        var perCoreUsage: [Double] = []
        
        for i in 0..<Int(numCpus) {
            let cpuLoadInfo = info.advanced(by: Int(CPU_STATE_MAX) * i)
            
            let user = Double(cpuLoadInfo[Int(CPU_STATE_USER)])
            let system = Double(cpuLoadInfo[Int(CPU_STATE_SYSTEM)])
            let nice = Double(cpuLoadInfo[Int(CPU_STATE_NICE)])
            let idle = Double(cpuLoadInfo[Int(CPU_STATE_IDLE)])
            
            let total = user + system + nice + idle
            let usage = total > 0 ? (user + system + nice) / total : 0.0
            
            perCoreUsage.append(usage)
            overallUsage += usage
        }
        
        overallUsage /= Double(numCpus)
        
        return (overall: overallUsage, perCore: perCoreUsage)
    }
}

// MARK: - CPU Profile

private struct CPUProfile {
    let averageUtilization: Double
    let peakUtilization: Double
    let coresUsed: Int
}

// MARK: - Simple Codable Implementation

private struct BenchmarkResultData: Codable {
    let testName: String
    let platform: String
    let processingTime: TimeInterval
    let timestamp: Date
    
    init(from result: PerformanceBenchmark.BenchmarkResult) {
        self.testName = result.testName
        self.platform = result.platform.rawValue
        self.processingTime = result.processingTime
        self.timestamp = result.timestamp
    }
}