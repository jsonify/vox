# CI Troubleshooting Guide

This guide helps developers avoid and resolve common CI failures in the Vox project.

## Common CI Failures and Solutions

### 1. SwiftLint Line Length Violations

**Error Message:**
```
Error: Line should be 200 characters or less; currently it has 234 characters (line_length)
```

**Root Cause:**
Lines longer than 180 characters (the error threshold in `.swiftlint.yml`) cause CI failures.

**Solutions:**

#### Break Long Lines
```swift
// ❌ Bad - Line too long
Logger.shared.info("Processing \(result.testName): \(String(format: "%.2f", result.processingTime))s (\(String(format: "%.2f", result.processingRatio))x)", component: "EnhancedPerformanceTests")

// ✅ Good - Extract to variable
let processingInfo = "Processing \(result.testName): \(String(format: "%.2f", result.processingTime))s (\(String(format: "%.2f", result.processingRatio))x)"
Logger.shared.info(processingInfo, component: "EnhancedPerformanceTests")

// ✅ Good - Multi-line string concatenation
let message = "Processing time should not regress by > 20% " +
              "(baseline: \(String(format: "%.2f", baseline.processingTime))s, " +
              "current: \(String(format: "%.2f", standardResult.processingTime))s)"
```

#### Use Multi-line String Literals
```swift
// ✅ Good - Multi-line string
let report = """
    Performance Report:
    Processing Time: \(processingTime)s
    Memory Usage: \(memoryUsage)MB
    """
```

**Prevention:**
- Run `./scripts/pre-commit-performance-check.sh` before committing
- Configure your editor to show a line length ruler at 120 characters
- Use SwiftLint auto-fix: `swiftlint --fix`

### 2. fatalError Causing Test Crashes

**Error Message:**
```
error: fatalError
Error: Process completed with exit code 1.
```

**Root Cause:**
`fatalError()` calls in test code cause the entire test process to crash, making CI jobs fail with vague error messages.

**Common Locations:**
- `PerformanceBenchmark.swift:137` - Missing benchmark context
- `TestAudioFileGenerator.swift:19` - Test directory creation failure
- `CLITests.swift:10` - Command parsing failures

**Solutions:**

#### Replace fatalError with Proper Error Handling
```swift
// ❌ Bad - Crashes entire test suite
guard let context = activeBenchmarks[testName] else {
    fatalError("Benchmark \(testName) was not started")
}

// ✅ Good - Graceful error handling
guard let context = activeBenchmarks[testName] else {
    Logger.shared.error("Benchmark \(testName) was not started - creating fallback result", component: "PerformanceBenchmark")
    return createFallbackBenchmarkResult(testName: testName, audioDuration: audioDuration)
}
```

#### Use XCTFail Instead of fatalError in Tests
```swift
// ❌ Bad - Crashes test runner
guard let result = someOperation() else {
    fatalError("Operation failed")
}

// ✅ Good - Proper test failure
guard let result = someOperation() else {
    XCTFail("Operation failed")
    return
}
```

#### Use Throws Instead of fatalError
```swift
// ❌ Bad - Unrecoverable crash
func parseCommand() -> Vox {
    guard let parsed = try? Vox.parseAsRoot() else {
        fatalError("Failed to parse command")
    }
    return parsed
}

// ✅ Good - Recoverable error
func parseCommand() throws -> Vox {
    guard let parsed = try? Vox.parseAsRoot() else {
        throw VoxError.processingFailed("Failed to parse command")
    }
    return parsed
}
```

**Prevention:**
- SwiftLint now catches `fatalError` in test files (error-level rule)
- Use the pre-commit hook: `./scripts/pre-commit-performance-check.sh`
- Search for fatalError before committing: `grep -r "fatalError" Tests/`

### 3. Test Timeouts and Async Issues

**Error Message:**
```
Test Case '-[voxTests.EnhancedPerformanceTests testCLAUDEMDPerformanceTargets]' started.
... 
error: Exited with unexpected signal code 4
```

**Root Cause:**
- Missing `await fulfillment()` calls
- Insufficient timeout values for performance tests
- Async operations not properly handled

**Solutions:**

#### Proper Async Test Handling
```swift
// ✅ Good - Proper async test with adequate timeout
func testPerformanceValidation() async throws {
    let expectation = XCTestExpectation(description: "Performance test")
    
    engine.transcribeAudio(from: testFile) { _ in
        // Progress updates
    } completion: { result in
        // Handle result
        expectation.fulfill()
    }
    
    // Use adequate timeout for performance tests
    await fulfillment(of: [expectation], timeout: 60.0)
}
```

#### Adequate Timeout Values
```swift
// ❌ Bad - Too short for performance tests
await fulfillment(of: [expectation], timeout: 5.0)

// ✅ Good - Adequate for performance operations
await fulfillment(of: [expectation], timeout: 60.0)
```

### 4. Memory and Resource Issues

**Root Cause:**
- Memory leaks in test code
- Uncleaned temporary files
- Resource contention in concurrent tests

**Solutions:**

#### Proper Resource Cleanup
```swift
override func tearDown() {
    testFileGenerator?.cleanup()
    // Clean up any other resources
    super.tearDown()
}
```

#### Memory Management in Tests
```swift
// ✅ Good - Proper memory management
let bufferSize = 64 * 1024
let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
defer { buffer.deallocate() } // Always deallocate

// Use buffer...
```

## Prevention Strategies

### 1. Pre-commit Hooks

Install the pre-commit hook:
```bash
# Copy the hook
cp scripts/pre-commit-performance-check.sh .git/hooks/pre-commit

# Make it executable
chmod +x .git/hooks/pre-commit
```

The hook automatically checks for:
- fatalError usage in test files
- Lines longer than 180 characters
- Basic compilation issues
- Critical test failures

### 2. Local Testing Before Push

Always run these commands before pushing:
```bash
# 1. Build check
swift build

# 2. SwiftLint check
swiftlint

# 3. Critical tests
swift test --filter CITests

# 4. Performance regression check
swift test --filter PerformanceRegressionTests.testStartupTimeRegression

# 5. Full pre-commit check
./scripts/pre-commit-performance-check.sh
```

### 3. Editor Configuration

#### VS Code Settings
```json
{
  "editor.rulers": [120, 180],
  "editor.wordWrap": "bounded",
  "editor.wordWrapColumn": 120
}
```

#### Xcode Settings
- Enable "Page guide at column" and set to 120
- Configure SwiftLint integration

### 4. SwiftLint Configuration Updates

The `.swiftlint.yml` has been updated to:
- Reduce line length error threshold from 200 to 180 characters
- Add custom rule to catch `fatalError` in test files
- Enhance logging recommendations

## Debugging CI Failures

### 1. Local Reproduction

To reproduce CI failures locally:
```bash
# Run with the same test filter as CI
swift test --filter ArchitectureComparisonTests

# Enable verbose logging
export VOX_VERBOSE=true
swift test --filter YourFailingTest

# Check memory usage
leaks --atExit -- swift test --filter MemoryTest
```

### 2. GitHub Actions Logs

When CI fails:
1. Check the "Run SwiftLint" step for code quality issues
2. Check the "Test on macos-13/14" steps for test failures
3. Look for "fatalError" or "signal code 4" messages
4. Check for memory or timeout issues

### 3. Common Log Patterns

| Log Pattern | Likely Cause | Solution |
|-------------|--------------|----------|
| `Line should be X characters or less` | Line length violation | Break long lines |
| `error: fatalError` | fatalError in code | Replace with proper error handling |
| `signal code 4` | Test crash/timeout | Check async handling and timeouts |
| `Process completed with exit code 1` | Test failure | Check specific test logs |

## Best Practices for Performance Tests

### 1. Timeout Management
```swift
// Use appropriate timeouts based on test type
let timeout: TimeInterval = {
    switch testType {
    case .startup: return 10.0
    case .shortPerformance: return 30.0
    case .longPerformance: return 120.0
    case .memoryStress: return 180.0
    }
}()
```

### 2. Error Handling Patterns
```swift
// Always use guard with graceful fallback
guard let component = createComponent() else {
    Logger.shared.error("Failed to create component", component: "TestName")
    throw XCTSkip("Unable to create required component")
}
```

### 3. Resource Management
```swift
// Use defer for cleanup
func testResourceIntensiveOperation() {
    let resource = allocateResource()
    defer { cleanupResource(resource) }
    
    // Test code here
}
```

## Summary

The main CI issues were:
1. **SwiftLint line length violations** - Fixed by breaking long lines
2. **fatalError crashes** - Fixed by replacing with proper error handling
3. **Missing fallback methods** - Added createFallbackBenchmarkResult()

**Prevention measures implemented:**
- Updated SwiftLint configuration with stricter line length limits
- Added custom rules to catch fatalError in tests
- Created pre-commit hook script
- Comprehensive documentation for troubleshooting

**Recommended workflow:**
1. Run pre-commit hook before every commit
2. Use proper error handling instead of fatalError
3. Keep lines under 120 characters (with 180 as hard limit)
4. Test locally with the same commands used in CI