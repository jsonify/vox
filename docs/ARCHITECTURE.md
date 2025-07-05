# Vox System Architecture

## Overview
Vox is a native macOS command-line interface (CLI) application that extracts audio from MP4 video files and transcribes the audio content to text using Apple's native SpeechAnalyzer framework with fallback to cloud-based transcription services.

## High-Level Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   CLI Interface │───▶│  Audio Processor │───▶│ Transcription   │
│                 │    │                  │    │ Engine          │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Argument Parser │    │   AVFoundation   │    │ SpeechAnalyzer  │
│                 │    │     ffmpeg       │    │   (Primary)     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
                                               ┌─────────────────┐
                                               │ Cloud Fallback  │
                                               │ (OpenAI/Rev.ai) │
                                               └─────────────────┘
```

## Technology Stack

### Core Technologies
- **Language**: Swift 5.9+
- **Target**: macOS 12.0+ (Monterey and later)
- **CLI Framework**: Swift ArgumentParser
- **Audio Processing**: AVFoundation + ffmpeg fallback
- **Transcription**: Apple SpeechAnalyzer (primary), cloud APIs (fallback)

### Development Tools
- **IDE**: Xcode 15.0+
- **Build System**: Swift Package Manager
- **Version Control**: Git
- **Dependency Management**: Swift Package Manager

## Component Architecture

### 1. CLI Interface Layer
Handles command line argument parsing, user interaction, progress reporting, and error display.

```swift
@main
struct VoxCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vox",
        abstract: "Fast MP4 audio transcription using native macOS frameworks"
    )
    
    // Command line argument parsing
    // User interaction management
    // Progress reporting
    // Error display
}
```

**Responsibilities:**
- Parse command line arguments
- Validate user input
- Display progress and status
- Handle user interruptions
- Format and display results

### 2. Audio Processing Layer
Manages MP4 audio extraction, format conversion, audio validation, and temporary file management.

```swift
class AudioProcessor {
    // MP4 audio extraction
    // Format conversion
    // Audio validation
    // Temporary file management
}
```

**Responsibilities:**
- Extract audio from MP4 files using AVFoundation
- Fallback to ffmpeg for compatibility
- Convert audio to optimal format for transcription
- Validate audio quality and format
- Manage temporary files securely

### 3. Transcription Engine Layer
Coordinates between native SpeechAnalyzer and cloud API services for audio transcription.

```swift
class TranscriptionEngine {
    // SpeechAnalyzer integration
    // Cloud API fallback
    // Result formatting
    // Language detection
}
```

**Responsibilities:**
- Attempt native transcription first
- Implement intelligent fallback to cloud services
- Handle language detection and specification
- Manage confidence scoring
- Extract timestamps and segments

### 4. Output Management Layer
Handles multiple output formats, file writing operations, metadata inclusion, and error recovery.

```swift
class OutputManager {
    // Multiple format support (TXT, SRT, JSON)
    // File writing operations
    // Metadata inclusion
    // Error recovery
}
```

**Responsibilities:**
- Generate output in multiple formats (TXT, SRT, JSON)
- Write files safely with error recovery
- Include comprehensive metadata
- Handle output path management

## Data Models

### Core Data Structures

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

struct TranscriptionSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let speakerID: String?
}

struct AudioFormat {
    let sampleRate: Int
    let channels: Int
    let bitDepth: Int
    let codec: String
    let duration: TimeInterval
}

enum TranscriptionEngine {
    case native(version: String)
    case openai(model: String)
    case revai
}
```

### Configuration Models

```swift
struct TranscriptionOptions {
    let language: String?
    let forceCloud: Bool
    let includeTimestamps: Bool
    let outputFormat: OutputFormat
    let fallbackConfig: FallbackConfig?
    let verbose: Bool
}

struct FallbackConfig {
    let provider: CloudProvider
    let apiKey: String
    let maxRetries: Int
    let timeoutInterval: TimeInterval
}

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case txt
    case srt
    case json
    
    var fileExtension: String {
        switch self {
        case .txt: return ".txt"
        case .srt: return ".srt"
        case .json: return ".json"
        }
    }
}
```

## Processing Pipeline

### 1. Input Validation
- Verify file existence and accessibility
- Check file format and codec support
- Validate command line arguments
- Ensure output path is writable

### 2. Audio Extraction
```swift
class AudioProcessor {
    func extractAudio(from videoPath: String) async throws -> URL {
        // Primary: Use AVFoundation for optimal performance
        if let audioURL = try? await extractWithAVFoundation(videoPath) {
            return audioURL
        }
        
        // Fallback: Use ffmpeg for compatibility
        return try await extractWithFFmpeg(videoPath)
    }
}
```

### 3. Native Transcription
```swift
class NativeTranscriptionEngine {
    func transcribe(_ audioURL: URL, language: String?) async throws -> TranscriptionResult {
        let request = SpeechAnalysisRequest(audioURL: audioURL)
        
        if let language = language {
            request.preferredLanguage = language
        }
        
        let result = try await speechAnalyzer.analyze(request)
        return TranscriptionResult(
            text: result.transcription,
            confidence: result.confidence,
            timestamps: result.segments,
            language: result.detectedLanguage
        )
    }
}
```

### 4. Intelligent Fallback
```swift
class TranscriptionCoordinator {
    func transcribe(_ audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        // Step 1: Try native SpeechAnalyzer
        if !options.forceCloud {
            if let result = try? await nativeEngine.transcribe(audioURL, language: options.language) {
                if result.confidence > 0.8 {
                    return result
                }
            }
        }
        
        // Step 2: Fallback to cloud if configured
        if let fallbackConfig = options.fallbackConfig {
            return try await cloudEngine.transcribe(audioURL, 
                                                  provider: fallbackConfig.provider,
                                                  apiKey: fallbackConfig.apiKey)
        }
        
        // Step 3: Return native result even if low confidence
        return try await nativeEngine.transcribe(audioURL, language: options.language)
    }
}
```

### 5. Output Generation
Support for multiple output formats with comprehensive metadata:

- **TXT**: Plain text with optional timestamps
- **SRT**: Subtitle format with time codes
- **JSON**: Structured data with full metadata

## System Requirements

### Minimum Requirements
- **Operating System**: macOS 12.0 (Monterey) or later
- **Architecture**: Intel x86_64 or Apple Silicon arm64
- **Memory**: 2GB RAM available
- **Storage**: 100MB free space
- **Network**: Internet connection for cloud fallback (optional)

### Recommended Requirements
- **Operating System**: macOS 13.0 (Ventura) or later
- **Architecture**: Apple Silicon for optimal performance
- **Memory**: 4GB RAM available
- **Storage**: 500MB free space for temporary files
- **Network**: Broadband connection for large file cloud processing

## Performance Specifications

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

## Security Architecture

### Privacy-First Design
- **Local Processing Priority**: Always attempt local transcription before cloud
- **User Control**: Explicit opt-in required for cloud processing
- **Data Retention**: No persistent storage of audio or transcriptions
- **Temporary Files**: Secure cleanup of all temporary data

### Security Implementation
```swift
class SecureFileManager {
    private let tempDirectory: URL
    
    init() throws {
        // Create secure temporary directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, 
                                              withIntermediateDirectories: true)
    }
    
    deinit {
        // Secure cleanup
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}
```

### API Key Management
```swift
class APIKeyManager {
    // Never store API keys persistently
    // Accept via environment variables or command line only
    // Clear from memory after use
    
    static func getAPIKey(for provider: CloudProvider) -> String? {
        switch provider {
        case .openai:
            return ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        case .revai:
            return ProcessInfo.processInfo.environment["REVAI_API_KEY"]
        }
    }
}
```

## Error Handling Architecture

### Error Categories
1. **User Input Errors** - File not found, invalid format, permission denied
2. **Processing Errors** - Audio extraction failed, transcription failed, network errors
3. **Output Errors** - Write permission, disk full, format error

### Recovery Strategies
```swift
enum RecoveryStrategy {
    case retry(maxAttempts: Int)
    case fallback(alternative: ProcessingMethod)
    case skipWithWarning
    case failWithError
}

class ErrorRecoveryManager {
    func handle(_ error: TranscriptionError) async throws -> TranscriptionResult? {
        switch error {
        case .nativeTranscriptionFailed:
            // Try cloud fallback if available
            return try await attemptCloudFallback()
        case .cloudAPIError(let apiError):
            // Retry with exponential backoff
            return try await retryWithBackoff(apiError)
        case .audioExtractionFailed:
            // Try alternative extraction method
            return try await attemptAlternativeExtraction()
        default:
            throw error
        }
    }
}
```

## Extensibility

### Plugin Architecture (Future)
The architecture supports future extension through:
- **Processing Plugins**: Custom audio processing steps
- **Transcription Plugins**: Additional transcription engines
- **Output Plugins**: Custom output formats
- **Filter Plugins**: Post-processing and enhancement

### API Integration Points
- **Cloud Providers**: Easy addition of new transcription services
- **Audio Formats**: Support for additional video/audio formats
- **Output Formats**: New export formats and metadata options
- **Language Models**: Integration with specialized language models

## Dependencies

### Swift Package Dependencies
```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-crypto", from: "2.0.0")
]
```

### System Dependencies
- **AVFoundation**: Native audio processing
- **SpeechAnalyzer**: Native transcription (macOS 12.0+)
- **ffmpeg**: Fallback audio processing (optional)
- **Network**: HTTP client for cloud APIs

This architecture provides a solid foundation for the Vox application while maintaining flexibility for future enhancements and ensuring optimal performance on macOS systems.