import Foundation

/// Configuration options for OutputWriter
struct OutputWriterOptions {
    let enableBackup: Bool
    let validateSpace: Bool
    let createDirectories: Bool
    let spaceMultiplier: Double
    let maxRetries: Int
    let retryDelay: TimeInterval
    
    public static let `default` = OutputWriterOptions(
        enableBackup: true,
        validateSpace: true,
        createDirectories: true,
        spaceMultiplier: 2.0,
        maxRetries: 3,
        retryDelay: 0.1
    )
}

/// Robust file writing system with comprehensive error handling and recovery
class OutputWriter {
    private let options: OutputWriterOptions
    private let fileManager: FileManager
    private let logger: Logger
    private let validator: OutputValidator
    
    init(options: OutputWriterOptions = .default) {
        self.options = options
        self.fileManager = FileManager.default
        self.logger = Logger.shared
        self.validator = OutputValidator()
    }
    
    /// Main interface for writing transcription results with full error recovery
    func writeTranscriptionResult(
        _ result: TranscriptionResult,
        to path: String,
        format: OutputFormat,
        textOptions: TextFormattingOptions? = nil,
        jsonOptions: JSONFormatter.JSONFormattingOptions? = nil
    ) throws -> SuccessConfirmation {
        let startTime = Date()
        logger.info("Writing transcription result to: \(path)", component: "OutputWriter")
        
        // Format the content
        let content = try formatContent(result, format: format, textOptions: textOptions, jsonOptions: jsonOptions)
        
        // Write with full error recovery
        try writeContentSafely(content, to: path)
        
        // Validate the written output
        let url = URL(fileURLWithPath: path)
        let validationReport = try validator.validateOutput(result, writtenTo: url, format: format)
        
        // Get file size for success confirmation
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        let processingTime = Date().timeIntervalSince(startTime)
        let successConfirmation = SuccessConfirmation(
            filePath: url,
            fileSize: fileSize,
            format: format,
            validationReport: validationReport,
            processingTime: processingTime
        )
        
        logger.info("Successfully wrote and validated transcription result (\(content.count) bytes)", component: "OutputWriter")
        
        return successConfirmation
    }
    
    /// Safely write content with comprehensive error handling and recovery
    func writeContentSafely(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        
        // Phase 1: Validation
        try validateOutputPath(url)
        try validateDiskSpace(content, path: url)
        try validatePermissions(url)
        
        // Phase 2: Atomic writing with backup
        try writeAtomically(content, to: url)
    }
    
    // MARK: - Validation Methods
    
    private func validateOutputPath(_ url: URL) throws {
        let path = url.path
        
        // Check if path is valid
        guard !path.isEmpty else {
            throw VoxError.invalidOutputPath("Empty path provided")
        }
        
        // Check for invalid characters (basic validation)
        let invalidChars = CharacterSet(charactersIn: "<>:\"|?*")
        if url.lastPathComponent.rangeOfCharacter(from: invalidChars) != nil {
            throw VoxError.invalidOutputPath("Path contains invalid characters: \(path)")
        }
        
        // Validate parent directory
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            if options.createDirectories {
                do {
                    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    logger.info("Created directory: \(parentDir.path)", component: "OutputWriter")
                } catch {
                    let errorMsg = "Cannot create directory \(parentDir.path): \(error.localizedDescription)"
                    throw VoxError.pathCreationFailed(errorMsg)
                }
            } else {
                throw VoxError.invalidOutputPath("Parent directory does not exist: \(parentDir.path)")
            }
        }
    }
    
    private func validateDiskSpace(_ content: String, path: URL) throws {
        guard options.validateSpace else { return }
        
        do {
            let data = content.data(using: .utf8) ?? Data()
            let requiredBytes = UInt64(Double(data.count) * options.spaceMultiplier)
            
            let parentDir = path.deletingLastPathComponent()
            let attributes = try fileManager.attributesOfFileSystem(forPath: parentDir.path)
            
            guard let freeSpace = attributes[.systemFreeSize] as? UInt64 else {
                logger.warn("Could not determine free disk space", component: "OutputWriter")
                return
            }
            
            if freeSpace < requiredBytes {
                throw VoxError.insufficientDiskSpace(required: requiredBytes, available: freeSpace)
            }
            
            let debugMsg = "Disk space check passed: \(freeSpace) bytes available, \(requiredBytes) required"
            logger.debug(debugMsg, component: "OutputWriter")
        } catch let error as VoxError {
            throw error
        } catch {
            let warnMsg = "Could not validate disk space: \(error.localizedDescription)"
            logger.warn(warnMsg, component: "OutputWriter")
            // Don't fail on space validation errors, just log them
        }
    }
    
    private func validatePermissions(_ url: URL) throws {
        let parentDir = url.deletingLastPathComponent()
        
        // Check write permissions on parent directory
        if !fileManager.isWritableFile(atPath: parentDir.path) {
            throw VoxError.permissionDenied("No write permission for directory: \(parentDir.path)")
        }
        
        // If file exists, check if it's writable
        if fileManager.fileExists(atPath: url.path) {
            if !fileManager.isWritableFile(atPath: url.path) {
                throw VoxError.permissionDenied("No write permission for file: \(url.path)")
            }
        }
    }
    
    // MARK: - Atomic Writing
    
    private func writeAtomically(_ content: String, to url: URL) throws {
        var backupURL: URL?
        var tempURL: URL?
        
        defer {
            // Cleanup: Remove temporary file if it exists
            if let temp = tempURL {
                try? fileManager.removeItem(at: temp)
            }
        }
        
        do {
            // Create backup if file exists
            if options.enableBackup && fileManager.fileExists(atPath: url.path) {
                backupURL = try createBackup(url)
            }
            
            // Write to temporary file
            tempURL = try writeToTemporaryFile(content, near: url)
            
            // Atomic move to final location
            guard let tempURL = tempURL else {
                throw VoxError.atomicWriteFailed("Temporary file URL is nil")
            }
            try performAtomicMove(from: tempURL, to: url)
            
            // Success: Remove backup if it exists
            if let backup = backupURL {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            // Failure: Restore from backup if available
            if let backup = backupURL {
                do {
                    try restoreFromBackup(backup, to: url)
                    logger.info("Restored from backup after write failure", component: "OutputWriter")
                } catch {
                    let errorMsg = "Failed to restore from backup: \(error.localizedDescription)"
                    logger.error(errorMsg, component: "OutputWriter")
                }
            }
            
            throw VoxError.atomicWriteFailed("Atomic write failed: \(error.localizedDescription)")
        }
    }
    
    private func writeToTemporaryFile(_ content: String, near url: URL) throws -> URL {
        let tempDir = url.deletingLastPathComponent()
        let tempName = ".\(url.lastPathComponent).tmp.\(UUID().uuidString)"
        let tempURL = tempDir.appendingPathComponent(tempName)
        
        do {
            try content.write(to: tempURL, atomically: false, encoding: .utf8)
            return tempURL
        } catch {
            throw VoxError.atomicWriteFailed("Failed to write temporary file: \(error.localizedDescription)")
        }
    }
    
    private func performAtomicMove(from tempURL: URL, to finalURL: URL) throws {
        // Remove existing file if it exists (backup was already created)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        
        // Atomic move
        try fileManager.moveItem(at: tempURL, to: finalURL)
    }
    
    // MARK: - Backup and Recovery
    
    private func createBackup(_ url: URL) throws -> URL {
        let backupURL = url.appendingPathExtension("backup.\(UUID().uuidString)")
        
        do {
            try fileManager.copyItem(at: url, to: backupURL)
            logger.debug("Created backup: \(backupURL.path)", component: "OutputWriter")
            return backupURL
        } catch {
            throw VoxError.backupFailed("Failed to create backup: \(error.localizedDescription)")
        }
    }
    
    private func restoreFromBackup(_ backupURL: URL, to finalURL: URL) throws {
        try fileManager.removeItem(at: finalURL)
        try fileManager.moveItem(at: backupURL, to: finalURL)
    }
    
    // MARK: - Content Formatting
    
    private func formatContent(
        _ result: TranscriptionResult,
        format: OutputFormat,
        textOptions: TextFormattingOptions?,
        jsonOptions: JSONFormatter.JSONFormattingOptions?
    ) throws -> String {
        let formatter = OutputFormatter()
        
        switch format {
        case .txt:
            if let textOptions = textOptions {
                return try formatter.format(result, as: format, options: textOptions)
            } else {
                return try formatter.format(result, as: format)
            }
        case .json:
            if let jsonOptions = jsonOptions {
                return try formatter.format(result, as: format, jsonOptions: jsonOptions)
            } else {
                return try formatter.format(result, as: format)
            }
        case .srt:
            return try formatter.format(result, as: format)
        }
    }
}
