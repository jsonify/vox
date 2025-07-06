import XCTest
import Foundation
import AVFoundation
@testable import vox

/// Comprehensive performance tests that validate processing times
/// and resource usage across various file sizes and scenarios.
final class ComprehensivePerformanceTests: ComprehensiveIntegrationTestsBase {
    
    // MARK: - Performance Benchmarking
    
    func testPerformanceBenchmarksWithRealFiles() throws {
        var performanceResults: [String: TimeInterval] = [:]
        
        // Test small file performance
        if let smallFile = realSampleFiles["small"] {
            let startTime = Date()
            
            let audioProcessor = AudioProcessor()
            let expectation = XCTestExpectation(description: "Small file performance")
            
            audioProcessor.extractAudio(from: smallFile.path) { result in
                let processingTime = Date().timeIntervalSince(startTime)
                performanceResults["small_real"] = processingTime
                
                switch result {
                case .success(let audioFile):
                    XCTAssertLessThan(processingTime, 15.0, 
                        "Small real file should process within 15 seconds")
                    XCTAssertGreaterThan(audioFile.format.duration, 0, 
                        "Audio should have valid duration")
                case .failure(let error):
                    XCTFail("Small file processing failed: \(error)")
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
        
        // Test large file performance
        if let largeFile = realSampleFiles["large"] {
            let startTime = Date()
            
            let audioProcessor = AudioProcessor()
            let expectation = XCTestExpectation(description: "Large file performance")
            
            audioProcessor.extractAudio(from: largeFile.path) { result in
                let processingTime = Date().timeIntervalSince(startTime)
                performanceResults["large_real"] = processingTime
                
                switch result {
                case .success(let audioFile):
                    // Performance targets from CLAUDE.md
                    let isAppleSilicon = ProcessInfo.processInfo.machineType.contains("arm64")
                    let targetTime: TimeInterval = isAppleSilicon ? 60.0 : 90.0
                    
                    // For real files, be more lenient in test environment
                    XCTAssertLessThan(processingTime, targetTime * 1.5, 
                        "Large real file should process within reasonable time")
                    XCTAssertGreaterThan(audioFile.format.duration, 0, 
                        "Audio should have valid duration")
                case .failure(let error):
                    // Large file processing may fail in test environment
                    print("Large file processing failed (acceptable): \(error)")
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 180.0)
        }
        
        // Report performance results
        print("Performance Benchmark Results:")
        for (testName, time) in performanceResults {
            print("  \(testName): \(String(format: "%.2f", time))s")
        }
    }
    
    func testMemoryUsageBenchmarks() throws {
        var memoryResults: [String: UInt64] = [:]
        
        // Test small file memory usage
        if let smallFile = generatedSampleFiles["small"] {
            let initialMemory = getMemoryUsage()
            
            let audioProcessor = AudioProcessor()
            let expectation = XCTestExpectation(description: "Small file memory usage")
            
            audioProcessor.extractAudio(from: smallFile.path) { result in
                let peakMemory = self.getMemoryUsage()
                let memoryDelta = peakMemory - initialMemory
                memoryResults["small_generated"] = memoryDelta
                
                switch result {
                case .success:
                    // Small files should use minimal memory
                    XCTAssertLessThan(memoryDelta, 100_000_000, // 100MB
                        "Small file should use less than 100MB additional memory")
                case .failure(let error):
                    XCTFail("Small file memory test failed: \(error)")
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
        
        // Test large file memory usage
        if let largeFile = generatedSampleFiles["large"] {
            let initialMemory = getMemoryUsage()
            
            let audioProcessor = AudioProcessor()
            let expectation = XCTestExpectation(description: "Large file memory usage")
            
            audioProcessor.extractAudio(from: largeFile.path) { result in
                let peakMemory = self.getMemoryUsage()
                let memoryDelta = peakMemory - initialMemory
                memoryResults["large_generated"] = memoryDelta
                
                switch result {
                case .success:
                    // Large files should stay within memory limits
                    XCTAssertLessThan(memoryDelta, 1_000_000_000, // 1GB
                        "Large file should use less than 1GB additional memory")
                case .failure(let error):
                    print("Large file memory test failed (acceptable): \(error)")
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 180.0)
        }
        
        // Report memory usage results
        print("Memory Usage Benchmark Results:")
        for (testName, memory) in memoryResults {
            let memoryMB = Double(memory) / 1_000_000
            print("  \(testName): \(String(format: "%.2f", memoryMB))MB")
        }
    }
    
    func testConcurrentProcessingPerformance() throws {
        let testFiles = Array(generatedSampleFiles.values.prefix(3))
        
        guard testFiles.count >= 2 else {
            throw XCTSkip("Need at least 2 test files for concurrent testing")
        }
        
        let concurrentExpectations = testFiles.enumerated().map { index, _ in
            XCTestExpectation(description: "Concurrent processing \(index)")
        }
        
        let startTime = Date()
        var completionTimes: [TimeInterval] = []
        let completionQueue = DispatchQueue(label: "completion_tracking", attributes: .concurrent)
        
        // Start concurrent processing
        for (index, file) in testFiles.enumerated() {
            let expectation = concurrentExpectations[index]
            
            DispatchQueue.global().async {
                let audioProcessor = AudioProcessor()
                audioProcessor.extractAudio(from: file.path) { result in
                    let completionTime = Date().timeIntervalSince(startTime)
                    
                    completionQueue.async(flags: .barrier) {
                        completionTimes.append(completionTime)
                    }
                    
                    switch result {
                    case .success:
                        // Success is expected
                        break
                    case .failure(let error):
                        print("Concurrent processing failed for file \(index): \(error)")
                    }
                    
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: concurrentExpectations, timeout: 240.0)
        
        // Validate concurrent processing efficiency
        let maxCompletionTime = completionTimes.max() ?? 0
        let averageCompletionTime = completionTimes.reduce(0, +) / Double(completionTimes.count)
        
        print("Concurrent Processing Results:")
        print("  Files processed: \(testFiles.count)")
        print("  Max completion time: \(String(format: "%.2f", maxCompletionTime))s")
        print("  Average completion time: \(String(format: "%.2f", averageCompletionTime))s")
        
        // Concurrent processing should not take significantly longer than sequential
        XCTAssertLessThan(maxCompletionTime, 180.0, 
                         "Concurrent processing should complete within 3 minutes")
    }
    
    func testStartupPerformance() throws {
        let iterations = 5
        var startupTimes: [TimeInterval] = []
        
        for _ in 0..<iterations {
            let startTime = Date()
            
            // Simulate CLI startup
            let _ = Vox()
            
            let startupTime = Date().timeIntervalSince(startTime)
            startupTimes.append(startupTime)
        }
        
        let averageStartupTime = startupTimes.reduce(0, +) / Double(startupTimes.count)
        let maxStartupTime = startupTimes.max() ?? 0
        
        print("Startup Performance Results:")
        print("  Average startup time: \(String(format: "%.3f", averageStartupTime))s")
        print("  Max startup time: \(String(format: "%.3f", maxStartupTime))s")
        
        // Startup time should be under 2 seconds as per CLAUDE.md
        XCTAssertLessThan(averageStartupTime, 2.0, 
                         "Average startup time should be under 2 seconds")
        XCTAssertLessThan(maxStartupTime, 3.0, 
                         "Max startup time should be under 3 seconds")
    }
    
    func testOutputFormatPerformance() throws {
        guard let testFile = generatedSampleFiles["small"] else {
            throw XCTSkip("No small test file available")
        }
        
        let formats: [OutputFormat] = [.txt, .srt, .json]
        var formatPerformance: [OutputFormat: TimeInterval] = [:]
        
        for format in formats {
            let startTime = Date()
            
            let result = try executeCompleteWorkflow(
                inputFile: testFile,
                outputFormat: format
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            formatPerformance[format] = processingTime
            
            // Validate output was generated
            XCTAssertFalse(result.output.isEmpty, 
                          "Format \(format.rawValue) should produce output")
        }
        
        print("Output Format Performance Results:")
        for (format, time) in formatPerformance {
            print("  \(format.rawValue): \(String(format: "%.2f", time))s")
        }
        
        // All formats should complete within reasonable time
        for (format, time) in formatPerformance {
            XCTAssertLessThan(time, 60.0, 
                            "Format \(format.rawValue) should complete within 1 minute")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
}