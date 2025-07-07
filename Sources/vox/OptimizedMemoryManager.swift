import Foundation

/// Advanced memory management with platform-specific optimizations
public final class OptimizedMemoryManager {
    // MARK: - Nested Types
    
    /// Memory pool for efficient buffer allocation
    private final class MemoryPool {
        let bufferSize: Int
        let poolSize: Int
        private var availableBuffers: [UnsafeMutableRawPointer]
        private var usedBuffers: Set<UnsafeMutableRawPointer>
        private let lock = NSLock()
        
        init(bufferSize: Int, poolSize: Int) {
            self.bufferSize = bufferSize
            self.poolSize = poolSize
            self.availableBuffers = []
            self.usedBuffers = []
            allocateBuffers()
        }
        
        private func allocateBuffers() {
            for _ in 0..<poolSize {
                let buffer = UnsafeMutableRawPointer.allocate(
                    byteCount: bufferSize,
                    alignment: MemoryLayout<UInt8>.alignment
                )
                availableBuffers.append(buffer)
            }
        }
        
        func borrowBuffer() -> UnsafeMutableRawPointer? {
            lock.lock()
            defer { lock.unlock() }
            
            guard let buffer = availableBuffers.popLast() else { return nil }
            usedBuffers.insert(buffer)
            return buffer
        }
        
        func returnBuffer(_ buffer: UnsafeMutableRawPointer) {
            lock.lock()
            defer { lock.unlock() }
            
            guard usedBuffers.remove(buffer) != nil else { return }
            buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)
            availableBuffers.append(buffer)
        }
        
        func deallocate() {
            lock.lock()
            defer { lock.unlock() }
            
            for buffer in availableBuffers + Array(usedBuffers) {
                buffer.deallocate()
            }
            availableBuffers.removeAll()
            usedBuffers.removeAll()
        }
    }
    
    /// Memory usage metrics
    public struct Metrics {
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
    private var memoryPools: [Int: MemoryPool]
    private let memoryQueue: DispatchQueue
    private let metricsLock: NSLock
    
    private var isMonitoring: Bool
    private var monitoringTimer: Timer?
    private var memoryUsageHistory: [UInt64]
    private var peakMemoryUsage: UInt64
    
    // MARK: - Initialization
    
    private init() {
        self.memoryConfig = platformOptimizer.getMemoryConfig()
        self.memoryPools = [:]
        self.memoryQueue = DispatchQueue(label: "vox.memory.manager", qos: .utility)
        self.metricsLock = NSLock()
        self.isMonitoring = false
        self.memoryUsageHistory = []
        self.peakMemoryUsage = 0
        setupMemoryPools()
    }
    
    deinit {
        stopMonitoring()
        deallocatePools()
    }
}

// MARK: - Public Interface

public extension OptimizedMemoryManager {
    func borrowBuffer(size: Int) -> UnsafeMutableRawPointer? {
        let suitableSize = memoryPools.keys.sorted().first { $0 >= size }
        
        guard let poolSize = suitableSize,
              let pool = memoryPools[poolSize] else {
            return UnsafeMutableRawPointer.allocate(
                byteCount: size,
                alignment: MemoryLayout<UInt8>.alignment
            )
        }
        
        return pool.borrowBuffer()
    }
    
    func returnBuffer(_ buffer: UnsafeMutableRawPointer, size: Int) {
        let suitableSize = memoryPools.keys.sorted().first { $0 >= size }
        
        guard let poolSize = suitableSize,
              let pool = memoryPools[poolSize] else {
            buffer.deallocate()
            return
        }
        
        pool.returnBuffer(buffer)
    }
    
    func getMetrics() -> Metrics {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        
        let currentUsage = getCurrentMemoryUsage()
        let threshold = UInt64(
            Double(memoryConfig.maxMemoryUsage) * memoryConfig.garbageCollectionThreshold
        )
        
        return Metrics(
            currentUsage: currentUsage,
            peakUsage: peakMemoryUsage,
            poolUtilization: calculatePoolUtilization(),
            fragmentationRatio: calculateFragmentationRatio(),
            gcRecommended: currentUsage > threshold,
            timestamp: Date()
        )
    }
    
    func startMonitoring(interval: TimeInterval? = nil) {
        guard !isMonitoring else { return }
        
        let monitoringInterval = interval ?? memoryConfig.garbageCollectionThreshold
        isMonitoring = true
        
        memoryQueue.async { [weak self] in
            self?.setupMonitoringTimer(interval: monitoringInterval)
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    func optimizedMemcopy(
        destination: UnsafeMutableRawPointer,
        source: UnsafeRawPointer,
        byteCount: Int
    ) {
        switch platformOptimizer.architecture {
        case .appleSilicon where memoryConfig.enableMemoryMapping && byteCount > 64 * 1024:
            performVMMemcopy(destination: destination, source: source, byteCount: byteCount)
        case .intel where byteCount > 128 * 1024:
            performChunkedMemcopy(destination: destination, source: source, byteCount: byteCount)
        default:
            destination.copyMemory(from: source, byteCount: byteCount)
        }
    }
}

// MARK: - Private Implementation

private extension OptimizedMemoryManager {
    func setupMemoryPools() {
        let audioConfig = platformOptimizer.getAudioProcessingConfig()
        let bufferSizes = [1024, 4096, audioConfig.bufferSize, 16384, 65536]
        
        for size in bufferSizes {
            memoryPools[size] = MemoryPool(
                bufferSize: size,
                poolSize: memoryConfig.bufferPoolSize
            )
        }
    }
    
    func deallocatePools() {
        for (_, pool) in memoryPools {
            pool.deallocate()
        }
        memoryPools.removeAll()
    }
    
    func setupMonitoringTimer(interval: TimeInterval) {
        monitoringTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.collectMetrics()
        }
        
        if let timer = monitoringTimer {
            RunLoop.current.add(timer, forMode: .default)
        }
        RunLoop.current.run()
    }
    
    func collectMetrics() {
        let currentUsage = getCurrentMemoryUsage()
        
        metricsLock.lock()
        memoryUsageHistory.append(currentUsage)
        peakMemoryUsage = max(peakMemoryUsage, currentUsage)
        
        if memoryUsageHistory.count > 100 {
            memoryUsageHistory.removeFirst()
        }
        metricsLock.unlock()
    }
    
    func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    func calculatePoolUtilization() -> Double {
        var totalBuffers = 0
        var usedBuffers = 0
        
        for (_, pool) in memoryPools {
            totalBuffers += pool.poolSize
            usedBuffers += pool.poolSize / 2 // Simplified estimation
        }
        
        return totalBuffers > 0 ? Double(usedBuffers) / Double(totalBuffers) : 0.0
    }
    
    func calculateFragmentationRatio() -> Double {
        guard memoryUsageHistory.count >= 2 else { return 0.0 }
        
        let recent = Array(memoryUsageHistory.suffix(10))
        let variance = calculateVariance(recent)
        let mean = recent.reduce(0, +) / UInt64(recent.count)
        
        return mean > 0 ? Double(variance) / Double(mean) : 0.0
    }
    
    func calculateVariance(_ values: [UInt64]) -> UInt64 {
        guard values.count > 1 else { return 0 }
        
        let mean = values.reduce(0, +) / UInt64(values.count)
        let squaredDiffs = values.map { value in
            let diff = Int64(value) - Int64(mean)
            return UInt64(diff * diff)
        }
        
        return squaredDiffs.reduce(0, +) / UInt64(squaredDiffs.count)
    }
    
    func performVMMemcopy(
        destination: UnsafeMutableRawPointer,
        source: UnsafeRawPointer,
        byteCount: Int
    ) {
        let pageSize = vm_page_size
        let alignedSize = (byteCount + Int(pageSize) - 1) & ~(Int(pageSize) - 1)
        
        if alignedSize == byteCount {
            let sourceVmAddress = vm_address_t(UInt(bitPattern: source))
            let destVmAddress = vm_address_t(UInt(bitPattern: destination))
            
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
        
        destination.copyMemory(from: source, byteCount: byteCount)
    }
    
    func performChunkedMemcopy(
        destination: UnsafeMutableRawPointer,
        source: UnsafeRawPointer,
        byteCount: Int
    ) {
        let chunkSize = 64 * 1024
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
}
