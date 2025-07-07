import Foundation

struct FFmpegAudioFormatParser {
    private static let logger = Logger.shared

    static func parseAudioFormat(from output: String, filePath: String) -> AudioFormat? {
        // Parse audio stream info from ffmpeg output
        // Example: Stream #0:1(und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, stereo, fltp, 128 kb/s

        let audioPattern = #"Audio: (\w+).*?(\d+) Hz.*?(\w+).*?(\d+) kb/s"#

        var codec = "aac"
        var sampleRate = 44100
        var channels = 2
        var bitRate: Int?

        if let regex = try? NSRegularExpression(pattern: audioPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            if let codecRange = Range(match.range(at: 1), in: output) {
                codec = String(output[codecRange])
            }
            
            if let sampleRateRange = Range(match.range(at: 2), in: output) {
                sampleRate = Int(String(output[sampleRateRange])) ?? 44100
            }
            
            if let channelRange = Range(match.range(at: 3), in: output) {
                let channelInfo = String(output[channelRange])
                channels = channelInfo.contains("stereo") ? 2 : 1
            }
            
            if let bitRateRange = Range(match.range(at: 4), in: output) {
                let bitRateKbps = Int(String(output[bitRateRange])) ?? 128
                bitRate = bitRateKbps * 1000 // Convert kb/s to b/s
            }
        }

        let duration = parseDuration(from: output)

        // Get actual file size
        let fileSize = getFileSize(for: filePath)

        // Validate the audio format
        let validation = AudioFormatValidator.validate(
            codec: codec,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate
        )

        return AudioFormat(
            codec: codec,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate,
            duration: duration,
            fileSize: fileSize,
            isValid: validation.isValid,
            validationError: validation.error
        )
    }

    static func parseDuration(from output: String) -> TimeInterval {
        // Parse duration from ffmpeg output
        // Format: Duration: 00:01:30.50, start: 0.000000, bitrate: 128 kb/s
        let durationPattern = #"Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})"#

        guard let regex = try? NSRegularExpression(pattern: durationPattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) else {
            logger.debug("Could not parse duration from ffmpeg output", component: "FFmpegAudioFormatParser")
            return 0.0
        }

        var hours = 0.0
        var minutes = 0.0
        var seconds = 0.0
        var centiseconds = 0.0
        
        if let hoursRange = Range(match.range(at: 1), in: output) {
            hours = Double(String(output[hoursRange])) ?? 0
        }
        if let minutesRange = Range(match.range(at: 2), in: output) {
            minutes = Double(String(output[minutesRange])) ?? 0
        }
        if let secondsRange = Range(match.range(at: 3), in: output) {
            seconds = Double(String(output[secondsRange])) ?? 0
        }
        if let centisecondsRange = Range(match.range(at: 4), in: output) {
            centiseconds = Double(String(output[centisecondsRange])) ?? 0
        }

        return hours * 3600 + minutes * 60 + seconds + centiseconds / 100
    }

    static func parseProgress(from output: String, totalDuration: TimeInterval) -> Double? {
        // Parse progress from ffmpeg output
        // Format: frame= 1234 fps=25.0 q=28.0 size=     256kB time=00:00:49.40 bitrate=  42.4kbits/s
        let progressPattern = #"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})"#

        guard totalDuration > 0,
              let regex = try? NSRegularExpression(pattern: progressPattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) else {
            return nil
        }

        var hours = 0.0
        var minutes = 0.0
        var seconds = 0.0
        var centiseconds = 0.0
        
        if let hoursRange = Range(match.range(at: 1), in: output) {
            hours = Double(String(output[hoursRange])) ?? 0
        }
        if let minutesRange = Range(match.range(at: 2), in: output) {
            minutes = Double(String(output[minutesRange])) ?? 0
        }
        if let secondsRange = Range(match.range(at: 3), in: output) {
            seconds = Double(String(output[secondsRange])) ?? 0
        }
        if let centisecondsRange = Range(match.range(at: 4), in: output) {
            centiseconds = Double(String(output[centisecondsRange])) ?? 0
        }

        let currentTime = hours * 3600 + minutes * 60 + seconds + centiseconds / 100
        return min(currentTime / totalDuration, 1.0)
    }

    private static func getFileSize(for filePath: String) -> UInt64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            return attributes[.size] as? UInt64
        } catch {
            logger.debug("Could not get file size for \(filePath): \(error)", component: "FFmpegAudioFormatParser")
            return nil
        }
    }
}
