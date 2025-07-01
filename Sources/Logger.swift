import Foundation
import os.log

public enum LogLevel: Int, CaseIterable, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
    
    var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        }
    }
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public class Logger: @unchecked Sendable {
    public static let shared = Logger()
    
    private let osLog: OSLog
    private let queue = DispatchQueue(label: "com.vox.logger", qos: .utility)
    private var _isVerbose: Bool = false
    private var _minimumLevel: LogLevel = .info
    
    var isVerbose: Bool {
        get { queue.sync { _isVerbose } }
        set { queue.sync { _isVerbose = newValue } }
    }
    
    var minimumLevel: LogLevel {
        get { queue.sync { _minimumLevel } }
        set { queue.sync { _minimumLevel = newValue } }
    }
    
    private init() {
        self.osLog = OSLog(subsystem: "com.vox.cli", category: "general")
    }
    
    public func configure(verbose: Bool) {
        isVerbose = verbose
        minimumLevel = verbose ? .debug : .info
    }
    
    public func debug(_ message: String, component: String? = nil, file: String = #file, line: Int = #line) {
        log(level: .debug, message: message, component: component, file: file, line: line)
    }
    
    public func info(_ message: String, component: String? = nil, file: String = #file, line: Int = #line) {
        log(level: .info, message: message, component: component, file: file, line: line)
    }
    
    public func warn(_ message: String, component: String? = nil, file: String = #file, line: Int = #line) {
        log(level: .warn, message: message, component: component, file: file, line: line)
    }
    
    public func error(_ message: String, component: String? = nil, file: String = #file, line: Int = #line) {
        log(level: .error, message: message, component: component, file: file, line: line)
    }
    
    private func log(level: LogLevel, message: String, component: String?, file: String, line: Int) {
        queue.sync {
            guard level >= self._minimumLevel else { return }
            
            let timestamp = self.formatTimestamp()
            let componentInfo = self.formatComponent(component, file: file)
            let formattedMessage = self.formatMessage(
                timestamp: timestamp,
                level: level,
                component: componentInfo,
                message: message,
                line: line
            )
            
            self.writeToStderr(formattedMessage)
            
            os_log("%{public}@", log: self.osLog, type: level.osLogType, formattedMessage)
        }
    }
    
    private func formatTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    private func formatComponent(_ component: String?, file: String) -> String {
        if let component = component {
            return component
        }
        
        let filename = URL(fileURLWithPath: file).lastPathComponent
        return String(filename.dropLast(6))
    }
    
    private func formatMessage(timestamp: String, level: LogLevel, component: String, message: String, line: Int) -> String {
        if isVerbose {
            return "[\(timestamp)] \(level.description) [\(component):\(line)] \(message)"
        } else {
            return "\(level.description): \(message)"
        }
    }
    
    private func writeToStderr(_ message: String) {
        fputs(message + "\n", stderr)
        fflush(stderr)
    }
}

public extension Logger {
    func logAudioProcessing(_ message: String) {
        info(message, component: "AudioProcessor")
    }
    
    func logTranscription(_ message: String) {
        info(message, component: "Transcription")
    }
    
    func logAPI(_ message: String) {
        debug(message, component: "API")
    }
    
    func logError(_ error: Error, component: String? = nil) {
        self.error("Error: \(error.localizedDescription)", component: component)
    }
}