import Foundation
import ArgumentParser

// MARK: - Configuration Models

enum OutputFormat: String, CaseIterable, ExpressibleByArgument, Codable {
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
