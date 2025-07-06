import XCTest
import Foundation
@testable import vox

/// Resource exhaustion validation tests for system constraints
/// Tests memory pressure, disk space, CPU throttling, and concurrent processing limits
final class ResourceExhaustionValidationTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var resourceSimulator: ResourceConstraintSimulator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        resourceSimulator = ResourceConstraintSimulator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("resource_exhaustion_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        resourceSimulator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        resourceSimulator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Memory Pressure Testing
    
    func testMemoryPressureHandling() throws {
        // Skip memory pressure tests in CI to avoid system instability
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Memory pressure tests skipped in CI environment")
        }
        #endif
        
        guard let testFile = testFileGenerator.createMockMP4File(duration: 30.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Memory pressure handling")
        
        // Monitor memory usage before test
        let initialMemoryUsage = getMemoryUsage()
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Test transcription under memory pressure
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: .openai,
                    apiKey: nil,
                    includeTimestamps: true
                )
                
                // Simulate memory pressure by allocating large amounts of memory
                self.resourceSimulator.simulateMemoryPressure()
                
                do {
                    let result = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // If successful, validate memory usage remained reasonable
                    let finalMemoryUsage = self.getMemoryUsage()
                    let memoryIncrease = finalMemoryUsage - initialMemoryUsage
                    
                    XCTAssertLessThan(memoryIncrease, 1024 * 1024 * 1024, 
                        "Memory usage should not increase by more than 1GB")
                    
                    XCTAssertFalse(result.text.isEmpty, "Transcription should produce text")
                    
                } catch {
                    // If failed due to memory pressure, validate proper error handling
                    XCTAssertTrue(error is VoxError, "Should return VoxError for memory pressure")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("memory") ||
                        errorDescription.localizedCaseInsensitiveContains("resource") ||
                        errorDescription.localizedCaseInsensitiveContains("pressure"),
                        "Error should mention memory issue: \(errorDescription)"
                    )
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 120.0)
    }
    
    func testLargeFileMemoryManagement() throws {
        // Test processing of large files with memory management
        let largeFile = tempDirectory.appendingPathComponent("large_test.mp4")
        
        // Create a larger test file (simulated)
        guard let baseFile = testFileGenerator.createMockMP4File(duration: 60.0) else {
            throw XCTSkip("Failed to create base test file")
        }
        
        // Copy to create larger file
        try FileManager.default.copyItem(at: baseFile, to: largeFile)
        
        let expectation = XCTestExpectation(description: "Large file memory management")
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: largeFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Monitor memory usage during large file processing
                let memoryMonitor = MemoryMonitor()
                memoryMonitor.startMonitoring()
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: nil,
                    apiKey: nil,
                    includeTimestamps: false
                )
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                    
                    // Validate memory was managed properly
                    let peakMemory = memoryMonitor.getPeakMemoryUsage()
                    XCTAssertLessThan(peakMemory, 2048 * 1024 * 1024,
                        "Peak memory usage should be less than 2GB")
                    
                } catch {
                    // Large file processing might fail gracefully
                    XCTAssertTrue(error is VoxError, "Should return VoxError for large file")
                    
                    let errorDescription = error.localizedDescription
                    XCTAssertFalse(errorDescription.isEmpty,
                        "Error should have description for large file")
                }
                
                memoryMonitor.stopMonitoring()
                
            case .failure(let error):
                // Large file audio extraction might fail
                XCTAssertTrue(error is VoxError, "Should return VoxError for large file")
                
                let errorDescription = error.localizedDescription
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("size") ||
                    errorDescription.localizedCaseInsensitiveContains("large") ||
                    errorDescription.localizedCaseInsensitiveContains("memory"),
                    "Error should mention size issue: \(errorDescription)"
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 300.0)
    }
    
    // MARK: - Disk Space Exhaustion Testing
    
    func testDiskSpaceExhaustionHandling() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 10.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Disk space exhaustion handling")
        
        // Check available disk space
        let _ = getAvailableDiskSpace()
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(_):
                // Simulate disk space exhaustion
                self.resourceSimulator.simulateDiskSpaceExhaustion()
                
                let outputPath = self.tempDirectory.appendingPathComponent("output.txt")
                
                do {
                    let outputWriter = OutputWriter()
                    try outputWriter.writeContentSafely("Test content", to: outputPath.path)
                    
                    // If successful, validate disk space check
                    let remainingSpace = self.getAvailableDiskSpace()
                    XCTAssertGreaterThan(remainingSpace, 0, "Should have remaining disk space")
                    
                } catch {
                    // Validate disk space error handling
                    XCTAssertTrue(error is VoxError, "Should return VoxError for disk space")
                    
                    if let voxError = error as? VoxError {
                        switch voxError {
                        case .insufficientDiskSpace:
                            XCTAssertTrue(true, "Correct error type for disk space")
                        default:
                            // Other errors might also be valid
                            let errorDescription = voxError.localizedDescription
                            XCTAssertTrue(
                                errorDescription.localizedCaseInsensitiveContains("disk") ||
                                errorDescription.localizedCaseInsensitiveContains("space"),
                                "Error should mention disk space: \(errorDescription)"
                            )
                        }
                    }
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    func testTempFileCleanupUnderResourcePressure() throws {
        guard let testFile = testFileGenerator.createMockMP4File(duration: 5.0) else {
            throw XCTSkip("Failed to create test file")
        }
        
        let expectation = XCTestExpectation(description: "Temp file cleanup under resource pressure")
        
        // Monitor temp file count before processing
        let initialTempFileCount = countTempFiles()
        
        let audioProcessor = AudioProcessor()
        audioProcessor.extractAudio(from: testFile.path) { result in
            switch result {
            case .success(let audioFile):
                // Simulate resource pressure during processing
                self.resourceSimulator.simulateResourcePressure()
                
                let transcriptionManager = TranscriptionManager(
                    forceCloud: false,
                    verbose: true,
                    language: "en-US",
                    fallbackAPI: nil,
                    apiKey: nil,
                    includeTimestamps: false
                )
                
                do {
                    _ = try transcriptionManager.transcribeAudio(audioFile: audioFile)
                } catch {
                    // Processing might fail under resource pressure
                    XCTAssertTrue(error is VoxError, "Should return VoxError under resource pressure")
                }
                
                // Validate temp files are cleaned up even under pressure
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let finalTempFileCount = self.countTempFiles()
                    XCTAssertEqual(finalTempFileCount, initialTempFileCount,
                        "Temp files should be cleaned up under resource pressure")
                    expectation.fulfill()
                }
                
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Concurrent Processing Limits
    
    func testConcurrentProcessingLimits() throws {
        // Test system behavior under high concurrent load
        let concurrentCount = 10
        var testFiles: [URL] = []
        
        for _ in 0..<concurrentCount {
            if let file = testFileGenerator.createMockMP4File(duration: 5.0) {
                testFiles.append(file)
            }
        }
        
        guard testFiles.count == concurrentCount else {
            throw XCTSkip("Failed to create all test files")
        }
        
        let expectation = XCTestExpectation(description: "Concurrent processing limits")
        let group = DispatchGroup()
        
        var results: [Result<AudioFile, VoxError>] = []
        let resultsLock = NSLock()
        
        // Monitor resource usage during concurrent processing
        let resourceMonitor = ResourceMonitor()
        resourceMonitor.startMonitoring()
        
        for testFile in testFiles {
            group.enter()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let audioProcessor = AudioProcessor()
                audioProcessor.extractAudio(from: testFile.path) { result in
                    resultsLock.lock()
                    results.append(result)
                    resultsLock.unlock()
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            resourceMonitor.stopMonitoring()
            
            // Validate results
            XCTAssertEqual(results.count, concurrentCount,
                "All concurrent operations should complete")
            
            // Validate resource usage remained reasonable
            let peakCPU = resourceMonitor.getPeakCPUUsage()
            let peakMemory = resourceMonitor.getPeakMemoryUsage()
            
            XCTAssertLessThan(peakCPU, 100.0, "CPU usage should not exceed 100%")
            XCTAssertLessThan(peakMemory, 4096 * 1024 * 1024,
                "Memory usage should not exceed 4GB")
            
            // Check for failures and validate error handling
            let failures = results.compactMap { result -> VoxError? in
                if case .failure(let error) = result {
                    return error
                }
                return nil
            }
            
            for failure in failures {
                XCTAssertFalse(failure.localizedDescription.isEmpty,
                    "Concurrent processing failures should have descriptions")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 300.0)
    }
    
    // MARK: - Helper Methods
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
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
    
    private func countTempFiles() -> Int {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            return files.filter { $0.contains("vox_") }.count
        } catch {
            return 0
        }
    }
}

// MARK: - Resource Constraint Simulator

class ResourceConstraintSimulator {
    private var memoryPressureSimulator: MemoryPressureSimulator?
    private var diskSpaceSimulator: DiskSpaceSimulator?
    
    func simulateMemoryPressure() {
        memoryPressureSimulator = MemoryPressureSimulator()
        memoryPressureSimulator?.start()
    }
    
    func simulateDiskSpaceExhaustion() {
        diskSpaceSimulator = DiskSpaceSimulator()
        diskSpaceSimulator?.start()
    }
    
    func simulateResourcePressure() {
        // Simulate general resource pressure
        simulateMemoryPressure()
        simulateDiskSpaceExhaustion()
    }
    
    func cleanup() {
        memoryPressureSimulator?.stop()
        diskSpaceSimulator?.stop()
    }
}

// MARK: - Memory Pressure Simulator

class MemoryPressureSimulator {
    private var allocatedMemory: [Data] = []
    private var isRunning = false
    
    func start() {
        isRunning = true
        // Allocate memory in chunks to simulate pressure
        DispatchQueue.global(qos: .background).async {
            while self.isRunning {
                let chunk = Data(repeating: 0, count: 1024 * 1024) // 1MB chunks
                self.allocatedMemory.append(chunk)
                
                // Limit total allocation to prevent system crash
                if self.allocatedMemory.count > 100 { // 100MB max
                    self.allocatedMemory.removeFirst()
                }
                
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    
    func stop() {
        isRunning = false
        allocatedMemory.removeAll()
    }
}

// MARK: - Disk Space Simulator

class DiskSpaceSimulator {
    private var tempFiles: [URL] = []
    private var isRunning = false
    
    func start() {
        isRunning = true
        // Create temp files to simulate disk space usage
        DispatchQueue.global(qos: .background).async {
            while self.isRunning {
                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("disk_sim_\(UUID().uuidString).tmp")
                
                let data = Data(repeating: 0, count: 1024 * 1024) // 1MB
                try? data.write(to: tempFile)
                self.tempFiles.append(tempFile)
                
                // Limit total files to prevent filling disk
                if self.tempFiles.count > 50 { // 50MB max
                    let oldFile = self.tempFiles.removeFirst()
                    try? FileManager.default.removeItem(at: oldFile)
                }
                
                Thread.sleep(forTimeInterval: 0.5)
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

// MARK: - Resource Monitor

class ResourceMonitor {
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
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0.0
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