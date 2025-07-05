import Foundation
import CryptoKit

// MARK: - Validation Models

enum ValidationStatus: String, Codable {
    case passed = "passed"
    case failed = "failed"
    case warning = "warning"
}

struct ValidationReport: Codable {
    let formatValidation: FormatValidationResult
    let integrityValidation: IntegrityValidationResult
    let encodingValidation: EncodingValidationResult
    let overallStatus: ValidationStatus
    let validationTime: TimeInterval
    let timestamp: Date
    
    init(formatValidation: FormatValidationResult,
         integrityValidation: IntegrityValidationResult,
         encodingValidation: EncodingValidationResult,
         validationTime: TimeInterval) {
        self.formatValidation = formatValidation
        self.integrityValidation = integrityValidation
        self.encodingValidation = encodingValidation
        self.validationTime = validationTime
        self.timestamp = Date()
        
        // Determine overall status based on individual results
        if formatValidation.status == .failed || 
           integrityValidation.status == .failed || 
           encodingValidation.status == .failed {
            self.overallStatus = .failed
        } else if formatValidation.status == .warning || 
                  integrityValidation.status == .warning || 
                  encodingValidation.status == .warning {
            self.overallStatus = .warning
        } else {
            self.overallStatus = .passed
        }
    }
}

struct FormatValidationResult: Codable {
    let status: ValidationStatus
    let format: OutputFormat
    let isCompliant: Bool
    let issues: [String]
    let details: [String: String]
    
    init(status: ValidationStatus, format: OutputFormat, isCompliant: Bool, issues: [String] = [], details: [String: String] = [:]) {
        self.status = status
        self.format = format
        self.isCompliant = isCompliant
        self.issues = issues
        self.details = details
    }
}

struct IntegrityValidationResult: Codable {
    let status: ValidationStatus
    let contentHash: String
    let fileSizeBytes: Int64
    let isCorrupted: Bool
    let checksumMatches: Bool
    let issues: [String]
    
    init(status: ValidationStatus, contentHash: String, fileSizeBytes: Int64, isCorrupted: Bool, checksumMatches: Bool, issues: [String] = []) {
        self.status = status
        self.contentHash = contentHash
        self.fileSizeBytes = fileSizeBytes
        self.isCorrupted = isCorrupted
        self.checksumMatches = checksumMatches
        self.issues = issues
    }
}

struct EncodingValidationResult: Codable {
    let status: ValidationStatus
    let encoding: String
    let isValidUTF8: Bool
    let hasInvalidCharacters: Bool
    let issues: [String]
    
    init(status: ValidationStatus, encoding: String, isValidUTF8: Bool, hasInvalidCharacters: Bool, issues: [String] = []) {
        self.status = status
        self.encoding = encoding
        self.isValidUTF8 = isValidUTF8
        self.hasInvalidCharacters = hasInvalidCharacters
        self.issues = issues
    }
}

struct SuccessConfirmation: Codable {
    let filePath: URL
    let fileSize: Int64
    let format: OutputFormat
    let validationReport: ValidationReport
    let timestamp: Date
    let processingTime: TimeInterval
    let message: String
    
    init(filePath: URL, fileSize: Int64, format: OutputFormat, validationReport: ValidationReport, processingTime: TimeInterval) {
        self.filePath = filePath
        self.fileSize = fileSize
        self.format = format
        self.validationReport = validationReport
        self.processingTime = processingTime
        self.timestamp = Date()
        
        // Generate success message based on validation results
        if validationReport.overallStatus == .passed {
            self.message = "File successfully written and validated: \(filePath.lastPathComponent) (\(fileSize) bytes)"
        } else if validationReport.overallStatus == .warning {
            self.message = "File written with warnings: \(filePath.lastPathComponent) (\(fileSize) bytes)"
        } else {
            self.message = "File written but validation failed: \(filePath.lastPathComponent) (\(fileSize) bytes)"
        }
    }
}

// MARK: - Output Validator

class OutputValidator {
    private let logger: Logger
    private let fileManager: FileManager
    
    init() {
        self.logger = Logger.shared
        self.fileManager = FileManager.default
    }
    
    /// Main validation method that performs comprehensive validation
    func validateOutput(_ result: TranscriptionResult, writtenTo path: URL, format: OutputFormat) throws -> ValidationReport {
        let startTime = Date()
        logger.info("Starting output validation for: \(path.lastPathComponent)", component: "OutputValidator")
        
        // Read the written file content
        let content = try String(contentsOf: path, encoding: .utf8)
        
        // Perform individual validations
        let formatValidation = try validateFormat(content, format: format)
        let integrityValidation = try validateIntegrity(result, writtenContent: content, path: path)
        let encodingValidation = try validateEncoding(path)
        
        let validationTime = Date().timeIntervalSince(startTime)
        let report = ValidationReport(
            formatValidation: formatValidation,
            integrityValidation: integrityValidation,
            encodingValidation: encodingValidation,
            validationTime: validationTime
        )
        
        let statusMsg = "Output validation completed with status: \(report.overallStatus.rawValue)"
        logger.info(statusMsg, component: "OutputValidator")
        
        return report
    }
    
    /// Validate format-specific compliance
    func validateFormat(_ content: String, format: OutputFormat) throws -> FormatValidationResult {
        logger.debug("Validating format: \(format.rawValue)", component: "OutputValidator")
        
        switch format {
        case .txt:
            return validateTextFormat(content)
        case .srt:
            return validateSRTFormat(content)
        case .json:
            return validateJSONFormat(content)
        }
    }
    
    /// Validate content integrity
    func validateIntegrity(_ originalResult: TranscriptionResult, writtenContent: String, path: URL) throws -> IntegrityValidationResult {
        logger.debug("Validating content integrity", component: "OutputValidator")
        
        var issues: [String] = []
        var status: ValidationStatus = .passed
        
        // Get file size
        let attributes = try fileManager.attributesOfItem(atPath: path.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        // Calculate content hash
        let contentData = writtenContent.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: contentData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Validate file size is reasonable
        if fileSize == 0 {
            issues.append("File is empty")
            status = .failed
        } else if fileSize < 10 {
            issues.append("File size is suspiciously small: \(fileSize) bytes")
            status = .warning
        }
        
        // Validate content contains original transcription text
        let isCorrupted = !writtenContent.contains(originalResult.text.prefix(min(100, originalResult.text.count)))
        if isCorrupted {
            issues.append("Content appears corrupted - original text not found")
            status = .failed
        }
        
        // For now, we don't have a reference checksum, so we'll mark as matching
        let checksumMatches = true
        
        return IntegrityValidationResult(
            status: status,
            contentHash: hashString,
            fileSizeBytes: fileSize,
            isCorrupted: isCorrupted,
            checksumMatches: checksumMatches,
            issues: issues
        )
    }
    
    /// Validate text encoding
    func validateEncoding(_ path: URL) throws -> EncodingValidationResult {
        logger.debug("Validating encoding", component: "OutputValidator")
        
        var issues: [String] = []
        var status: ValidationStatus = .passed
        
        // Read file as UTF-8 and validate
        let content = try String(contentsOf: path, encoding: .utf8)
        let isValidUTF8 = content.utf8.count == content.count
        
        if !isValidUTF8 {
            issues.append("Invalid UTF-8 encoding detected")
            status = .failed
        }
        
        // Check for invalid characters
        let hasInvalidCharacters = content.contains { (char: Character) in
            let scalar = char.unicodeScalars.first
            return scalar?.properties.generalCategory == .control && char != "\n" && char != "\r" && char != "\t"
        }
        
        if hasInvalidCharacters {
            issues.append("Invalid control characters detected")
            status = .warning
        }
        
        return EncodingValidationResult(
            status: status,
            encoding: "UTF-8",
            isValidUTF8: isValidUTF8,
            hasInvalidCharacters: hasInvalidCharacters,
            issues: issues
        )
    }
    
    // MARK: - Format-Specific Validation
    
    private func validateTextFormat(_ content: String) -> FormatValidationResult {
        var issues: [String] = []
        var status: ValidationStatus = .passed
        var details: [String: String] = [:]
        
        // Basic text validation
        if content.isEmpty {
            issues.append("Text content is empty")
            status = .failed
        }
        
        // Check for reasonable line lengths
        let lines = content.components(separatedBy: .newlines)
        let longLines = lines.filter { $0.count > 1000 }
        if !longLines.isEmpty {
            issues.append("Found \(longLines.count) extremely long lines")
            status = .warning
        }
        
        details["lineCount"] = "\(lines.count)"
        details["characterCount"] = "\(content.count)"
        
        return FormatValidationResult(
            status: status,
            format: .txt,
            isCompliant: issues.isEmpty,
            issues: issues,
            details: details
        )
    }
    
    private func validateSRTFormat(_ content: String) -> FormatValidationResult {
        var issues: [String] = []
        var status: ValidationStatus = .passed
        var details: [String: String] = [:]
        
        if content.isEmpty {
            issues.append("SRT content is empty")
            status = .failed
            return FormatValidationResult(status: status, format: .srt, isCompliant: false, issues: issues, details: details)
        }
        
        // Parse SRT blocks
        let blocks = content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        if blocks.isEmpty {
            issues.append("No valid SRT blocks found")
            status = .failed
        }
        
        var validBlocks = 0
        for (index, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            // Each block should have at least 3 lines: sequence, timestamp, text
            if lines.count < 3 {
                issues.append("Block \(index + 1) has insufficient lines")
                status = .warning
                continue
            }
            
            // Validate sequence number
            if Int(lines[0]) == nil {
                issues.append("Block \(index + 1) has invalid sequence number")
                status = .warning
                continue
            }
            
            // Validate timestamp format
            let timestampPattern = #"^\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}$"#
            if lines[1].range(of: timestampPattern, options: .regularExpression) == nil {
                issues.append("Block \(index + 1) has invalid timestamp format")
                status = .warning
                continue
            }
            
            validBlocks += 1
        }
        
        details["totalBlocks"] = "\(blocks.count)"
        details["validBlocks"] = "\(validBlocks)"
        
        return FormatValidationResult(
            status: status,
            format: .srt,
            isCompliant: validBlocks == blocks.count,
            issues: issues,
            details: details
        )
    }
    
    private func validateJSONFormat(_ content: String) -> FormatValidationResult {
        var issues: [String] = []
        var status: ValidationStatus = .passed
        var details: [String: String] = [:]
        
        if content.isEmpty {
            issues.append("JSON content is empty")
            status = .failed
            return FormatValidationResult(status: status, format: .json, isCompliant: false, issues: issues, details: details)
        }
        
        // Validate JSON structure
        do {
            let data = content.data(using: .utf8) ?? Data()
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            
            if let dict = jsonObject as? [String: Any] {
                // Validate expected keys
                let expectedKeys = ["text", "language", "confidence", "duration", "segments", "engine", "processingTime", "audioFormat"]
                let missingKeys = expectedKeys.filter { dict[$0] == nil }
                
                if !missingKeys.isEmpty {
                    issues.append("Missing expected keys: \(missingKeys.joined(separator: ", "))")
                    status = .warning
                }
                
                details["keyCount"] = "\(dict.keys.count)"
                details["hasExpectedStructure"] = "\(missingKeys.isEmpty)"
            } else {
                issues.append("JSON root is not an object")
                status = .warning
            }
        } catch {
            issues.append("Invalid JSON format: \(error.localizedDescription)")
            status = .failed
        }
        
        return FormatValidationResult(
            status: status,
            format: .json,
            isCompliant: issues.isEmpty,
            issues: issues,
            details: details
        )
    }
}

// MARK: - Error Extensions

extension VoxError {
    static func outputValidationFailed(_ reason: String) -> VoxError {
        return .processingFailed("Output validation failed: \(reason)")
    }
}