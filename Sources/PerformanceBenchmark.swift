import Foundation
import AVFoundation

/// Comprehensive performance benchmarking system for Intel and Apple Silicon optimization validation
public final class PerformanceBenchmark {
    // MARK: - Types

    public struct BenchmarkResult {
        public let testName: String
        public let platform: PlatformOptimizer.Architecture
        public let processingTime: TimeInterval
        public let memoryUsage: MemoryProfile
        public let thermalImpact: ThermalProfile
        public let efficiency: EfficiencyMetrics
        public let timestamp: Date

        public var processingRatio: Double {
            efficiency.processingTimeRatio
        }

        public var summary: String {
            """
            \(testName) (\(platform.displayName)):
              Processing: \(String(format: "%.2f", processingTime))s
              Ratio: \(String(format: "%.2f", processingRatio))x real-time
              Memory: \(String(format: "%.1f", memoryUsage.peakMB))MB peak
              Efficiency: \(String(format: "%.1f", efficiency.energyEfficiency * 100))%
            """
        }
    }

    public struct MemoryProfile {
        public let initialMB: Double
        public let peakMB: Double
        public let averageMB: Double
        public let leakMB: Double
        public let gcEvents: Int

        public init(initial: UInt64, peak: UInt64, average: UInt64, leak: UInt64, gcEvents: Int) {
            self.initialMB = Double(initial) / (1024 * 1024)
            self.peakMB = Double(peak) / (1024 * 1024)
            self.averageMB = Double(average) / (1024 * 1024)
            self.leakMB = Double(leak) / (1024 * 1024)
            self.gcEvents = gcEvents
        }
    }

    public struct ThermalProfile {
        public let initialState: ProcessInfo.ThermalState
        public let peakState: ProcessInfo.ThermalState
        public let finalState: ProcessInfo.ThermalState
        public let thermalPressureSeconds: TimeInterval

        public var thermalImpact: String {
            if thermalPressureSeconds > 0 {
                return "High (\(String(format: "%.1f", thermalPressureSeconds))s pressure)"
            } else if peakState.rawValue > initialState.rawValue {
                return "Medium (state increased)"
            } else {
                return "Low (stable)"
            }
        }
    }

    public struct EfficiencyMetrics {
        public let processingTimeRatio: Double  // processing time / audio duration
        public let memoryEfficiency: Double     // 1.0 - (peak_memory / available_memory)
        public let energyEfficiency: Double     // platform-specific energy usage estimate
        public let concurrencyUtilization: Double // how well multi-threading was used

        public var overallScore: Double {
            let weights: [Double] = [0.4, 0.2, 0.3, 0.1] // processing, memory, energy, concurrency
            let metrics = [
                min(1.0, 2.0 / processingTimeRatio), // Lower is better for processing ratio
                memoryEfficiency,
                energyEfficiency,
                concurrencyUtilization
            ]

            return zip(weights, metrics).reduce(0.0) { $0 + $1.0 * $1.1 }
        }
    }

    internal struct BenchmarkContext {
        let startTime: Date
        let initialMemory: UInt64
        let initialThermalState: ProcessInfo.ThermalState
        var memorySnapshots: [UInt64] = []
        var thermalSnapshots: [ProcessInfo.ThermalState] = []
        var gcEventCount: Int = 0
    }

    // MARK: - Properties

    public static let shared = PerformanceBenchmark()

    internal let platformOptimizer = PlatformOptimizer.shared
    internal let memoryManager = OptimizedMemoryManager.shared

    private var activeBenchmarks: [String: BenchmarkContext] = [:]
    private let benchmarkQueue = DispatchQueue(label: "vox.benchmark", qos: .userInitiated)
    private let contextLock = NSLock()

    private var monitoringTimer: Timer?

    // MARK: - Initialization

    private init() {
        Logger.shared.info(
            "Initialized PerformanceBenchmark for \(platformOptimizer.architecture.displayName)", 
            component: "PerformanceBenchmark"
        )
    }

    // MARK: - Benchmark Control

    public func startBenchmark(_ testName: String) {
        contextLock.lock()
        defer { contextLock.unlock() }

        let context = BenchmarkContext(
            startTime: Date(),
            initialMemory: getCurrentMemoryUsage(),
            initialThermalState: ProcessInfo.processInfo.thermalState
        )

        activeBenchmarks[testName] = context
        startMonitoring(for: testName)

        Logger.shared.info("Started benchmark: \(testName)", component: "PerformanceBenchmark")
    }

    public func endBenchmark(_ testName: String, audioDuration: TimeInterval) -> BenchmarkResult {
        contextLock.lock()
        guard let context = activeBenchmarks[testName] else {
            contextLock.unlock()
            Logger.shared.error("Benchmark \(testName) was not started - creating fallback result", 
                                component: "PerformanceBenchmark")
            
            // Create a fallback result to avoid crashing
            let fallbackResult = createFallbackBenchmarkResult(testName: testName, audioDuration: audioDuration)
            return fallbackResult
        }
        activeBenchmarks.removeValue(forKey: testName)
        contextLock.unlock()

        stopMonitoring()

        let endTime = Date()
        let processingTime = endTime.timeIntervalSince(context.startTime)
        let finalMemory = getCurrentMemoryUsage()
        let finalThermalState = ProcessInfo.processInfo.thermalState

        // Calculate memory profile
        let memoryProfile = calculateMemoryProfile(
            context: context,
            finalMemory: finalMemory
        )

        // Calculate thermal profile
        let thermalProfile = calculateThermalProfile(
            context: context,
            finalState: finalThermalState,
            duration: processingTime
        )

        // Calculate efficiency metrics
        let efficiency = calculateEfficiencyMetrics(
            processingTime: processingTime,
            audioDuration: audioDuration,
            memoryProfile: memoryProfile,
            thermalProfile: thermalProfile
        )

        let result = BenchmarkResult(
            testName: testName,
            platform: platformOptimizer.architecture,
            processingTime: processingTime,
            memoryUsage: memoryProfile,
            thermalImpact: thermalProfile,
            efficiency: efficiency,
            timestamp: endTime
        )

        Logger.shared.info(
            "Completed benchmark: \(testName) - \(String(format: "%.2f", processingTime))s",
            component: "PerformanceBenchmark"
        )
        return result
    }

    // MARK: - Monitoring

    private func startMonitoring(for testName: String) {
        benchmarkQueue.async { [weak self] in
            self?.monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                self?.recordSnapshot(for: testName)
            }

            RunLoop.current.add(self?.monitoringTimer ?? Timer(), forMode: .default)
            RunLoop.current.run()
        }
    }

    private func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    private func recordSnapshot(for testName: String) {
        contextLock.lock()
        defer { contextLock.unlock() }

        guard var context = activeBenchmarks[testName] else { return }

        context.memorySnapshots.append(getCurrentMemoryUsage())
        context.thermalSnapshots.append(ProcessInfo.processInfo.thermalState)

        activeBenchmarks[testName] = context
    }

    // MARK: - Calculation Methods (see extensions below)

    internal func calculateEnergyEfficiency(
        processingRatio: Double,
        thermalProfile: ThermalProfile
    ) -> Double {
        var baseEfficiency: Double

        switch platformOptimizer.architecture {
        case .appleSilicon:
            // Apple Silicon is more energy efficient
            baseEfficiency = 0.9

        case .intel:
            // Intel systems consume more energy
            baseEfficiency = 0.7

        case .unknown:
            baseEfficiency = 0.5
        }

        // Reduce efficiency for thermal pressure
        let thermalPenalty = thermalProfile.thermalPressureSeconds > 0 ? 0.2 : 0.0

        // Reduce efficiency for slow processing
        let processingPenalty = processingRatio > 2.0 ? (processingRatio - 2.0) * 0.1 : 0.0

        return max(0.0, baseEfficiency - thermalPenalty - processingPenalty)
    }

    // MARK: - Benchmark Suites

    public func runComprehensiveBenchmark(audioFile: AudioFile) async -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []

        // Standard transcription benchmark
        if let standardResult = await benchmarkStandardTranscription(audioFile) {
            results.append(standardResult)
        }

        // Optimized transcription benchmark
        if let optimizedResult = await benchmarkOptimizedTranscription(audioFile) {
            results.append(optimizedResult)
        }

        // Memory stress test
        if let memoryResult = await benchmarkMemoryStress(audioFile) {
            results.append(memoryResult)
        }

        // Concurrent processing benchmark
        if let concurrentResult = await benchmarkConcurrentProcessing(audioFile) {
            results.append(concurrentResult)
        }

        return results
    }

    // MARK: - Benchmark Methods (see extensions below)

    // MARK: - Utilities

    private func createFallbackBenchmarkResult(testName: String, audioDuration: TimeInterval) -> BenchmarkResult {
        let fallbackMemoryProfile = MemoryProfile(
            initial: 0,
            peak: 100 * 1024 * 1024, // 100MB fallback
            average: 50 * 1024 * 1024, // 50MB fallback
            leak: 0,
            gcEvents: 0
        )
        
        let fallbackThermalProfile = ThermalProfile(
            initialState: .nominal,
            peakState: .nominal,
            finalState: .nominal,
            thermalPressureSeconds: 0
        )
        
        let fallbackEfficiency = EfficiencyMetrics(
            processingTimeRatio: 1.0,
            memoryEfficiency: 0.5,
            energyEfficiency: 0.5,
            concurrencyUtilization: 0.5
        )
        
        return BenchmarkResult(
            testName: testName,
            platform: platformOptimizer.architecture,
            processingTime: audioDuration, // Use audio duration as fallback
            memoryUsage: fallbackMemoryProfile,
            thermalImpact: fallbackThermalProfile,
            efficiency: fallbackEfficiency,
            timestamp: Date()
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

    // MARK: - Reporting (see extensions below)
}


