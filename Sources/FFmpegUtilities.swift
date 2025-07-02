import Foundation

struct FFmpegUtilities {
    private static let ffmpegPath = "/opt/homebrew/bin/ffmpeg" // Common homebrew path
    private static let alternativePaths = [
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
        "/opt/local/bin/ffmpeg"
    ]
    
    /// Check if ffmpeg is available on the system
    static func isFFmpegAvailable() -> Bool {
        // First check common installation paths
        let allPaths = [ffmpegPath] + alternativePaths
        
        for path in allPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }
        
        // Fallback: try to execute ffmpeg from PATH
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["ffmpeg"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Find the ffmpeg executable path
    static func findFFmpegPath() -> String? {
        let allPaths = [ffmpegPath] + alternativePaths
        
        for path in allPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Try to find in PATH
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["ffmpeg"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Fall through to return nil
        }
        
        return nil
    }
}