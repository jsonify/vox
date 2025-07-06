import Foundation

// MARK: - Benchmark Methods Extension

extension PerformanceBenchmark {
    internal func benchmarkStandardTranscription(_ audioFile: AudioFile) async -> BenchmarkResult? {
        let testName = "Standard_Transcription"
        startBenchmark(testName)

        do {
            let transcriber = try SpeechTranscriber()
            _ = try await transcriber.transcribe(audioFile: audioFile)
            return endBenchmark(testName, audioDuration: audioFile.format.duration)
        } catch {
            Logger.shared.error("Standard transcription benchmark failed: \(error)", component: "PerformanceBenchmark")
            return endBenchmark(testName, audioDuration: audioFile.format.duration)
        }
    }

    internal func benchmarkOptimizedTranscription(_ audioFile: AudioFile) async -> BenchmarkResult? {
        let testName = "Optimized_Transcription"
        startBenchmark(testName)

        return await withCheckedContinuation { continuation in
            let engine = OptimizedTranscriptionEngine()

            engine.transcribeAudio(from: audioFile) { _ in
                // Progress updates
            } completion: { _ in
                let benchmarkResult = self.endBenchmark(testName, audioDuration: audioFile.format.duration)
                continuation.resume(returning: benchmarkResult)
            }
        }
    }

    internal func benchmarkMemoryStress(_ audioFile: AudioFile) async -> BenchmarkResult? {
        let testName = "Memory_Stress"
        startBenchmark(testName)

        // Simulate memory-intensive operations
        let iterations = platformOptimizer.architecture == .appleSilicon ? 1000 : 500

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    let bufferSize = 64 * 1024
                    if let buffer = self.memoryManager.borrowBuffer(size: bufferSize) {
                        // Simulate work with buffer
                        usleep(1000) // 1ms
                        self.memoryManager.returnBuffer(buffer, size: bufferSize)
                    }
                }
            }
        }

        return endBenchmark(testName, audioDuration: audioFile.format.duration)
    }

    internal func benchmarkConcurrentProcessing(_ audioFile: AudioFile) async -> BenchmarkResult? {
        let testName = "Concurrent_Processing"
        startBenchmark(testName)

        let concurrentTasks = platformOptimizer.getAudioProcessingConfig().concurrentOperations

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrentTasks {
                group.addTask {
                    // Simulate concurrent audio processing
                    let processor = AudioProcessor()
                    processor.extractAudio(from: audioFile.url.path) { _ in
                        // Progress callback
                    } completion: { _ in
                        // Completion
                    }
                }
            }
        }

        return endBenchmark(testName, audioDuration: audioFile.format.duration)
    }
}
