import Foundation

/// Manages display of transcription results and quality assessment
struct ResultDisplayManager {
    private let forceCloud: Bool
    private let timestamps: Bool
    private let formatter: OutputFormatter

    init(forceCloud: Bool, timestamps: Bool) {
        self.forceCloud = forceCloud
        self.timestamps = timestamps
        self.formatter = OutputFormatter()
    }

    func displayTranscriptionResult(_ result: TranscriptionResult) {
        Logger.shared.info("Transcription completed successfully")
        Logger.shared.info("  - Language: \(result.language)")
        fputs("  - Confidence: \(String(format: "%.1f%%", result.confidence * 100))\n", stdout)
        fputs("  - Duration: \(String(format: "%.2f", result.duration)) seconds\n", stdout)
        fputs("  - Processing time: \(String(format: "%.2f", result.processingTime)) seconds\n", stdout)
        fputs("  - Engine: \(result.engine.rawValue)\n", stdout)

        // Add comprehensive quality assessment
        let confidenceManager = ConfidenceManager()
        let qualityAssessment = confidenceManager.assessQuality(result: result)
        let qualityReport = confidenceManager.generateQualityReport(assessment: qualityAssessment)
        fputs("\n\(qualityReport)\n", stdout)

        // Show fallback recommendation if applicable
        if qualityAssessment.shouldUseFallback && !forceCloud {
            fputs("\n💡 Try running with --fallback-api openai for better accuracy\n", stdout)
        }

        displayTranscript(result)
    }

    private func displayTranscript(_ result: TranscriptionResult) {
        if timestamps && !result.segments.isEmpty {
            fputs("\n--- Transcript with timestamps ---\n", stdout)
            for segment in result.segments {
                let startTime = formatter.formatTime(segment.startTime)
                let endTime = formatter.formatTime(segment.endTime)
                fputs("[\(startTime) - \(endTime)] \(segment.text)\n", stdout)
            }
        } else {
            fputs("\n--- Transcript ---\n", stdout)
            fputs("\(result.text)\n", stdout)
        }
    }
}
