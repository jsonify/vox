import Foundation

/// Configuration for confidence scoring and quality assessment
struct ConfidenceConfig {
    /// Minimum confidence threshold for acceptable transcription (0.0-1.0)
    let minAcceptableConfidence: Double

    /// Threshold for triggering quality warnings (0.0-1.0)
    let warningThreshold: Double

    /// Threshold for automatically triggering fallback to cloud services (0.0-1.0)
    let fallbackThreshold: Double

    /// Minimum confidence threshold for individual segments (0.0-1.0)
    let segmentConfidenceThreshold: Double

    /// Maximum percentage of low-confidence segments allowed before triggering warnings
    let maxLowConfidenceSegmentPercentage: Double

    static let `default` = ConfidenceConfig(
        minAcceptableConfidence: 0.3,      // 30% minimum confidence
        warningThreshold: 0.5,             // Warn below 50%
        fallbackThreshold: 0.25,           // Fallback below 25%
        segmentConfidenceThreshold: 0.4,   // Flag segments below 40%
        maxLowConfidenceSegmentPercentage: 0.3  // Warn if >30% segments are low confidence
    )
}

/// Quality assessment result with detailed confidence analysis
struct QualityAssessment {
    /// Overall confidence score (0.0-1.0)
    let overallConfidence: Double

    /// Quality level based on confidence thresholds
    let qualityLevel: QualityLevel

    /// Segments with confidence below threshold
    let lowConfidenceSegments: [LowConfidenceSegment]

    /// Percentage of segments with low confidence
    let lowConfidencePercentage: Double

    /// Recommendations for improving transcription quality
    let recommendations: [QualityRecommendation]

    /// Whether fallback to cloud services is recommended
    let shouldUseFallback: Bool

    /// Warning messages about transcription quality
    let warnings: [String]
}

/// Quality level classification
enum QualityLevel: String, CaseIterable {
    case excellent = "excellent"    // >80% confidence
    case good = "good"             // 60-80% confidence
    case acceptable = "acceptable"  // 40-60% confidence
    case poor = "poor"             // 20-40% confidence
    case unacceptable = "unacceptable" // <20% confidence

    var description: String {
        switch self {
        case .excellent: return "Excellent transcription quality"
        case .good: return "Good transcription quality"
        case .acceptable: return "Acceptable transcription quality"
        case .poor: return "Poor transcription quality - consider using fallback"
        case .unacceptable: return "Unacceptable transcription quality - fallback recommended"
        }
    }

    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .acceptable: return "🟠"
        case .poor: return "🔴"
        case .unacceptable: return "⚫"
        }
    }
}

/// Segment with low confidence requiring attention
struct LowConfidenceSegment {
    let segment: TranscriptionSegment
    let index: Int
    let reason: String
    let suggestedAction: String
}

/// Quality improvement recommendation
struct QualityRecommendation {
    let type: RecommendationType
    let message: String
    let priority: Priority

    enum RecommendationType {
        case audioquality
        case language
        case fallback
        case preprocessing
    }

    enum Priority {
        case high, medium, low
    }
}

/// Manager for confidence scoring and quality assessment
class ConfidenceManager {
    private let config: ConfidenceConfig

    init(config: ConfidenceConfig = .default) {
        self.config = config
    }

    /// Assess transcription quality and generate recommendations
    func assessQuality(result: TranscriptionResult) -> QualityAssessment {
        let overallConfidence = result.confidence
        let qualityLevel = determineQualityLevel(confidence: overallConfidence)
        let lowConfidenceSegments = identifyLowConfidenceSegments(segments: result.segments)
        let lowConfidencePercentage = calculateLowConfidencePercentage(
            lowConfidenceCount: lowConfidenceSegments.count,
            totalCount: result.segments.count
        )

        let recommendations = generateRecommendations(
            result: result,
            qualityLevel: qualityLevel,
            lowConfidencePercentage: lowConfidencePercentage
        )

        let shouldUseFallback = shouldTriggerFallback(
            overallConfidence: overallConfidence,
            lowConfidencePercentage: lowConfidencePercentage
        )

        let warnings = generateWarnings(
            qualityLevel: qualityLevel,
            lowConfidenceSegments: lowConfidenceSegments,
            lowConfidencePercentage: lowConfidencePercentage,
            shouldUseFallback: shouldUseFallback
        )

        return QualityAssessment(
            overallConfidence: overallConfidence,
            qualityLevel: qualityLevel,
            lowConfidenceSegments: lowConfidenceSegments,
            lowConfidencePercentage: lowConfidencePercentage,
            recommendations: recommendations,
            shouldUseFallback: shouldUseFallback,
            warnings: warnings
        )
    }

    /// Check if transcription result meets minimum quality standards
    func meetsQualityStandards(result: TranscriptionResult) -> Bool {
        let assessment = assessQuality(result: result)
        return assessment.overallConfidence >= config.minAcceptableConfidence &&
            assessment.lowConfidencePercentage <= config.maxLowConfidenceSegmentPercentage
    }

    /// Generate quality report for CLI output
    func generateQualityReport(assessment: QualityAssessment) -> String {
        var report = [String]()

        report.append("📊 Quality Assessment:")
        report.append("  \(assessment.qualityLevel.emoji) \(assessment.qualityLevel.description)")
        report.append("  - Overall Confidence: \(String(format: "%.1f%%", assessment.overallConfidence * 100))")

        if !assessment.lowConfidenceSegments.isEmpty {
            report.append("  - Low Confidence Segments: \(assessment.lowConfidenceSegments.count) (\(String(format: "%.1f%%", assessment.lowConfidencePercentage * 100)))")
        }

        if assessment.shouldUseFallback {
            report.append("  - 🔄 Fallback recommended")
        }

        if !assessment.warnings.isEmpty {
            report.append("\n⚠️  Quality Warnings:")
            for warning in assessment.warnings {
                report.append("  - \(warning)")
            }
        }

        if !assessment.recommendations.isEmpty {
            report.append("\n💡 Recommendations:")
            for recommendation in assessment.recommendations {
                let priorityIcon = recommendation.priority == .high ? "🔥" :
                    recommendation.priority == .medium ? "⚡" : "💡"
                report.append("  \(priorityIcon) \(recommendation.message)")
            }
        }

        return report.joined(separator: "\n")
    }

    // MARK: - Private Methods

    private func determineQualityLevel(confidence: Double) -> QualityLevel {
        switch confidence {
        case 0.8...1.0: return .excellent
        case 0.6..<0.8: return .good
        case 0.4..<0.6: return .acceptable
        case 0.2..<0.4: return .poor
        default: return .unacceptable
        }
    }

    private func identifyLowConfidenceSegments(segments: [TranscriptionSegment]) -> [LowConfidenceSegment] {
        return segments.enumerated().compactMap { index, segment in
            guard segment.confidence < config.segmentConfidenceThreshold else { return nil }

            let reason = determineSegmentIssueReason(segment: segment)
            let suggestedAction = determineSuggestedAction(segment: segment)

            return LowConfidenceSegment(
                segment: segment,
                index: index,
                reason: reason,
                suggestedAction: suggestedAction
            )
        }
    }

    private func calculateLowConfidencePercentage(lowConfidenceCount: Int, totalCount: Int) -> Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(lowConfidenceCount) / Double(totalCount)
    }

    private func shouldTriggerFallback(overallConfidence: Double, lowConfidencePercentage: Double) -> Bool {
        return overallConfidence < config.fallbackThreshold ||
            lowConfidencePercentage > config.maxLowConfidenceSegmentPercentage
    }

    private func generateRecommendations(
        result: TranscriptionResult,
        qualityLevel: QualityLevel,
        lowConfidencePercentage: Double
    ) -> [QualityRecommendation] {
        var recommendations = [QualityRecommendation]()

        // Audio quality recommendations
        if result.confidence < 0.5 {
            recommendations.append(QualityRecommendation(
                type: .audioquality,
                message: "Consider using higher quality audio files for better transcription accuracy",
                priority: .medium
            ))
        }

        // Language recommendations
        if result.confidence < 0.4 && result.language != "en-US" {
            recommendations.append(QualityRecommendation(
                type: .language,
                message: "Try using a different language setting or enable language detection",
                priority: .high
            ))
        }

        // Fallback recommendations
        if qualityLevel == .poor || qualityLevel == .unacceptable {
            recommendations.append(QualityRecommendation(
                type: .fallback,
                message: "Use cloud transcription services (--fallback-api openai) for better accuracy",
                priority: .high
            ))
        }

        // Preprocessing recommendations
        if lowConfidencePercentage > 0.4 {
            recommendations.append(QualityRecommendation(
                type: .preprocessing,
                message: "Consider noise reduction or audio enhancement preprocessing",
                priority: .medium
            ))
        }

        return recommendations
    }

    private func generateWarnings(
        qualityLevel: QualityLevel,
        lowConfidenceSegments: [LowConfidenceSegment],
        lowConfidencePercentage: Double,
        shouldUseFallback: Bool
    ) -> [String] {
        var warnings = [String]()

        if qualityLevel == .poor || qualityLevel == .unacceptable {
            warnings.append("Transcription quality is \(qualityLevel.rawValue) - results may be unreliable")
        }

        if lowConfidencePercentage > config.maxLowConfidenceSegmentPercentage {
            warnings.append("\(String(format: "%.1f%%", lowConfidencePercentage * 100)) of segments have low confidence")
        }

        if shouldUseFallback {
            warnings.append("Consider using cloud transcription fallback for better accuracy")
        }

        if !lowConfidenceSegments.isEmpty && lowConfidenceSegments.count > 5 {
            warnings.append("Multiple segments (\(lowConfidenceSegments.count)) require manual review")
        }

        return warnings
    }

    private func determineSegmentIssueReason(segment: TranscriptionSegment) -> String {
        let duration = segment.endTime - segment.startTime
        let confidence = segment.confidence

        if confidence < 0.2 {
            return "Very low confidence score"
        } else if duration < 0.5 {
            return "Very short segment"
        } else if duration > 30.0 {
            return "Very long segment"
        } else if segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Empty or whitespace-only text"
        } else {
            return "Below confidence threshold"
        }
    }

    private func determineSuggestedAction(segment: TranscriptionSegment) -> String {
        let duration = segment.endTime - segment.startTime
        let confidence = segment.confidence

        if confidence < 0.1 {
            return "Manual review required"
        } else if duration < 0.5 {
            return "May need audio enhancement"
        } else if segment.text.count < 3 {
            return "Verify transcription accuracy"
        } else {
            return "Review and potentially re-transcribe"
        }
    }
}
