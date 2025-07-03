import Foundation

class TempFileManager {
    
    static let shared = TempFileManager()
    
    private let logger = Logger.shared
    private let fileManager = FileManager.default
    private var managedFiles: Set<String> = []
    private let queue = DispatchQueue(label: "com.vox.tempfilemanager", attributes: .concurrent)
    
    private init() {
        // TEMP FIX: Disable cleanup handlers during static initialization
        // TODO: Implement lazy cleanup handler setup on first use
        // setupCleanupOnExit()
    }
    
    deinit {
        cleanupAllFiles()
    }
    
    // MARK: - Public Interface
    
    func createTemporaryAudioFile(extension fileExtension: String = "m4a") -> URL? {
        return queue.sync {
            return createSecureTemporaryFile(extension: fileExtension, prefix: "vox_audio_")
        }
    }
    
    func createTemporaryFile(extension fileExtension: String, prefix: String = "vox_") -> URL? {
        return queue.sync {
            return createSecureTemporaryFile(extension: fileExtension, prefix: prefix)
        }
    }
    
    func registerTemporaryFile(at url: URL) {
        queue.async(flags: .barrier) {
            self.managedFiles.insert(url.path)
            self.logger.debug("Registered temporary file: \(url.path)", component: "TempFileManager")
        }
    }
    
    func cleanupFile(at url: URL) -> Bool {
        return queue.sync(flags: .barrier) {
            return performCleanup(for: url.path)
        }
    }
    
    func cleanupFiles(at urls: [URL]) -> [URL] {
        return queue.sync(flags: .barrier) {
            var failedCleanups: [URL] = []
            
            for url in urls {
                if !performCleanup(for: url.path) {
                    failedCleanups.append(url)
                }
            }
            
            return failedCleanups
        }
    }
    
    func cleanupAllFiles() {
        queue.sync(flags: .barrier) {
            let filesToCleanup = Array(managedFiles)
            var failedCount = 0
            
            for filePath in filesToCleanup {
                if !performCleanup(for: filePath) {
                    failedCount += 1
                }
            }
            
            if failedCount > 0 {
                logger.warn("Failed to cleanup \(failedCount) temporary files", component: "TempFileManager")
            } else if !filesToCleanup.isEmpty {
                logger.info("Successfully cleaned up \(filesToCleanup.count) temporary files", component: "TempFileManager")
            }
        }
    }
    
    var managedFileCount: Int {
        return queue.sync {
            return managedFiles.count
        }
    }
    
    // MARK: - Private Implementation
    
    private func createSecureTemporaryFile(extension fileExtension: String, prefix: String) -> URL? {
        let tempDir = fileManager.temporaryDirectory
        let uniqueFileName = "\(prefix)\(UUID().uuidString).\(fileExtension)"
        let tempURL = tempDir.appendingPathComponent(uniqueFileName)
        
        // Set secure permissions immediately after creation concept
        do {
            // Create empty file first
            fileManager.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
            
            // Set secure permissions (owner read/write only)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
            
            // Register the file for cleanup tracking
            managedFiles.insert(tempURL.path)
            
            logger.debug("Created secure temporary file: \(tempURL.path)", component: "TempFileManager")
            return tempURL
            
        } catch {
            logger.error("Failed to create secure temporary file: \(error.localizedDescription)", component: "TempFileManager")
            // Attempt cleanup if file was partially created
            try? fileManager.removeItem(at: tempURL)
            return nil
        }
    }
    
    private func performCleanup(for filePath: String) -> Bool {
        guard managedFiles.contains(filePath) else {
            logger.debug("File not managed by TempFileManager: \(filePath)", component: "TempFileManager")
            return true // Consider unmanaged files as "successfully cleaned"
        }
        
        guard fileManager.fileExists(atPath: filePath) else {
            // File doesn't exist, remove from tracking
            managedFiles.remove(filePath)
            logger.debug("File already removed: \(filePath)", component: "TempFileManager")
            return true
        }
        
        do {
            try fileManager.removeItem(atPath: filePath)
            managedFiles.remove(filePath)
            logger.debug("Successfully cleaned up temporary file: \(filePath)", component: "TempFileManager")
            return true
        } catch {
            logger.error("Failed to cleanup temporary file \(filePath): \(error.localizedDescription)", component: "TempFileManager")
            
            // Attempt to zero out the file content as a security measure if deletion fails
            attemptSecureWipe(at: filePath)
            return false
        }
    }
    
    private func attemptSecureWipe(at filePath: String) {
        do {
            let fileURL = URL(fileURLWithPath: filePath)
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            
            if let fileSize = attributes[.size] as? UInt64, fileSize > 0 {
                // Overwrite with zeros
                let zeroData = Data(count: Int(fileSize))
                try zeroData.write(to: fileURL)
                logger.warn("Secure wiped temporary file that could not be deleted: \(filePath)", component: "TempFileManager")
            }
        } catch {
            logger.error("Failed to secure wipe temporary file: \(error.localizedDescription)", component: "TempFileManager")
        }
    }
    
    private func setupCleanupOnExit() {
        // Register cleanup handlers for various termination scenarios
        
        // Normal app termination
        atexit {
            TempFileManager.shared.cleanupAllFiles()
        }
        
        // Signal handlers for abnormal termination
        signal(SIGINT) { _ in
            TempFileManager.shared.cleanupAllFiles()
            exit(SIGINT)
        }
        
        signal(SIGTERM) { _ in
            TempFileManager.shared.cleanupAllFiles()
            exit(SIGTERM)
        }
        
        // Process interrupt
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler {
            TempFileManager.shared.cleanupAllFiles()
            exit(SIGINT)
        }
        source.resume()
        
        logger.debug("Setup cleanup handlers for process termination", component: "TempFileManager")
    }
}

// MARK: - Extensions for Convenience

extension TempFileManager {
    
    func withTemporaryFile<T>(extension fileExtension: String = "m4a", 
                             prefix: String = "vox_",
                             operation: (URL) throws -> T) rethrows -> T? {
        guard let tempURL = createTemporaryFile(extension: fileExtension, prefix: prefix) else {
            return nil
        }
        
        defer {
            _ = cleanupFile(at: tempURL)
        }
        
        return try operation(tempURL)
    }
    
    func withTemporaryAudioFile<T>(operation: (URL) throws -> T) rethrows -> T? {
        return try withTemporaryFile(extension: "m4a", prefix: "vox_audio_", operation: operation)
    }
}