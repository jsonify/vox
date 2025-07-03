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
        print("\n✓ Transcription completed successfully") // swiftlint:disable:this no_print
        print("  - Language: \(result.language)") // swiftlint:disable:this no_print
        print("  - Confidence: \(String(format: "%.1f%%", result.confidence * 100))") // swiftlint:disable:this no_print
        print("  - Duration: \(String(format: "%.2f", result.duration)) seconds") // swiftlint:disable:this no_print
        print("  - Processing time: \(String(format: "%.2f", result.processingTime)) seconds") // swiftlint:disable:this no_print
        print("  - Engine: \(result.engine.rawValue)") // swiftlint:disable:this no_print
        
        // Add comprehensive quality assessment
        let confidenceManager = ConfidenceManager()
        let qualityAssessment = confidenceManager.assessQuality(result: result)
        let qualityReport = confidenceManager.generateQualityReport(assessment: qualityAssessment)
        print("\n\(qualityReport)") // swiftlint:disable:this no_print
        
        // Show fallback recommendation if applicable
        if qualityAssessment.shouldUseFallback && !forceCloud {
            print("\n💡 Try running with --fallback-api openai for better accuracy") // swiftlint:disable:this no_print
        }
        
        displayTranscript(result)
    }
    
    private func displayTranscript(_ result: TranscriptionResult) {
        if timestamps && !result.segments.isEmpty {
            print("\n--- Transcript with timestamps ---") // swiftlint:disable:this no_print
            for segment in result.segments {
                let startTime = formatter.formatTime(segment.startTime)
                let endTime = formatter.formatTime(segment.endTime)
                print("[\(startTime) - \(endTime)] \(segment.text)") // swiftlint:disable:this no_print
            }
        } else {
            print("\n--- Transcript ---") // swiftlint:disable:this no_print
            print(result.text) // swiftlint:disable:this no_print
        }
    }
}