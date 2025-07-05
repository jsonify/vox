# Vox Testing Guidelines

## Overview
This document provides comprehensive guidelines for writing and maintaining tests in the Vox project, based on lessons learned from CI failures and compilation errors.

## Testing Strategy

### Test Categories
1. **Unit Tests** - Component and function validation
2. **Integration Tests** - End-to-end workflow testing  
3. **Performance Tests** - Speed and memory benchmarks
4. **Cross-Architecture Tests** - Intel vs Apple Silicon validation
5. **CI Tests** - Basic model and configuration tests safe for CI environments

### Test File Size Limits
- **Maximum 400 lines per test file** (per project requirements)
- Split large test files into focused, smaller files
- Use descriptive naming conventions

## Critical Testing Rules

### 1. OutputWriter API Usage
**ALWAYS use the correct OutputWriter methods:**

```swift
// ✅ CORRECT
try outputWriter.writeContentSafely(content, to: path)
try outputWriter.writeTranscriptionResult(result, to: path, format: format)

// ❌ INCORRECT - These methods don't exist
try outputWriter.writeContent(content, to: path)  // NO
try outputWriter.write(content, to: path)         // NO
```

### 2. CLI Command Configuration
**ArgumentParser commands require `var` for property assignment:**

```swift
// ✅ CORRECT
var voxCommand = Vox()
voxCommand.inputFile = "test.mp4"
voxCommand.output = "output.txt"

// ❌ INCORRECT - Cannot assign to let properties
let voxCommand = Vox()
voxCommand.inputFile = "test.mp4"  // Compilation error
```

### 3. Error Type Assertions
**Avoid redundant type checks when Result types guarantee the error type:**

```swift
// ✅ CORRECT - Result<AudioFile, VoxError> already guarantees VoxError
case .failure(let error):
    // Error is already guaranteed to be VoxError by the Result type
    let description = error.localizedDescription
    XCTAssertFalse(description.isEmpty)

// ❌ INCORRECT - Redundant check causes warnings
case .failure(let error):
    XCTAssertTrue(error is VoxError, "Should return VoxError")  // Always true warning
```

### 4. Switch Statement Completeness
**Every case in a switch must have at least one executable statement:**

```swift
// ✅ CORRECT
case .failure(_):
    // Error handling comment
    break  // Executable statement required

// ❌ INCORRECT - Compilation error
case .failure(_):
    // Error handling comment
    // No executable statement
```

### 5. Unused Variable Handling
**Replace unused variables with underscore:**

```swift
// ✅ CORRECT
let _ = ProgressDisplayManager()  // Or even better: _ = ProgressDisplayManager()

// ❌ INCORRECT - Unused variable warning
let progressManager = ProgressDisplayManager()  // Never used
```

## Test Implementation Guidelines

### Test Data Management
```swift
class TestDataManager {
    static let sampleFiles: [TestFile] = [
        TestFile(name: "short_speech.mp4", duration: 30, language: "en-US"),
        TestFile(name: "long_presentation.mp4", duration: 1800, language: "en-US"),
        TestFile(name: "multilingual.mp4", duration: 300, language: "mixed"),
        TestFile(name: "poor_quality.mp4", duration: 120, language: "en-US"),
        TestFile(name: "silent_video.mp4", duration: 60, language: nil)
    ]
    
    static func getSampleFile(_ name: String) -> URL {
        return Bundle.module.url(forResource: name, withExtension: nil)!
    }
}
```

### Performance Testing Framework
```swift
class PerformanceTestSuite {
    func measureTranscriptionSpeed() async throws {
        let testFile = TestDataManager.getSampleFile("long_presentation.mp4")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let result = try await transcriptionEngine.transcribe(testFile)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let realTimeRatio = result.duration / processingTime
        
        XCTAssertGreaterThan(realTimeRatio, 1.0, "Should process faster than real-time")
        
        print("Processing Speed: \(realTimeRatio)x real-time")
        print("File Duration: \(result.duration)s")
        print("Processing Time: \(processingTime)s")
    }
}
```

## Performance Targets

### Processing Speed Targets
- **Apple Silicon**: Process 30-minute video in < 60 seconds
- **Intel Mac**: Process 30-minute video in < 90 seconds
- **Startup Time**: Application launch < 2 seconds
- **Memory Usage**: Peak usage < 1GB for typical files

### Scalability Limits
- **File Size**: Support files up to 2GB
- **Duration**: Support videos up to 4 hours
- **Concurrent Processing**: Single file processing (sequential for multiple files)
- **Temporary Storage**: Auto-cleanup with 10GB safety limit

## CI-Safe Testing Patterns

### CI Test Requirements
- No file system operations
- No external dependencies
- Fast execution (< 1 second per test)
- Basic model and enum validation only

### Test Categories by Environment
1. **CI Tests** (`CITests.swift`) - Basic model and configuration tests
2. **Local Integration Tests** - File operations and full workflow tests
3. **Performance Tests** - Benchmarking with proper resource cleanup

### macOS Compatibility
**Always test deprecated API usage:**

```swift
// ✅ macOS 13+ compatible
Task {
    let duration = try await asset.load(.duration)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
}

// ⚠️ Works but generates warnings on macOS 13+
let duration = asset.duration  // Deprecated
let tracks = asset.tracks(withMediaType: .audio)  // Deprecated
```

## Test File Organization

### Naming Conventions
```
ComponentNameCategoryTests.swift
Examples:
- AudioProcessorBasicTests.swift
- AudioProcessorErrorTests.swift  
- AudioProcessorPerformanceTests.swift
- TranscriptionEngineTests.swift
- OutputWriterTests.swift
- CITests.swift (special case for CI-only tests)
```

### Directory Structure
```
Tests/
├── VoxTests/
│   ├── CITests.swift                    # CI-safe basic tests
│   ├── AudioProcessorBasicTests.swift
│   ├── AudioProcessorErrorTests.swift
│   ├── TranscriptionEngineTests.swift
│   ├── OutputWriterTests.swift
│   └── PerformanceTests.swift
├── IntegrationTests/
│   ├── EndToEndTests.swift
│   └── FileProcessingTests.swift
└── TestResources/
    ├── sample_short.mp4
    ├── sample_long.mp4
    └── sample_multilingual.mp4
```

## Common Pitfalls to Avoid

### 1. API Method Names
Always verify method existence before using:
```bash
# Check available methods
swift-doc generate Sources/ --format html
# Or use Xcode autocomplete to verify method names
```

### 2. Result Type Patterns
When using `Result<Success, Failure>`, remember:
- Failure type is already constrained
- No need for `is` type checks
- Use pattern matching effectively

### 3. Resource Cleanup
Always clean up test resources:
```swift
override func tearDown() {
    super.tearDown()
    // Clean up temporary files
    try? FileManager.default.removeItem(at: tempDirectory)
}
```

### 4. Asynchronous Testing
Use proper expectations for async operations:
```swift
let expectation = XCTestExpectation(description: "Audio processing")
audioProcessor.extractAudio(from: path) { result in
    // Test assertions here
    expectation.fulfill()
}
wait(for: [expectation], timeout: 30.0)
```

## CI Configuration Best Practices

### Multi-Platform Testing
```yaml
strategy:
  matrix:
    os: [macos-13, macos-14]  # Test multiple macOS versions
    swift-version: ['5.9']
```

### Test Filtering
Use `--filter` for CI to run only safe tests:
```bash
swift test --filter CITests  # Only basic tests
swift test --filter "!Integration"  # Exclude integration tests
swift test --filter "!Performance"  # Exclude performance tests
```

### GitHub Actions Configuration
```yaml
- name: Run CI Tests
  run: swift test --filter CITests --verbose

- name: Run Integration Tests (macOS only)
  run: swift test --filter IntegrationTests
  if: runner.os == 'macOS'
```

## Debugging Test Failures

### Local Testing Workflow
1. Run tests locally before pushing:
   ```bash
   swift test --filter CITests
   swift build --verbose
   ```

2. Check for warnings:
   ```bash
   swift test 2>&1 | grep warning
   ```

3. Test specific components:
   ```bash
   swift test --filter AudioProcessor
   swift test --filter TranscriptionEngine
   ```

### CI Debugging Steps
1. Check the exact error in CI logs
2. Reproduce locally with same Swift/Xcode version
3. Test on multiple macOS versions if available
4. Verify test file line counts:
   ```bash
   find Tests -name "*.swift" -exec wc -l {} \; | sort -nr
   ```

## Code Review Checklist

Before submitting test code, verify:
- [ ] All OutputWriter method calls use correct API
- [ ] CLI command objects use `var` not `let`
- [ ] No redundant `is VoxError` type checks
- [ ] All switch cases have executable statements
- [ ] No unused variables (use `_` instead)
- [ ] Test file under 400 lines
- [ ] Async tests use proper expectations
- [ ] Resources properly cleaned up
- [ ] macOS compatibility considered
- [ ] CI-safe tests separated from integration tests
- [ ] Performance benchmarks have realistic targets

## Test Templates

### Basic Test File Template
```swift
import XCTest
@testable import vox

final class ComponentNameTests: XCTestCase {
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, 
                                               withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testBasicFunctionality() {
        // Test implementation
    }
}
```

### CI-Safe Test Template
```swift
import XCTest
@testable import vox

final class CITests: XCTestCase {
    
    func testDataModels() {
        // Test basic model creation and validation
        let result = TranscriptionResult(
            text: "test",
            language: "en-US",
            confidence: 0.95,
            duration: 30.0,
            segments: [],
            engine: .native(version: "1.0"),
            processingTime: 1.0,
            audioFormat: AudioFormat(sampleRate: 16000, channels: 1, bitDepth: 16, codec: "PCM", duration: 30.0)
        )
        
        XCTAssertEqual(result.text, "test")
        XCTAssertEqual(result.confidence, 0.95)
    }
    
    func testEnumCases() {
        // Test enum functionality without external dependencies
        let format = OutputFormat.txt
        XCTAssertEqual(format.fileExtension, ".txt")
        
        let srtFormat = OutputFormat.srt
        XCTAssertEqual(srtFormat.fileExtension, ".srt")
    }
}
```

### Performance Test Template
```swift
import XCTest
@testable import vox

final class PerformanceTests: XCTestCase {
    
    func testTranscriptionPerformance() {
        measure {
            // Performance critical code here
            let processor = AudioProcessor()
            // Mock or lightweight operations only
        }
    }
    
    func testMemoryUsage() {
        // Memory usage validation
        let initialMemory = getMemoryUsage()
        
        // Run memory-intensive operations
        
        let finalMemory = getMemoryUsage()
        let memoryDelta = finalMemory - initialMemory
        
        XCTAssertLessThan(memoryDelta, 1_000_000_000, "Memory usage should be under 1GB")
    }
}
```

## Quick Reference

### Correct Patterns
```swift
// OutputWriter usage
try outputWriter.writeContentSafely(content, to: path)

// CLI configuration
var command = Vox()
command.inputFile = path

// Error handling
case .failure(let error):
    XCTAssertFalse(error.localizedDescription.isEmpty)

// Unused variables
let _ = SomeClass()

// Async testing
let expectation = XCTestExpectation(description: "operation")
// ... async operation
wait(for: [expectation], timeout: 10.0)
```

### Test Commands Reference
```bash
# Run all tests
swift test

# Run CI-safe tests only
swift test --filter CITests

# Run specific test file
swift test --filter AudioProcessorTests

# Exclude slow tests
swift test --filter "!Performance"

# Verbose output
swift test --verbose

# Build without running
swift build --verbose
```

This comprehensive testing guide ensures reliable, maintainable tests that work across different environments and provide confidence in the Vox application's quality and performance.
