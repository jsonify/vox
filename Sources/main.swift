import ArgumentParser
import Foundation

@main
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
        if verbose {
            print("Starting transcription of: \(inputFile)")
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
    }
}

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case txt
    case srt
    case json
    
    var defaultValueDescription: String {
        return "txt"
    }
}

enum FallbackAPI: String, CaseIterable, ExpressibleByArgument {
    case openai
    case revai
}
