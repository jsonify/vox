import Foundation

// MARK: - Memory Monitoring

class MemoryMonitor {
    func getCurrentUsage() -> MemoryUsage {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let currentBytes = result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        
        // Get system memory info
        var systemInfo = vm_statistics64()
        var systemCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let systemResult = withUnsafeMutablePointer(to: &systemInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &systemCount)
            }
        }
        
        let pageSize = UInt64(vm_page_size)
        let availableBytes = systemResult == KERN_SUCCESS ?
            UInt64(systemInfo.free_count + systemInfo.inactive_count) * pageSize : 0
        
        // Track peak usage (simplified - in real implementation would need persistent tracking)
        let peakBytes = currentBytes
        
        return MemoryUsage(
            currentBytes: currentBytes,
            peakBytes: peakBytes,
            availableBytes: availableBytes
        )
    }
}
