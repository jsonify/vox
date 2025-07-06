import Foundation

// MARK: - Reporting Extension

extension PerformanceBenchmark {
    public func generateBenchmarkReport(_ results: [BenchmarkResult]) -> String {
        var report = """
        ===== Performance Benchmark Report =====
        Platform: \(platformOptimizer.architecture.displayName)
        Cores: \(platformOptimizer.processorCount)
        Memory: \(String(format: "%.1f", Double(platformOptimizer.physicalMemory) / (1024 * 1024 * 1024)))GB
        Timestamp: \(Date())

        """

        for result in results {
            report += result.summary + "\n\n"
        }

        // Calculate overall performance score
        if !results.isEmpty {
            let averageScore = results.reduce(0.0) { $0 + $1.efficiency.overallScore } / Double(results.count)
            report += "Overall Performance Score: \(String(format: "%.1f", averageScore * 100))%\n"
        }

        return report
    }

    public func logBenchmarkResult(_ result: BenchmarkResult) {
        Logger.shared.info(
            "=== Benchmark Result: \(result.testName) ===",
            component: "PerformanceBenchmark"
        )
        Logger.shared.info(
            "Processing Time: \(String(format: "%.2f", result.processingTime))s",
            component: "PerformanceBenchmark"
        )
        Logger.shared.info(
            "Processing Ratio: \(String(format: "%.2f", result.processingRatio))x real-time",
            component: "PerformanceBenchmark"
        )
        Logger.shared.info(
            "Peak Memory: \(String(format: "%.1f", result.memoryUsage.peakMB))MB",
            component: "PerformanceBenchmark"
        )
        Logger.shared.info(
            "Thermal Impact: \(result.thermalImpact.thermalImpact)",
            component: "PerformanceBenchmark"
        )
        Logger.shared.info(
            "Efficiency Score: \(String(format: "%.1f", result.efficiency.overallScore * 100))%",
            component: "PerformanceBenchmark"
        )
    }
}
