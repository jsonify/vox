import Foundation

/// Configuration options for text formatting
struct TextFormattingOptions {
    let includeTimestamps: Bool
    let includeSpeakerIDs: Bool
    let includeConfidenceScores: Bool
    let paragraphBreakThreshold: TimeInterval
    let sentenceBreakThreshold: TimeInterval
    let timestampFormat: TimestampFormat
    let confidenceThreshold: Double
    let lineWidth: Int
    
    enum TimestampFormat {
        case hms // [00:01:23]
        case seconds // [83.5s]
        case milliseconds // [83500ms]
    }
    
    static let `default` = TextFormattingOptions(
        includeTimestamps: false,
        includeSpeakerIDs: false,
        includeConfidenceScores: false,
        paragraphBreakThreshold: 2.0,
        sentenceBreakThreshold: 0.8,
        timestampFormat: .hms,
        confidenceThreshold: 0.5,
        lineWidth: 80
    )
}

/// Handles advanced text formatting for transcription results
class TextFormatter {
    private let options: TextFormattingOptions
    private let outputFormatter: OutputFormatter
    
    init(options: TextFormattingOptions = .default) {
        self.options = options
        self.outputFormatter = OutputFormatter()
    }
    
    /// Formats a transcription result as clean, readable text
    func formatAsText(_ result: TranscriptionResult) -> String {
        var output = ""
        var currentSpeaker: String? = nil
        var currentParagraph: [String] = []
        var lastEndTime: TimeInterval = 0
        
        for (_, segment) in result.segments.enumerated() {
            let isNewParagraph = shouldStartNewParagraph(segment, lastEndTime: lastEndTime)
            let isNewSpeaker = segment.speakerID != currentSpeaker
            
            // Handle paragraph breaks
            if isNewParagraph || isNewSpeaker {
                if !currentParagraph.isEmpty {
                    output += formatParagraph(currentParagraph, speaker: currentSpeaker) + "\n\n"
                    currentParagraph = []
                }
                currentSpeaker = segment.speakerID
            }
            
            // Build segment text with optional annotations
            let segmentText = formatSegment(segment, isFirstInParagraph: currentParagraph.isEmpty)
            currentParagraph.append(segmentText)
            
            lastEndTime = segment.endTime
        }
        
        // Add final paragraph
        if !currentParagraph.isEmpty {
            output += formatParagraph(currentParagraph, speaker: currentSpeaker)
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Formats a transcription result with detailed metadata
    func formatAsDetailedText(_ result: TranscriptionResult) -> String {
        var output = ""
        
        // Add header with metadata
        output += formatHeader(result)
        output += "\n" + String(repeating: "=", count: 50) + "\n\n"
        
        // Add formatted transcript
        output += formatAsText(result)
        
        // Add footer with statistics
        output += "\n\n" + String(repeating: "=", count: 50) + "\n"
        output += formatFooter(result)
        
        return output
    }
    
    // MARK: - Private Methods
    
    private func shouldStartNewParagraph(_ segment: TranscriptionSegment, lastEndTime: TimeInterval) -> Bool {
        let timeSinceLastSegment = segment.startTime - lastEndTime
        
        // Check for explicit paragraph boundaries
        if segment.isParagraphBoundary {
            return true
        }
        
        // Check for silence-based paragraph breaks
        if timeSinceLastSegment > options.paragraphBreakThreshold {
            return true
        }
        
        // Check for speaker changes
        if segment.hasSpeakerChange {
            return true
        }
        
        return false
    }
    
    private func formatSegment(_ segment: TranscriptionSegment, isFirstInParagraph: Bool) -> String {
        var text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add timestamp if requested and this is the first segment in paragraph
        if options.includeTimestamps && isFirstInParagraph {
            let timestamp = formatTimestamp(segment.startTime)
            text = "\(timestamp) \(text)"
        }
        
        // Add confidence score if requested and below threshold
        if options.includeConfidenceScores && segment.confidence < options.confidenceThreshold {
            let confidence = String(format: "%.1f", segment.confidence * 100)
            text += " [confidence: \(confidence)%]"
        }
        
        return text
    }
    
    private func formatParagraph(_ segments: [String], speaker: String?) -> String {
        var paragraph = segments.joined(separator: " ")
        
        // Add speaker identification if requested
        if options.includeSpeakerIDs, let speaker = speaker {
            paragraph = "\(speaker): \(paragraph)"
        }
        
        // Apply line wrapping if needed
        if options.lineWidth > 0 {
            paragraph = wrapText(paragraph, width: options.lineWidth)
        }
        
        return paragraph
    }
    
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        switch options.timestampFormat {
        case .hms:
            return "[\(outputFormatter.formatTime(seconds))]"
        case .seconds:
            return "[\(String(format: "%.1f", seconds))s]"
        case .milliseconds:
            return "[\(Int(seconds * 1000))ms]"
        }
    }
    
    private func formatHeader(_ result: TranscriptionResult) -> String {
        var header = "TRANSCRIPTION REPORT\n"
        header += "Duration: \(outputFormatter.formatTime(result.duration))\n"
        header += "Language: \(result.language)\n"
        header += "Engine: \(result.engine.rawValue)\n"
        header += "Overall Confidence: \(String(format: "%.1f", result.confidence * 100))%\n"
        header += "Processing Time: \(String(format: "%.1f", result.processingTime))s\n"
        header += "Segments: \(result.segments.count)\n"
        
        // Add speaker count if available
        let speakers = Set(result.segments.compactMap { $0.speakerID })
        if !speakers.isEmpty {
            header += "Speakers: \(speakers.count) (\(speakers.sorted().joined(separator: ", ")))\n"
        }
        
        return header
    }
    
    private func formatFooter(_ result: TranscriptionResult) -> String {
        var footer = "STATISTICS\n"
        footer += "Total Words: \(result.segments.reduce(0) { $0 + $1.text.components(separatedBy: .whitespaces).count })\n"
        footer += "Average Confidence: \(String(format: "%.1f", result.segments.map { $0.confidence }.reduce(0, +) / Double(result.segments.count) * 100))%\n"
        
        let lowConfidenceSegments = result.segments.filter { $0.confidence < options.confidenceThreshold }
        if !lowConfidenceSegments.isEmpty {
            footer += "Low Confidence Segments: \(lowConfidenceSegments.count)\n"
        }
        
        return footer
    }
    
    private func wrapText(_ text: String, width: Int) -> String {
        let words = text.components(separatedBy: .whitespaces)
        var lines: [String] = []
        var currentLine = ""
        
        for word in words {
            if currentLine.isEmpty {
                currentLine = word
            } else if (currentLine + " " + word).count <= width {
                currentLine += " " + word
            } else {
                lines.append(currentLine)
                currentLine = word
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - OutputFormatter Extension

extension OutputFormatter {
    /// Enhanced text formatting using TextFormatter
    func formatAsEnhancedText(_ result: TranscriptionResult, options: TextFormattingOptions = .default) -> String {
        let formatter = TextFormatter(options: options)
        return formatter.formatAsText(result)
    }
    
    /// Detailed text formatting with metadata
    func formatAsDetailedText(_ result: TranscriptionResult, options: TextFormattingOptions = .default) -> String {
        let formatter = TextFormatter(options: options)
        return formatter.formatAsDetailedText(result)
    }
}