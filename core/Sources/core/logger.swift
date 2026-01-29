import Foundation
import SwiftUI

public protocol Logger: Sendable { 
    func debug(_ message: String)
    func error(_ message: String, handlerType: String?, error: Error?)
    func warning(_ message: String, handlerType: String?)
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
}

