import Foundation

// MARK: - Error Models

public enum VoxError: Error, LocalizedError {
    case invalidInputFile(String)
    case audioExtractionFailed(String)
    case transcriptionFailed(String)
    case outputWriteFailed(String)
    case apiKeyMissing(String)
    case unsupportedFormat(String)
    case audioFormatValidationFailed(String)
    case incompatibleAudioProperties(String)
    case transcriptionInProgress
    case speechRecognitionUnavailable
    case invalidAudioFile
    case temporaryFileCreationFailed(String)
    case temporaryFileCleanupFailed(String)
    case processingFailed(String)
    case insufficientDiskSpace(required: UInt64, available: UInt64)
    case invalidOutputPath(String)
    case permissionDenied(String)
    case backupFailed(String)
    case atomicWriteFailed(String)
    case pathCreationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidInputFile(let path):
            return "Invalid input file: \(path)"
        case .audioExtractionFailed(let reason):
            return "Audio extraction failed: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .outputWriteFailed(let reason):
            return "Failed to write output: \(reason)"
        case .apiKeyMissing(let service):
            return "API key missing for \(service)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .audioFormatValidationFailed(let details):
            return "Audio format validation failed: \(details)"
        case .incompatibleAudioProperties(let details):
            return "Incompatible audio properties: \(details)"
        case .temporaryFileCreationFailed(let reason):
            return "Failed to create temporary file: \(reason)"
        case .temporaryFileCleanupFailed(let reason):
            return "Failed to cleanup temporary file: \(reason)"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .transcriptionInProgress:
            return "A transcription is already in progress"
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available"
        case .invalidAudioFile:
            return "Invalid audio file"
        case let .insufficientDiskSpace(required, available):
            let requiredMB = Double(required) / (1024 * 1024)
            let availableMB = Double(available) / (1024 * 1024)
            let reqStr = String(format: "%.2f", requiredMB)
            let availStr = String(format: "%.2f", availableMB)
            return "Insufficient disk space. Required: \(reqStr) MB, Available: \(availStr) MB"
        case .invalidOutputPath(let path):
            return "Invalid output path: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .backupFailed(let reason):
            return "Backup failed: \(reason)"
        case .atomicWriteFailed(let reason):
            return "Atomic write failed: \(reason)"
        case .pathCreationFailed(let reason):
            return "Path creation failed: \(reason)"
        }
    }
    
    func log() {
        Logger.shared.error(self.localizedDescription, component: componentName)
    }
    
    private var componentName: String {
        switch self {
        case .invalidInputFile, .unsupportedFormat:
            return "FileProcessor"
        case .audioExtractionFailed, .audioFormatValidationFailed, .incompatibleAudioProperties:
            return "AudioProcessor"
        case .transcriptionFailed:
            return "Transcription"
        case .outputWriteFailed:
            return "OutputWriter"
        case .apiKeyMissing:
            return "API"
        case .temporaryFileCreationFailed, .temporaryFileCleanupFailed:
            return "TempFileManager"
        case .processingFailed:
            return "Processor"
        case .transcriptionInProgress, .speechRecognitionUnavailable, .invalidAudioFile:
            return "Transcription"
        case .insufficientDiskSpace, .invalidOutputPath, .permissionDenied, .backupFailed, 
             .atomicWriteFailed, .pathCreationFailed:
            return "OutputWriter"
        }
    }
}
