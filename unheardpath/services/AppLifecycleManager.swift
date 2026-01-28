//
//  AppLifecycleManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// Simple logger protocol for app-wide logging
/// Allows injection of custom logging implementations for testing
/// Made internal (not private) to allow test access and use across services
protocol AppLifecycleLogger: Sendable {
    func debug(_ message: String)
    func error(_ message: String, handlerType: String?, error: Error?)
    func warning(_ message: String, handlerType: String?)
}

/// Log entry structure for storing log records
struct LogEntry: Sendable {
    let timestamp: Date
    let level: LogLevel
    let message: String
    let handlerType: String?
    let error: String?
    
    enum LogLevel: String, Sendable {
        case debug
        case warning
        case error
        case info
    }
}

/// Default logger implementation with log storage
/// DEBUG builds: verbose logging + in-memory storage
/// RELEASE builds: minimal/silent logging (can still store for crash reporting)
/// Made internal (not private) to allow test access and use across services
class DefaultAppLifecycleLogger: AppLifecycleLogger, @unchecked Sendable {
    /// Shared singleton instance for app-wide use
    static let shared = DefaultAppLifecycleLogger()
    
    /// In-memory log storage (thread-safe using DispatchQueue)
    private let logQueue = DispatchQueue(label: "com.unheardpath.logger", attributes: .concurrent)
    private var _logEntries: [LogEntry] = []
    
    /// Maximum number of log entries to keep in memory (prevents memory issues)
    private let maxLogEntries = 1000
    
    /// Get all stored log entries (thread-safe)
    var allLogs: [LogEntry] {
        logQueue.sync {
            return _logEntries
        }
    }
    
    /// Get logs as formatted string
    var formattedLogs: String {
        let logs = allLogs
        return logs.map { (entry: LogEntry) -> String in
            let timestamp = Self.formatTimestamp(entry.timestamp)
            let handlerInfo = entry.handlerType.map { " [\($0)]" } ?? ""
            let errorInfo = entry.error.map { ": \($0)" } ?? ""
            let emoji = entry.level == .error ? "❌" : entry.level == .warning ? "⚠️" : "📱"
            return "\(timestamp) \(emoji) \(entry.message)\(handlerInfo)\(errorInfo)"
        }.joined(separator: "\n")
    }
    
    /// Clear all stored logs
    func clearLogs() {
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

    func info(_ message: String) {
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
    
    func debug(_ message: String) {
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
    
    func error(_ message: String, handlerType: String?, error: Error?) {
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
    
    func warning(_ message: String, handlerType: String?) {
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

/// Protocol for services that need app lifecycle management
/// All conforming types must be @MainActor isolated
///
/// **Usage**:
/// Types conforming to this protocol can be registered with AppLifecycleManager
/// using the convenience method `registerLifecycleHandler(_:)`
@MainActor
protocol AppLifecycleHandler: AnyObject {
    func appDidEnterBackground()
    func appWillEnterForeground()
}

/// Type-erased wrapper for lifecycle handlers to avoid protocol conformance issues with @MainActor classes
/// This allows @MainActor classes to register handlers without Swift 6 concurrency warnings
///
/// **Handler Requirements**:
/// - Handlers are non-throwing closures. Any errors must be caught and handled internally.
/// - Handlers execute synchronously on MainActor and should complete quickly.
/// - Heavy work should be offloaded to background queues.
private struct LifecycleHandlerCallbacks {
    /// Non-throwing closure called when app enters background
    /// Must handle errors internally - any thrown errors will be caught and logged
    let didEnterBackground: @MainActor () -> Void
    
    /// Non-throwing closure called when app enters foreground
    /// Must handle errors internally - any thrown errors will be caught and logged
    let willEnterForeground: @MainActor () -> Void
}

/// Weak reference wrapper for lifecycle handlers to prevent retain cycles
private class WeakLifecycleHandler {
    weak var object: AnyObject?
    let callbacks: LifecycleHandlerCallbacks
    
    init(object: AnyObject, callbacks: LifecycleHandlerCallbacks) {
        self.object = object
        self.callbacks = callbacks
    }
}

/// Centralized manager for app lifecycle events
/// Allows services to register as handlers for background/foreground transitions
///
/// **Execution Model**:
/// - All handlers execute **synchronously on the MainActor** (main thread)
/// - Handlers should complete quickly (<100ms) to avoid blocking other handlers
/// - Heavy work (network calls, file I/O, complex computations) should be offloaded
///   to background queues using `Task.detached` or `DispatchQueue.global()`
///
/// **Error Isolation**:
/// - Handlers are non-throwing closures. Errors must be caught and handled internally.
/// - If a handler unexpectedly throws, the error is logged but does not prevent
///   other handlers from executing.
///
/// **Cleanup Behavior**:
/// - Deallocated handlers are automatically removed during notification
/// - The handlers array is always rewritten to maintain validity (negligible cost)
///
/// **Thread Safety**:
/// - This class is `@MainActor` isolated. All handler callbacks execute on the main thread.
/// - Registration/unregistration must be called from MainActor context.
///
/// **Performance Monitoring**:
/// - In DEBUG builds, handlers taking >100ms trigger warnings
/// - Use this to identify handlers that need optimization
///
/// **Example Usage**:
/// ```swift
/// // Register a handler (use weak capture to avoid retain cycles)
/// appLifecycleManager.register(
///     object: self,
///     didEnterBackground: { [weak self] in
///         guard let self else { return }
///         // Lightweight work on main thread
///         self.saveState()
///         
///         // Heavy work offloaded to background
///         Task.detached {
///             await self.performHeavyCleanup()
///         }
///     },
///     willEnterForeground: { [weak self] in
///         guard let self else { return }
///         self.refreshUI()
///     }
/// )
/// ```
@MainActor
class AppLifecycleManager: ObservableObject {
    /// Published state indicating whether the app is currently in the background
    @Published var isAppInBackground: Bool = false {
        didSet {
            // Persist app state to UserDefaults for widget access
            // Note: StorageManager will automatically add "UHP." prefix
            StorageManager.saveToUserDefaults(isAppInBackground, forKey: appStateIsInBackgroundKey)
            
            // Reload widget timeline immediately to reflect app state change
            WidgetCenter.shared.reloadTimelines(ofKind: "widget")
            
            #if DEBUG
            logger.debug("Widget timeline reloaded due to app state change: \(isAppInBackground ? "background" : "foreground")")
            #endif
        }
    }
    
    /// Weak references to registered lifecycle handlers
    private var handlers: [WeakLifecycleHandler] = []
    
    /// Logger for lifecycle events (injectable for testing)
    /// Defaults to shared logger instance for app-wide consistency
    private let logger: AppLifecycleLogger
    
    // UserDefaults key for widget state
    // Note: StorageManager will automatically add "UHP." prefix
    private let appStateIsInBackgroundKey = "AppState.isInBackground"
    
    /// Shared logger instance accessible from AppLifecycleManager
    /// All services should use this same instance for consistent logging
    /// Returns the concrete type so you can access log storage methods (allLogs, formattedLogs, etc.)
    /// Can be used as AppLifecycleLogger protocol type for dependency injection
    /// Marked as nonisolated so it can be accessed from any context (logger is Sendable)
    nonisolated static var sharedLogger: DefaultAppLifecycleLogger {
        DefaultAppLifecycleLogger.shared
    }
    
    init(logger: AppLifecycleLogger = DefaultAppLifecycleLogger.shared) {
        self.logger = logger
        // Initialize app state in UserDefaults (defaults to foreground)
        // This ensures widget always has a valid value to read
        if !StorageManager.existsInUserDefaults(forKey: appStateIsInBackgroundKey) {
            StorageManager.saveToUserDefaults(false, forKey: appStateIsInBackgroundKey)
        }
        setupAppLifecycleObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App Lifecycle Observers
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc nonisolated private func handleDidEnterBackground() {
        // Bridge to MainActor since @objc methods are nonisolated
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAppInBackground = true
            logger.debug("AppLifecycleManager: App entered background")
            
            // Call all registered handlers on MainActor
            self.notifyHandlers { callbacks in
                callbacks.didEnterBackground()
            }
        }
    }
    
    @objc nonisolated private func handleWillEnterForeground() {
        // Bridge to MainActor since @objc methods are nonisolated
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAppInBackground = false
            logger.debug("AppLifecycleManager: App entering foreground")
            
            // Call all registered handlers on MainActor
            self.notifyHandlers { callbacks in
                callbacks.willEnterForeground()
            }
        }
    }
    
    // MARK: - Handler Registration
    
    /// Registers a handler to receive app lifecycle events
    ///
    /// **Registration Behavior**:
    /// - If the same object is registered multiple times, previous registrations are replaced
    /// - This ensures each object has only one active registration
    /// - Registration is thread-safe (must be called from MainActor context)
    ///
    /// **Handler Requirements**:
    /// - Handlers are non-throwing closures that execute on MainActor
    /// - Handlers should complete quickly (<100ms) to avoid blocking other handlers
    /// - Use weak capture in closures to avoid retain cycles: `{ [weak self] in ... }`
    ///
    /// - Parameters:
    ///   - object: The object to register (stored weakly to prevent retain cycles)
    ///   - didEnterBackground: Non-throwing closure called when app enters background (runs on @MainActor)
    ///   - willEnterForeground: Non-throwing closure called when app enters foreground (runs on @MainActor)
    func register(
        object: AnyObject,
        didEnterBackground: @escaping @MainActor () -> Void,
        willEnterForeground: @escaping @MainActor () -> Void
    ) {
        // Remove any existing reference to this object (de-duplication)
        // This ensures each object has only one active registration
        handlers.removeAll { $0.object === object }
        
        // Add new weak reference with callbacks
        let callbacks = LifecycleHandlerCallbacks(
            didEnterBackground: didEnterBackground,
            willEnterForeground: willEnterForeground
        )
        handlers.append(WeakLifecycleHandler(object: object, callbacks: callbacks))
        
        let handlerType = String(describing: type(of: object))
        logger.debug("Registered handler: \(handlerType)")
    }
    
    /// Unregisters a handler from receiving app lifecycle events
    /// - Parameter object: The object to unregister
    func unregister(object: AnyObject) {
        handlers.removeAll { $0.object === object }
        
        let handlerType = String(describing: type(of: object))
        logger.debug("Unregistered handler: \(handlerType)")
    }
    
    /// Convenience method for registering protocol-conforming lifecycle handlers
    /// This provides a type-safe, cleaner API for types that conform to AppLifecycleHandler
    ///
    /// **Usage**:
    /// ```swift
    /// extension MyService: AppLifecycleHandler {
    ///     func appDidEnterBackground() { /* ... */ }
    ///     func appWillEnterForeground() { /* ... */ }
    /// }
    ///
    /// appLifecycleManager.registerLifecycleHandler(myService)
    /// ```
    ///
    /// - Parameter handler: Handler conforming to AppLifecycleHandler protocol
    func registerLifecycleHandler(_ handler: AppLifecycleHandler) {
        register(
            object: handler as AnyObject,
            didEnterBackground: { handler.appDidEnterBackground() },
            willEnterForeground: { handler.appWillEnterForeground() }
        )
    }
    
    // MARK: - Private Helpers
    
    /// Notifies all registered handlers, automatically cleaning up nil weak references
    /// All handlers are called on the main actor since AppLifecycleManager is @MainActor
    ///
    /// **Error Handling**: Handlers are expected to be non-throwing, but any unexpected
    /// errors are caught and logged without preventing other handlers from executing.
    ///
    /// **Performance**: Handlers execute synchronously. Slow handlers will block other handlers.
    /// In DEBUG builds, slow handlers (>100ms) trigger warnings.
    private func notifyHandlers(_ action: (LifecycleHandlerCallbacks) -> Void) {
        var validHandlers: [WeakLifecycleHandler] = []
        
        for weakHandler in handlers {
            guard let object = weakHandler.object else { continue }
            validHandlers.append(weakHandler)
            
            #if DEBUG
            let startTime = CFAbsoluteTimeGetCurrent()
            #endif
            
            // Defensive error catching (handlers should not throw, but catch just in case)
            do {
                action(weakHandler.callbacks)
            } catch {
                let handlerType = String(describing: type(of: object))
                logger.error("Handler error", handlerType: handlerType, error: error)
            }
            
            #if DEBUG
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            if duration > 0.1 { // 100ms threshold
                let handlerType = String(describing: type(of: object))
                logger.warning("Slow handler detected (\(String(format: "%.0f", duration * 1000))ms)", handlerType: handlerType)
            }
            #endif
        }
        
        // Always rewrite array to maintain validity (negligible cost, simpler correctness)
        handlers = validHandlers
    }
}



