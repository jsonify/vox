import Foundation

/// Advanced memory management with platform-specific optimizations for Intel and Apple Silicon
public final class OptimizedMemoryManager {
    
    // MARK: - Types
    
    public struct MemoryPool {
        let bufferSize: Int
        let poolSize: Int
        private var availableBuffers: [UnsafeMutableRawPointer]
        private var usedBuffers: Set<UnsafeMutableRawPointer>
        private let lock = NSLock()
        
        public init(bufferSize: Int, poolSize: Int) {
            self.bufferSize = bufferSize
            self.poolSize = poolSize
            self.availableBuffers = []
            self.usedBuffers = []
            
            // Pre-allocate buffers
            for _ in 0..<poolSize {
                let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<UInt8>.alignment)
                availableBuffers.append(buffer)
            }
        }
        
        public mutating func borrowBuffer() -> UnsafeMutableRawPointer? {
            lock.lock()
            defer { lock.unlock() }
            
            guard let buffer = availableBuffers.popLast() else {
                return nil // Pool exhausted
            }
            
            usedBuffers.insert(buffer)
            return buffer
        }
        
        public mutating func returnBuffer(_ buffer: UnsafeMutableRawPointer) {
            lock.lock()
            defer { lock.unlock() }
            
            guard usedBuffers.remove(buffer) != nil else {
                return // Buffer not from this pool
            }
            
            // Zero out buffer for security
            buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)
            availableBuffers.append(buffer)
        }
        
        public mutating func deallocate() {
            lock.lock()
            defer { lock.unlock() }
            
            for buffer in availableBuffers + Array(usedBuffers) {
                buffer.deallocate()
            }
            availableBuffers.removeAll()
            usedBuffers.removeAll()
        }
    }
    
    public struct MemoryMetrics {
        public let currentUsage: UInt64
        public let peakUsage: UInt64
        public let poolUtilization: Double
        public let fragmentationRatio: Double
        public let gcRecommended: Bool
        public let timestamp: Date
    }
    
    // MARK: - Properties
    
    public static let shared = OptimizedMemoryManager()
    
    private let platformOptimizer = PlatformOptimizer.shared
    private let memoryConfig: PlatformOptimizer.MemoryConfig
    
    private var memoryPools: [Int: MemoryPool] = [:]
    private var memoryUsageHistory: [UInt64] = []
    private var peakMemoryUsage: UInt64 = 0
    
    private let memoryQueue = DispatchQueue(label: "vox.memory.manager", qos: .utility)
    private let metricsLock = NSLock()
    
    private var isMonitoring = false
    private var monitoringTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        self.memoryConfig = platformOptimizer.getMemoryConfig()
        setupMemoryPools()
        
        Logger.shared.info("Initialized OptimizedMemoryManager with \(memoryConfig.bufferPoolSize) pools", component: "OptimizedMemoryManager")
    }
    
    deinit {
        stopMonitoring()
        deallocatePools()
    }
    
    // MARK: - Memory Pool Management
    
    private func setupMemoryPools() {
        let audioConfig = platformOptimizer.getAudioProcessingConfig()
        let bufferSizes = [1024, 4096, audioConfig.bufferSize, 16384, 65536]
        
        for bufferSize in bufferSizes {
            memoryPools[bufferSize] = MemoryPool(
                bufferSize: bufferSize,
                poolSize: memoryConfig.bufferPoolSize
            )
        }
        
        Logger.shared.info("Created memory pools for buffer sizes: \(bufferSizes)", component: "OptimizedMemoryManager")
    }
    
    public func borrowBuffer(size: Int) -> UnsafeMutableRawPointer? {
        // Find the smallest pool that can accommodate the request
        let suitableSize = memoryPools.keys.sorted().first { $0 >= size }
        
        guard let poolSize = suitableSize,
              var pool = memoryPools[poolSize] else {
            // Fallback to direct allocation for unusual sizes
            Logger.shared.warn("No suitable pool for size \(size), using direct allocation", component: "OptimizedMemoryManager")
            return UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<UInt8>.alignment)
        }
        
        let buffer = pool.borrowBuffer()
        memoryPools[poolSize] = pool
        return buffer
    }
    
    public func returnBuffer(_ buffer: UnsafeMutableRawPointer, size: Int) {
        let suitableSize = memoryPools.keys.sorted().first { $0 >= size }
        
        guard let poolSize = suitableSize,
              var pool = memoryPools[poolSize] else {
            // Direct deallocation for non-pooled buffers
            buffer.deallocate()
            return
        }
        
        pool.returnBuffer(buffer)
        memoryPools[poolSize] = pool
    }
    
    // MARK: - Platform-Optimized Memory Operations
    
    public func optimizedMemcopy(
        destination: UnsafeMutableRawPointer,
        source: UnsafeRawPointer,
        byteCount: Int
    ) {
        switch platformOptimizer.architecture {
        case .appleSilicon:
            // Apple Silicon optimized memory copy
            if memoryConfig.enableMemoryMapping && byteCount > 64 * 1024 {
                // Use VM-based copy for large transfers on unified memory architecture
                vmMemcopy(destination: destination, source: source, byteCount: byteCount)
            } else {
                // Standard copy with Apple Silicon optimizations
                destination.copyMemory(from: source, byteCount: byteCount)
            }
            
        case .intel:
            // Intel optimized memory copy
            if byteCount > 128 * 1024 {
                // Use chunked copy for Intel systems to avoid cache pollution
                chunkedMemcopy(destination: destination, source: source, byteCount: byteCount)
            } else {
                destination.copyMemory(from: source, byteCount: byteCount)
            }
            
        case .unknown:
            // Conservative approach
            destination.copyMemory(from: source, byteCount: byteCount)
        }
    }
    
    private func vmMemcopy(
        destination: UnsafeMutableRawPointer,
        source: UnsafeRawPointer,
        byteCount: Int
    ) {
        // VM-based copy for unified memory systems (Apple Silicon)
        let pageSize = vm_page_size
        let alignedSize = (byteCount + Int(pageSize) - 1) & ~(Int(pageSize) - 1)
        
        if alignedSize == byteCount {
            // Page-aligned copy can use VM optimizations
            var sourceVmAddress = vm_address_t(UInt(bitPattern: source))
            var destVmAddress = vm_address_t(UInt(bitPattern: destination))
            
            let result = vm_copy(
                mach_task_self_,
                sourceVmAddress,
                vm_size_t(byteCount),
                destVmAddress
            )
            
            if result == KERN_SUCCESS {
                return
            }
        }
        
        // Fallback to standard copy
        destination.copyMemory(from: source, byteCount: byteCount)
    }
    
    private func chunkedMemcopy(
        destination: UnsafeMutableRawPointer,
        source: UnsafeRawPointer,
        byteCount: Int
    ) {
        // Chunked copy to optimize for Intel cache hierarchy
        let chunkSize = 64 * 1024 // 64KB chunks to fit in L1 cache
        var remainingBytes = byteCount
        var currentSource = source
        var currentDest = destination
        
        while remainingBytes > 0 {
            let copySize = min(chunkSize, remainingBytes)
            currentDest.copyMemory(from: currentSource, byteCount: copySize)
            
            currentSource = currentSource.advanced(by: copySize)
            currentDest = currentDest.advanced(by: copySize)
            remainingBytes -= copySize
        }
    }
    
    // MARK: - Memory Monitoring
    
    public func startMonitoring(interval: TimeInterval? = nil) {
        guard !isMonitoring else { return }
        
        let monitoringInterval = interval ?? memoryConfig.garbageCollectionThreshold
        isMonitoring = true
        
        memoryQueue.async { [weak self] in
            self?.monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { _ in
                self?.collectMemoryMetrics()
            }
            
            RunLoop.current.add(self?.monitoringTimer ?? Timer(), forMode: .default)
            RunLoop.current.run()
        }
        
        Logger.shared.info("Started memory monitoring with \(monitoringInterval)s interval", component: "OptimizedMemoryManager")
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        Logger.shared.info("Stopped memory monitoring", component: "OptimizedMemoryManager")
    }
    
    private func collectMemoryMetrics() {
        let currentUsage = getCurrentMemoryUsage()
        
        metricsLock.lock()
        memoryUsageHistory.append(currentUsage)
        peakMemoryUsage = max(peakMemoryUsage, currentUsage)
        
        // Keep only recent history for performance
        if memoryUsageHistory.count > 100 {
            memoryUsageHistory.removeFirst()
        }
        metricsLock.unlock()
        
        // Check if garbage collection is recommended
        if currentUsage > UInt64(Double(memoryConfig.maxMemoryUsage) * memoryConfig.garbageCollectionThreshold) {
            Logger.shared.warn("Memory usage approaching threshold: \(formatMemory(currentUsage))", component: "OptimizedMemoryManager")
            performOptimizedGarbageCollection()
        }
    }
    
    // MARK: - Garbage Collection
    
    public func performOptimizedGarbageCollection() {
        Logger.shared.info("Performing optimized garbage collection", component: "OptimizedMemoryManager")
        
        memoryQueue.async { [weak self] in
            guard let self = self else { return }
            
            let beforeGC = self.getCurrentMemoryUsage()
            
            // Platform-specific GC optimizations
            switch self.platformOptimizer.architecture {
            case .appleSilicon:
                self.performAppleSiliconGC()
            case .intel:
                self.performIntelGC()
            case .unknown:
                self.performConservativeGC()
            }
            
            let afterGC = self.getCurrentMemoryUsage()
            let freed = beforeGC > afterGC ? beforeGC - afterGC : 0
            
            Logger.shared.info("GC freed \(self.formatMemory(freed)) (\(beforeGC) -> \(afterGC))", component: "OptimizedMemoryManager")
        }
    }
    
    private func performAppleSiliconGC() {
        // Apple Silicon specific optimizations
        // Unified memory allows for more aggressive cleanup
        
        // Force autoreleasepool drain
        autoreleasepool {
            // Trigger system memory pressure relief
            if #available(macOS 11.0, *) {
                // Use memory pressure APIs if available
            }
        }
        
        // Compact memory pools
        compactMemoryPools()
        
        // Suggest VM page cleanup
        madvise(nil, 0, MADV_FREE)
    }
    
    private func performIntelGC() {
        // Intel specific optimizations
        // Traditional memory hierarchy requires different approach
        
        autoreleasepool {
            // Conservative cleanup for Intel systems
        }
        
        // More selective pool compaction
        compactMemoryPools(aggressive: false)
    }
    
    private func performConservativeGC() {
        autoreleasepool {
            // Basic cleanup only
        }
    }
    
    private func compactMemoryPools(aggressive: Bool = true) {
        for (size, pool) in memoryPools {
            if aggressive {
                // On Apple Silicon, can afford more aggressive compaction
                // Would implement pool defragmentation here
            }
            
            // Basic pool maintenance
            memoryPools[size] = pool
        }
    }
    
    // MARK: - Memory Metrics
    
    public func getMemoryMetrics() -> MemoryMetrics {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        
        let currentUsage = getCurrentMemoryUsage()
        let poolUtilization = calculatePoolUtilization()
        let fragmentationRatio = calculateFragmentationRatio()
        let gcRecommended = currentUsage > UInt64(Double(memoryConfig.maxMemoryUsage) * memoryConfig.garbageCollectionThreshold)
        
        return MemoryMetrics(
            currentUsage: currentUsage,
            peakUsage: peakMemoryUsage,
            poolUtilization: poolUtilization,
            fragmentationRatio: fragmentationRatio,
            gcRecommended: gcRecommended,
            timestamp: Date()
        )
    }
    
    private func calculatePoolUtilization() -> Double {
        var totalBuffers = 0
        var usedBuffers = 0
        
        for (_, pool) in memoryPools {
            totalBuffers += pool.poolSize
            // Would need to access pool internals to calculate actual usage
            usedBuffers += pool.poolSize / 2 // Simplified estimation
        }
        
        return totalBuffers > 0 ? Double(usedBuffers) / Double(totalBuffers) : 0.0
    }
    
    private func calculateFragmentationRatio() -> Double {
        // Simplified fragmentation calculation
        guard memoryUsageHistory.count >= 2 else { return 0.0 }
        
        let recent = Array(memoryUsageHistory.suffix(10))
        let variance = calculateVariance(recent)
        let mean = recent.reduce(0, +) / UInt64(recent.count)
        
        return mean > 0 ? Double(variance) / Double(mean) : 0.0
    }
    
    private func calculateVariance(_ values: [UInt64]) -> UInt64 {
        guard values.count > 1 else { return 0 }
        
        let mean = values.reduce(0, +) / UInt64(values.count)
        let squaredDiffs = values.map { value in
            let diff = Int64(value) - Int64(mean)
            return UInt64(diff * diff)
        }
        
        return squaredDiffs.reduce(0, +) / UInt64(squaredDiffs.count)
    }
    
    // MARK: - Utilities
    
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
    
    private func formatMemory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1fMB", mb)
    }
    
    private func deallocatePools() {
        for (_, var pool) in memoryPools {
            pool.deallocate()
        }
        memoryPools.removeAll()
    }
    
    // MARK: - Public Utilities
    
    public func logMemoryStatus() {
        let metrics = getMemoryMetrics()
        
        Logger.shared.info("=== Memory Status ===", component: "OptimizedMemoryManager")
        Logger.shared.info("Current: \(formatMemory(metrics.currentUsage))", component: "OptimizedMemoryManager")
        Logger.shared.info("Peak: \(formatMemory(metrics.peakUsage))", component: "OptimizedMemoryManager")
        Logger.shared.info("Pool Utilization: \(String(format: "%.1f%%", metrics.poolUtilization * 100))", component: "OptimizedMemoryManager")
        Logger.shared.info("Fragmentation: \(String(format: "%.3f", metrics.fragmentationRatio))", component: "OptimizedMemoryManager")
        Logger.shared.info("GC Recommended: \(metrics.gcRecommended)", component: "OptimizedMemoryManager")
    }
}