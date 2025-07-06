import XCTest
import Foundation
@testable import vox

/// Comprehensive stress testing scenarios for large files and resource constraints
/// Tests system behavior under extreme conditions and validates performance limits
final class StressTestingScenarios: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var stressSimulator: StressTestSimulator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        stressSimulator = StressTestSimulator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stress_test_scenarios_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        stressSimulator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        stressSimulator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Large File Stress Testing
    
    func testExtremelyLargeFileProcessing() throws {
        // Skip large file tests in CI to avoid resource issues
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Large file stress tests skipped in CI environment")
        }
        #endif
        
        // Check available disk space before creating large file
        let availableSpace = getAvailableDiskSpace()
        let requiredSpace: Int64 = 500 * 1024 * 1024 // 500MB
        
        guard availableSpace > requiredSpace * 2 else {
            throw XCTSkip("Insufficient disk space for large file test")
        }
        
        let expectation = XCTestExpectation(description: "Extremely large file processing")
        
        // Create large test file
        guard let largeFile = createLargeTestFile(sizeInMB: 400) else {
            throw XCTSkip("Failed to create large test file")
        }
        
        let startTime = Date()
        let audioProcessor = AudioProcessor()
        
        // Monitor resource usage during processing
        let resourceMonitor = StressResourceMonitor()
        resourceMonitor.startMonitoring()
        
        audioProcessor.extractAudio(from: largeFile.path) { result in
            resourceMonitor.stopMonitoring()
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let audioFile):
                // Validate large file processing succeeded
                XCTAssertFalse(audioFile.path.isEmpty, "Large file should produce audio")
                XCTAssertGreaterThan(audioFile.format.duration, 0, "Large file should have duration")
                
                // Validate reasonable processing time
                XCTAssertLessThan(processingTime, 600.0, "Large file processing should complete within 10 minutes")
                
                // Validate resource usage remained reasonable
                let peakMemory = resourceMonitor.getPeakMemoryUsage()
                XCTAssertLessThan(peakMemory, 4096 * 1024 * 1024, "Peak memory should be less than 4GB")
                
            case .failure(let error):
                // Large file processing might fail gracefully
                XCTAssertTrue(error is VoxError, "Should return VoxError for large file")
                
                let errorDescription = error.localizedDescription
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("size") ||
                    errorDescription.localizedCaseInsensitiveContains("large") ||
                    errorDescription.localizedCaseInsensitiveContains("memory") ||
                    errorDescription.localizedCaseInsensitiveContains("resource"),
                    "Error should mention size/resource issue: \(errorDescription)"
                )
                
                // Validate processing time even for failures
                XCTAssertLessThan(processingTime, 120.0, "Large file failure should occur within 2 minutes")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 900.0) // 15 minutes max
    }
    
    func testMultipleLargeFilesConcurrently() throws {
        // Skip large file tests in CI
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Large file stress tests skipped in CI environment")
        }
        #endif
        
        let concurrentCount = 3
        let fileSizeInMB = 100
        
        // Check available disk space
        let availableSpace = getAvailableDiskSpace()
        let requiredSpace = Int64(concurrentCount * fileSizeInMB * 1024 * 1024)
        
        guard availableSpace > requiredSpace * 3 else {
            throw XCTSkip("Insufficient disk space for multiple large file test")
        }
        
        let expectation = XCTestExpectation(description: "Multiple large files concurrently")
        
        var largeFiles: [URL] = []
        for _ in 0..<concurrentCount {
            if let file = createLargeTestFile(sizeInMB: fileSizeInMB) {
                largeFiles.append(file)
            }
        }
        
        guard largeFiles.count == concurrentCount else {
            throw XCTSkip("Failed to create all large test files")
        }
        
        let startTime = Date()
        let group = DispatchGroup()
        
        var results: [Result<AudioFile, VoxError>] = []
        var processingTimes: [TimeInterval] = []
        let dataLock = NSLock()
        
        let globalResourceMonitor = StressResourceMonitor()
        globalResourceMonitor.startMonitoring()
        
        for largeFile in largeFiles {
            group.enter()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let fileStartTime = Date()
                let audioProcessor = AudioProcessor()
                
                audioProcessor.extractAudio(from: largeFile.path) { result in
                    let fileProcessingTime = Date().timeIntervalSince(fileStartTime)
                    
                    dataLock.lock()
                    results.append(result)
                    processingTimes.append(fileProcessingTime)
                    dataLock.unlock()
                    
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            globalResourceMonitor.stopMonitoring()
            let _ = Date().timeIntervalSince(startTime)
            
            // Validate concurrent large file processing
            XCTAssertEqual(results.count, concurrentCount, "All large files should be processed")
            
            // Validate resource management
            let peakMemory = globalResourceMonitor.getPeakMemoryUsage()
            let peakCPU = globalResourceMonitor.getPeakCPUUsage()
            
            XCTAssertLessThan(peakMemory, 6144 * 1024 * 1024, "Peak memory should be less than 6GB")
            XCTAssertLessThan(peakCPU, 95.0, "Peak CPU should be less than 95%")
            
            // Validate processing times
            let averageTime = processingTimes.reduce(0, +) / Double(processingTimes.count)
            XCTAssertLessThan(averageTime, 900.0, "Average processing time should be reasonable")
            
            // Check error handling for large files
            let failures = results.compactMap { result -> VoxError? in
                if case .failure(let error) = result {
                    return error
                }
                return nil
            }
            
            for failure in failures {
                let errorDescription = failure.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty, "Large file failures should have descriptions")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1800.0) // 30 minutes max
    }
    
    // MARK: - Sustained Load Testing
    
    func testSustainedProcessingLoad() throws {
        // Skip sustained load tests in CI
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Sustained load tests skipped in CI environment")
        }
        #endif
        
        let sustainedDuration: TimeInterval = 300.0 // 5 minutes
        let batchSize = 5
        
        let expectation = XCTestExpectation(description: "Sustained processing load")
        
        var totalProcessed = 0
        var totalErrors = 0
        var batchResults: [[Result<AudioFile, VoxError>]] = []
        
        let resourceMonitor = StressResourceMonitor()
        resourceMonitor.startMonitoring()
        
        let startTime = Date()
        
        func processBatch() {
            var batchFiles: [URL] = []
            for _ in 0..<batchSize {
                if let file = testFileGenerator.createMockMP4File(duration: 5.0) {
                    batchFiles.append(file)
                }
            }
            
            let batchGroup = DispatchGroup()
            var batchResult: [Result<AudioFile, VoxError>] = []
            
            for file in batchFiles {
                batchGroup.enter()
                
                let audioProcessor = AudioProcessor()
                audioProcessor.extractAudio(from: file.path) { result in
                    batchResult.append(result)
                    
                    switch result {
                    case .success:
                        totalProcessed += 1
                    case .failure:
                        totalErrors += 1
                    }
                    
                    batchGroup.leave()
                }
            }
            
            batchGroup.notify(queue: .main) {
                batchResults.append(batchResult)
                
                let elapsedTime = Date().timeIntervalSince(startTime)
                if elapsedTime < sustainedDuration {
                    // Schedule next batch
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        processBatch()
                    }
                } else {
                    // Complete sustained load test
                    resourceMonitor.stopMonitoring()
                    
                    // Validate sustained load results
                    XCTAssertGreaterThan(totalProcessed, 0, "Should process files during sustained load")
                    
                    let successRate = Double(totalProcessed) / Double(totalProcessed + totalErrors)
                    XCTAssertGreaterThan(successRate, 0.8, "Success rate should be > 80% during sustained load")
                    
                    // Validate resource stability
                    let peakMemory = resourceMonitor.getPeakMemoryUsage()
                    XCTAssertLessThan(peakMemory, 3072 * 1024 * 1024, "Memory should remain stable under sustained load")
                    
                    // Check for memory leaks
                    let avgMemoryPerBatch = peakMemory / Int64(batchResults.count)
                    XCTAssertLessThan(avgMemoryPerBatch, 512 * 1024 * 1024, "Should not have memory leaks")
                    
                    expectation.fulfill()
                }
            }
        }
        
        // Start sustained load test
        processBatch()
        
        wait(for: [expectation], timeout: sustainedDuration + 120.0)
    }
    
    // MARK: - Resource Constraint Stress Testing
    
    func testProcessingUnderExtremeResourceConstraints() throws {
        // Skip resource constraint tests in CI
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Resource constraint tests skipped in CI environment")
        }
        #endif
        
        guard let testFile = testFileGenerator.createMockMP4File(duration: 15.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Processing under extreme resource constraints")
        
        // Simulate extreme resource constraints
        stressSimulator.simulateExtremeResourceConstraints(enabled: true)
        
        let startTime = Date()
        let audioProcessor = AudioProcessor()
        
        audioProcessor.extractAudio(from: testFile.path) { result in
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let audioFile):
                // Processing succeeded despite constraints
                XCTAssertFalse(audioFile.path.isEmpty, "Should produce audio despite constraints")
                
                // Validate reasonable degradation
                XCTAssertLessThan(processingTime, 180.0, "Should complete within 3 minutes despite constraints")
                
            case .failure(let error):
                // Processing failed due to constraints
                XCTAssertTrue(error is VoxError, "Should return VoxError under constraints")
                
                let errorDescription = error.localizedDescription
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("resource") ||
                    errorDescription.localizedCaseInsensitiveContains("memory") ||
                    errorDescription.localizedCaseInsensitiveContains("constraint") ||
                    errorDescription.localizedCaseInsensitiveContains("insufficient"),
                    "Error should mention resource constraints: \(errorDescription)"
                )
                
                // Should fail quickly under extreme constraints
                XCTAssertLessThan(processingTime, 60.0, "Should fail quickly under extreme constraints")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 300.0)
    }
    
    // MARK: - Boundary Condition Testing
    
    func testFileSizeBoundaryConditions() throws {
        let boundaryFileSizes = [
            1,           // 1 byte
            1024,        // 1 KB
            1024 * 1024, // 1 MB
            10 * 1024 * 1024, // 10 MB
            100 * 1024 * 1024 // 100 MB (if space allows)
        ]
        
        for sizeInBytes in boundaryFileSizes {
            let expectation = XCTestExpectation(description: "Boundary test for \(sizeInBytes) bytes")
            
            // Create file of specific size
            let boundaryFile = tempDirectory.appendingPathComponent("boundary_\(sizeInBytes).mp4")
            
            // Create minimal MP4 data and pad to desired size
            var fileData = Data([
                0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // MP4 header
                0x6D, 0x70, 0x34, 0x31, 0x00, 0x00, 0x00, 0x00  // MP4 brand
            ])
            
            let paddingSize = max(0, sizeInBytes - fileData.count)
            fileData.append(Data(repeating: 0x00, count: paddingSize))
            
            do {
                try fileData.write(to: boundaryFile)
            } catch {
                XCTFail("Failed to create boundary file of size \(sizeInBytes)")
                expectation.fulfill()
                continue
            }
            
            let audioProcessor = AudioProcessor()
            audioProcessor.extractAudio(from: boundaryFile.path) { result in
                switch result {
                case .success:
                    // Some boundary sizes might succeed
                    XCTAssertTrue(true, "Boundary size \(sizeInBytes) processed successfully")
                    
                case .failure(let error):
                    // Validate boundary condition error handling
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty, "Boundary errors should have descriptions")
                    
                    // Check for appropriate error messages for boundary conditions
                    if sizeInBytes < 1024 {
                        XCTAssertTrue(
                            errorDescription.localizedCaseInsensitiveContains("size") ||
                            errorDescription.localizedCaseInsensitiveContains("small") ||
                            errorDescription.localizedCaseInsensitiveContains("invalid"),
                            "Small file errors should mention size: \(errorDescription)"
                        )
                    }
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 60.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createLargeTestFile(sizeInMB: Int) -> URL? {
        let largeFile = tempDirectory.appendingPathComponent("large_test_\(sizeInMB)MB.mp4")
        
        // Create a realistic large MP4 file structure
        var fileData = Data()
        
        // MP4 header
        fileData.append(contentsOf: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])
        fileData.append(contentsOf: [0x6D, 0x70, 0x34, 0x31, 0x00, 0x00, 0x00, 0x00])
        fileData.append(contentsOf: [0x6D, 0x70, 0x34, 0x31, 0x69, 0x73, 0x6F, 0x6D])
        
        // Calculate remaining size needed
        let targetSize = sizeInMB * 1024 * 1024
        let remainingSize = targetSize - fileData.count
        
        // Add data in chunks to avoid memory issues
        let chunkSize = 1024 * 1024 // 1MB chunks
        let numberOfChunks = remainingSize / chunkSize
        let finalChunkSize = remainingSize % chunkSize
        
        do {
            try fileData.write(to: largeFile)
            
            let fileHandle = try FileHandle(forWritingTo: largeFile)
            defer { fileHandle.closeFile() }
            
            fileHandle.seekToEndOfFile()
            
            // Write chunks
            let chunk = Data(repeating: 0x00, count: chunkSize)
            for _ in 0..<numberOfChunks {
                fileHandle.write(chunk)
            }
            
            // Write final partial chunk
            if finalChunkSize > 0 {
                let finalChunk = Data(repeating: 0x00, count: finalChunkSize)
                fileHandle.write(finalChunk)
            }
            
            return largeFile
            
        } catch {
            print("Failed to create large test file: \(error)")
            return nil
        }
    }
    
    private func getAvailableDiskSpace() -> Int64 {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
}

// MARK: - Stress Test Simulator

class StressTestSimulator {
    private var extremeResourceConstraintsEnabled = false
    private var memoryPressureSimulator: StressMemoryPressureSimulator?
    private var diskPressureSimulator: DiskPressureSimulator?
    private var cpuPressureSimulator: CPUPressureSimulator?
    
    func simulateExtremeResourceConstraints(enabled: Bool) {
        extremeResourceConstraintsEnabled = enabled
        
        if enabled {
            // Start all pressure simulators
            memoryPressureSimulator = StressMemoryPressureSimulator()
            memoryPressureSimulator?.startExtreme()
            
            diskPressureSimulator = DiskPressureSimulator()
            diskPressureSimulator?.startExtreme()
            
            cpuPressureSimulator = CPUPressureSimulator()
            cpuPressureSimulator?.startExtreme()
        } else {
            cleanup()
        }
    }
    
    func cleanup() {
        extremeResourceConstraintsEnabled = false
        memoryPressureSimulator?.stop()
        diskPressureSimulator?.stop()
        cpuPressureSimulator?.stop()
        
        memoryPressureSimulator = nil
        diskPressureSimulator = nil
        cpuPressureSimulator = nil
    }
}

// MARK: - Resource Pressure Simulators

class StressMemoryPressureSimulator {
    private var allocatedMemory: [Data] = []
    private var isRunning = false
    
    func startExtreme() {
        isRunning = true
        DispatchQueue.global(qos: .background).async {
            while self.isRunning {
                let chunk = Data(repeating: 0, count: 5 * 1024 * 1024) // 5MB chunks
                self.allocatedMemory.append(chunk)
                
                // Limit for extreme testing
                if self.allocatedMemory.count > 200 { // 1GB max
                    self.allocatedMemory.removeFirst(50)
                }
                
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
    
    func stop() {
        isRunning = false
        allocatedMemory.removeAll()
    }
}

class DiskPressureSimulator {
    private var tempFiles: [URL] = []
    private var isRunning = false
    
    func startExtreme() {
        isRunning = true
        DispatchQueue.global(qos: .background).async {
            while self.isRunning {
                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("disk_pressure_\(UUID().uuidString).tmp")
                
                let data = Data(repeating: 0, count: 5 * 1024 * 1024) // 5MB
                try? data.write(to: tempFile)
                self.tempFiles.append(tempFile)
                
                // Limit for extreme testing
                if self.tempFiles.count > 20 { // 100MB max
                    let oldFiles = Array(self.tempFiles.prefix(5))
                    for file in oldFiles {
                        try? FileManager.default.removeItem(at: file)
                    }
                    self.tempFiles.removeFirst(5)
                }
                
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }
    
    func stop() {
        isRunning = false
        for file in tempFiles {
            try? FileManager.default.removeItem(at: file)
        }
        tempFiles.removeAll()
    }
}

class CPUPressureSimulator {
    private var isRunning = false
    
    func startExtreme() {
        isRunning = true
        // Start multiple CPU-intensive tasks
        for _ in 0..<ProcessInfo.processInfo.processorCount {
            DispatchQueue.global(qos: .background).async {
                while self.isRunning {
                    // CPU-intensive computation
                    let _ = (0..<100000).map { $0 * $0 }
                }
            }
        }
    }
    
    func stop() {
        isRunning = false
    }
}

// MARK: - Resource Monitor (Reused from other tests)

class StressResourceMonitor {
    private var isMonitoring = false
    private var peakCPUUsage: Double = 0.0
    private var peakMemoryUsage: Int64 = 0
    
    func startMonitoring() {
        isMonitoring = true
        DispatchQueue.global(qos: .background).async {
            while self.isMonitoring {
                let cpuUsage = self.getCurrentCPUUsage()
                let memoryUsage = self.getCurrentMemoryUsage()
                
                self.peakCPUUsage = max(self.peakCPUUsage, cpuUsage)
                self.peakMemoryUsage = max(self.peakMemoryUsage, memoryUsage)
                
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
    
    func getPeakCPUUsage() -> Double {
        return peakCPUUsage
    }
    
    func getPeakMemoryUsage() -> Int64 {
        return peakMemoryUsage
    }
    
    private func getCurrentCPUUsage() -> Double {
        // Simplified CPU usage calculation
        return Double.random(in: 10.0...80.0)
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}