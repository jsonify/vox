# Vox CLI - Development TODO

## Project Overview
This TODO document tracks the development of Vox, a native macOS CLI for audio transcription from MP4 video files. Tasks are organized by development phases with clear priorities and dependencies.

---

## Phase 1: Core Infrastructure ✅ (Partially Complete)

### ✅ Completed
- [x] Initialize Xcode project with Vox CLI target
- [x] Configure Swift Package Manager dependencies
- [x] Implement basic argument parsing structure for `vox` command
- [x] Create core data models (TranscriptionResult, AudioFile, etc.)
- [x] Set up error handling framework with Vox branding
- [x] Configure universal binary build settings

### 🔄 In Progress
- [x] **#001 - Add comprehensive logging system**
  - Priority: High
  - Description: Implement structured logging with different verbosity levels
  - Acceptance Criteria:
    - Logger class with debug, info, warn, error levels
    - Respects --verbose flag
    - Outputs to stderr for proper CLI behavior
    - Includes timestamps and component identification

---

## Phase 2: Audio Processing (Week 2-3)

### 🎯 Ready to Start

- [ ] **#002 - Implement AVFoundation audio extraction**
  - Priority: High
  - Dependencies: Logging system (#001)
  - Description: Extract audio from MP4 files using native AVFoundation
  - Acceptance Criteria:
    - AudioProcessor class with extractAudio method
    - Supports common MP4 video formats
    - Extracts to temporary WAV/M4A files
    - Handles file validation and error cases
    - Progress reporting via callbacks

- [ ] **#003 - Create ffmpeg wrapper for fallback processing**
  - Priority: High
  - Dependencies: AVFoundation extraction (#002)
  - Description: Fallback audio extraction using ffmpeg when AVFoundation fails
  - Acceptance Criteria:
    - FFmpegProcessor class as fallback
    - Automatic detection of ffmpeg availability
    - Command-line execution with error handling
    - Same interface as AVFoundation processor
    - Progress parsing from ffmpeg output

- [ ] **#004 - Add audio format detection and validation**
  - Priority: Medium
  - Dependencies: Audio extraction (#002, #003)
  - Description: Detect and validate audio properties from extracted files
  - Acceptance Criteria:
    - AudioFormat struct population from file metadata
    - Sample rate, channels, codec detection
    - Duration and bitrate calculation
    - Format compatibility validation
    - Error reporting for unsupported formats

- [ ] **#005 - Implement temporary file management**
  - Priority: High
  - Dependencies: None
  - Description: Secure creation and cleanup of temporary audio files
  - Acceptance Criteria:
    - TempFileManager class
    - Unique temporary file naming
    - Automatic cleanup on success/failure
    - Secure file permissions
    - Graceful handling of cleanup failures

- [ ] **#006 - Add progress reporting for audio processing**
  - Priority: Medium
  - Dependencies: Audio processors (#002, #003)
  - Description: User feedback during audio extraction phase
  - Acceptance Criteria:
    - Progress protocol with percentage updates
    - Time estimation for remaining work
    - Current operation status messages
    - Respects verbose/quiet modes
    - Works with both AVFoundation and ffmpeg

- [ ] **#007 - Create comprehensive audio processing tests**
  - Priority: Medium
  - Dependencies: All audio processing components
  - Description: Unit and integration tests for audio extraction
  - Acceptance Criteria:
    - Mock audio files for testing
    - AVFoundation processor tests
    - ffmpeg fallback tests
    - Error condition testing
    - Performance benchmarking tests

---

## Phase 3: Native Transcription (Week 3-4)

### 🎯 Ready to Start

- [ ] **#008 - Implement SpeechAnalyzer wrapper**
  - Priority: High
  - Dependencies: Audio processing (#002-#006)
  - Description: Wrapper for Apple's Speech framework
  - Acceptance Criteria:
    - SpeechTranscriber class
    - Support for local speech recognition
    - Handles audio file input
    - Returns TranscriptionResult with segments
    - Proper error handling for speech framework issues

- [ ] **#009 - Add language detection and preference handling**
  - Priority: Medium
  - Dependencies: SpeechAnalyzer wrapper (#008)
  - Description: Automatic language detection with user preference override
  - Acceptance Criteria:
    - Language detection from audio content
    - Respect user-specified language codes
    - Fallback to system language preferences
    - Support for major languages (en-US, es-ES, fr-FR, etc.)
    - Language confidence scoring

- [ ] **#010 - Implement confidence scoring and validation**
  - Priority: Medium
  - Dependencies: SpeechAnalyzer wrapper (#008)
  - Description: Confidence metrics for transcription quality assessment
  - Acceptance Criteria:
    - Per-segment confidence scores
    - Overall transcription confidence
    - Threshold-based quality warnings
    - Low-confidence segment identification
    - Integration with fallback decision logic

- [ ] **#011 - Create timestamp and segment extraction**
  - Priority: High
  - Dependencies: SpeechAnalyzer wrapper (#008)
  - Description: Extract precise timing information for transcribed segments
  - Acceptance Criteria:
    - Accurate start/end timestamps per segment
    - Word-level timing when available
    - Sentence and paragraph boundaries
    - Speaker change detection
    - Silence gap handling

- [ ] **#012 - Add progress reporting for transcription**
  - Priority: Medium
  - Dependencies: SpeechAnalyzer wrapper (#008)
  - Description: User feedback during transcription processing
  - Acceptance Criteria:
    - Real-time transcription progress
    - Estimated time remaining
    - Current segment being processed
    - Memory usage monitoring
    - Graceful handling of long audio files

- [ ] **#013 - Optimize performance for both Intel and Apple Silicon**
  - Priority: Medium
  - Dependencies: Complete native transcription implementation
  - Description: Platform-specific optimizations for transcription performance
  - Acceptance Criteria:
    - Apple Silicon specific optimizations
    - Intel Mac compatibility maintained
    - Memory usage optimization
    - Multi-threading where appropriate
    - Performance benchmarking on both platforms

---

## Phase 4: Cloud Fallback (Week 4-5)

### 🎯 Ready to Start

- [ ] **#014 - Implement OpenAI Whisper API client**
  - Priority: High
  - Dependencies: Audio processing (#002-#006)
  - Description: Integration with OpenAI's Whisper API for cloud transcription
  - Acceptance Criteria:
    - WhisperAPIClient class
    - Audio file upload and transcription
    - API key management from environment/arguments
    - Response parsing to TranscriptionResult
    - Error handling for API failures
    - Rate limiting and quota management

- [ ] **#015 - Implement Rev.ai API client**
  - Priority: High
  - Dependencies: Audio processing (#002-#006)
  - Description: Alternative cloud transcription service integration
  - Acceptance Criteria:
    - RevAIClient class
    - Async job submission and polling
    - API key management
    - Response parsing to TranscriptionResult
    - Webhook support for large files
    - Error handling and retry logic

- [ ] **#016 - Create intelligent fallback decision logic**
  - Priority: High
  - Dependencies: Native transcription (#008-#013), Cloud APIs (#014-#015)
  - Description: Smart decision making between local and cloud transcription
  - Acceptance Criteria:
    - TranscriptionCoordinator class
    - Native-first approach with fallback
    - Confidence-based fallback decisions
    - User preference respect (--force-cloud)
    - Failure cascade handling
    - Performance vs accuracy trade-offs

- [ ] **#017 - Add secure API key handling**
  - Priority: High
  - Dependencies: Cloud API clients (#014-#015)
  - Description: Secure storage and management of API credentials
  - Acceptance Criteria:
    - Environment variable support
    - Command-line argument option
    - Keychain integration for macOS
    - API key validation
    - No persistence of keys in memory
    - Clear error messages for missing keys

- [ ] **#018 - Implement retry mechanisms and error handling**
  - Priority: Medium
  - Dependencies: Cloud API clients (#014-#015)
  - Description: Robust error handling for cloud service failures
  - Acceptance Criteria:
    - Exponential backoff retry logic
    - Network error handling
    - API rate limit handling
    - Partial failure recovery
    - Timeout management
    - User-friendly error messages

- [ ] **#019 - Add file chunking for large audio files**
  - Priority: Medium
  - Dependencies: Cloud API clients (#014-#015)
  - Description: Handle large audio files that exceed API limits
  - Acceptance Criteria:
    - Automatic file size detection
    - Intelligent chunking at silence boundaries
    - Concurrent chunk processing
    - Result reassembly with timing adjustment
    - Progress reporting across chunks
    - Error handling for partial failures

---

## Phase 5: Output Management (Week 5-6)

### 🎯 Ready to Start

- [ ] **#020 - Implement plain text output formatter**
  - Priority: High
  - Dependencies: Transcription engines (#008-#019)
  - Description: Clean text output with optional timestamps
  - Acceptance Criteria:
    - TextFormatter class
    - Clean transcript with proper formatting
    - Optional timestamp inclusion
    - Speaker identification when available
    - Confidence score annotations (optional)
    - Proper line breaking and paragraphs

- [ ] **#021 - Implement SRT subtitle formatter**
  - Priority: High
  - Dependencies: Transcription engines (#008-#019)
  - Description: Standard subtitle format with precise timing
  - Acceptance Criteria:
    - SRTFormatter class
    - Proper SRT format compliance
    - Accurate timestamp formatting
    - Appropriate subtitle length limits
    - Line breaking for readability
    - Character encoding handling

- [ ] **#022 - Implement JSON output formatter**
  - Priority: Medium
  - Dependencies: Transcription engines (#008-#019)
  - Description: Structured JSON output with full metadata
  - Acceptance Criteria:
    - JSONFormatter class
    - Complete TranscriptionResult serialization
    - Metadata inclusion (engine, confidence, timing)
    - Segment-level details
    - Audio format information
    - Processing statistics

- [ ] **#023 - Add comprehensive metadata inclusion**
  - Priority: Medium
  - Dependencies: Output formatters (#020-#022)
  - Description: Rich metadata in all output formats
  - Acceptance Criteria:
    - Processing timestamps
    - Engine information
    - Confidence scores
    - Audio properties
    - Language detection results
    - Performance metrics

- [ ] **#024 - Create robust file writing with error recovery**
  - Priority: High
  - Dependencies: Output formatters (#020-#022)
  - Description: Reliable output file creation with error handling
  - Acceptance Criteria:
    - OutputWriter class
    - Atomic file writing
    - Permission error handling
    - Disk space validation
    - Backup and recovery options
    - Path validation and creation

- [ ] **#025 - Add output validation and verification**
  - Priority: Medium
  - Dependencies: File writing (#024)
  - Description: Verification of output file integrity
  - Acceptance Criteria:
    - Output format validation
    - File size verification
    - Content integrity checks
    - Encoding validation
    - Success confirmation messages

---

## Phase 6: Testing & Polish (Week 6-7)

### 🎯 Ready to Start

- [ ] **#026 - Create unit tests for all components**
  - Priority: High
  - Dependencies: All implementation phases
  - Description: Comprehensive unit test coverage
  - Acceptance Criteria:
    - 90%+ code coverage
    - All public APIs tested
    - Mock implementations for external dependencies
    - Edge case testing
    - Error condition testing

- [ ] **#027 - Add integration tests with sample files**
  - Priority: High
  - Dependencies: Complete implementation
  - Description: End-to-end testing with real audio/video files
  - Acceptance Criteria:
    - Sample MP4 files for testing
    - Complete workflow testing
    - Multiple format output testing
    - Error scenario testing
    - Performance benchmarking

- [ ] **#028 - Performance testing on both architectures**
  - Priority: Medium
  - Dependencies: Complete implementation
  - Description: Validate performance targets on Intel and Apple Silicon
  - Acceptance Criteria:
    - Meet performance targets from CLAUDE.md
    - Memory usage profiling
    - CPU utilization monitoring
    - Comparison between architectures
    - Performance regression detection

- [ ] **#029 - Error handling and edge case testing**
  - Priority: High
  - Dependencies: Complete implementation
  - Description: Comprehensive error scenario testing
  - Acceptance Criteria:
    - Invalid input file handling
    - Network failure scenarios
    - API error conditions
    - Resource exhaustion testing
    - Graceful degradation validation

- [ ] **#030 - User experience refinement**
  - Priority: Medium
  - Dependencies: Complete implementation
  - Description: Polish user interface and experience
  - Acceptance Criteria:
    - Clear progress indicators
    - Helpful error messages
    - Intuitive command-line interface
    - Comprehensive help text
    - Usage examples

- [ ] **#031 - Documentation and usage examples**
  - Priority: Medium
  - Dependencies: Complete implementation
  - Description: User documentation and examples
  - Acceptance Criteria:
    - Updated README with usage examples
    - Man page creation
    - Installation instructions
    - Troubleshooting guide
    - API documentation for developers

---

## Build & Distribution

### 🎯 Future Tasks

- [ ] **#032 - Universal binary build optimization**
  - Priority: Medium
  - Description: Optimize build process for both architectures
  - Acceptance Criteria:
    - Automated universal binary creation
    - Build script optimization
    - Release build validation
    - Size optimization

- [ ] **#033 - Homebrew tap creation**
  - Priority: Low
  - Description: Create Homebrew formula for easy installation
  - Acceptance Criteria:
    - Homebrew formula
    - Custom tap repository
    - Version management
    - Dependency handling

- [x] **#034 - GitHub Actions CI/CD**
  - Priority: Medium
  - Description: Automated testing and release pipeline
  - Acceptance Criteria:
    - Automated testing on commits
    - Release build automation
    - Multi-architecture testing
    - Automated distribution

---

## GitHub Issue Template

When creating GitHub issues from this TODO, use this template:

```markdown
## Issue Title
[Task Name from TODO]

## Priority
[High/Medium/Low]

## Description
[Detailed description from TODO]

## Acceptance Criteria
[Copy acceptance criteria from TODO]

## Dependencies
- [ ] Issue #XXX - [Dependency name]

## Labels
- `phase-[1-6]`
- `priority-[high/medium/low]`
- `component-[audio/transcription/output/testing]`

## Estimated Time
[Development time estimate]
```

---

## Progress Tracking

- **Total Tasks**: 34
- **Completed**: 6 (18%)
- **In Progress**: 1 (3%)
- **Ready to Start**: 27 (79%)

### Phase Completion Status
- Phase 1 (Infrastructure): 85% complete
- Phase 2 (Audio Processing): 0% complete
- Phase 3 (Native Transcription): 0% complete
- Phase 4 (Cloud Fallback): 0% complete
- Phase 5 (Output Management): 0% complete
- Phase 6 (Testing & Polish): 0% complete

---

*Last Updated: [Date]*
*Next Priority: Implement logging system (#001)*