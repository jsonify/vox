import Foundation

/// Protocol for networking layer to enable testing with simulated responses
public protocol APIClient {
    func transcribe(
        audioFile: AudioFile,
        language: String?,
        includeTimestamps: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> TranscriptionResult
}

// Default implementation for WhisperAPIClient
extension WhisperAPIClient: APIClient {}
