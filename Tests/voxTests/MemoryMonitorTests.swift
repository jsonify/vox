import XCTest
@testable import vox

final class MemoryMonitorTests: XCTestCase {
    /// Tests memory usage calculation and percentage accuracy
    /// - Validates total system memory is available
    /// - Verifies usage percentage calculation matches expected value
    /// - Logs memory statistics via proper logging system
    func testMemoryUsageCalculation() {
        let monitor = MemoryMonitor()
        let usage = monitor.getCurrentUsage()

        // Verify usage percentage calculation
        let totalSystemMemory = ProcessInfo.processInfo.physicalMemory
        XCTAssertGreaterThan(totalSystemMemory, 0, "Total system memory should be greater than 0")

        let expectedPercentage = (Double(usage.currentBytes) / Double(totalSystemMemory)) * 100.0
        XCTAssertEqual(usage.usagePercentage, expectedPercentage, accuracy: 0.1, "Memory usage percentage should match expected calculation")

        // Log memory stats for verification
        let memoryStats = """
            Memory Test Stats:
            - Total System Memory: \(formatBytes(totalSystemMemory))
            - Current Usage: \(formatBytes(usage.currentBytes))
            - Available: \(formatBytes(usage.availableBytes))
            - Usage Percentage: \(String(format: "%.1f%%", usage.usagePercentage))
            """
        
        Logger.shared.debug(memoryStats, component: "Tests")
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .memory
        )
    }
}
