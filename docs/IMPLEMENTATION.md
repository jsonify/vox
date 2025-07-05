# Vox Implementation Guide

## Overview
This document outlines the complete development plan for implementing the Vox CLI application, including phases, milestones, tasks, and technical requirements.

## Development Phases

### Phase 1: Core Infrastructure (Week 1-2)

#### Objectives
Establish the foundational project structure, basic CLI interface, and core data models.

#### Deliverables
- Vox project setup with Swift Package Manager
- Basic CLI argument parsing with ArgumentParser
- Core data models and error types
- Project structure and build configuration

#### Tasks
- [ ] Initialize Xcode project with Vox CLI target
- [ ] Configure Swift Package Manager dependencies
- [ ] Implement basic argument parsing structure for `vox` command
- [ ] Create core data models (TranscriptionResult, AudioFile, etc.)
- [ ] Set up error handling framework with Vox branding
- [ ] Configure universal binary build settings

#### Technical Specifications
```swift
// Package.swift
let package = Package(
    name: "vox",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "vox", targets: ["vox"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "vox",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(name: "VoxTests", dependencies: ["vox"])
    ]
)
```

#### Success Criteria
- Project builds successfully on both Intel and Apple Silicon
- Basic `vox --help` command works
- Core data models are properly defined
- Initial test structure is in place

---

### Phase 2: Audio Processing (Week 2-3)

#### Objectives
Implement robust audio extraction from MP4 files using AVFoundation with ffmpeg fallback.

#### Deliverables
- Audio extraction from MP4 files
- AVFoundation integration
- ffmpeg fallback implementation
- Audio format validation

#### Tasks
- [ ] Implement AVFoundation-based audio extraction
- [ ] Create ffmpeg wrapper for fallback processing
- [ ] Add audio format detection and validation
- [ ] Implement temporary file management
- [ ] Add progress reporting for audio processing
- [ ] Create comprehensive audio processing tests

#### Technical Implementation
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
    
    private func extractWithAVFoundation(_ videoPath: String) async throws -> URL {
        let asset = AVAsset(url: URL(fileURLWithPath: videoPath))
        
        // macOS 13+ compatible approach
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw VoxError.noAudioTrackFound
        }
        
        // Export audio to temporary file
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        // ... export implementation
    }
}
```

#### Success Criteria
- Successfully extract audio from various MP4 formats
- Fallback mechanism works when AVFoundation fails
- Temporary files are properly managed and cleaned up
- Audio quality validation is implemented

---

### Phase 3: Native Transcription (Week 3-4)

#### Objectives
Integrate Apple's SpeechAnalyzer framework for native, privacy-first transcription.

#### Deliverables
- SpeechAnalyzer integration
- Language detection and specification
- Confidence scoring
- Timestamp extraction

#### Tasks
- [ ] Implement SpeechAnalyzer wrapper
- [ ] Add language detection and preference handling
- [ ] Implement confidence scoring and validation
- [ ] Create timestamp and segment extraction
- [ ] Add progress reporting for transcription
- [ ] Optimize performance for both Intel and Apple Silicon

#### Technical Implementation
```swift
import Speech

class NativeTranscriptionEngine {
    private let speechRecognizer: SFSpeechRecognizer
    
    init(locale: Locale = Locale.current) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoxError.speechRecognizerUnavailable
        }
        self.speechRecognizer = recognizer
    }
    
    func transcribe(_ audioURL: URL, language: String?) async throws -> TranscriptionResult {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true // Privacy-first
        
        return try await withCheckedThrowingContinuation { continuation in
            speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: VoxError.transcriptionFailed(error))
                    return
                }
                
                guard let result = result, result.isFinal else { return }
                
                let transcriptionResult = TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    language: self.speechRecognizer.locale.identifier,
                    confidence: self.calculateConfidence(result),
                    duration: self.calculateDuration(result),
                    segments: self.extractSegments(result),
                    engine: .native(version: "1.0"),
                    processingTime: 0, // Will be calculated by caller
                    audioFormat: AudioFormat() // Will be provided by caller
                )
                
                continuation.resume(returning: transcriptionResult)
            }
        }
    }
    
    private func calculateConfidence(_ result: SFSpeechRecognitionResult) -> Double {
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else { return 0.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Double(segments.count)
    }
    
    private func extractSegments(_ result: SFSpeechRecognitionResult) -> [TranscriptionSegment] {
        return result.bestTranscription.segments.map { segment in
            TranscriptionSegment(
                text: segment.substring,
                startTime: segment.timestamp,
                endTime: segment.timestamp + segment.duration,
                confidence: segment.confidence,
                speakerID: nil
            )
        }
    }
}
```

#### Success Criteria
- Native transcription works on both Intel and Apple Silicon
- Language detection and preference handling implemented
- Confidence scoring provides meaningful quality metrics
- Timestamp extraction enables subtitle generation

---

### Phase 4: Cloud Fallback (Week 4-5)

#### Objectives
Implement cloud-based transcription services as intelligent fallback options.

#### Deliverables
- OpenAI Whisper API integration
- Rev.ai API integration
- Intelligent fallback logic
- API key management

#### Tasks
- [ ] Implement OpenAI Whisper API client
- [ ] Implement Rev.ai API client
- [ ] Create intelligent fallback decision logic
- [ ] Add secure API key handling
- [ ] Implement retry mechanisms and error handling
- [ ] Add file chunking for large audio files

#### Technical Implementation
```swift
class CloudTranscriptionEngine {
    enum Provider {
        case openai
        case revai
    }
    
    func transcribe(_ audioURL: URL, 
                   provider: Provider, 
                   apiKey: String) async throws -> TranscriptionResult {
        switch provider {
        case .openai:
            return try await transcribeWithOpenAI(audioURL, apiKey: apiKey)
        case .revai:
            return try await transcribeWithRevAI(audioURL, apiKey: apiKey)
        }
    }
    
    private func transcribeWithOpenAI(_ audioURL: URL, apiKey: String) async throws -> TranscriptionResult {
        let audioData = try Data(contentsOf: audioURL)
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VoxError.cloudAPIError("OpenAI API request failed")
        }
        
        let result = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return convertOpenAIResponse(result)
    }
}

class TranscriptionCoordinator {
    private let nativeEngine: NativeTranscriptionEngine
    private let cloudEngine: CloudTranscriptionEngine
    
    func transcribe(_ audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Step 1: Try native SpeechAnalyzer unless forced to use cloud
        if !options.forceCloud {
            do {
                let result = try await nativeEngine.transcribe(audioURL, language: options.language)
                let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                
                // Return if confidence is acceptable
                if result.confidence > 0.8 {
                    return result.with(processingTime: processingTime)
                }
                
                // Log low confidence but continue to cloud fallback
                print("vox ⚠️  Low confidence (\(result.confidence)), trying cloud fallback...")
            } catch {
                print("vox ⚠️  Native transcription failed: \(error.localizedDescription)")
            }
        }
        
        // Step 2: Fallback to cloud if configured
        if let fallbackConfig = options.fallbackConfig {
            do {
                let result = try await cloudEngine.transcribe(audioURL, 
                                                            provider: fallbackConfig.provider,
                                                            apiKey: fallbackConfig.apiKey)
                let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                return result.with(processingTime: processingTime)
            } catch {
                print("vox ⚠️  Cloud transcription failed: \(error.localizedDescription)")
            }
        }
        
        // Step 3: Return native result even if low confidence
        let result = try await nativeEngine.transcribe(audioURL, language: options.language)
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        return result.with(processingTime: processingTime)
    }
}
```

#### Success Criteria
- OpenAI Whisper API integration works reliably
- Rev.ai API integration provides alternative cloud option
- Intelligent fallback logic makes appropriate decisions
- API keys are handled securely without persistence

---

### Phase 5: Output Management (Week 5-6)

#### Objectives
Implement comprehensive output formatting and file management capabilities.

#### Deliverables
- Multiple output format support (TXT, SRT, JSON)
- File writing operations with error recovery
- Metadata inclusion
- Output validation

#### Tasks
- [ ] Implement plain text output formatter
- [ ] Implement SRT subtitle formatter
- [ ] Implement JSON output formatter
- [ ] Add comprehensive metadata inclusion
- [ ] Create robust file writing with error recovery
- [ ] Add output validation and verification

#### Technical Implementation
```swift
class OutputManager {
    func writeTranscriptionResult(_ result: TranscriptionResult, 
                                 to path: String, 
                                 format: OutputFormat,
                                 includeTimestamps: Bool = false) throws {
        let content: String
        let finalPath: String
        
        switch format {
        case .txt:
            content = generatePlainText(result, includeTimestamps: includeTimestamps)
            finalPath = ensureExtension(path, ".txt")
            
        case .srt:
            content = generateSRT(result)
            finalPath = ensureExtension(path, ".srt")
            
        case .json:
            content = try generateJSON(result)
            finalPath = ensureExtension(path, ".json")
        }
        
        try writeContentSafely(content, to: finalPath)
    }
    
    private func generatePlainText(_ result: TranscriptionResult, includeTimestamps: Bool) -> String {
        if includeTimestamps && !result.segments.isEmpty {
            return result.segments.map { segment in
                "[\(formatTimestamp(segment.startTime))] \(segment.text)"
            }.joined(separator: "\n")
        } else {
            return result.text
        }
    }
    
    private func generateSRT(_ result: TranscriptionResult) -> String {
        return result.segments.enumerated().map { index, segment in
            let startTime = formatSRTTimestamp(segment.startTime)
            let endTime = formatSRTTimestamp(segment.endTime)
            return "\(index + 1)\n\(startTime) --> \(endTime)\n\(segment.text)\n"
        }.joined(separator: "\n")
    }
    
    private func generateJSON(_ result: TranscriptionResult) throws -> String {
        let output = JSONOutput(
            transcription: result.text,
            language: result.language,
            confidence: result.confidence,
            duration: result.duration,
            segments: result.segments.map { segment in
                SegmentOutput(
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    confidence: segment.confidence,
                    speakerID: segment.speakerID
                )
            },
            metadata: MetadataOutput(
                engine: result.engine.description,
                processingTime: result.processingTime,
                audioFormat: result.audioFormat,
                voxVersion: getVoxVersion()
            )
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(output)
        return String(data: data, encoding: .utf8)!
    }
    
    private func writeContentSafely(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        
        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, 
                                              withIntermediateDirectories: true, 
                                              attributes: nil)
        
        // Write atomically for safety
        try content.write(to: url, atomically: true, encoding: .utf8)
        
        // Verify the write was successful
        let verifyContent = try String(contentsOf: url, encoding: .utf8)
        guard verifyContent == content else {
            throw VoxError.outputVerificationFailed
        }
    }
    
    private func formatSRTTimestamp(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}

struct JSONOutput: Codable {
    let transcription: String
    let language: String
    let confidence: Double
    let duration: TimeInterval
    let segments: [SegmentOutput]
    let metadata: MetadataOutput
}

struct SegmentOutput: Codable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let speakerID: String?
}

struct MetadataOutput: Codable {
    let engine: String
    let processingTime: TimeInterval
    let audioFormat: AudioFormat
    let voxVersion: String
    let timestamp: Date = Date()
}
```

#### Success Criteria
- All three output formats generate correctly
- File writing is atomic and includes verification
- Metadata is comprehensive and useful
- Error recovery handles write failures gracefully

---

### Phase 6: Testing & Polish (Week 6-7)

#### Objectives
Create comprehensive test coverage, optimize performance, and polish the user experience.

#### Deliverables
- Comprehensive test suite
- Performance optimization
- Error handling refinement
- Documentation and usage examples

#### Tasks
- [ ] Create unit tests for all components
- [ ] Add integration tests with sample files
- [ ] Performance testing on both architectures
- [ ] Error handling and edge case testing
- [ ] User experience refinement
- [ ] Documentation and usage examples

#### Test Implementation Strategy
```swift
final class VoxIntegrationTests: XCTestCase {
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
    
    func testEndToEndTranscription() async throws {
        // Test complete workflow from MP4 to transcript
        let sampleVideo = TestDataManager.getSampleFile("short_speech.mp4")
        let outputPath = tempDirectory.appendingPathComponent("output.txt").path
        
        var command = Vox()
        command.inputFile = sampleVideo.path
        command.output = outputPath
        command.format = .txt
        
        try await command.run()
        
        let output = try String(contentsOfFile: outputPath)
        XCTAssertFalse(output.isEmpty, "Output should not be empty")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
    }
    
    func testPerformanceBenchmarks() async throws {
        let testFile = TestDataManager.getSampleFile("performance_test.mp4")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let processor = AudioProcessor()
        let audioURL = try await processor.extractAudio(from: testFile.path)
        
        let transcriptionEngine = try NativeTranscriptionEngine()
        let result = try await transcriptionEngine.transcribe(audioURL, language: nil)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let realTimeRatio = result.duration / processingTime
        
        XCTAssertGreaterThan(realTimeRatio, 1.0, "Should process faster than real-time")
        
        // Performance targets based on architecture
        #if arch(arm64)
        XCTAssertGreaterThan(realTimeRatio, 30.0, "Apple Silicon should be very fast")
        #else
        XCTAssertGreaterThan(realTimeRatio, 20.0, "Intel should still be reasonably fast")
        #endif
    }
}
```

#### Success Criteria
- All tests pass on both Intel and Apple Silicon
- Performance meets or exceeds targets
- Error handling covers all edge cases
- User experience is smooth and informative

## Technical Milestones

### Milestone 1: Basic Functionality (End of Week 2)
- `vox` command accepts MP4 input and produces text output
- Native SpeechAnalyzer transcription working
- Basic error handling implemented
- **Success Test**: `vox sample.mp4` produces transcript

### Milestone 2: Enhanced Features (End of Week 4)
- Multiple output formats supported (`vox video.mp4 --format srt`)
- Cloud fallback functional (`vox video.mp4 --fallback-api openai`)
- Progress indicators implemented with Vox branding
- **Success Test**: All output formats work, cloud fallback activates when needed

### Milestone 3: Production Ready (End of Week 6)
- Comprehensive error handling with helpful suggestions
- Performance optimized for both Intel and Apple Silicon
- Full test coverage and documentation complete
- **Success Test**: Application handles all error conditions gracefully

## Build Configuration

### Universal Binary Setup
```swift
// Build Settings for Universal Binary
ARCHS = arm64 x86_64
VALID_ARCHS = arm64 x86_64
MACOSX_DEPLOYMENT_TARGET = 12.0
SWIFT_VERSION = 5.9
```

### Release Build Optimization
```swift
// Release Configuration
SWIFT_OPTIMIZATION_LEVEL = -O
SWIFT_COMPILATION_MODE = wholemodule
GCC_OPTIMIZATION_LEVEL = s
DEAD_CODE_STRIPPING = YES
STRIP_INSTALLED_PRODUCT = YES
```

### Development Commands
```bash
# Build the project
swift build

# Run tests
swift test

# Build for release
swift build -c release

# Create universal binary
lipo -create -output vox \
  .build/x86_64-apple-macosx/release/vox \
  .build/arm64-apple-macosx/release/vox

# Check test file line counts (must be under 400 lines each)
find Tests -name "*.swift" -exec wc -l {} \; | sort -nr

# Run performance benchmarks
swift test --filter Performance
```

## Quality Assurance

### Code Review Checklist
- [ ] All OutputWriter method calls use correct API
- [ ] CLI command objects use `var` not `let`
- [ ] No redundant type checks in error handling
- [ ] All switch cases have executable statements
- [ ] No unused variables (use `_` instead)
- [ ] Test files under 400 lines each
- [ ] Async tests use proper expectations
- [ ] Resources properly cleaned up
- [ ] macOS compatibility verified

### Performance Validation
- [ ] Apple Silicon: 30-minute video < 60 seconds
- [ ] Intel Mac: 30-minute video < 90 seconds
- [ ] Memory usage < 1GB for typical files
- [ ] Application startup < 2 seconds

### Error Handling Validation
- [ ] File not found errors have helpful messages
- [ ] Network errors trigger appropriate fallbacks
- [ ] Audio extraction failures try alternative methods
- [ ] Output write errors suggest solutions

This implementation guide provides a structured approach to building Vox with clear milestones, technical specifications, and quality gates to ensure a robust, high-performance CLI application.