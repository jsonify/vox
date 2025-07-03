import Foundation

/// OpenAI Whisper API client for cloud-based transcription fallback
class WhisperAPIClient {
    
    // MARK: - Configuration
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let session: URLSession
    private let maxFileSize: Int64 = 25 * 1024 * 1024 // 25MB limit per OpenAI docs
    private let maxRetries = 3
    private let rateLimitDelay: TimeInterval = 1.0
    
    // MARK: - Rate Limiting
    
    private var lastRequestTime: Date = Date.distantPast
    private let minRequestInterval: TimeInterval = 1.0 // Minimum 1 second between requests
    
    // MARK: - Initialization
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120.0 // 2 minutes for file upload
        config.timeoutIntervalForResource = 300.0 // 5 minutes total
        config.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: config)
        
        Logger.shared.debug("WhisperAPIClient initialized", component: "OpenAI")
    }
    
    // MARK: - Public API
    
    /// Transcribe audio file using OpenAI Whisper API
    /// - Parameters:
    ///   - audioFile: The audio file to transcribe
    ///   - language: Optional language code (e.g., "en", "es")
    ///   - includeTimestamps: Whether to include word-level timestamps
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: TranscriptionResult containing the transcribed text and metadata
    func transcribe(
        audioFile: AudioFile,
        language: String? = nil,
        includeTimestamps: Bool = false,
        progressCallback: ProgressCallback? = nil
    ) async throws -> TranscriptionResult {
        
        Logger.shared.info("Starting OpenAI Whisper transcription for file: \(audioFile.path)", component: "OpenAI")
        
        // Validate file size
        try validateFileSize(audioFile)
        
        // Rate limiting
        await enforceRateLimit()
        
        // Prepare request
        let request = try createMultipartRequest(
            audioFile: audioFile,
            language: language,
            includeTimestamps: includeTimestamps
        )
        
        // Report initial progress
        let startTime = Date()
        progressCallback?(TranscriptionProgress(
            progress: 0.1,
            status: "Uploading to OpenAI Whisper API...",
            phase: .extracting,
            startTime: startTime
        ))
        
        // Perform request with retry logic
        let response = try await performRequestWithRetry(request: request, progressCallback: progressCallback)
        
        // Parse response
        let result = try parseResponse(response, audioFile: audioFile, startTime: startTime)
        
        Logger.shared.info("OpenAI Whisper transcription completed successfully", component: "OpenAI")
        Logger.shared.debug("Result: \(result.text.prefix(100))...", component: "OpenAI")
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func validateFileSize(_ audioFile: AudioFile) throws {
        guard let fileSize = audioFile.format.fileSize else {
            throw VoxError.audioFormatValidationFailed("Unable to determine file size")
        }
        
        if Int64(fileSize) > maxFileSize {
            let sizeMB = Double(fileSize) / (1024 * 1024)
            let maxSizeMB = Double(maxFileSize) / (1024 * 1024)
            throw VoxError.processingFailed("File size \(String(format: "%.1f", sizeMB))MB exceeds OpenAI limit of \(String(format: "%.0f", maxSizeMB))MB")
        }
        
        Logger.shared.debug("File size validation passed: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))", component: "OpenAI")
    }
    
    private func enforceRateLimit() async {
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minRequestInterval {
            let delay = minRequestInterval - timeSinceLastRequest
            Logger.shared.debug("Rate limiting: waiting \(String(format: "%.1f", delay))s", component: "OpenAI")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
    
    private func createMultipartRequest(
        audioFile: AudioFile,
        language: String?,
        includeTimestamps: Bool
    ) throws -> URLRequest {
        
        guard let url = URL(string: baseURL) else {
            throw VoxError.processingFailed("Invalid OpenAI API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append(createFormField(name: "model", value: "whisper-1", boundary: boundary))
        
        // Add language parameter if provided
        if let language = language {
            body.append(createFormField(name: "language", value: language, boundary: boundary))
        }
        
        // Add response format
        let responseFormat = includeTimestamps ? "verbose_json" : "json"
        body.append(createFormField(name: "response_format", value: responseFormat, boundary: boundary))
        
        // Add timestamp granularities if needed
        if includeTimestamps {
            body.append(createFormField(name: "timestamp_granularities[]", value: "word", boundary: boundary))
        }
        
        // Add audio file
        let audioData = try Data(contentsOf: audioFile.url)
        body.append(createFileField(
            name: "file",
            filename: audioFile.url.lastPathComponent,
            data: audioData,
            mimeType: getMimeType(for: audioFile.format.codec),
            boundary: boundary
        ))
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        Logger.shared.debug("Created multipart request with \(body.count) bytes", component: "OpenAI")
        
        return request
    }
    
    private func createFormField(name: String, value: String, boundary: String) -> Data {
        var field = Data()
        field.append("--\(boundary)\r\n".data(using: .utf8)!)
        field.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        field.append("\(value)\r\n".data(using: .utf8)!)
        return field
    }
    
    private func createFileField(name: String, filename: String, data: Data, mimeType: String, boundary: String) -> Data {
        var field = Data()
        field.append("--\(boundary)\r\n".data(using: .utf8)!)
        field.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        field.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        field.append(data)
        field.append("\r\n".data(using: .utf8)!)
        return field
    }
    
    private func getMimeType(for codec: String) -> String {
        switch codec.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a", "aac":
            return "audio/mp4"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        default:
            return "audio/mpeg" // Default fallback
        }
    }
    
    private func performRequestWithRetry(
        request: URLRequest,
        progressCallback: ProgressCallback?
    ) async throws -> (Data, URLResponse) {
        
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                Logger.shared.debug("OpenAI API request attempt \(attempt)/\(maxRetries)", component: "OpenAI")
                
                // Update progress for upload
                progressCallback?(TranscriptionProgress(
                    progress: 0.2 + (0.1 * Double(attempt - 1)),
                    status: "Uploading to OpenAI (attempt \(attempt))...",
                    phase: .extracting,
                    startTime: Date()
                ))
                
                let (data, response) = try await session.data(for: request)
                
                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse {
                    Logger.shared.debug("OpenAI API response status: \(httpResponse.statusCode)", component: "OpenAI")
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        return (data, response)
                    case 429: // Rate limit
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? rateLimitDelay
                        Logger.shared.warn("Rate limited by OpenAI API, waiting \(retryAfter)s", component: "OpenAI")
                        try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                        continue
                    case 401:
                        throw VoxError.apiKeyMissing("Invalid OpenAI API key")
                    case 413:
                        throw VoxError.processingFailed("File too large for OpenAI API")
                    default:
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw VoxError.transcriptionFailed("OpenAI API error (\(httpResponse.statusCode)): \(errorMessage)")
                    }
                }
                
                return (data, response)
                
            } catch {
                lastError = error
                Logger.shared.warn("OpenAI API request failed (attempt \(attempt)): \(error.localizedDescription)", component: "OpenAI")
                
                // Don't retry on certain errors
                if case VoxError.apiKeyMissing = error {
                    throw error
                }
                
                // Wait before retry
                if attempt < maxRetries {
                    let delay = Double(attempt) * rateLimitDelay
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? VoxError.transcriptionFailed("OpenAI API request failed after \(maxRetries) attempts")
    }
    
    private func parseResponse(_ response: (Data, URLResponse), audioFile: AudioFile, startTime: Date) throws -> TranscriptionResult {
        let (data, _) = response
        
        Logger.shared.debug("Parsing OpenAI response (\(data.count) bytes)", component: "OpenAI")
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VoxError.transcriptionFailed("Invalid JSON response from OpenAI API")
        }
        
        guard let text = json["text"] as? String else {
            throw VoxError.transcriptionFailed("Missing text field in OpenAI response")
        }
        
        // Parse segments if available (verbose format)
        var segments: [TranscriptionSegment] = []
        if let wordsArray = json["words"] as? [[String: Any]] {
            segments = parseWordSegments(wordsArray)
        } else {
            // Create a single segment for the entire text
            segments = [TranscriptionSegment(
                text: text,
                startTime: 0,
                endTime: audioFile.format.duration,
                confidence: 1.0,
                speakerID: nil,
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )]
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Determine language from response or fallback
        let detectedLanguage = json["language"] as? String ?? "unknown"
        
        return TranscriptionResult(
            text: text,
            language: detectedLanguage,
            confidence: calculateOverallConfidence(segments),
            duration: audioFile.format.duration,
            segments: segments,
            engine: .openaiWhisper,
            processingTime: processingTime,
            audioFormat: audioFile.format
        )
    }
    
    private func parseWordSegments(_ wordsArray: [[String: Any]]) -> [TranscriptionSegment] {
        return wordsArray.compactMap { wordData in
            guard let word = wordData["word"] as? String,
                  let start = wordData["start"] as? Double,
                  let end = wordData["end"] as? Double else {
                return nil
            }
            
            let confidence = wordData["confidence"] as? Double ?? 1.0
            
            let wordTiming = WordTiming(
                word: word,
                startTime: start,
                endTime: end,
                confidence: confidence
            )
            
            return TranscriptionSegment(
                text: word,
                startTime: start,
                endTime: end,
                confidence: confidence,
                speakerID: nil,
                words: wordTiming,
                segmentType: .speech,
                pauseDuration: nil
            )
        }
    }
    
    private func calculateOverallConfidence(_ segments: [TranscriptionSegment]) -> Double {
        guard !segments.isEmpty else { return 0.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Double(segments.count)
    }
}

// MARK: - API Key Management

extension WhisperAPIClient {
    
    /// Create WhisperAPIClient with API key from various sources
    /// - Parameter providedKey: API key provided via command line
    /// - Returns: Configured WhisperAPIClient instance
    /// - Throws: VoxError if no API key is found
    static func create(with providedKey: String?) throws -> WhisperAPIClient {
        let apiKey = providedKey 
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["VOX_OPENAI_API_KEY"]
        
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw VoxError.apiKeyMissing("OpenAI API key not found. Set OPENAI_API_KEY environment variable or use --api-key")
        }
        
        // Validate API key format (should start with sk-)
        guard apiKey.hasPrefix("sk-") else {
            throw VoxError.apiKeyMissing("Invalid OpenAI API key format")
        }
        
        Logger.shared.debug("OpenAI API key configured", component: "OpenAI")
        
        return WhisperAPIClient(apiKey: apiKey)
    }
}

// MARK: - Error Extensions

extension VoxError {
    static func openAIError(_ message: String) -> VoxError {
        return .transcriptionFailed("OpenAI Whisper: \(message)")
    }
    
    static func networkError(_ message: String) -> VoxError {
        return .transcriptionFailed("Network error: \(message)")
    }
    
    static func rateLimitError(_ retryAfter: TimeInterval) -> VoxError {
        return .transcriptionFailed("Rate limited. Retry after \(retryAfter) seconds")
    }
}