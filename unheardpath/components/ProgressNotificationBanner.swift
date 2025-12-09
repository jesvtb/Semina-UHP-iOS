import SwiftUI

// MARK: - Progress Notification Banner Component
/// A notification banner specifically for progress-related notifications in liveUpdateStack.
/// Auto-dismisses after 4 seconds. When a new notification arrives, SwiftUI automatically
/// removes this banner (onDisappear cancels the dismiss task).
/// Uses `onNotificationDismiss` (separate from the message bubble's `onDismiss`).
struct ProgressNotificationBanner: View {
    let notification: NotificationData
    let onNotificationDismiss: () -> Void
    @State private var dismissTask: Task<Void, Never>?
    
    /// Maps notification type to SF Symbol icon name
    private var iconName: String {
        guard let type = notification.type else {
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
            // Icon placeholder
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(.primary)
                .frame(width: 24, height: 24)
            
            // Notification message
            Text(notification.message)
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
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Start auto-dismiss timer
                dismissTask = Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            onNotificationDismiss()
                        }
                    }
                }
            }
            .onDisappear {
                // Cancel dismiss task when view disappears (e.g., when new notification arrives)
                // SwiftUI automatically calls this when currentNotification changes
                dismissTask?.cancel()
            }
    }
}

