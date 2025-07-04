import Foundation
import AVFoundation

/// Platform-specific optimization manager for Intel and Apple Silicon Macs
public final class PlatformOptimizer {
    // MARK: - Platform Detection

    public enum Architecture: String, CaseIterable {
        case appleSilicon = "arm64"
        case intel = "x86_64"
        case unknown = "unknown"

        var displayName: String {
            switch self {
            case .appleSilicon:
                return "Apple Silicon"
            case .intel:
                return "Intel"
            case .unknown:
                return "Unknown"
            }
        }
    }

    public enum OptimizationLevel: String, CaseIterable {
        case maximum
        case balanced
        case conservative

        var concurrencyMultiplier: Double {
            switch self {
            case .maximum:
                return 1.5
            case .balanced:
                return 1.0
            case .conservative:
                return 0.7
            }
        }
    }

    // MARK: - Singleton

    public static let shared = PlatformOptimizer()

    // MARK: - Properties

    public let architecture: Architecture
    public let processorCount: Int
    public let physicalMemory: UInt64
    public let thermalState: ProcessInfo.ThermalState

    private let optimizationLevel: OptimizationLevel

    // MARK: - Initialization

    private init() {
        // Detect architecture
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }

        if machine.hasPrefix("arm64") {
            self.architecture = .appleSilicon
        } else if machine.hasPrefix("x86_64") {
            self.architecture = .intel
        } else {
            self.architecture = .unknown
        }

        // System capabilities
        self.processorCount = ProcessInfo.processInfo.processorCount
        self.physicalMemory = ProcessInfo.processInfo.physicalMemory
        self.thermalState = ProcessInfo.processInfo.thermalState

        // Determine optimization level based on system
        if architecture == .appleSilicon && physicalMemory >= 16 * 1024 * 1024 * 1024 {
            self.optimizationLevel = .maximum
        } else if processorCount >= 8 {
            self.optimizationLevel = .balanced
        } else {
            self.optimizationLevel = .conservative
        }

        Logger.shared.info(
            "Platform: \(architecture.displayName), Cores: \(processorCount), Memory: " +
            "\(formatMemory(physicalMemory)), Optimization: \(optimizationLevel.rawValue)",
            component: "PlatformOptimizer"
        )
    }

    // MARK: - Audio Processing Optimizations

    public struct AudioProcessingConfig {
        public let concurrentOperations: Int
        public let bufferSize: Int
        public let useHardwareAcceleration: Bool
        public let priorityQOS: DispatchQoS.QoSClass

        public static let `default` = AudioProcessingConfig(
            concurrentOperations: 1,
            bufferSize: 4096,
            useHardwareAcceleration: false,
            priorityQOS: .userInitiated
        )
    }

    public func getAudioProcessingConfig() -> AudioProcessingConfig {
        let baseConcurrency = max(1, processorCount / 2)
        let optimizedConcurrency = Int(Double(baseConcurrency) * optimizationLevel.concurrencyMultiplier)

        let bufferSize: Int
        let useHardwareAcceleration: Bool
        let priorityQOS: DispatchQoS.QoSClass

        switch architecture {
        case .appleSilicon:
            // Apple Silicon optimizations
            bufferSize = physicalMemory >= 16 * 1024 * 1024 * 1024 ? 8192 : 4096
            useHardwareAcceleration = true
            priorityQOS = thermalState == .nominal ? .userInitiated : .utility

        case .intel:
            // Intel optimizations
            bufferSize = 4096
            useHardwareAcceleration = processorCount >= 8
            priorityQOS = .userInitiated

        case .unknown:
            // Conservative defaults
            bufferSize = 2048
            useHardwareAcceleration = false
            priorityQOS = .utility
        }

        return AudioProcessingConfig(
            concurrentOperations: optimizedConcurrency,
            bufferSize: bufferSize,
            useHardwareAcceleration: useHardwareAcceleration,
            priorityQOS: priorityQOS
        )
    }

    // MARK: - Speech Recognition Optimizations

    public struct SpeechRecognitionConfig {
        public let useOnDeviceRecognition: Bool
        public let segmentDuration: TimeInterval
        public let memoryMonitoringInterval: TimeInterval
        public let progressReportingInterval: TimeInterval

        public static let `default` = SpeechRecognitionConfig(
            useOnDeviceRecognition: true,
            segmentDuration: 60.0,
            memoryMonitoringInterval: 1.0,
            progressReportingInterval: 0.5
        )
    }

    public func getSpeechRecognitionConfig() -> SpeechRecognitionConfig {
        let baseInterval: TimeInterval = 0.5

        let memoryInterval: TimeInterval
        let progressInterval: TimeInterval
        let segmentDuration: TimeInterval

        switch architecture {
        case .appleSilicon:
            // Apple Silicon has Neural Engine - can handle more frequent updates
            memoryInterval = thermalState == .nominal ? baseInterval : baseInterval * 2
            progressInterval = 0.25
            segmentDuration = optimizationLevel == .maximum ? 120.0 : 60.0

        case .intel:
            // Intel processors - more conservative
            memoryInterval = baseInterval * 1.5
            progressInterval = baseInterval
            segmentDuration = 60.0

        case .unknown:
            // Very conservative
            memoryInterval = baseInterval * 3
            progressInterval = baseInterval * 2
            segmentDuration = 30.0
        }

        return SpeechRecognitionConfig(
            useOnDeviceRecognition: true,
            segmentDuration: segmentDuration,
            memoryMonitoringInterval: memoryInterval,
            progressReportingInterval: progressInterval
        )
    }

    // MARK: - Memory Management Optimizations

    public struct MemoryConfig {
        public let maxMemoryUsage: UInt64
        public let bufferPoolSize: Int
        public let enableMemoryMapping: Bool
        public let garbageCollectionThreshold: Double

        public static let `default` = MemoryConfig(
            maxMemoryUsage: 1024 * 1024 * 1024,
            bufferPoolSize: 4,
            enableMemoryMapping: false,
            garbageCollectionThreshold: 0.8
        )
    }

    public func getMemoryConfig() -> MemoryConfig {
        let availableMemory = physicalMemory
        let maxUsageRatio: Double

        switch architecture {
        case .appleSilicon:
            // Unified memory architecture - can use more efficiently
            maxUsageRatio = optimizationLevel == .maximum ? 0.6 : 0.4

        case .intel:
            // Traditional memory architecture - more conservative
            maxUsageRatio = 0.3

        case .unknown:
            maxUsageRatio = 0.2
        }

        let maxMemoryUsage = UInt64(Double(availableMemory) * maxUsageRatio)
        let bufferPoolSize = max(2, processorCount / 2)
        let enableMemoryMapping = architecture == .appleSilicon && availableMemory >= 8 * 1024 * 1024 * 1024

        return MemoryConfig(
            maxMemoryUsage: maxMemoryUsage,
            bufferPoolSize: bufferPoolSize,
            enableMemoryMapping: enableMemoryMapping,
            garbageCollectionThreshold: thermalState == .nominal ? 0.8 : 0.6
        )
    }

    // MARK: - Performance Monitoring

    public func shouldEnableDetailedProfiling() -> Bool {
        return architecture == .appleSilicon && optimizationLevel == .maximum
    }

    public func getRecommendedFileChunkSize(for fileDuration: TimeInterval) -> TimeInterval {
        switch architecture {
        case .appleSilicon:
            // Can handle larger chunks efficiently
            if fileDuration <= 300 { // 5 minutes
                return fileDuration
            } else {
                return optimizationLevel == .maximum ? 300 : 180
            }

        case .intel:
            // Smaller chunks for Intel
            if fileDuration <= 120 { // 2 minutes
                return fileDuration
            } else {
                return 120
            }

        case .unknown:
            return min(60, fileDuration)
        }
    }

    // MARK: - Thermal Management

    public func adjustForThermalState() -> OptimizationLevel {
        switch thermalState {
        case .nominal:
            return optimizationLevel
        case .fair:
            return optimizationLevel == .maximum ? .balanced : optimizationLevel
        case .serious, .critical:
            return .conservative
        @unknown default:
            return .conservative
        }
    }

    // MARK: - Utilities

    private func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1fGB", gb)
    }

    public func logSystemInfo() {
        Logger.shared.info("=== System Performance Profile ===", component: "PlatformOptimizer")
        Logger.shared.info("Architecture: \(architecture.displayName)", component: "PlatformOptimizer")
        Logger.shared.info("CPU Cores: \(processorCount)", component: "PlatformOptimizer")
        Logger.shared.info("Physical Memory: \(formatMemory(physicalMemory))", component: "PlatformOptimizer")
        Logger.shared.info("Thermal State: \(thermalState)", component: "PlatformOptimizer")
        Logger.shared.info("Optimization Level: \(optimizationLevel.rawValue)", component: "PlatformOptimizer")

        let audioConfig = getAudioProcessingConfig()
        Logger.shared.info(
            "Audio Config: \(audioConfig.concurrentOperations) ops, \(audioConfig.bufferSize) buffer",
            component: "PlatformOptimizer"
        )

        let speechConfig = getSpeechRecognitionConfig()
        Logger.shared.info(
            "Speech Config: \(speechConfig.segmentDuration)s segments, " +
            "\(speechConfig.progressReportingInterval)s intervals",
            component: "PlatformOptimizer"
        )

        let memoryConfig = getMemoryConfig()
        Logger.shared.info(
            "Memory Config: \(formatMemory(memoryConfig.maxMemoryUsage)) max, " +
            "\(memoryConfig.bufferPoolSize) pools",
            component: "PlatformOptimizer"
        )
    }
}
