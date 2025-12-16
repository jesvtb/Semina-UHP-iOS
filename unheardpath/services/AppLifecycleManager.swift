//
//  AppLifecycleManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import SwiftUI
import UIKit

/// Type-erased wrapper for lifecycle handlers to avoid protocol conformance issues with @MainActor classes
/// This allows @MainActor classes to register handlers without Swift 6 concurrency warnings
private struct LifecycleHandlerCallbacks {
    let didEnterBackground: @MainActor () -> Void
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
@MainActor
class AppLifecycleManager: ObservableObject {
    /// Published state indicating whether the app is currently in the background
    @Published var isAppInBackground: Bool = false
    
    /// Weak references to registered lifecycle handlers
    private var handlers: [WeakLifecycleHandler] = []
    
    init() {
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
    
    @objc private func handleDidEnterBackground() {
        // Bridge to MainActor since @objc methods are nonisolated
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAppInBackground = true
            #if DEBUG
            print("📱 AppLifecycleManager: App entered background")
            #endif
            
            // Call all registered handlers on MainActor
            self.notifyHandlers { callbacks in
                callbacks.didEnterBackground()
            }
        }
    }
    
    @objc private func handleWillEnterForeground() {
        // Bridge to MainActor since @objc methods are nonisolated
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAppInBackground = false
            #if DEBUG
            print("📱 AppLifecycleManager: App entering foreground")
            #endif
            
            // Call all registered handlers on MainActor
            self.notifyHandlers { callbacks in
                callbacks.willEnterForeground()
            }
        }
    }
    
    // MARK: - Handler Registration
    
    /// Registers a handler to receive app lifecycle events
    /// - Parameters:
    ///   - object: The object to register (stored weakly to prevent retain cycles)
    ///   - didEnterBackground: Closure called when app enters background (runs on @MainActor)
    ///   - willEnterForeground: Closure called when app enters foreground (runs on @MainActor)
    func register(
        object: AnyObject,
        didEnterBackground: @escaping @MainActor () -> Void,
        willEnterForeground: @escaping @MainActor () -> Void
    ) {
        // Remove any existing reference to this object (if re-registering)
        handlers.removeAll { $0.object === object }
        
        // Add new weak reference with callbacks
        let callbacks = LifecycleHandlerCallbacks(
            didEnterBackground: didEnterBackground,
            willEnterForeground: willEnterForeground
        )
        handlers.append(WeakLifecycleHandler(object: object, callbacks: callbacks))
        
        #if DEBUG
        print("✅ AppLifecycleManager: Registered handler: \(type(of: object))")
        #endif
    }
    
    /// Unregisters a handler from receiving app lifecycle events
    /// - Parameter object: The object to unregister
    func unregister(object: AnyObject) {
        handlers.removeAll { $0.object === object }
        
        #if DEBUG
        print("✅ AppLifecycleManager: Unregistered handler: \(type(of: object))")
        #endif
    }
    
    // MARK: - Private Helpers
    
    /// Notifies all registered handlers, automatically cleaning up nil weak references
    /// All handlers are called on the main actor since AppLifecycleManager is @MainActor
    private func notifyHandlers(_ action: (LifecycleHandlerCallbacks) -> Void) {
        // Clean up nil weak references while iterating
        var validHandlers: [WeakLifecycleHandler] = []
        
        for weakHandler in handlers {
            if weakHandler.object != nil {
                validHandlers.append(weakHandler)
                // Callbacks are @MainActor closures, called from @MainActor context
                action(weakHandler.callbacks)
            }
        }
        
        // Update handlers array to remove deallocated references
        handlers = validHandlers
    }
}



