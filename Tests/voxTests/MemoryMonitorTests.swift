import XCTest
@testable import vox

final class MemoryMonitorTests: XCTestCase {
    func testMemoryUsageCalculation() {
        let monitor = MemoryMonitor()
        let usage = monitor.getCurrentUsage()

        // Verify usage percentage calculation
        let totalSystemMemory = ProcessInfo.processInfo.physicalMemory
        XCTAssertGreaterThan(totalSystemMemory, 0, "Total system memory should be greater than 0")

        let expectedPercentage = (Double(usage.currentBytes) / Double(totalSystemMemory)) * 100.0
        XCTAssertEqual(usage.usagePercentage, expectedPercentage, accuracy: 0.1,
                       "Memory usage percentage should match expected calculation")

        // Log memory stats for verification
        print("Memory Test Stats:")
        print("- Total System Memory: \(ByteCountFormatter.string(fromByteCount: Int64(totalSystemMemory), countStyle: .memory))")
        print("- Current Usage: \(ByteCountFormatter.string(fromByteCount: Int64(usage.currentBytes), countStyle: .memory))")
        print("- Available: \(ByteCountFormatter.string(fromByteCount: Int64(usage.availableBytes), countStyle: .memory))")
        print("- Usage Percentage: \(String(format: "%.1f%%", usage.usagePercentage))")
    }
}
