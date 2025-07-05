# Vox - Audio Transcription CLI

[![CI](https://github.com/jsonify/vox/actions/workflows/ci.yml/badge.svg)](https://github.com/jsonify/vox/actions/workflows/ci.yml)
[![Release](https://github.com/jsonify/vox/actions/workflows/release.yml/badge.svg)](https://github.com/jsonify/vox/actions/workflows/release.yml)

## Project Overview
Vox is a native macOS command-line interface (CLI) application that extracts audio from MP4 video files and transcribes the audio content to text using Apple's native SpeechAnalyzer framework with fallback to cloud-based transcription services.

## Key Technologies
- **Language**: Swift 5.9+
- **Target**: macOS 12.0+ (Monterey and later)
- **CLI Framework**: Swift ArgumentParser
- **Audio Processing**: AVFoundation + ffmpeg fallback
- **Transcription**: Apple SpeechAnalyzer (primary), cloud APIs (fallback)
- **Build System**: Swift Package Manager

## Quick Reference

### Command Structure
```bash
vox [input-file] [options]

# Basic usage examples
vox video.mp4
vox video.mp4 -o transcript.txt
vox video.mp4 --format srt
vox video.mp4 -v --timestamps

# Advanced usage
vox lecture.mp4 --language en-US --fallback-api openai
vox presentation.mp4 --format json --force-cloud
vox interview.mp4 --timestamps --verbose

# Batch processing
vox *.mp4
```

### Core Command Line Arguments
- `inputFile: String` - Input MP4 video file path
- `-o, --output: String?` - Output file path
- `-f, --format: OutputFormat` - Output format: txt, srt, json (default: txt)
- `-l, --language: String?` - Language code (e.g., en-US, es-ES)
- `--fallback-api: FallbackAPI?` - Fallback API: openai, revai
- `--api-key: String?` - API key for fallback service
- `-v, --verbose: Bool` - Enable verbose output
- `--force-cloud: Bool` - Force cloud transcription (skip native)
- `--timestamps: Bool` - Include timestamps in output

## 📚 Documentation Structure

This project uses focused documentation files for different aspects of development and usage:

### For Users and Getting Started
- **[README.md](README.md)** - Project overview, installation, and quick start guide
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions *(to be created)*

### For Developers
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design, components, and data models
- **[IMPLEMENTATION.md](docs/IMPLEMENTATION.md)** - Development phases, technical tasks, and milestones
- **[TESTING.md](docs/TESTING.md)** - Testing strategy, test categories, and performance targets

### For DevOps and Deployment
- **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Build configuration, packaging, and distribution
- **[SECURITY.md](docs/SECURITY.md)** - Privacy considerations, security architecture, and API key handling

### Reference Materials
- **[API.md](docs/API.md)** - Cloud API integration details *(to be created)*
- **[ROADMAP.md](docs/ROADMAP.md)** - Future enhancements and maintenance plan *(to be created)*

## Performance Targets
- **Apple Silicon**: Process 30-minute video in < 60 seconds
- **Intel Mac**: Process 30-minute video in < 90 seconds
- **Startup Time**: Application launch < 2 seconds
- **Memory Usage**: Peak usage < 1GB for typical files

## Key Data Models

### TranscriptionResult
```swift
struct TranscriptionResult {
    let text: String
    let language: String
    let confidence: Double
    let duration: TimeInterval
    let segments: [TranscriptionSegment]
    let engine: TranscriptionEngine
    let processingTime: TimeInterval
    let audioFormat: AudioFormat
}
```

### TranscriptionSegment
```swift
struct TranscriptionSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let speakerID: String?
}
```

### OutputFormat
```swift
enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case txt
    case srt
    case json
}
```

## Development Quick Start

### Environment Setup
```bash
# Clone the repository
git clone https://github.com/jsonify/vox.git
cd vox

# Build the project
swift build

# Run tests
swift test

# Build for release
swift build -c release
```

### Key Development Rules

#### Test File Requirements
- **Maximum 400 lines per test file** to maintain readability and focus
- Split large test files into focused, smaller files
- Use descriptive naming: `AudioProcessorBasicTests.swift`, `AudioProcessorErrorTests.swift`

#### Critical Testing Patterns
```swift
// ✅ CORRECT OutputWriter usage
try outputWriter.writeContentSafely(content, to: path)
try outputWriter.writeTranscriptionResult(result, to: path, format: format)

// ✅ CORRECT CLI configuration
var voxCommand = Vox()
voxCommand.inputFile = "test.mp4"
voxCommand.output = "output.txt"

// ✅ CORRECT error handling
case .failure(let error):
    XCTAssertFalse(error.localizedDescription.isEmpty)
```

### Build Configuration
```bash
# Universal Binary Setup
ARCHS = arm64 x86_64
VALID_ARCHS = arm64 x86_64
MACOSX_DEPLOYMENT_TARGET = 12.0
SWIFT_VERSION = 5.9

# Development Commands
swift build                    # Standard build
swift test                     # Run all tests
swift test --filter CITests    # CI-safe tests only
swift build -c release         # Release build

# Check test file line counts (must be under 400 lines each)
find Tests -name "*.swift" -exec wc -l {} \; | sort -nr

# Create universal binary
lipo -create -output vox \
  .build/x86_64-apple-macosx/release/vox \
  .build/arm64-apple-macosx/release/vox
```

## Security & Privacy
- **Local Processing Priority**: Always attempt local transcription before cloud
- **User Control**: Explicit opt-in required for cloud processing
- **Data Retention**: No persistent storage of audio or transcriptions
- **Temporary Files**: Secure cleanup of all temporary data
- **API Key Security**: Secure handling and non-persistence of API keys

*See [SECURITY.md](docs/SECURITY.md) for comprehensive security details.*

## Environment Variables
- `OPENAI_API_KEY` - OpenAI API key for Whisper fallback
- `REVAI_API_KEY` - Rev.ai API key for cloud transcription
- `VOX_VERBOSE` - Enable verbose logging by default

## Distribution
- **Standalone Executable**: Self-contained `vox` binary
- **Installation**: Copy to `/usr/local/bin` or add to PATH
- **Homebrew**: Custom tap for easy installation
- **GitHub Releases**: Universal binary distribution

*See [DEPLOYMENT.md](docs/DEPLOYMENT.md) for complete distribution setup.*

## Documentation Navigation Guide

### 🚀 Getting Started
1. Start with **[README.md](README.md)** for installation and basic usage
2. Check **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** if you encounter issues

### 👨‍💻 Development Workflow
1. **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Understand the system design
2. **[IMPLEMENTATION.md](docs/IMPLEMENTATION.md)** - Follow the development phases
3. **[TESTING.md](docs/TESTING.md)** - Write and run tests properly
4. **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Build and distribute

### 🔒 Security & Privacy
1. **[SECURITY.md](docs/SECURITY.md)** - Comprehensive security architecture
2. **[API.md](docs/API.md)** - Cloud service integration details

### 📈 Project Management
1. **[ROADMAP.md](docs/ROADMAP.md)** - Future features and timeline
2. This file (**CLAUDE.md**) - Master reference and navigation

## Current Status
- ✅ Project structure defined
- ✅ Architecture documented
- ✅ Implementation plan created
- ✅ Testing strategy established
- ✅ Security framework designed
- 🔄 Development in progress (Phase 1)

## Quick Links
- **Repository**: https://github.com/jsonify/vox
- **Issues**: https://github.com/jsonify/vox/issues
- **Releases**: https://github.com/jsonify/vox/releases

---

**This CLAUDE.md serves as the master navigation document. For specific implementation details, testing procedures, deployment instructions, or security information, refer to the appropriate specialized documentation files listed above.**
