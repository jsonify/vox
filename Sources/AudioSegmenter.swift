import Foundation
import AVFoundation

/// Utility for splitting audio files into temporal segments for concurrent transcription
public final class AudioSegmenter {
    // MARK: - Types

    public struct AudioSegmentFile {
        public let url: URL
        public let startTime: TimeInterval
        public let duration: TimeInterval
        public let segmentIndex: Int
        public let totalSegments: Int
        public let isTemporary: Bool

        public init(url: URL, startTime: TimeInterval, duration: TimeInterval,
                    segmentIndex: Int, totalSegments: Int, isTemporary: Bool = true) {
            self.url = url
            self.startTime = startTime
            self.duration = duration
            self.segmentIndex = segmentIndex
            self.totalSegments = totalSegments
            self.isTemporary = isTemporary
        }
    }

    public enum SegmentationError: Error, LocalizedError {
        case invalidInputFile
        case assetLoadingFailed(String)
        case exportFailed(String)
        case temporaryDirectoryCreationFailed

        public var errorDescription: String? {
            switch self {
            case .invalidInputFile:
                return "Invalid input audio file"
            case .assetLoadingFailed(let details):
                return "Asset loading failed: \(details)"
            case .exportFailed(let details):
                return "Audio export failed: \(details)"
            case .temporaryDirectoryCreationFailed:
                return "Failed to create temporary directory for segments"
            }
        }
    }

    // MARK: - Properties

    private let tempFileManager = TempFileManager.shared
    private var createdSegmentFiles: [URL] = []
    private let cleanupQueue = DispatchQueue(label: "vox.audio.segmenter.cleanup", qos: .utility)

    // MARK: - Initialization

    public init() {
        Logger.shared.info("Initialized AudioSegmenter", component: "AudioSegmenter")
    }

    deinit {
        cleanupAllSegments()
    }

    // MARK: - Public API

    /// Splits an audio file into segments of specified duration
    /// - Parameters:
    ///   - audioFile: The source audio file to segment
    ///   - segmentDuration: Duration of each segment in seconds
    /// - Returns: Array of AudioSegmentFile objects representing the segments
    /// - Throws: SegmentationError if the segmentation fails
    public func createSegments(
        from audioFile: AudioFile,
        segmentDuration: TimeInterval
    ) async throws -> [AudioSegmentFile] {
        Logger.shared.info("Creating audio segments from \(audioFile.path) with \(segmentDuration)s duration", component: "AudioSegmenter")

        // Load the audio asset
        let asset = AVURLAsset(url: audioFile.url)

        // Wait for asset to load key properties
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw SegmentationError.invalidInputFile
        }

        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)

        guard totalDuration > 0 else {
            throw SegmentationError.invalidInputFile
        }

        // Calculate segment count and prepare segment info
        let segmentCount = Int(ceil(totalDuration / segmentDuration))
        var segments: [AudioSegmentFile] = []

        Logger.shared.info("Splitting \(String(format: "%.2f", totalDuration))s audio into \(segmentCount) segments", component: "AudioSegmenter")

        // Create temporary directory for segments
        let segmentDirectory = try createSegmentDirectory()

        // Create each segment file
        for i in 0..<segmentCount {
            let segmentStartTime = TimeInterval(i) * segmentDuration
            let segmentActualDuration = min(segmentDuration, totalDuration - segmentStartTime)

            let segmentFile = try await createSegmentFile(
                from: asset,
                startTime: segmentStartTime,
                duration: segmentActualDuration,
                segmentIndex: i,
                totalSegments: segmentCount,
                outputDirectory: segmentDirectory
            )

            segments.append(segmentFile)
            createdSegmentFiles.append(segmentFile.url)
        }

        Logger.shared.info("Successfully created \(segments.count) audio segments", component: "AudioSegmenter")
        return segments
    }

    /// Cleans up all created segment files
    public func cleanupAllSegments() {
        cleanupQueue.async { [weak self] in
            guard let self = self else { return }

            let filesToCleanup = self.createdSegmentFiles
            self.createdSegmentFiles.removeAll()

            for segmentURL in filesToCleanup {
                do {
                    if FileManager.default.fileExists(atPath: segmentURL.path) {
                        try FileManager.default.removeItem(at: segmentURL)
                        Logger.shared.debug("Cleaned up segment file: \(segmentURL.lastPathComponent)", component: "AudioSegmenter")
                    }
                } catch {
                    Logger.shared.error("Failed to cleanup segment file \(segmentURL.path): \(error)", component: "AudioSegmenter")
                }
            }

            Logger.shared.info("Completed cleanup of audio segments", component: "AudioSegmenter")
        }
    }

    /// Cleans up specific segment files
    public func cleanupSegments(_ segments: [AudioSegmentFile]) {
        cleanupQueue.async {
            for segment in segments where segment.isTemporary {
                do {
                    if FileManager.default.fileExists(atPath: segment.url.path) {
                        try FileManager.default.removeItem(at: segment.url)
                        Logger.shared.debug("Cleaned up segment: \(segment.url.lastPathComponent)", component: "AudioSegmenter")
                    }
                } catch {
                    Logger.shared.error("Failed to cleanup segment \(segment.url.path): \(error)", component: "AudioSegmenter")
                }
            }
        }
    }

    // MARK: - Private Implementation

    private func createSegmentDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let segmentDir = tempDir.appendingPathComponent("vox_segments_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: segmentDir, withIntermediateDirectories: true)
            return segmentDir
        } catch {
            throw SegmentationError.temporaryDirectoryCreationFailed
        }
    }

    private func createSegmentFile(
        from asset: AVURLAsset,
        startTime: TimeInterval,
        duration: TimeInterval,
        segmentIndex: Int,
        totalSegments: Int,
        outputDirectory: URL
    ) async throws -> AudioSegmentFile {
        // Create output URL for this segment
        let outputFileName = String(format: "segment_%03d.m4a", segmentIndex)
        let outputURL = outputDirectory.appendingPathComponent(outputFileName)

        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SegmentationError.exportFailed("Could not create export session")
        }

        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        // Set time range for this segment
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let durationCMTime = CMTime(seconds: duration, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCMTime, duration: durationCMTime)
        exportSession.timeRange = timeRange

        // Use preset settings optimized for speech recognition
        // The Apple M4A preset already provides good settings for speech

        Logger.shared.debug("Creating segment \(segmentIndex): \(String(format: "%.2f", startTime))s - \(String(format: "%.2f", startTime + duration))s", component: "AudioSegmenter")

        // Perform export
        await exportSession.export()

        // Check export status
        switch exportSession.status {
        case .completed:
            let segmentFile = AudioSegmentFile(
                url: outputURL,
                startTime: startTime,
                duration: duration,
                segmentIndex: segmentIndex,
                totalSegments: totalSegments,
                isTemporary: true
            )

            Logger.shared.debug("Successfully created segment \(segmentIndex) at \(outputURL.path)", component: "AudioSegmenter")
            return segmentFile

        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw SegmentationError.exportFailed("Segment \(segmentIndex): \(errorMessage)")

        case .cancelled:
            throw SegmentationError.exportFailed("Segment \(segmentIndex): Export was cancelled")

        default:
            throw SegmentationError.exportFailed("Segment \(segmentIndex): Unexpected export status")
        }
    }
}
