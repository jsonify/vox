import Foundation
import Speech

// MARK: - Segment Processing Extension

extension SpeechTranscriber {
    func determineSegmentType(
        text: String,
        pauseDuration: TimeInterval?,
        isFirstSegment: Bool,
        isLastSegment: Bool,
        previousText: String?
    ) -> SegmentType {
        // Check for silence gaps (pause > speaker change threshold typically indicates speaker change or paragraph break)
        if let pause = pauseDuration, pause > TimingThresholds.speakerChangeThreshold {
            return .speakerChange
        }

        // Check for sentence boundaries
        if text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
            return .sentenceBoundary
        }

        // Check for paragraph boundaries (long pause + sentence ending)
        if let pause = pauseDuration, pause > TimingThresholds.paragraphBoundaryThreshold,
           let prevText = previousText,
           prevText.hasSuffix(".") || prevText.hasSuffix("!") || prevText.hasSuffix("?") {
            return .paragraphBoundary
        }

        // Check for silence (empty or very short segments with low confidence)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .silence
        }

        return .speech
    }

    func extractWordTimings(from segment: SFTranscriptionSegment) -> WordTiming? {
        // Apple's SFTranscriptionSegment represents word-level segments
        // Each segment typically contains one word with timing information
        let word = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !word.isEmpty else { return nil }

        // TEMP DEBUG: Bypass Logger calls
        if word.split(separator: " ").count > 1 {
            fputs("DEBUG: Unexpected multi-word segment found: '\(word)'\n", stderr)
        }

        return WordTiming(
            word: word,
            startTime: segment.timestamp,
            endTime: segment.timestamp + segment.duration,
            confidence: Double(segment.confidence)
        )
    }

    func detectSpeakerChange(at index: Int, in segments: [SFTranscriptionSegment]) -> String? {
        // Apple Speech framework doesn't provide speaker diarization
        // This is a placeholder for future enhancement or integration with other services
        // For now, we'll detect potential speaker changes based on significant pause patterns

        guard index > 0 else { return "Speaker1" }

        let currentSegment = segments[index]
        let previousSegment = segments[index - 1]
        let pauseDuration = currentSegment.timestamp - (previousSegment.timestamp + previousSegment.duration)

        // Simple heuristic: if there's a pause > definite speaker change threshold, assume speaker change
        if pauseDuration > TimingThresholds.definiteSpeakerChangeThreshold {
            return "Speaker\((index % 4) + 1)" // Cycle through up to 4 speakers
        }

        return "Speaker1" // Default to single speaker
    }
}
