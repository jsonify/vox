# Vox Testing Guidelines

## Overview
This document provides comprehensive guidelines for writing and maintaining tests in the Vox project, based on lessons learned from CI failures and compilation errors.

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

## CI-Safe Testing Patterns

### Test Categories
1. **CI Tests** (`CITests.swift`) - Basic model and configuration tests that don't require file system operations
2. **Integration Tests** - Tests that require file operations but should be robust
3. **Performance Tests** - Benchmarking tests with proper resource cleanup

### CI Test Requirements
- No file system operations
- No external dependencies
- Fast execution (< 1 second per test)
- Basic model and enum validation only

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

### File Size Limits
- **Maximum 400 lines per test file** (per CLAUDE.md requirement)
- Split large test files into focused, smaller files
- Use descriptive naming: `AudioProcessorBasicTests.swift`, `AudioProcessorErrorTests.swift`

### Naming Conventions
```
ComponentNameCategoryTests.swift
Examples:
- AudioProcessorBasicTests.swift
- AudioProcessorErrorTests.swift  
- AudioProcessorPerformanceTests.swift
- OutputWriterTests.swift
- CITests.swift (special case for CI-only tests)
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
```

## Debugging Test Failures

### Local Testing
1. Run tests locally before pushing:
   ```bash
   swift test --filter CITests
   swift build --verbose
   ```

2. Check for warnings:
   ```bash
   swift test 2>&1 | grep warning
   ```

### CI Debugging
1. Check the exact error in CI logs
2. Reproduce locally with same Swift/Xcode version
3. Test on multiple macOS versions if available

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
```

### File Template
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

This documentation should prevent future compilation errors and CI failures by establishing clear patterns and practices for test development.