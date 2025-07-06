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
            return "❌ Invalid input file: \(path)\n   💡 Please check that the file exists and is a valid MP4 video file."
        case .audioExtractionFailed(let reason):
            return "❌ Audio extraction failed: \(reason)\n   💡 Try: 1) Check if file is corrupted, " +
                   "2) Ensure enough disk space, 3) Verify file permissions."
        case .transcriptionFailed(let reason):
            return "❌ Transcription failed: \(reason)\n   💡 Try: 1) Use --force-cloud for cloud transcription, " +
                   "2) Specify --language for better accuracy, 3) Check your internet connection."
        case .outputWriteFailed(let reason):
            return "❌ Failed to write output: \(reason)\n   💡 Check: 1) Output directory exists, " +
                   "2) You have write permissions, 3) Enough disk space available."
        case .apiKeyMissing(let service):
            return "❌ API key missing for \(service)\n   💡 Set your API key: 1) Use --api-key flag, " +
                   "2) Set \(service.uppercased())_API_KEY environment variable, 3) Or use native transcription without --force-cloud."
        case .unsupportedFormat(let format):
            return "❌ Unsupported format: \(format)\n   💡 Supported formats: MP4 video files with common codecs (H.264, H.265, etc.)"
        case .audioFormatValidationFailed(let details):
            return "❌ Audio format validation failed: \(details)\n   💡 The video file may be corrupted or use an unsupported audio codec."
        case .incompatibleAudioProperties(let details):
            return "❌ Incompatible audio properties: \(details)\n   💡 Try converting your video to a standard format with compatible audio codec."
        case .temporaryFileCreationFailed(let reason):
            return "❌ Failed to create temporary file: \(reason)\n   💡 Check: 1) Disk space in /tmp, " +
                   "2) System permissions, 3) Restart if the issue persists."
        case .temporaryFileCleanupFailed(let reason):
            return "⚠️  Failed to cleanup temporary file: \(reason)\n   💡 You may need to manually clean up temporary files in /tmp."
        case .processingFailed(let reason):
            return "❌ Processing failed: \(reason)\n   💡 Try: 1) Run with --verbose for details, " +
                   "2) Check file integrity, 3) Ensure sufficient system resources."
        case .transcriptionInProgress:
            return "❌ A transcription is already in progress\n   💡 Wait for the current transcription to complete or restart the application."
        case .speechRecognitionUnavailable:
            return "❌ Speech recognition is not available\n   💡 Try: 1) Use --force-cloud for cloud transcription, " +
                   "2) Check macOS Speech Recognition settings, 3) Ensure macOS 12.0+ is installed."
        case .invalidAudioFile:
            return "❌ Invalid audio file\n   💡 The extracted audio is corrupted or empty. Try a different input video file."
        case let .insufficientDiskSpace(required, available):
            let requiredMB = Double(required) / (1024 * 1024)
            let availableMB = Double(available) / (1024 * 1024)
            let reqStr = String(format: "%.2f", requiredMB)
            let availStr = String(format: "%.2f", availableMB)
            return "❌ Insufficient disk space. Required: \(reqStr) MB, Available: \(availStr) MB\n   💡 Free up disk space or use a different output location."
        case .invalidOutputPath(let path):
            return "❌ Invalid output path: \(path)\n   💡 Check: 1) Directory exists, " +
                   "2) Path is writable, 3) Use absolute or relative paths correctly."
        case .permissionDenied(let path):
            return "❌ Permission denied: \(path)\n   💡 Fix: 1) Check file/directory permissions, " +
                   "2) Use 'sudo' if needed, 3) Ensure you own the target directory."
        case .backupFailed(let reason):
            return "❌ Backup failed: \(reason)\n   💡 The original file couldn't be backed up. Check disk space and permissions."
        case .atomicWriteFailed(let reason):
            return "❌ Atomic write failed: \(reason)\n   💡 File writing was interrupted. Check disk space and try again."
        case .pathCreationFailed(let reason):
            return "❌ Path creation failed: \(reason)\n   💡 Unable to create output directory. Check permissions and path validity."
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
