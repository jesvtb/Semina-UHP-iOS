import Foundation
import SwiftUI

/// Shared manager for managing toast notifications
/// Ensures both chat and orchestrator endpoints can display toasts consistently
@MainActor
class ToastManager: ObservableObject {
    @Published var currentToastData: ToastData?
    
    init() {
        self.currentToastData = nil
    }
    
    /// Show a toast notification
    /// - Parameter toastData: The toast data to display
    func show(_ toastData: ToastData) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentToastData = toastData
        }
        
        #if DEBUG
        print("✅ ToastManager: Showing toast - type: \(toastData.type ?? "nil"), message: \(toastData.message)")
        #endif
    }
    
    /// Dismiss the current toast
    func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentToastData = nil
        }
        
        #if DEBUG
        print("✅ ToastManager: Dismissed toast")
        #endif
    }
}
