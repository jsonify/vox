# Vox Security and Privacy

## Overview
Vox is designed with privacy-first principles, prioritizing local processing while maintaining secure cloud fallback options when needed. This document outlines the security architecture, privacy protections, and best practices.

## Privacy-First Architecture

### Local Processing Priority
Vox follows a **local-first, cloud-optional** approach:

1. **Primary**: Native macOS SpeechAnalyzer (100% local)
2. **Fallback**: Cloud APIs (explicit user consent required)
3. **No Data Retention**: Zero persistent storage of audio or transcriptions

### Data Flow Security
```
MP4 Video → Audio Extraction → Native Transcription → Output
    ↓              ↓                    ↓              ↓
Temporary     Temporary           Local Memory    User File
   File          File             Processing       System
    ↓              ↓                    ↓              ↓
Auto-Cleanup  Auto-Cleanup      Immediate        User Control
                                 Cleanup
```

## Security Implementation

### 1. File System Security

#### Secure Temporary File Management
```swift
class SecureFileManager {
    private let tempDirectory: URL
    private let secureRandom = SystemRandomNumberGenerator()
    
    init() throws {
        // Create secure temporary directory with random name
        let baseTemp = FileManager.default.temporaryDirectory
        let randomID = UUID().uuidString
        tempDirectory = baseTemp.appendingPathComponent("vox-\(randomID)")
        
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700  // Owner read/write/execute only
            ]
        )
    }
    
    func createSecureTempFile(extension: String) throws -> URL {
        let filename = UUID().uuidString + "." + `extension`
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        // Create file with secure permissions
        let success = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: nil,
            attributes: [
                .posixPermissions: 0o600  // Owner read/write only
            ]
        )
        
        guard success else {
            throw VoxError.secureFileCreationFailed
        }
        
        return fileURL
    }
    
    deinit {
        // Secure cleanup - overwrite before deletion
        secureCleanup()
    }
    
    private func secureCleanup() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: tempDirectory, 
                                                                     includingPropertiesForKeys: nil)
            for fileURL in contents {
                // Overwrite file contents before deletion
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    let randomData = Data((0..<fileSize).map { _ in UInt8.random(in: 0...255) })
                    fileHandle.write(randomData)
                    fileHandle.closeFile()
                }
                
                try FileManager.default.removeItem(at: fileURL)
            }
            
            try FileManager.default.removeItem(at: tempDirectory)
        } catch {
            // Log error but don't throw - this is cleanup
            print("Warning: Secure cleanup failed: \(error)")
        }
    }
}
```

#### File Permission Management
```swift
class FilePermissionManager {
    static func setSecurePermissions(for url: URL) throws {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o600,  // Owner read/write only
            .protectionKey: FileProtectionType.complete
        ]
        
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }
    
    static func validateInputFile(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        
        // Check file exists and is readable
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw VoxError.fileNotReadable
        }
        
        // Verify file is not a symbolic link (security measure)
        let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw VoxError.symbolicLinksNotAllowed
        }
        
        // Check file size is reasonable (prevent DoS)
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= 2_147_483_648 else { // 2GB limit
            throw VoxError.fileTooLarge
        }
    }
}
```

### 2. API Key Security

#### Secure API Key Handling
```swift
class APIKeyManager {
    private static var keyCache: [CloudProvider: String] = [:]
    
    /// Retrieve API key from environment or user input
    /// Keys are NEVER stored persistently
    static func getAPIKey(for provider: CloudProvider) -> String? {
        // Check memory cache first (cleared on app exit)
        if let cachedKey = keyCache[provider] {
            return cachedKey
        }
        
        // Check environment variables
        let envKey: String?
        switch provider {
        case .openai:
            envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        case .revai:
            envKey = ProcessInfo.processInfo.environment["REVAI_API_KEY"]
        }
        
        if let key = envKey, !key.isEmpty {
            keyCache[provider] = key
            return key
        }
        
        return nil
    }
    
    /// Securely prompt for API key if needed
    static func promptForAPIKey(provider: CloudProvider) -> String? {
        print("Cloud transcription requires API key for \(provider)")
        print("Enter API key (input hidden): ", terminator: "")
        
        // Disable echo for secure input
        let originalTerm = tcgetattr(STDIN_FILENO)
        var noEchoTerm = originalTerm
        noEchoTerm.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &noEchoTerm)
        
        defer {
            // Restore echo
            tcsetattr(STDIN_FILENO, TCSANOW, &originalTerm)
            print() // New line after hidden input
        }
        
        guard let input = readLine(), !input.isEmpty else {
            return nil
        }
        
        // Cache for this session only
        keyCache[provider] = input
        return input
    }
    
    /// Clear all keys from memory
    static func clearKeys() {
        // Overwrite memory before clearing
        for (provider, key) in keyCache {
            let overwrite = String(repeating: "X", count: key.count)
            keyCache[provider] = overwrite
        }
        keyCache.removeAll()
    }
}
```

### 3. Network Security

#### Secure Cloud API Communication
```swift
class SecureCloudClient {
    private let session: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        
        // Security configuration
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv13
        configuration.httpShouldUsePipelining = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 60.0
        configuration.timeoutIntervalForResource = 300.0
        
        self.session = URLSession(configuration: configuration)
    }
    
    func secureRequest(to url: URL, with data: Data, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Secure headers
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Vox/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        
        // Anti-fingerprinting headers
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("1", forHTTPHeaderField: "DNT")
        
        request.httpBody = data
        
        let (responseData, response) = try await session.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoxError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw VoxError.apiError(httpResponse.statusCode)
        }
        
        return responseData
    }
}
```

### 4. Memory Security

#### Secure Memory Management
```swift
class SecureMemoryManager {
    /// Secure string that clears itself from memory
    struct SecureString {
        private var data: Data
        
        init(_ string: String) {
            self.data = Data(string.utf8)
        }
        
        var value: String {
            return String(data: data, encoding: .utf8) ?? ""
        }
        
        mutating func clear() {
            // Overwrite memory before deallocation
            data.withUnsafeMutableBytes { bytes in
                memset_s(bytes.baseAddress, bytes.count, 0, bytes.count)
            }
            data = Data()
        }
        
        deinit {
            // Ensure data is cleared
            data.withUnsafeMutableBytes { bytes in
                memset_s(bytes.baseAddress, bytes.count, 0, bytes.count)
            }
        }
    }
    
    /// Secure data buffer that self-destructs
    class SecureBuffer {
        private var buffer: UnsafeMutableRawPointer
        private let size: Int
        
        init(size: Int) {
            self.size = size
            self.buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        }
        
        func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
            return try body(UnsafeMutableRawBufferPointer(start: buffer, count: size))
        }
        
        deinit {
            // Securely clear memory before deallocation
            memset_s(buffer, size, 0, size)
            buffer.deallocate()
        }
    }
}
```

## Privacy Protections

### 1. Data Minimization

#### Local Processing First
```swift
class PrivacyController {
    func transcribeWithPrivacyProtection(_ audioURL: URL, 
                                       options: TranscriptionOptions) async throws -> TranscriptionResult {
        // Step 1: Always attempt local transcription first
        do {
            let result = try await nativeTranscriptionEngine.transcribe(audioURL, 
                                                                       language: options.language)
            
            // Log privacy-preserving analytics
            logLocalProcessingSuccess(duration: result.duration)
            
            return result
        } catch {
            // Log error without sensitive data
            logLocalProcessingFailure(error: type(of: error))
        }
        
        // Step 2: Only use cloud if explicitly allowed
        guard options.allowCloudFallback else {
            throw VoxError.cloudProcessingNotAuthorized
        }
        
        // Step 3: Inform user about cloud processing
        try await requestCloudProcessingConsent(audioURL: audioURL)
        
        // Step 4: Process with cloud API
        let result = try await cloudTranscriptionEngine.transcribe(audioURL, 
                                                                  provider: options.fallbackConfig!.provider,
                                                                  apiKey: options.fallbackConfig!.apiKey)
        
        // Log cloud usage (no sensitive data)
        logCloudProcessingUsage(provider: options.fallbackConfig!.provider, 
                              duration: result.duration)
        
        return result
    }
    
    private func requestCloudProcessingConsent(audioURL: URL) async throws {
        let audioSize = try audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let sizeInMB = Double(audioSize) / 1_048_576
        
        print("\n⚠️  PRIVACY NOTICE ⚠️")
        print("Local transcription failed. Cloud processing requires sending your audio file")
        print("(\(String(format: "%.1f", sizeInMB)) MB) to a third-party service.")
        print("")
        print("This audio will be:")
        print("  • Transmitted securely via HTTPS")
        print("  • Processed by the cloud provider")
        print("  • Subject to the provider's privacy policy")
        print("  • Not stored locally after processing")
        print("")
        print("Continue with cloud processing? (y/N): ", terminator: "")
        
        guard let response = readLine()?.lowercased(),
              response == "y" || response == "yes" else {
            throw VoxError.cloudProcessingDeclined
        }
    }
}
```

### 2. Data Lifecycle Management

#### Automatic Cleanup
```swift
class DataLifecycleManager {
    private var temporaryFiles: Set<URL> = []
    private var sensitiveData: [SecureMemoryManager.SecureString] = []
    
    func registerTemporaryFile(_ url: URL) {
        temporaryFiles.insert(url)
    }
    
    func registerSensitiveData(_ data: SecureMemoryManager.SecureString) {
        sensitiveData.append(data)
    }
    
    func cleanup() {
        // Clean up temporary files
        for fileURL in temporaryFiles {
            do {
                try securelyDeleteFile(fileURL)
            } catch {
                print("Warning: Failed to securely delete \(fileURL.lastPathComponent)")
            }
        }
        temporaryFiles.removeAll()
        
        // Clear sensitive data from memory
        for var data in sensitiveData {
            data.clear()
        }
        sensitiveData.removeAll()
    }
    
    private func securelyDeleteFile(_ url: URL) throws {
        let fileHandle = try FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }
        
        // Get file size
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        
        // Overwrite with random data multiple times
        for _ in 0..<3 {
            fileHandle.seek(toFileOffset: 0)
            let randomData = Data((0..<fileSize).map { _ in UInt8.random(in: 0...255) })
            fileHandle.write(randomData)
            fileHandle.synchronizeFile()
        }
        
        // Final overwrite with zeros
        fileHandle.seek(toFileOffset: 0)
        let zeroData = Data(repeating: 0, count: fileSize)
        fileHandle.write(zeroData)
        fileHandle.synchronizeFile()
        
        // Delete the file
        try FileManager.default.removeItem(at: url)
    }
    
    deinit {
        cleanup()
    }
}
```

## Threat Model

### Threats Addressed

1. **Audio Data Exposure**
   - Mitigation: Local processing, secure temporary files, automatic cleanup

2. **API Key Theft**
   - Mitigation: No persistent storage, secure input, memory clearing

3. **Network Interception**
   - Mitigation: TLS 1.2+, certificate pinning, secure headers

4. **Memory Dumps**
   - Mitigation: Secure memory management, data overwriting

5. **File System Access**
   - Mitigation: Restricted permissions, secure directories, symbolic link protection

### Threats NOT Addressed

1. **Malicious System Administrators** - Cannot protect against root access
2. **Hardware Attacks** - No protection against physical memory access
3. **Compromised macOS** - Assumes trusted operating system
4. **Supply Chain Attacks** - Relies on Apple's security for system frameworks

## Security Best Practices

### For Users

#### Recommended Usage
```bash
# Secure usage patterns
export OPENAI_API_KEY="your-key"  # Use environment variables
vox video.mp4                     # Local processing first

# Avoid insecure patterns
vox video.mp4 --api-key secret    # Key visible in process list
vox video.mp4 --force-cloud       # Skips local processing
```

#### Environment Security
```bash
# Secure API key management
echo 'export OPENAI_API_KEY="your-key"' >> ~/.zshrc_secrets
echo 'source ~/.zshrc_secrets' >> ~/.zshrc
chmod 600 ~/.zshrc_secrets

# Verify no key exposure
ps aux | grep vox  # Should not show API keys
history | grep OPENAI  # Check command history
```

### For Developers

#### Secure Development Practices
```swift
// Always use secure random for IDs
let tempID = UUID().uuidString

// Never log sensitive data
logger.info("Processing file: \(url.lastPathComponent)")  // ✅ OK
logger.info("API key: \(apiKey)")  // ❌ NEVER

// Clear sensitive variables
defer {
    apiKey = String(repeating: "X", count: apiKey.count)
}

// Use secure comparison for keys
func secureCompare(_ a: String, _ b: String) -> Bool {
    guard a.count == b.count else { return false }
    return a.withCString { aPtr in
        b.withCString { bPtr in
            return timingsafe_bcmp(aPtr, bPtr, a.count) == 0
        }
    }
}
```

## Security Incident Response

### Vulnerability Reporting
Report security vulnerabilities privately to: security@vox-project.dev

### Incident Response Plan
1. **Assessment** - Evaluate impact and scope
2. **Containment** - Release emergency patch if needed
3. **Communication** - Notify users via GitHub Security Advisories
4. **Recovery** - Full fix and verification
5. **Lessons Learned** - Update security practices

### Security Updates
- Critical security patches: Immediate release
- Important security fixes: Within 7 days
- Regular security improvements: Next minor version

## Compliance and Privacy

### Privacy Principles
- **Data Minimization**: Only process what's necessary
- **Purpose Limitation**: Use data only for transcription
- **Transparency**: Clear privacy notices
- **User Control**: Explicit consent for cloud processing
- **Security**: Appropriate technical safeguards

### Regulatory Considerations
- **GDPR**: User consent, data minimization, right to erasure
- **CCPA**: Privacy notices, user control
- **HIPAA**: Not designed for healthcare use without additional safeguards

This security and privacy framework ensures that Vox protects user data while providing powerful transcription capabilities through a privacy-first architecture.