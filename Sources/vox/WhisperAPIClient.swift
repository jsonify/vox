import Foundation

// MARK: - WhisperClientConfig

public struct WhisperClientConfig {
    let apiKey: String
    let endpoint: String?
    
    public init(apiKey: String, endpoint: String? = nil) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
}

/// OpenAI Whisper API client for cloud-based transcription fallback
public class WhisperAPIClient {
    // MARK: - Configuration

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    private let maxFileSize: Int64 = 25 * 1024 * 1024 // 25MB limit per OpenAI docs
    private let maxRetries = 3
    private let rateLimitDelay: TimeInterval = 1.0

    // MARK: - Rate Limiting

    private var lastRequestTime = Date.distantPast
    private let minRequestInterval: TimeInterval = 1.0 // Minimum 1 second between requests

    // MARK: - Initialization
public init(config: WhisperClientConfig) {
    self.apiKey = config.apiKey
    self.baseURL = config.endpoint ?? "https://api.openai.com/v1/audio/transcriptions"


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
    public func transcribe(
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
        body.append(createRequestParameters(language: language, includeTimestamps: includeTimestamps, boundary: boundary))
        body.append(try createAudioFileData(audioFile: audioFile, boundary: boundary))
        body.append(createBoundaryClosing(boundary: boundary))
        
        request.httpBody = body
        
        Logger.shared.debug("Created multipart request with \(body.count) bytes", component: "OpenAI")
        return request
    }
    
    private func createRequestParameters(
        language: String?,
        includeTimestamps: Bool,
        boundary: String
    ) -> Data {
        var parametersData = Data()
        
        // Add model parameter
        parametersData.append(createFormField(name: "model", value: "whisper-1", boundary: boundary))
        
        // Add language parameter if provided
        if let language = language {
            parametersData.append(createFormField(name: "language", value: language, boundary: boundary))
        }
        
        // Add response format
        let responseFormat = includeTimestamps ? "verbose_json" : "json"
        parametersData.append(createFormField(name: "response_format", value: responseFormat, boundary: boundary))
        
        // Add timestamp granularities if needed
        if includeTimestamps {
            parametersData.append(createFormField(name: "timestamp_granularities[]", value: "word", boundary: boundary))
        }
        
        return parametersData
    }
    
    private func createAudioFileData(audioFile: AudioFile, boundary: String) throws -> Data {
        let audioData = try Data(contentsOf: audioFile.url)
        return createFileField(
            name: "file",
            filename: audioFile.url.lastPathComponent,
            data: audioData,
            mimeType: getMimeType(for: audioFile.format.codec),
            boundary: boundary
        )
    }
    
    private func createBoundaryClosing(boundary: String) -> Data {
        guard let boundaryData = "--\(boundary)--\r\n".data(using: .utf8) else {
            return Data()
        }
        return boundaryData
    }

    private func createFormField(name: String, value: String, boundary: String) -> Data {
        var field = Data()
        if let boundaryData = "--\(boundary)\r\n".data(using: .utf8) {
            field.append(boundaryData)
        }
        if let contentData = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8) {
            field.append(contentData)
        }
        if let valueData = "\(value)\r\n".data(using: .utf8) {
            field.append(valueData)
        }
        return field
    }

    private func createFileField(name: String, filename: String, data: Data, mimeType: String, boundary: String) -> Data {
        var field = Data()
        if let boundaryData = "--\(boundary)\r\n".data(using: .utf8) {
            field.append(boundaryData)
        }
        if let contentDispositionData = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8) {
            field.append(contentDispositionData)
        }
        if let contentTypeData = "Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8) {
            field.append(contentTypeData)
        }
        field.append(data)
        if let endData = "\r\n".data(using: .utf8) {
            field.append(endData)
        }
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
                return try await performSingleRequest(
                    request: request,
                    attempt: attempt,
                    progressCallback: progressCallback
                )
            } catch {
                if let voxError = error as? VoxError, case .apiKeyMissing = voxError {
                    throw error
                }
                
                lastError = error
                Logger.shared.warn("OpenAI API request failed (attempt \(attempt)): \(error.localizedDescription)",
                                 component: "OpenAI")
                
                if attempt < maxRetries {
                    try await handleRetryDelay(attempt: attempt)
                }
            }
        }
        
        throw lastError ?? VoxError.transcriptionFailed("OpenAI API request failed after \(maxRetries) attempts")
    }
    
    private func performSingleRequest(
        request: URLRequest,
        attempt: Int,
        progressCallback: ProgressCallback?
    ) async throws -> (Data, URLResponse) {
        Logger.shared.debug("OpenAI API request attempt \(attempt)/\(maxRetries)", component: "OpenAI")
        
        updateProgress(attempt: attempt, progressCallback: progressCallback)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return (data, response)
        }
        
        Logger.shared.debug("OpenAI API response status: \(httpResponse.statusCode)", component: "OpenAI")
        
        try await handleHTTPResponse(httpResponse, data: data)
        return (data, response)
    }
    
    private func handleHTTPResponse(_ response: HTTPURLResponse, data: Data) async throws {
        switch response.statusCode {
        case 200...299:
            return
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? rateLimitDelay
            Logger.shared.warn("Rate limited by OpenAI API, waiting \(retryAfter)s", component: "OpenAI")
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            throw VoxError.rateLimitError(retryAfter)
        case 401:
            throw VoxError.apiKeyMissing("Invalid OpenAI API key")
        case 413:
            throw VoxError.processingFailed("File too large for OpenAI API")
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VoxError.transcriptionFailed("OpenAI API error (\(response.statusCode)): \(errorMessage)")
        }
    }
    
    private func handleRetryDelay(attempt: Int) async throws {
        let delay = Double(attempt) * rateLimitDelay
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    
    private func updateProgress(attempt: Int, progressCallback: ProgressCallback?) {
        progressCallback?(TranscriptionProgress(
            progress: 0.2 + (0.1 * Double(attempt - 1)),
            status: "Uploading to OpenAI (attempt \(attempt))...",
            phase: .extracting,
            startTime: Date()
        ))
    }

    private func parseResponse(_ response: (Data, URLResponse), audioFile: AudioFile, startTime: Date) throws -> TranscriptionResult {
        let (data, _) = response
        Logger.shared.debug("Parsing OpenAI response (\(data.count) bytes)", component: "OpenAI")
        
        let (text, json) = try parseJSONResponse(data)
        let segments = try createTranscriptionSegments(json: json, text: text, audioFile: audioFile)
        let processingTime = Date().timeIntervalSince(startTime)
        let detectedLanguage = json["language"] as? String ?? "unknown"
        
        return createTranscriptionResult(
            text: text,
            language: detectedLanguage,
            segments: segments,
            audioFile: audioFile,
            processingTime: processingTime
        )
    }
    
    private func parseJSONResponse(_ data: Data) throws -> (String, [String: Any]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VoxError.transcriptionFailed("Invalid JSON response from OpenAI API")
        }
        
        guard let text = json["text"] as? String else {
            throw VoxError.transcriptionFailed("Missing text field in OpenAI response")
        }
        
        return (text, json)
    }
    
    private func createTranscriptionSegments(
        json: [String: Any],
        text: String,
        audioFile: AudioFile
    ) throws -> [TranscriptionSegment] {
        if let wordsArray = json["words"] as? [[String: Any]] {
            return parseWordSegments(wordsArray)
        }
        
        // Create a single segment for the entire text
        return [
            TranscriptionSegment(
                text: text,
                startTime: 0,
                endTime: audioFile.format.duration,
                confidence: 1.0,
                speakerID: nil,
                words: nil,
                segmentType: .speech,
                pauseDuration: nil
            )
        ]
    }
    
    private func createTranscriptionResult(
        text: String,
        language: String,
        segments: [TranscriptionSegment],
        audioFile: AudioFile,
        processingTime: TimeInterval
    ) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            language: language,
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
    public static func create(with config: WhisperClientConfig?) throws -> WhisperAPIClient {
        let apiKey = config?.apiKey
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
        
        return WhisperAPIClient(config: WhisperClientConfig(apiKey: apiKey))
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
