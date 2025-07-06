import Foundation

// MARK: - Calculation Methods Extension

extension PerformanceBenchmark {
    internal func calculateMemoryProfile(
        context: BenchmarkContext,
        finalMemory: UInt64
    ) -> MemoryProfile {
        let allMemoryReadings = [context.initialMemory] + context.memorySnapshots + [finalMemory]

        let peak = allMemoryReadings.max() ?? context.initialMemory
        let average = allMemoryReadings.reduce(0, +) / UInt64(allMemoryReadings.count)
        let leak = finalMemory > context.initialMemory ? finalMemory - context.initialMemory : 0

        return MemoryProfile(
            initial: context.initialMemory,
            peak: peak,
            average: average,
            leak: leak,
            gcEvents: context.gcEventCount
        )
    }

    internal func calculateThermalProfile(
        context: BenchmarkContext,
        finalState: ProcessInfo.ThermalState,
        duration: TimeInterval
    ) -> ThermalProfile {
        let allThermalStates = [context.initialThermalState] + context.thermalSnapshots + [finalState]
        let peakState = allThermalStates.max { $0.rawValue < $1.rawValue } ?? context.initialThermalState

        // Calculate time under thermal pressure
        let pressureStates = allThermalStates.filter { $0.rawValue >= ProcessInfo.ThermalState.fair.rawValue }
        let thermalPressureSeconds = Double(pressureStates.count) * 0.5 // 0.5s sampling interval

        return ThermalProfile(
            initialState: context.initialThermalState,
            peakState: peakState,
            finalState: finalState,
            thermalPressureSeconds: thermalPressureSeconds
        )
    }

    internal func calculateEfficiencyMetrics(
        processingTime: TimeInterval,
        audioDuration: TimeInterval,
        memoryProfile: MemoryProfile,
        thermalProfile: ThermalProfile
    ) -> EfficiencyMetrics {
        let processingRatio = processingTime / audioDuration

        // Memory efficiency (lower peak usage is better)
        let availableMemory = Double(platformOptimizer.physicalMemory) / (1024 * 1024)
        let memoryEfficiency = max(0.0, 1.0 - (memoryProfile.peakMB / availableMemory))

        // Energy efficiency (platform-specific estimation)
        let energyEfficiency = calculateEnergyEfficiency(
            processingRatio: processingRatio,
            thermalProfile: thermalProfile
        )

        // Concurrency utilization (based on processing ratio and core count)
        let idealRatio = 1.0 / Double(platformOptimizer.processorCount)
        let concurrencyUtilization = min(1.0, idealRatio / processingRatio)

        return EfficiencyMetrics(
            processingTimeRatio: processingRatio,
            memoryEfficiency: memoryEfficiency,
            energyEfficiency: energyEfficiency,
            concurrencyUtilization: concurrencyUtilization
        )
    }
}
