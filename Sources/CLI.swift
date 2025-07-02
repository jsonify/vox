import ArgumentParser
import Foundation

struct Vox: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vox",
        abstract: "Audio transcription CLI for MP4 video files",
        version: "1.0.0"
    )
    
    @Argument(help: "Input MP4 video file path")
    var inputFile: String
    
    @Option(name: [.short, .long], help: "Output file path")
    var output: String?
    
    @Option(name: [.short, .long], help: "Output format: txt, srt, json")
    var format: OutputFormat = .txt
    
    @Option(name: [.short, .long], help: "Language code (e.g., en-US, es-ES)")
    var language: String?
    
    @Option(help: "Fallback API: openai, revai")
    var fallbackApi: FallbackAPI?
    
    @Option(help: "API key for fallback service")
    var apiKey: String?
    
    @Flag(name: [.short, .long], help: "Enable verbose output")
    var verbose = false
    
    @Flag(help: "Force cloud transcription (skip native)")
    var forceCloud = false
    
    @Flag(help: "Include timestamps in output")
    var timestamps = false
    
    func run() throws {
        Logger.shared.configure(verbose: verbose)
        
        Logger.shared.info("Vox CLI - Audio transcription tool", component: "CLI")
        Logger.shared.debug("Verbose logging enabled", component: "CLI")
        
        Logger.shared.info("Input file: \(inputFile)", component: "CLI")
        Logger.shared.info("Output format: \(format)", component: "CLI")
        
        if let output = output {
            Logger.shared.info("Output file: \(output)", component: "CLI")
        }
        
        if let language = language {
            Logger.shared.info("Language: \(language)", component: "CLI")
        }
        
        if let fallbackApi = fallbackApi {
            Logger.shared.info("Fallback API: \(fallbackApi)", component: "CLI")
        }
        
        if forceCloud {
            Logger.shared.info("Using cloud transcription (forced)", component: "CLI")
        } else {
            Logger.shared.info("Using native transcription with fallback", component: "CLI")
        }
        
        if timestamps {
            Logger.shared.info("Timestamps enabled", component: "CLI")
        }
        
        print("Vox CLI - Audio transcription tool")
        print("Input file: \(inputFile)")
        print("Output format: \(format)")
        
        if let output = output {
            print("Output file: \(output)")
        }
        
        if forceCloud {
            print("Using cloud transcription")
        } else {
            print("Using native transcription with fallback")
        }
        
        try processAudioFile()
    }
    
    private func processAudioFile() throws {
        let audioProcessor = AudioProcessor()
        let semaphore = DispatchSemaphore(value: 0)
        var processingError: Error?
        
        print("Extracting audio from: \(inputFile)")
        
        audioProcessor.extractAudio(from: inputFile, 
                                  progressCallback: { progressReport in
                                      self.displayProgress(progressReport)
                                  }) { result in
            switch result {
            case .success(let audioFile):
                Logger.shared.info("Audio extraction completed successfully", component: "CLI")
                print("✓ Audio extracted successfully")
                print("  - Format: \(audioFile.format.codec)")
                print("  - Sample Rate: \(audioFile.format.sampleRate) Hz")
                print("  - Channels: \(audioFile.format.channels)")
                print("  - Duration: \(String(format: "%.2f", audioFile.format.duration)) seconds")
                
                if let bitRate = audioFile.format.bitRate {
                    print("  - Bit Rate: \(bitRate) bps")
                }
                
                if let tempPath = audioFile.temporaryPath {
                    print("  - Temporary file: \(tempPath)")
                }
                
                audioProcessor.cleanupTemporaryFiles(for: audioFile)
                
            case .failure(let error):
                Logger.shared.error("Audio extraction failed: \(error.localizedDescription)", component: "CLI")
                processingError = error
            }
            
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = processingError {
            throw error
        }
        
        print("Audio processing completed successfully!")
    }
    
    private func displayProgress(_ progress: ProgressReport) {
        if verbose {
            // Detailed progress in verbose mode
            let timeInfo = if progress.estimatedTimeRemaining != nil {
                " (ETA: \(progress.formattedTimeRemaining), elapsed: \(progress.formattedElapsedTime))"
            } else {
                " (elapsed: \(progress.formattedElapsedTime))"
            }
            
            let speedInfo = if let speed = progress.processingSpeed {
                " [\(String(format: "%.2f", speed * 100))/s]"
            } else {
                ""
            }
            
            print("[\(progress.currentPhase.rawValue)] \(progress.formattedProgress) - \(progress.currentStatus)\(timeInfo)\(speedInfo)")
        } else {
            // Simple progress bar in normal mode
            if progress.currentProgress > 0 {
                let barWidth = 30
                let filled = Int(progress.currentProgress * Double(barWidth))
                let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barWidth - filled)
                
                let timeInfo = if progress.estimatedTimeRemaining != nil {
                    " ETA: \(progress.formattedTimeRemaining)"
                } else {
                    ""
                }
                
                print("\r[\(bar)] \(progress.formattedProgress) - \(progress.currentPhase.rawValue)\(timeInfo)", terminator: "")
                
                if progress.isComplete {
                    print() // New line after completion
                }
            }
        }
    }
}