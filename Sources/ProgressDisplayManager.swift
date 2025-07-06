import Foundation

/// Manages progress display for both audio processing and transcription
struct ProgressDisplayManager {
    private let verbose: Bool
    private static let memoryMonitor = MemoryMonitor()

    init(verbose: Bool = false) {
        self.verbose = verbose
    }

    func displayProgress(_ progress: TranscriptionProgress) {
        if verbose {
            displayVerboseProgress(progress)
        } else {
            displaySimpleProgress(progress)
        }
    }

    @Sendable static func displayProgressReport(_ progress: TranscriptionProgress, verbose: Bool) {
        let manager = ProgressDisplayManager(verbose: verbose)
        manager.displayProgress(progress)
    }

    private func displayVerboseProgress(_ progress: TranscriptionProgress) {
        // Detailed progress in verbose mode with enhanced information
        let timeInfo = if progress.estimatedTimeRemaining != nil {
            " (ETA: \(progress.formattedTimeRemaining), elapsed: \(progress.formattedElapsedTime))"
        } else {
            " (elapsed: \(progress.formattedElapsedTime))"
        }

        let speedInfo = if let speed = progress.processingSpeed {
            " [\(String(format: "%.1f", speed))x speed]"
        } else {
            ""
        }

        // Show current status with more context for transcription
        let statusPrefix = progress.currentPhase == .extracting ? "🎤" : "⚙️"
        let progressLine = "\(statusPrefix) [\(progress.currentPhase.rawValue)] \(progress.formattedProgress) - \(progress.currentStatus)\(timeInfo)\(speedInfo)"
        print(progressLine) // swiftlint:disable:this no_print

        // Show memory usage if available during transcription
        if progress.currentPhase == .extracting && progress.currentProgress > 0.1 {
            let memoryUsage = Self.memoryMonitor.getCurrentUsage()
            let memoryCurrentStr = String(format: "%.1f", memoryUsage.currentMB)
            let memoryPercentStr = String(format: "%.1f", memoryUsage.usagePercentage)
            print("   💾 Memory: \(memoryCurrentStr) MB (\(memoryPercentStr)%)") // swiftlint:disable:this no_print
        }
    }

    private func displaySimpleProgress(_ progress: TranscriptionProgress) {
        // Enhanced progress bar in normal mode
        if progress.currentProgress > 0 {
            let barWidth = 40
            let filled = Int(progress.currentProgress * Double(barWidth))
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barWidth - filled)

            let timeInfo = if progress.estimatedTimeRemaining != nil {
                " ETA: \(progress.formattedTimeRemaining)"
            } else {
                ""
            }

            let speedInfo = if let speed = progress.processingSpeed {
                " (\(String(format: "%.1f", speed))x)"
            } else {
                ""
            }

            // Different icons for different phases
            let phaseIcon = switch progress.currentPhase {
            case .initializing, .analyzing, .validating, .finalizing:
                "⚙️"
            case .extracting, .converting:
                "🎤"
            case .complete:
                "✅"
            }

            print("\r\(phaseIcon) [\(bar)] \(progress.formattedProgress)\(timeInfo)\(speedInfo)", terminator: "") // swiftlint:disable:this no_print

            if progress.isComplete {
                print() // New line after completion // swiftlint:disable:this no_print
            }
        }
    }
}
