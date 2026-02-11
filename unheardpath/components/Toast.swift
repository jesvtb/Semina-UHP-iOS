import SwiftUI

// MARK: - Activity Update Banner Component
/// A banner for activity updates in liveUpdateStack.
///
/// **Dismiss behavior by toast type:**
/// - "info" toasts represent in-progress operations and persist with a spinner until replaced
///   by the next toast or dismissed externally (e.g., on `stop` event). A 60-second stale guard
///   auto-dismisses if no new event arrives (safety net for backend errors).
/// - All other types (success, error, warning, etc.) auto-dismiss after 4 seconds.
///
/// When a new toast arrives, SwiftUI removes this view (onDisappear cancels any pending timer).
/// Uses `onToastDimiss` (separate from the message bubble's `onDismiss`).
struct ToastView: View {
    let toastData: ToastData
    let onToastDimiss: () -> Void
    @State private var dismissTask: Task<Void, Never>?
    
    /// Whether this toast represents an in-progress operation that should persist until
    /// replaced or externally dismissed (e.g., by a `stop` SSE event).
    private var isInProgress: Bool {
        guard let type = toastData.type?.lowercased() else { return false }
        switch type {
        case "info", "information", "search", "search web", "update", "refresh", "location", "gps":
            return true
        default:
            return false
        }
    }
    
    /// Maps activity update type to SF Symbol icon name
    private var iconName: String {
        guard let type = toastData.type else {
            return "bell.fill" // Default icon for null type
        }
        
        switch type.lowercased() {
        case "info", "information":
            return "info.circle.fill"
        case "search", "search web":
            return "magnifyingglass"
        case "success", "completed":
            return "checkmark.circle.fill"
        case "warning", "alert":
            return "exclamationmark.triangle.fill"
        case "error", "failure":
            return "xmark.circle.fill"
        case "location", "gps":
            return "location.fill"
        case "journey", "trip":
            return "signpost.right.and.left.fill"
        case "message", "chat":
            return "message.fill"
        case "update", "refresh":
            return "arrow.clockwise.circle.fill"
        default:
            return "bell.fill" // Default icon for unknown types
        }
    }
    
    // The banner content itself
    private var bannerContent: some View {
        HStack(spacing: 12) {
            if isInProgress {
                // Spinner for in-progress toasts
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                    .frame(width: 24, height: 24)
            } else {
                // Static icon for terminal-state toasts
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24)
            }
            
            // Activity update message
            Text(toastData.message)
                .bodyText()
                .foregroundColor(Color("onBkgTextColor20"))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)  // Inner padding: space between content and background
        .padding(.vertical, 12)     // Inner padding: space between content and background
        .background(
            Color("AppBkgColor")
                .opacity(0.95)
                .cornerRadius(Spacing.current.spaceS)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
    
    var body: some View {
        bannerContent
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                startDismissTimer()
            }
            .onDisappear {
                // Cancel dismiss task when view disappears (e.g., when new toast arrives or
                // externally dismissed via stop event)
                dismissTask?.cancel()
            }
    }
    
    /// Starts the appropriate dismiss timer based on toast type.
    /// - In-progress toasts: 60-second stale guard (safety net if backend never sends stop)
    /// - Terminal toasts: 4-second auto-dismiss
    private func startDismissTimer() {
        let timeout: UInt64 = isInProgress
            ? 60_000_000_000  // 60 seconds — stale guard for in-progress toasts
            : 4_000_000_000   // 4 seconds — auto-dismiss for terminal toasts
        
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: timeout)
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onToastDimiss()
                }
            }
        }
    }
}

