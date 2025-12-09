import SwiftUI

/// Manages state for the LiveUpdateStack overlay component
/// Groups related state: lastMessage, currentNotification, and isMessageExpanded
@MainActor
class LiveUpdateViewModel: ObservableObject {
    @Published var lastMessage: ChatMessage?
    @Published var currentNotification: NotificationData?
    @Published var isMessageExpanded: Bool = false
    
    /// Dismisses the message bubble and resets expansion state
    func dismissMessage() {
        lastMessage = nil
        isMessageExpanded = false
    }
    
    /// Sets a new notification with animation
    func setNotification(_ notification: NotificationData) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentNotification = notification
        }
    }
    
    /// Updates the last message (used when streaming completes)
    func updateLastMessage(_ message: ChatMessage) {
        lastMessage = message
    }
}

struct LiveUpdateStack: View {
    let message: ChatMessage
    @Binding var currentNotification: NotificationData?
    @Binding var isExpanded: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        // Helper to check if text would exceed 3 lines
        let estimatedLineCount = Typography.estimateLineCount(for: message.text, font: UIFont.systemFont(ofSize: 15), maxWidth: UIScreen.main.bounds.width - 80)
        let shouldShowExpandButton = estimatedLineCount > 5
        let bkgColor = message.isUser ? Color("AccentColor") : Color("onBkgTextColor30")
        
        return VStack {
            Spacer()
            if let notification = currentNotification {
                ProgressNotificationBanner(
                    notification: notification,
                    onNotificationDismiss: {
                        currentNotification = nil
                    }
                )
            }
            HStack {
                
                // Message bubble with text and dismiss button overlay
                ZStack(alignment: .topTrailing) {
                    // Message bubble with text
                    VStack(alignment: .leading, spacing: 0) {
                        Text(message.text)
                            .bodyText()
                            .padding(.horizontal, Spacing.current.spaceXs)
                            .padding(.vertical, Spacing.current.space2xs)
                            .foregroundColor(Color("AppBkgColor"))
                            .background(bkgColor)
                            .cornerRadius(Spacing.current.spaceS)
                            .lineLimit(isExpanded ? nil : 5)
                            
                        
                        // Expand/Collapse button - only show if text is longer than 3 lines
                        if shouldShowExpandButton {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isExpanded.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(isExpanded ? "Show less" : "Show more")
                                            .bodyText(size: .articleMinus1)
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .bodyText(size: .articleMinus1)
                                    }
                                    .foregroundColor(Color("onBkgTextColor10"))
                                    
                                    .padding(.horizontal, Spacing.current.space2xs)
                                    .padding(.vertical, Spacing.current.space3xs)
                                }
                                .padding(.trailing, Spacing.current.space2xs)
                                .padding(.bottom, Spacing.current.space3xs)
                            }
                        }
                    }
                    .background(bkgColor)
                    .cornerRadius(Spacing.current.spaceXs)
                    
                    // Dismiss button positioned at upper right corner, overlapping the border
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onDismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("AppBkgColor"))
                            .padding(Spacing.current.space2xs)
                            .background(bkgColor)
                            .clipShape(Circle())
                    }
                    .padding(.top, -6)
                    .padding(.trailing, -6)
                }
                
                .padding(.horizontal, Spacing.current.spaceXs)
                Spacer()
            }
        }
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
        .background(Color.clear)
    }
}

