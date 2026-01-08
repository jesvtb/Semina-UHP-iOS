import SwiftUI

// MARK: - Activity Update Banner Component
/// A banner specifically for activity updates in liveUpdateStack.
/// Auto-dismisses after 4 seconds. When a new activity update arrives, SwiftUI automatically
/// removes this banner (onDisappear cancels the dismiss task).
/// Uses `onToastDimiss` (separate from the message bubble's `onDismiss`).
struct ToastView: View {
    let toastData: ToastData
    let onToastDimiss: () -> Void
    @State private var dismissTask: Task<Void, Never>?
    
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
            // Icon placeholder
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(.primary)
                .frame(width: 24, height: 24)
            
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
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Start auto-dismiss timer
                dismissTask = Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            onToastDimiss()
                        }
                    }
                }
            }
            .onDisappear {
                // Cancel dismiss task when view disappears (e.g., when new activity update arrives)
                // SwiftUI automatically calls this when currentToastData changes
                dismissTask?.cancel()
            }
    }
}

