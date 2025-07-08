# Native Transcription Hanging Issue

## Summary
Native transcription using Apple's Speech framework hangs indefinitely when called from the CLI application, despite the same code working perfectly in standalone tests.

## Current Status
- ✅ **Demo content removed** - No longer shows fake "[DEMO]" transcriptions
- ✅ **Fallback disabled** - Only uses native transcription as requested
- ✅ **Bypass implemented** - Removed temporary bypass that was preventing native transcription
- ❌ **Hanging issue** - Speech recognition callback never fires in CLI context

## Problem Description

### What Works
Standalone test using identical code pattern:
```swift
// This works perfectly and transcribes audio successfully
let result: String = try await withCheckedThrowingContinuation { continuation in
    let task = recognizer.recognitionTask(with: request) { result, error in
        if let result = result, result.isFinal {
            continuation.resume(returning: result.bestTranscription.formattedString)
        }
    }
}
```

### What Doesn't Work
Same exact pattern embedded in CLI application hangs after:
```
DEBUG: About to start recognition task
```

The Speech recognition callback is never called, despite:
- Speech recognition authorization being granted
- Speech recognizer being available
- Audio file being valid and readable
- Same audio file working in standalone test

## Root Cause Analysis

### Execution Context Issue
The problem appears to be related to how the Speech framework integrates with the main run loop:

1. **Standalone test**: Uses `RunLoop.main.run()` which properly integrates with main run loop
2. **CLI app**: Uses `Task { ... }` with `semaphore.wait()` which may not properly integrate with Speech framework's main thread requirements

### Evidence
- Same audio file works in both contexts
- Same Speech framework calls work in both contexts  
- Same async/await pattern works in both contexts
- Only difference is execution environment (standalone vs CLI Task context)

## Current Implementation Status

### Files Modified
- `Sources/vox/SpeechTranscriber.swift` - Removed temporary bypass, simplified async implementation
- `Sources/vox/TranscriptionManager.swift` - Disabled fallback, removed demo content
- `Sources/vox/CLI.swift` - Added direct transcription bypass for testing

### Debug Output Issue
DEBUG statements are always shown instead of only appearing with `--debug` flag. The app has:
- `globalDebugEnabled` flag in CLI.swift
- `debugPrint()` utility function
- But many debug statements use `fputs("DEBUG: ...", stderr)` directly

## Proposed Solution

### 1. Fix Speech Framework Integration
Ensure Speech recognition runs properly in CLI context by:
- Running Speech recognition on main thread with proper run loop integration
- Investigating if `RunLoop.main.run()` or similar is needed in CLI context
- Ensuring Speech framework callbacks are properly dispatched

### 2. Conditional Debug Output
Replace direct `fputs("DEBUG: ...", stderr)` calls with conditional debug output:
```swift
// Instead of:
fputs("DEBUG: Message\n", stderr)

// Use:
debugPrint("Message")
```

### 3. Clean Up Temporary Code
Remove temporary bypasses and restore proper architecture:
- Remove direct transcription bypass in `CLI.swift`
- Restore `TranscriptionManager` usage
- Ensure proper error handling and progress reporting

## Implementation Plan

### Phase 1: Fix Speech Framework Integration
1. Research Speech framework main thread requirements
2. Implement proper main thread/run loop integration
3. Test with existing audio files
4. Verify callback execution

### Phase 2: Clean Up Debug Output
1. Audit all debug output statements
2. Replace `fputs` with conditional `debugPrint`
3. Test with and without `--debug` flag
4. Ensure clean user experience

### Phase 3: Restore Architecture
1. Remove temporary bypasses
2. Restore proper TranscriptionManager flow
3. Add comprehensive error handling
4. Test end-to-end functionality

## Testing Requirements

### Success Criteria
- [ ] Native transcription works from CLI without hanging
- [ ] Speech recognition callbacks fire properly
- [ ] DEBUG output only appears with `--debug` flag
- [ ] Real transcription results (not demo content)
- [ ] Proper error handling and user feedback

### Test Cases
1. Basic transcription: `vox video.mp4 -o transcript.txt`
2. Debug mode: `vox video.mp4 --debug -o transcript.txt`
3. Verbose mode: `vox video.mp4 --verbose -o transcript.txt`
4. Error handling: Invalid files, permission issues, etc.

## Related Files
- `Sources/vox/SpeechTranscriber.swift` - Core transcription logic
- `Sources/vox/TranscriptionManager.swift` - Orchestration layer
- `Sources/vox/CLI.swift` - Main application entry point
- `Sources/vox/Logger.swift` - Logging infrastructure

## Priority
**High** - This blocks the core functionality of native transcription.

## Labels
- `bug`
- `transcription`
- `speech-framework`
- `native-transcription`
- `high-priority`