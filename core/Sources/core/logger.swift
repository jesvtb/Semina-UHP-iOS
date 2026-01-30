import Foundation

public protocol Logger: Sendable { 
    func debug(_ message: String)
    func error(_ message: String, handlerType: String?, error: Error?)
    func warning(_ message: String, handlerType: String?)
    func info(_ message: String)
}

public struct LogEntry: Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let handlerType: String?
    public let error: String?
}

public enum LogLevel: String, Sendable {
    case debug
    case error
    case warning
    case info
}

/// No-op logger for use when logging is not required (e.g. default for APIClient).
public struct NoOpLogger: Logger {
    public init() {}
    public func debug(_ message: String) {}
    public func error(_ message: String, handlerType: String?, error: Error?) {}
    public func warning(_ message: String, handlerType: String?) {}
    public func info(_ message: String) {}
}

/// In-memory logger implementation with log storage
/// DEBUG builds: verbose logging + in-memory storage
/// RELEASE builds: minimal/silent logging (can still store for crash reporting)
public class InMemoryLogger: Logger, @unchecked Sendable {
    /// Shared singleton instance for app-wide use
    public static let shared = InMemoryLogger()
    
    /// In-memory log storage (thread-safe using DispatchQueue)
    private let logQueue = DispatchQueue(label: "com.unheardpath.logger", attributes: .concurrent)
    private var _logEntries: [LogEntry] = []
    
    /// Maximum number of log entries to keep in memory (prevents memory issues)
    private let maxLogEntries: Int
    
    /// Initialize with configurable maximum log entries
    /// - Parameter maxEntries: Maximum number of log entries to keep (default: 1000)
    public init(maxEntries: Int = 1000) {
        self.maxLogEntries = maxEntries
    }
    
    /// Get all stored log entries (thread-safe)
    public var allLogs: [LogEntry] {
        logQueue.sync {
            return _logEntries
        }
    }
    
    /// Get logs as formatted string
    public var formattedLogs: String {
        let logs = allLogs
        return logs.map { (entry: LogEntry) -> String in
            let timestamp = Self.formatTimestamp(entry.timestamp)
            let handlerInfo = entry.handlerType.map { " [\($0)]" } ?? ""
            let errorInfo = entry.error.map { ": \($0)" } ?? ""
            let emoji: String
            switch entry.level {
            case .error:
                emoji = "❌"
            case .warning:
                emoji = "⚠️"
            case .info:
                emoji = "ℹ️"
            case .debug:
                emoji = "📱"
            }
            return "\(timestamp) \(emoji) \(entry.message)\(handlerInfo)\(errorInfo)"
        }.joined(separator: "\n")
    }
    
    /// Clear all stored logs
    public func clearLogs() {
        logQueue.async(flags: .barrier) { [weak self] in
            self?._logEntries.removeAll()
        }
    }
    
    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func addLog(_ entry: LogEntry) {
        logQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self._logEntries.append(entry)
            // Keep only the most recent entries
            if self._logEntries.count > self.maxLogEntries {
                self._logEntries.removeFirst(self._logEntries.count - self.maxLogEntries)
            }
        }
    }

    public func info(_ message: String) {
        let entry = LogEntry(
            timestamp: Date(),
            level: .info,
            message: message,
            handlerType: nil,
            error: nil
        )
        addLog(entry)
        
        #if DEBUG
        print("INFO ℹ️ \(message)")
        #endif
    }
    
    public func debug(_ message: String) {
        let entry = LogEntry(
            timestamp: Date(),
            level: .debug,
            message: message,
            handlerType: nil,
            error: nil
        )
        addLog(entry)
        
        #if DEBUG
        print("DBUG 🧪  \(message)")
        #endif
    }
    
    public func error(_ message: String, handlerType: String?, error: Error?) {
        let errorString = error.map { $0.localizedDescription } ?? nil
        let entry = LogEntry(
            timestamp: Date(),
            level: .error,
            message: message,
            handlerType: handlerType,
            error: errorString
        )
        addLog(entry)
        
        #if DEBUG
        let handlerInfo = handlerType.map { " [\($0)]" } ?? ""
        let errorInfo = error.map { ": \($0)" } ?? ""
        print("ERRR ❌  \(message)\(handlerInfo)\(errorInfo)")
        #else
        // In release builds, still store errors for crash reporting
        // but don't print to console
        #endif
    }
    
    public func warning(_ message: String, handlerType: String?) {
        let entry = LogEntry(
            timestamp: Date(),
            level: .warning,
            message: message,
            handlerType: handlerType,
            error: nil
        )
        addLog(entry)
        
        #if DEBUG
        let handlerInfo = handlerType.map { " [\($0)]" } ?? ""
        print("WARN ⚠️ \(message)\(handlerInfo)")
        #endif
    }
}

