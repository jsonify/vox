# API Documentation

This document provides comprehensive API documentation for developers who want to understand the Vox CLI internals, integrate with cloud services, or extend the functionality.

## Core Components

### Command Line Interface

The main entry point is the `Vox` struct which implements Swift ArgumentParser:

```swift
@main
struct Vox: AsyncParsableCommand {
    @Argument(help: "Input MP4 video file")
    var inputFile: String
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Output format (txt, srt, json)")
    var format: OutputFormat = .txt
    
    @Option(name: .shortAndLong, help: "Language code (e.g., en-US)")
    var language: String?
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false
    
    @Flag(help: "Include timestamps in output")
    var timestamps: Bool = false
    
    @Flag(help: "Force cloud transcription")
    var forceCloud: Bool = false
    
    @Option(help: "Fallback API service")
    var fallbackApi: FallbackAPI?
    
    @Option(help: "API key for fallback service")
    var apiKey: String?
}
```

### Data Models

#### TranscriptionResult
```swift
struct TranscriptionResult: Codable {
    let text: String
    let language: String
    let confidence: Double
    let duration: TimeInterval
    let segments: [TranscriptionSegment]
    let engine: TranscriptionEngine
    let processingTime: TimeInterval
    let audioFormat: AudioFormat
    let metadata: TranscriptionMetadata
    
    var formattedText: String {
        return segments.map { $0.text }.joined(separator: " ")
    }
    
    var averageConfidence: Double {
        return segments.map { $0.confidence }.reduce(0, +) / Double(segments.count)
    }
}
```

#### TranscriptionSegment
```swift
struct TranscriptionSegment: Codable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let speakerID: String?
    
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    var formattedTimestamp: String {
        return TimeFormatter.format(startTime: startTime, endTime: endTime)
    }
}
```

#### AudioFormat
```swift
struct AudioFormat: Codable {
    let sampleRate: Int
    let channels: Int
    let bitDepth: Int
    let codec: String
    let duration: TimeInterval
    
    var description: String {
        return "\(codec) \(sampleRate)Hz \(channels)ch \(bitDepth)bit"
    }
}
```

#### TranscriptionEngine
```swift
enum TranscriptionEngine: String, Codable {
    case native = "apple_speech_analyzer"
    case openai = "openai_whisper"
    case revai = "revai_cloud"
    
    var displayName: String {
        switch self {
        case .native: return "Apple SpeechAnalyzer"
        case .openai: return "OpenAI Whisper"
        case .revai: return "Rev.ai"
        }
    }
}
```

#### OutputFormat
```swift
enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case txt
    case srt
    case json
    
    var fileExtension: String {
        return ".\(self.rawValue)"
    }
    
    var mimeType: String {
        switch self {
        case .txt: return "text/plain"
        case .srt: return "application/x-subrip"
        case .json: return "application/json"
        }
    }
}
```

## Core Services

### AudioProcessor

Handles audio extraction and preprocessing:

```swift
class AudioProcessor {
    func extractAudio(from videoPath: String) async throws -> AudioData {
        // Extract audio from MP4 using AVFoundation
        // Fallback to ffmpeg if native extraction fails
    }
    
    func preprocessAudio(_ audio: AudioData) async throws -> AudioData {
        // Normalize audio levels
        // Remove silence
        // Apply noise reduction
    }
    
    func analyzeAudioQuality(_ audio: AudioData) -> AudioQuality {
        // Analyze signal-to-noise ratio
        // Detect speech presence
        // Estimate transcription confidence
    }
}
```

### TranscriptionService

Core transcription orchestration:

```swift
class TranscriptionService {
    private let nativeTranscriber: NativeTranscriber
    private let cloudTranscriber: CloudTranscriber
    
    func transcribe(
        audio: AudioData,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        // Attempt native transcription first
        if !options.forceCloud {
            do {
                return try await nativeTranscriber.transcribe(audio, options: options)
            } catch {
                // Log error and fall back to cloud
            }
        }
        
        // Use cloud transcription
        return try await cloudTranscriber.transcribe(audio, options: options)
    }
}
```

### NativeTranscriber

Apple SpeechAnalyzer integration:

```swift
class NativeTranscriber {
    func transcribe(
        _ audio: AudioData,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Configure language and other options
        if let language = options.language {
            request.locale = Locale(identifier: language)
        }
        
        // Perform transcription
        let result = try await recognizer.recognitionTask(with: request)
        
        return TranscriptionResult(
            text: result.bestTranscription.formattedString,
            language: result.locale?.identifier ?? "unknown",
            confidence: result.confidence,
            duration: audio.duration,
            segments: result.segments.map { segment in
                TranscriptionSegment(
                    text: segment.substring,
                    startTime: segment.timestamp,
                    endTime: segment.timestamp + segment.duration,
                    confidence: segment.confidence,
                    speakerID: nil
                )
            },
            engine: .native,
            processingTime: processingTime,
            audioFormat: audio.format,
            metadata: metadata
        )
    }
}
```

### CloudTranscriber

Cloud service integration:

```swift
class CloudTranscriber {
    func transcribe(
        _ audio: AudioData,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        switch options.fallbackAPI {
        case .openai:
            return try await transcribeWithOpenAI(audio, options: options)
        case .revai:
            return try await transcribeWithRevAI(audio, options: options)
        case .none:
            throw TranscriptionError.noCloudServiceConfigured
        }
    }
    
    private func transcribeWithOpenAI(
        _ audio: AudioData,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        // Convert audio to required format
        let audioData = try audio.asWAV()
        
        // Prepare request
        var request = URLRequest(url: openAIURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(options.apiKey)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Parse response
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        return TranscriptionResult(
            text: openAIResponse.text,
            language: openAIResponse.language,
            confidence: 0.95, // OpenAI doesn't provide confidence
            duration: audio.duration,
            segments: openAIResponse.segments?.map { segment in
                TranscriptionSegment(
                    text: segment.text,
                    startTime: segment.start,
                    endTime: segment.end,
                    confidence: 0.95,
                    speakerID: nil
                )
            } ?? [],
            engine: .openai,
            processingTime: processingTime,
            audioFormat: audio.format,
            metadata: metadata
        )
    }
}
```

## Cloud API Integration

### OpenAI Whisper API

#### Endpoint
```
POST https://api.openai.com/v1/audio/transcriptions
```

#### Request Format
```swift
struct OpenAIRequest {
    let file: Data // Audio file data
    let model: String = "whisper-1"
    let language: String? // Optional language code
    let prompt: String? // Optional context
    let response_format: String = "verbose_json"
    let temperature: Double = 0.0
    let timestamp_granularities: [String] = ["segment"]
}
```

#### Response Format
```swift
struct OpenAIResponse: Codable {
    let text: String
    let language: String
    let duration: Double
    let segments: [OpenAISegment]?
    
    struct OpenAISegment: Codable {
        let id: Int
        let seek: Int
        let start: Double
        let end: Double
        let text: String
        let tokens: [Int]
        let temperature: Double
        let avg_logprob: Double
        let compression_ratio: Double
        let no_speech_prob: Double
    }
}
```

### Rev.ai API

#### Endpoint
```
POST https://api.rev.ai/speechtotext/v1/jobs
```

#### Request Format
```swift
struct RevAIRequest {
    let media_url: String? // For URL-based submissions
    let metadata: String? // Optional metadata
    let callback_url: String? // Webhook URL
    let skip_diarization: Bool = false
    let skip_punctuation: Bool = false
    let speaker_channels_count: Int? // For multi-channel audio
    let custom_vocabularies: [String]? // Custom vocabulary
    let filter_profanity: Bool = false
    let remove_disfluencies: Bool = false
    let delete_after_seconds: Int = 2592000 // 30 days
    let language: String? // Language code
    let transcriber: String = "machine" // or "human"
    let verbatim: Bool = false
    let rush: Bool = false
    let segments_to_transcribe: [TimeRange]? // Partial transcription
    let speaker_names: [SpeakerName]? // Speaker identification
}
```

#### Response Format
```swift
struct RevAIResponse: Codable {
    let id: String
    let status: String // "in_progress", "completed", "failed"
    let created_on: String
    let completed_on: String?
    let callback_url: String?
    let duration_seconds: Double?
    let media_url: String?
    
    // Full transcript (when status is "completed")
    let monologues: [Monologue]?
    
    struct Monologue: Codable {
        let speaker: Int
        let elements: [Element]
        
        struct Element: Codable {
            let type: String // "text", "punct"
            let value: String
            let ts: Double? // Timestamp
            let end_ts: Double? // End timestamp
            let confidence: Double?
        }
    }
}
```

## Output Formatters

### TextFormatter
```swift
class TextFormatter: OutputFormatter {
    func format(result: TranscriptionResult, options: FormatOptions) -> String {
        if options.includeTimestamps {
            return result.segments.map { segment in
                let timestamp = TimeFormatter.format(segment.startTime)
                return "[\(timestamp)] \(segment.text)"
            }.joined(separator: "\n")
        } else {
            return result.formattedText
        }
    }
}
```

### SRTFormatter
```swift
class SRTFormatter: OutputFormatter {
    func format(result: TranscriptionResult, options: FormatOptions) -> String {
        return result.segments.enumerated().map { index, segment in
            let startTime = TimeFormatter.formatSRT(segment.startTime)
            let endTime = TimeFormatter.formatSRT(segment.endTime)
            return "\(index + 1)\n\(startTime) --> \(endTime)\n\(segment.text)\n"
        }.joined(separator: "\n")
    }
}
```

### JSONFormatter
```swift
class JSONFormatter: OutputFormatter {
    func format(result: TranscriptionResult, options: FormatOptions) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try! encoder.encode(result)
        return String(data: data, encoding: .utf8)!
    }
}
```

## Error Handling

### Error Types
```swift
enum VoxError: Error, LocalizedError {
    case invalidInputFile(String)
    case audioExtractionFailed(String)
    case transcriptionFailed(String)
    case outputWriteFailed(String)
    case networkError(String)
    case apiKeyMissing(String)
    case unsupportedFormat(String)
    case insufficientPermissions(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInputFile(let path):
            return "Invalid input file: \(path)"
        case .audioExtractionFailed(let reason):
            return "Audio extraction failed: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .outputWriteFailed(let reason):
            return "Failed to write output: \(reason)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .apiKeyMissing(let service):
            return "API key missing for \(service)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .insufficientPermissions(let resource):
            return "Insufficient permissions for: \(resource)"
        }
    }
}
```

## Configuration

### Environment Variables
```swift
enum Environment {
    static let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    static let revAIKey = ProcessInfo.processInfo.environment["REVAI_API_KEY"]
    static let verbose = ProcessInfo.processInfo.environment["VOX_VERBOSE"] != nil
    static let tempDir = ProcessInfo.processInfo.environment["VOX_TEMP_DIR"] ?? "/tmp"
}
```

### Configuration File
```swift
struct VoxConfig: Codable {
    let defaultLanguage: String?
    let defaultOutputFormat: OutputFormat
    let preferredCloudService: FallbackAPI?
    let maxFileSize: Int64
    let tempDirectoryPath: String
    let enableVerboseLogging: Bool
    let autoCleanupTemp: Bool
    
    static let defaultConfig = VoxConfig(
        defaultLanguage: nil,
        defaultOutputFormat: .txt,
        preferredCloudService: nil,
        maxFileSize: 2_000_000_000, // 2GB
        tempDirectoryPath: "/tmp",
        enableVerboseLogging: false,
        autoCleanupTemp: true
    )
}
```

## Performance Monitoring

### Metrics Collection
```swift
struct ProcessingMetrics {
    let startTime: Date
    let endTime: Date
    let inputFileSize: Int64
    let audioDuration: TimeInterval
    let processingTime: TimeInterval
    let memoryUsage: Int64
    let transcriptionEngine: TranscriptionEngine
    let outputFormat: OutputFormat
    
    var processingSpeedRatio: Double {
        return audioDuration / processingTime
    }
    
    var throughputMBps: Double {
        return Double(inputFileSize) / (1024 * 1024) / processingTime
    }
}
```

## Testing APIs

### Test Utilities
```swift
class MockTranscriptionService: TranscriptionService {
    var shouldFailNative = false
    var shouldFailCloud = false
    var mockResult: TranscriptionResult?
    
    override func transcribe(
        audio: AudioData,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        if let mockResult = mockResult {
            return mockResult
        }
        
        return TranscriptionResult(
            text: "Mock transcription text",
            language: "en-US",
            confidence: 0.95,
            duration: 60.0,
            segments: [
                TranscriptionSegment(
                    text: "Mock transcription text",
                    startTime: 0.0,
                    endTime: 60.0,
                    confidence: 0.95,
                    speakerID: nil
                )
            ],
            engine: .native,
            processingTime: 1.0,
            audioFormat: AudioFormat(
                sampleRate: 44100,
                channels: 1,
                bitDepth: 16,
                codec: "pcm",
                duration: 60.0
            ),
            metadata: TranscriptionMetadata(
                voxVersion: "1.0.0",
                timestamp: Date(),
                systemInfo: SystemInfo()
            )
        )
    }
}
```

### Sample Test Data
```swift
extension AudioData {
    static func mockAudio() -> AudioData {
        // Generate mock audio data for testing
        let sampleRate = 44100
        let duration = 10.0
        let samples = Int(sampleRate * duration)
        
        var audioData = Data()
        for i in 0..<samples {
            let sample = sin(2.0 * Double.pi * 440.0 * Double(i) / Double(sampleRate))
            let intSample = Int16(sample * 32767)
            audioData.append(Data(bytes: &intSample, count: 2))
        }
        
        return AudioData(
            data: audioData,
            format: AudioFormat(
                sampleRate: sampleRate,
                channels: 1,
                bitDepth: 16,
                codec: "pcm",
                duration: duration
            )
        )
    }
}
```

## Extension Points

### Custom Output Formatters
```swift
protocol OutputFormatter {
    func format(result: TranscriptionResult, options: FormatOptions) -> String
}

// Example: Custom XML formatter
class XMLFormatter: OutputFormatter {
    func format(result: TranscriptionResult, options: FormatOptions) -> String {
        var xml = "<transcription>\n"
        xml += "  <metadata>\n"
        xml += "    <language>\(result.language)</language>\n"
        xml += "    <confidence>\(result.confidence)</confidence>\n"
        xml += "    <duration>\(result.duration)</duration>\n"
        xml += "  </metadata>\n"
        xml += "  <segments>\n"
        
        for segment in result.segments {
            xml += "    <segment>\n"
            xml += "      <text>\(segment.text)</text>\n"
            xml += "      <start>\(segment.startTime)</start>\n"
            xml += "      <end>\(segment.endTime)</end>\n"
            xml += "    </segment>\n"
        }
        
        xml += "  </segments>\n"
        xml += "</transcription>"
        
        return xml
    }
}
```

### Custom Cloud Providers
```swift
protocol CloudTranscriptionProvider {
    func transcribe(
        audio: AudioData,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult
}

// Example: Azure Speech Services
class AzureSpeechProvider: CloudTranscriptionProvider {
    func transcribe(
        audio: AudioData,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        // Implementation for Azure Speech Services
        // Similar to OpenAI/Rev.ai implementations
    }
}
```

## Security Considerations

### API Key Management
```swift
class SecureKeyManager {
    private let keychain = Keychain(service: "com.vox.cli")
    
    func storeAPIKey(_ key: String, for service: String) throws {
        try keychain.set(key, key: service)
    }
    
    func retrieveAPIKey(for service: String) -> String? {
        return try? keychain.getString(service)
    }
    
    func removeAPIKey(for service: String) throws {
        try keychain.remove(service)
    }
}
```

### Temporary File Security
```swift
class SecureFileManager {
    static func createSecureTemporaryFile(extension: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).\(extension)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        // Create with restricted permissions
        let created = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        )
        
        guard created else {
            throw VoxError.outputWriteFailed("Could not create temporary file")
        }
        
        return fileURL
    }
    
    static func secureDelete(at url: URL) {
        // Overwrite file with random data before deletion
        if let handle = try? FileHandle(forWritingTo: url) {
            let size = try? handle.seekToEnd()
            if let size = size {
                let randomData = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
                handle.seek(toFileOffset: 0)
                handle.write(randomData)
            }
            handle.closeFile()
        }
        
        try? FileManager.default.removeItem(at: url)
    }
}
```

---

*This API documentation provides a comprehensive overview of the Vox CLI internals. For specific implementation details, refer to the source code and unit tests.*