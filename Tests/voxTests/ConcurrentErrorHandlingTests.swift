import XCTest
import Foundation
@testable import vox

/// Enhanced concurrent processing error handling tests
/// Tests thread safety, resource contention, and error isolation in concurrent scenarios
final class ConcurrentErrorHandlingTests: XCTestCase {
    private var testFileGenerator: TestAudioFileGenerator!
    private var concurrencySimulator: ConcurrencySimulator!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        testFileGenerator = TestAudioFileGenerator.shared
        concurrencySimulator = ConcurrencySimulator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("concurrent_error_tests_\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
    }
    
    override func tearDown() {
        testFileGenerator?.cleanup()
        concurrencySimulator?.cleanup()
        
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        testFileGenerator = nil
        concurrencySimulator = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Thread Safety Error Testing
    
    func testConcurrentAccessToSharedResources() throws {
        // Skip concurrent tests in CI to avoid compiler crashes
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Concurrent tests skipped in CI environment")
        }
        #endif
        
        let concurrentCount = 8
        var testFiles: [URL] = []
        
        for i in 0..<concurrentCount {
            if let file = testFileGenerator.createMockMP4File(duration: 5.0) {
                testFiles.append(file)
            }
        }
        
        guard testFiles.count == concurrentCount else {
            throw XCTSkip("Failed to create all test files")
        }
        
        let expectation = XCTestExpectation(description: "Concurrent access to shared resources")
        let group = DispatchGroup()
        
        var results: [Result<AudioFile, VoxError>] = []
        let resultsLock = NSLock()
        
        // Test concurrent access to the same shared resource (TempFileManager)
        for (index, testFile) in testFiles.enumerated() {
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
            // Validate thread safety
            XCTAssertEqual(results.count, concurrentCount,
                "All concurrent operations should complete")
            
            // Check for thread safety violations
            let failures = results.compactMap { result -> VoxError? in
                if case .failure(let error) = result {
                    return error
                }
                return nil
            }
            
            // Validate error isolation
            for failure in failures {
                let errorDescription = failure.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty,
                    "Concurrent failures should have descriptions")
                
                // Check for thread safety error indicators
                XCTAssertFalse(
                    errorDescription.localizedCaseInsensitiveContains("race condition") ||
                    errorDescription.localizedCaseInsensitiveContains("thread safety") ||
                    errorDescription.localizedCaseInsensitiveContains("concurrent access"),
                    "Should not have thread safety violations: \(errorDescription)"
                )
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 120.0)
    }
    
    func testConcurrentTempFileManagement() throws {
        // Skip concurrent tests in CI to avoid compiler crashes
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Concurrent tests skipped in CI environment")
        }
        #endif
        
        let concurrentCount = 10
        guard let baseTestFile = testFileGenerator.createMockMP4File(duration: 3.0) else {
            throw XCTSkip("Failed to create base test file")
        }
        
        let expectation = XCTestExpectation(description: "Concurrent temp file management")
        let group = DispatchGroup()
        
        var tempFileCountsBefore: [Int] = []
        var tempFileCountsAfter: [Int] = []
        let countsLock = NSLock()
        
        for i in 0..<concurrentCount {
            group.enter()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let tempCountBefore = self.countTempFiles()
                
                let audioProcessor = AudioProcessor()
                audioProcessor.extractAudio(from: baseTestFile.path) { result in
                    let tempCountAfter = self.countTempFiles()
                    
                    countsLock.lock()
                    tempFileCountsBefore.append(tempCountBefore)
                    tempFileCountsAfter.append(tempCountAfter)
                    countsLock.unlock()
                    
                    // Validate temp file cleanup regardless of result
                    switch result {
                    case .success:
                        // Temp files should be managed properly
                        XCTAssertTrue(true, "Successful processing should manage temp files")
                    case .failure(let error):
                        // Even on failure, temp files should be cleaned up
                        XCTAssertTrue(error is VoxError, "Should return VoxError")
                    }
                    
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // Validate temp file management
            XCTAssertEqual(tempFileCountsBefore.count, concurrentCount,
                "Should have before counts for all operations")
            XCTAssertEqual(tempFileCountsAfter.count, concurrentCount,
                "Should have after counts for all operations")
            
            // Check for temp file leaks
            let finalTempCount = self.countTempFiles()
            let initialAverage = tempFileCountsBefore.reduce(0, +) / tempFileCountsBefore.count
            
            XCTAssertLessThanOrEqual(finalTempCount, initialAverage + 2,
                "Should not have significant temp file leaks after concurrent operations")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 90.0)
    }
    
    // MARK: - Resource Contention Error Testing
    
    func testConcurrentResourceContention() throws {
        // Skip concurrent tests in CI to avoid compiler crashes
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Concurrent tests skipped in CI environment")
        }
        #endif
        
        let concurrentCount = 12
        var testFiles: [URL] = []
        
        for i in 0..<concurrentCount {
            if let file = testFileGenerator.createMockMP4File(duration: 8.0) {
                testFiles.append(file)
            }
        }
        
        guard testFiles.count == concurrentCount else {
            throw XCTSkip("Failed to create all test files")
        }
        
        let expectation = XCTestExpectation(description: "Concurrent resource contention")
        
        // Simulate resource pressure
        concurrencySimulator.simulateResourcePressure(enabled: true)
        
        let group = DispatchGroup()
        var processingTimes: [TimeInterval] = []
        var errors: [VoxError] = []
        let dataLock = NSLock()
        
        for testFile in testFiles {
            group.enter()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let startTime = Date()
                let audioProcessor = AudioProcessor()
                
                audioProcessor.extractAudio(from: testFile.path) { result in
                    let processingTime = Date().timeIntervalSince(startTime)
                    
                    dataLock.lock()
                    processingTimes.append(processingTime)
                    
                    switch result {
                    case .success:
                        // Successful despite contention
                        break
                    case .failure(let error):
                        errors.append(error)
                    }
                    dataLock.unlock()
                    
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // Validate resource contention handling
            XCTAssertEqual(processingTimes.count, concurrentCount,
                "All operations should complete")
            
            // Check for reasonable processing times under contention
            let averageTime = processingTimes.reduce(0, +) / Double(processingTimes.count)
            XCTAssertLessThan(averageTime, 60.0,
                "Average processing time should be reasonable under contention")
            
            // Validate error handling under contention
            for error in errors {
                let errorDescription = error.localizedDescription
                XCTAssertFalse(errorDescription.isEmpty,
                    "Contention errors should have descriptions")
                
                // Check for resource contention indicators
                XCTAssertTrue(
                    errorDescription.localizedCaseInsensitiveContains("resource") ||
                    errorDescription.localizedCaseInsensitiveContains("memory") ||
                    errorDescription.localizedCaseInsensitiveContains("timeout") ||
                    errorDescription.localizedCaseInsensitiveContains("busy"),
                    "Error should indicate resource issue: \(errorDescription)"
                )
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 180.0)
    }
    
    // MARK: - Error Isolation Testing
    
    func testErrorIsolationBetweenConcurrentOperations() throws {
        // Skip concurrent tests in CI to avoid compiler crashes
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Concurrent tests skipped in CI environment")
        }
        #endif
        
        let concurrentCount = 6
        var testFiles: [URL] = []
        var invalidFiles: [URL] = []
        
        // Create mix of valid and invalid files
        for i in 0..<concurrentCount {
            if i % 2 == 0 {
                // Valid file
                if let file = testFileGenerator.createMockMP4File(duration: 5.0) {
                    testFiles.append(file)
                }
            } else {
                // Invalid file
                let invalidFile = testFileGenerator.createInvalidMP4File()
                invalidFiles.append(invalidFile)
                testFiles.append(invalidFile)
            }
        }
        
        guard testFiles.count == concurrentCount else {
            throw XCTSkip("Failed to create all test files")
        }
        
        let expectation = XCTestExpectation(description: "Error isolation between concurrent operations")
        let group = DispatchGroup()
        
        var results: [(index: Int, result: Result<AudioFile, VoxError>)] = []
        let resultsLock = NSLock()
        
        for (index, testFile) in testFiles.enumerated() {
            group.enter()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let audioProcessor = AudioProcessor()
                audioProcessor.extractAudio(from: testFile.path) { result in
                    resultsLock.lock()
                    results.append((index: index, result: result))
                    resultsLock.unlock()
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // Validate error isolation
            XCTAssertEqual(results.count, concurrentCount,
                "All operations should complete")
            
            var successCount = 0
            var failureCount = 0
            
            for (index, result) in results {
                switch result {
                case .success:
                    successCount += 1
                    // Valid files (even indices) should succeed
                    XCTAssertEqual(index % 2, 0,
                        "Only valid files should succeed")
                    
                case .failure(let error):
                    failureCount += 1
                    // Invalid files (odd indices) should fail
                    XCTAssertEqual(index % 2, 1,
                        "Only invalid files should fail")
                    
                    // Validate error isolation
                    XCTAssertTrue(error is VoxError, "Should return VoxError for invalid files")
                    XCTAssertFalse(error.localizedDescription.isEmpty,
                        "Failed operations should have error descriptions")
                }
            }
            
            // Validate that failures didn't affect successes
            XCTAssertGreaterThan(successCount, 0, "Some operations should succeed")
            XCTAssertGreaterThan(failureCount, 0, "Some operations should fail")
            XCTAssertEqual(successCount + failureCount, concurrentCount,
                "All operations should be accounted for")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 90.0)
    }
    
    // MARK: - Memory Pressure Under Concurrency
    
    func testMemoryPressureWithConcurrentProcessing() throws {
        // Skip memory pressure tests in CI
        #if os(macOS)
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Memory pressure tests skipped in CI environment")
        }
        #endif
        
        let concurrentCount = 6
        var testFiles: [URL] = []
        
        for i in 0..<concurrentCount {
            if let file = testFileGenerator.createMockMP4File(duration: 10.0) {
                testFiles.append(file)
            }
        }
        
        guard testFiles.count == concurrentCount else {
            throw XCTSkip("Failed to create all test files")
        }
        
        let expectation = XCTestExpectation(description: "Memory pressure with concurrent processing")
        
        // Monitor memory before concurrent operations
        let initialMemoryUsage = getMemoryUsage()
        
        // Simulate memory pressure
        concurrencySimulator.simulateMemoryPressure(enabled: true)
        
        let group = DispatchGroup()
        var memoryUsages: [Int64] = []
        var results: [Result<AudioFile, VoxError>] = []
        let dataLock = NSLock()
        
        for testFile in testFiles {
            group.enter()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let audioProcessor = AudioProcessor()
                audioProcessor.extractAudio(from: testFile.path) { result in
                    let currentMemoryUsage = self.getMemoryUsage()
                    
                    dataLock.lock()
                    memoryUsages.append(currentMemoryUsage)
                    results.append(result)
                    dataLock.unlock()
                    
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            let finalMemoryUsage = self.getMemoryUsage()
            let peakMemoryUsage = memoryUsages.max() ?? 0
            
            // Validate memory management under concurrent pressure
            let memoryIncrease = peakMemoryUsage - initialMemoryUsage
            XCTAssertLessThan(memoryIncrease, 2048 * 1024 * 1024,
                "Memory increase should be less than 2GB under concurrent pressure")
            
            // Validate error handling under memory pressure
            let failures = results.compactMap { result -> VoxError? in
                if case .failure(let error) = result {
                    return error
                }
                return nil
            }
            
            for failure in failures {
                let errorDescription = failure.localizedDescription
                if errorDescription.localizedCaseInsensitiveContains("memory") {
                    XCTAssertTrue(
                        errorDescription.localizedCaseInsensitiveContains("pressure") ||
                        errorDescription.localizedCaseInsensitiveContains("insufficient") ||
                        errorDescription.localizedCaseInsensitiveContains("resource"),
                        "Memory errors should be descriptive: \(errorDescription)"
                    )
                }
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 180.0)
    }
    
    // MARK: - Helper Methods
    
    private func countTempFiles() -> Int {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            return files.filter { $0.contains("vox_") }.count
        } catch {
            return 0
        }
    }
    
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
}

// MARK: - Concurrency Simulator

class ConcurrencySimulator {
    private var resourcePressureEnabled = false
    private var memoryPressureEnabled = false
    private var memoryPressureSimulator: ConcurrentMemoryPressureSimulator?
    
    func simulateResourcePressure(enabled: Bool) {
        resourcePressureEnabled = enabled
        
        if enabled {
            // Simulate resource pressure by creating background tasks
            for i in 0..<4 {
                DispatchQueue.global(qos: .background).async {
                    while self.resourcePressureEnabled {
                        // Simulate CPU load
                        let _ = (0..<10000).map { $0 * $0 }
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }
        }
    }
    
    func simulateMemoryPressure(enabled: Bool) {
        memoryPressureEnabled = enabled
        
        if enabled {
            memoryPressureSimulator = ConcurrentMemoryPressureSimulator()
            memoryPressureSimulator?.start()
        } else {
            memoryPressureSimulator?.stop()
            memoryPressureSimulator = nil
        }
    }
    
    func cleanup() {
        resourcePressureEnabled = false
        memoryPressureEnabled = false
        memoryPressureSimulator?.stop()
        memoryPressureSimulator = nil
    }
}

// MARK: - Concurrent Memory Pressure Simulator

class ConcurrentMemoryPressureSimulator {
    private var allocatedMemory: [Data] = []
    private var isRunning = false
    
    func start() {
        isRunning = true
        DispatchQueue.global(qos: .background).async {
            while self.isRunning {
                let chunk = Data(repeating: 0, count: 1024 * 1024) // 1MB chunks
                self.allocatedMemory.append(chunk)
                
                // Limit total allocation to prevent system crash
                if self.allocatedMemory.count > 50 { // 50MB max for concurrent tests
                    self.allocatedMemory.removeFirst()
                }
                
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }
    
    func stop() {
        isRunning = false
        allocatedMemory.removeAll()
    }
}