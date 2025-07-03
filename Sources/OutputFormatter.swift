import Foundation

/// Handles formatting transcription results into different output formats
struct OutputFormatter {
    
    func format(_ result: TranscriptionResult, as format: OutputFormat, includeTimestamps: Bool = false) throws -> String {
        switch format {
        case .txt:
            // Use enhanced text formatting with basic options for backward compatibility
            let options = TextFormattingOptions(
                includeTimestamps: includeTimestamps,
                includeSpeakerIDs: true,
                includeConfidenceScores: false,
                paragraphBreakThreshold: 2.0,
                sentenceBreakThreshold: 0.8,
                timestampFormat: .hms,
                confidenceThreshold: 0.5,
                lineWidth: 80
            )
            return formatAsEnhancedText(result, options: options)
        case .srt:
            return formatAsSRT(result)
        case .json:
            return try formatAsJSON(result)
        }
    }
    
    /// Format transcription result with full TextFormatter configuration options
    func format(_ result: TranscriptionResult, as format: OutputFormat, options: TextFormattingOptions) throws -> String {
        switch format {
        case .txt:
            return formatAsEnhancedText(result, options: options)
        case .srt:
            return formatAsSRT(result)
        case .json:
            return try formatAsJSON(result)
        }
    }
    
    func saveTranscriptionResult(_ result: TranscriptionResult, to path: String, format: OutputFormat) throws {
        let content = try self.format(result, as: format)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
    
    /// Save transcription result with full TextFormatter configuration options
    func saveTranscriptionResult(_ result: TranscriptionResult, to path: String, format: OutputFormat, options: TextFormattingOptions) throws {
        let content = try self.format(result, as: format, options: options)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
    
    /// Format transcription result with custom JSON formatting options
    func format(_ result: TranscriptionResult, as format: OutputFormat, jsonOptions: JSONFormatter.JSONFormattingOptions) throws -> String {
        switch format {
        case .txt:
            return formatAsEnhancedText(result, options: .default)
        case .srt:
            return formatAsSRT(result)
        case .json:
            let jsonFormatter = JSONFormatter(options: jsonOptions)
            return try jsonFormatter.formatAsJSON(result)
        }
    }
    
    /// Save transcription result with custom JSON formatting options
    func saveTranscriptionResult(_ result: TranscriptionResult, to path: String, format: OutputFormat, jsonOptions: JSONFormatter.JSONFormattingOptions) throws {
        let content = try self.format(result, as: format, jsonOptions: jsonOptions)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
    
    private func formatAsSRT(_ result: TranscriptionResult) -> String {
        var srtContent = ""
        
        for (index, segment) in result.segments.enumerated() {
            let startTime = formatSRTTime(segment.startTime)
            let endTime = formatSRTTime(segment.endTime)
            
            srtContent += "\(index + 1)\n"
            srtContent += "\(startTime) --> \(endTime)\n"
            srtContent += "\(segment.text)\n\n"
        }
        
        return srtContent
    }
    
    private func formatSRTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }
    
    private func formatAsJSON(_ result: TranscriptionResult) throws -> String {
        let jsonFormatter = JSONFormatter()
        return try jsonFormatter.formatAsJSON(result)
    }
    
    func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}