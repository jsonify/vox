# Issue #31: Robust File Writing with Error Recovery

**Link**: https://github.com/jsonify/vox/issues/31

## Analysis

### Current State
- **OutputFormatter** exists with basic file writing using `String.write(toFile:atomically:encoding:)`
- **Error handling** exists with `VoxError.outputWriteFailed` but limited recovery
- **Dependencies** are complete (issues #27, #28, #29 all closed)
- **Formatters** are implemented (TextFormatter, JSONFormatter, SRT in OutputFormatter)

### Problems with Current Implementation
1. **Limited error recovery** - Only throws `VoxError.outputWriteFailed`
2. **No disk space validation** - May fail on insufficient space
3. **No path validation** - May fail on invalid paths or permissions
4. **No backup mechanism** - Data loss risk if write fails
5. **No atomic writing guarantees** - Built-in atomicity may fail in edge cases

### Requirements Analysis

#### Core Requirements
1. **OutputWriter class** - Centralized, robust file writing
2. **Atomic writing** - Ensure data integrity during writes
3. **Permission error handling** - Detect and handle permission issues
4. **Disk space validation** - Check available space before writing
5. **Backup/recovery** - Backup existing files and recover on failure
6. **Path validation** - Validate and create paths as needed

#### Implementation Strategy

### 1. OutputWriter Class Design
```swift
class OutputWriter {
    // Configuration
    private let enableBackup: Bool
    private let validateSpace: Bool
    private let createDirectories: Bool
    
    // Core methods
    func writeContent(_:to:format:options:) throws
    func writeContentSafely(_:to:format:options:) throws
    
    // Validation methods
    private func validatePath(_:) throws
    private func validateDiskSpace(_:path:) throws
    private func validatePermissions(_:) throws
    
    // Atomic writing
    private func writeAtomically(_:to:) throws
    
    // Backup/recovery
    private func createBackup(_:) throws -> URL?
    private func restoreFromBackup(_:) throws
}
```

### 2. Error Handling Extensions
```swift
extension VoxError {
    case insufficientDiskSpace(required: UInt64, available: UInt64)
    case invalidOutputPath(String)
    case permissionDenied(String)
    case backupFailed(String)
    case atomicWriteFailed(String)
    case pathCreationFailed(String)
}
```

### 3. Integration Points
- **OutputFormatter** will use OutputWriter instead of direct file writing
- **CLI** will configure OutputWriter options
- **Error handling** will be enhanced with specific recovery strategies

## Implementation Plan

### Phase 1: Core OutputWriter
1. Create OutputWriter class with basic structure
2. Implement path validation and creation
3. Add disk space validation
4. Implement permission checking

### Phase 2: Atomic Writing
1. Implement atomic writing with temporary files
2. Add backup mechanism for existing files
3. Implement recovery from backup on failure

### Phase 3: Integration
1. Update OutputFormatter to use OutputWriter
2. Add new error types to VoxError
3. Update CLI to configure OutputWriter

### Phase 4: Testing
1. Test with various edge cases
2. Test permission scenarios
3. Test disk space scenarios
4. Test atomic writing failures

## Technical Details

### Atomic Writing Strategy
1. Write to temporary file in same directory
2. Create backup of existing file (if exists)
3. Atomically move temporary file to final location
4. Remove backup on success, restore on failure

### Disk Space Validation
- Check available space using FileManager
- Require 2x content size for safety (temp file + final file)
- Graceful handling of space estimation errors

### Path Validation
- Validate parent directory exists or can be created
- Check write permissions on parent directory
- Validate filename for filesystem compatibility

### Error Recovery
- Automatic backup restoration on write failure
- Cleanup of temporary files on all code paths
- Detailed error reporting with recovery suggestions