import Foundation
import Speech

/// Manages individual transcription tasks and their coordination
final class TranscriptionTaskManager {
    // MARK: - Types

    struct TranscriptionTask {
        let audioSegment: AudioSegmenter.AudioSegmentFile
        let recognizer: SFSpeechRecognizer
        let startTime: Date
        let taskID: String
    }

    // MARK: - Properties

    private let processingQueue: DispatchQueue
    private let speechConfig: PlatformOptimizer.SpeechRecognitionConfig

    private var recognitionTasks: [String: SFSpeechRecognitionTask] = [:]
    private var completedSegments: [TranscriptionSegment] = []
    private let taskLock = NSLock()
    private let segmentLock = NSLock()

    // MARK: - Initialization

    init(processingQueue: DispatchQueue, speechConfig: PlatformOptimizer.SpeechRecognitionConfig) {
        self.processingQueue = processingQueue
        self.speechConfig = speechConfig
    }

    // MARK: - Public API

    func createSpeechRecognizer(for language: String?) -> SFSpeechRecognizer? {
        let locale: Locale
        if let language = language {
            locale = Locale(identifier: language)
        } else {
            locale = Locale.current
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            Logger.shared.warn(
                "Speech recognizer not available for locale: \(locale.identifier)", 
                component: "TranscriptionTaskManager"
            )
            return nil
        }

        guard recognizer.isAvailable else {
            Logger.shared.warn(
                "Speech recognizer not currently available for locale: \(locale.identifier)", 
                component: "TranscriptionTaskManager"
            )
            return nil
        }

        return recognizer
    }

    func addCompletedSegment(_ segment: TranscriptionSegment) {
        segmentLock.lock()
        defer { segmentLock.unlock() }
        completedSegments.append(segment)
    }

    func getCompletedSegments() -> [TranscriptionSegment] {
        segmentLock.lock()
        defer { segmentLock.unlock() }
        return completedSegments
    }

    func clearCompletedSegments() {
        segmentLock.lock()
        defer { segmentLock.unlock() }
        completedSegments.removeAll()
    }

    func addRecognitionTask(_ task: SFSpeechRecognitionTask, for taskID: String) {
        taskLock.lock()
        defer { taskLock.unlock() }
        recognitionTasks[taskID] = task
    }

    func removeRecognitionTask(for taskID: String) {
        taskLock.lock()
        defer { taskLock.unlock() }
        recognitionTasks.removeValue(forKey: taskID)
    }

    func cancelAllTasks() {
        taskLock.lock()
        defer { taskLock.unlock() }

        for task in recognitionTasks.values {
            task.cancel()
        }
        recognitionTasks.removeAll()
    }

    func buildTranscriptionResult(
        from segments: [TranscriptionSegment],
        audioFile: AudioFile,
        language: String,
        startTime: Date
    ) -> TranscriptionResult {
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
        let fullText = sortedSegments.map { $0.text }.joined(separator: " ")
        let averageConfidence = sortedSegments.isEmpty ? 0.0 : 
            sortedSegments.map { $0.confidence }.reduce(0, +) / Double(sortedSegments.count)
        let processingTime = Date().timeIntervalSince(startTime)

        return TranscriptionResult(
            text: fullText,
            language: language,
            confidence: averageConfidence,
            duration: audioFile.format.duration,
            segments: sortedSegments,
            engine: .speechAnalyzer,
            processingTime: processingTime,
            audioFormat: audioFile.format
        )
    }

    func validateSegmentFile(_ segmentFile: AudioSegmenter.AudioSegmentFile) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: segmentFile.url.path) else {
            Logger.shared.error(
                "Segment file does not exist: \(segmentFile.url.path)",
                component: "TranscriptionTaskManager"
            )
            return false
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: segmentFile.url.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize == 0 {
                Logger.shared.error(
                    "Segment file is empty: \(segmentFile.url.path)",
                    component: "TranscriptionTaskManager"
                )
                return false
            }
        } catch {
            Logger.shared.error(
                "Failed to check segment file attributes: \(error)",
                component: "TranscriptionTaskManager"
            )
            return false
        }

        return true
    }
}
