import SwiftUI
import MarkdownUI
import core

// MARK: - Message Reaction Buttons

/// Right-aligned group of reaction buttons (dislike, like, bookmark) for assistant messages.
/// Sends chat_liked / chat_disliked / chat_bookmarked events with message_id; toggles to fill icon on tap.
struct MessageReactions: View {
    let message: ChatMessage
    @EnvironmentObject private var eventManager: EventManager
    @State private var isDisliked = false
    @State private var isLiked = false
    @State private var isBookmarked = false

    private func sendChatReaction(evtType: String) {
        let evtData: [String: JSONValue] = ["message_id": .string(message.id.uuidString)]
        let event = UserEventBuilder.build(
            evtType: evtType,
            evtData: evtData,
            sessionId: eventManager.sessionId
        )
        Task {
            do {
                _ = try await eventManager.addEvent(event)
            } catch {
                AppLifecycleManager.sharedLogger.error(
                    "Failed to send \(evtType)",
                    handlerType: "MessageReactions",
                    error: error
                )
            }
        }
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: Spacing.current.space2xs) {
                Button {
                    isDisliked = true
                    sendChatReaction(evtType: "chat_disliked")
                } label: {
                    Image(systemName: isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: Spacing.current.spaceXs))
                        .foregroundColor(Color("onBkgTextColor30"))
                }
                .buttonStyle(.plain)
                Button {
                    isLiked = true
                    sendChatReaction(evtType: "chat_liked")
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: Spacing.current.spaceXs))
                        .foregroundColor(Color("onBkgTextColor30"))
                }
                .buttonStyle(.plain)
                Button {
                    isBookmarked = true
                    sendChatReaction(evtType: "chat_bookmarked")
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: Spacing.current.spaceXs))
                        .foregroundColor(Color("onBkgTextColor30"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.current.spaceXs)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var messageWidth: CGFloat {
        UIScreen.main.bounds.width - Spacing.current.spaceXl
    }

    /// Color for body text, blockquote, and normal content.
    private var bodyColor: Color {
        message.isUser ? Color("AppBkgColor") : Color("onBkgTextColor30")
    }

    /// Color for headings, italic (*emphasis*), and strong/bold (**bold**).
    private var emphasisColor: Color {
        message.isUser ? Color("AppBkgColor") : Color("onBkgTextColor20")
    }

    var body: some View {
        if !message.text.isEmpty {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: Spacing.current.space2xs) {
        HStack(spacing: 0) {
            if message.isUser {
                Spacer()
            }
            Markdown(message.text)
                .markdownTextStyle(\.text) {
                    ForegroundColor(bodyColor)
                }
                .markdownTextStyle(\.code) {
                    ForegroundColor(bodyColor)
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
                .markdownTextStyle(\.link) {
                    ForegroundColor(bodyColor)
                }
                .markdownTextStyle(\.strong) {
                    ForegroundColor(emphasisColor)
                    FontWeight(.semibold)
                }
                .markdownTextStyle(\.emphasis) {
                    ForegroundColor(emphasisColor)
                }
                .markdownBlockStyle(\.paragraph) { configuration in
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.25))
                        .markdownMargin(top: 0, bottom: 8)
                }
                .markdownBlockStyle(\.blockquote) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(bodyColor)
                        }
                }
                .markdownBlockStyle(\.heading1) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(emphasisColor)
                            FontWeight(.semibold)
                            FontSize(.em(1.5))
                        }
                        .markdownMargin(top: 8, bottom: 4)
                }
                .markdownBlockStyle(\.heading2) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(emphasisColor)
                            FontWeight(.semibold)
                            FontSize(.em(1.25))
                        }
                        .markdownMargin(top: 6, bottom: 6)
                }
                .markdownBlockStyle(\.heading3) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(emphasisColor)
                            FontWeight(.semibold)
                            FontSize(.em(1.1))
                        }
                        .markdownMargin(top: 4, bottom: 2)
                }
                .markdownBlockStyle(\.heading4) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(emphasisColor)
                            FontWeight(.semibold)
                        }
                        .markdownMargin(top: 4, bottom: 2)
                }
                .markdownBlockStyle(\.heading5) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(emphasisColor)
                            FontWeight(.semibold)
                            FontSize(.em(0.9))
                        }
                        .markdownMargin(top: 2, bottom: 2)
                }
                .markdownBlockStyle(\.heading6) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(emphasisColor)
                            FontWeight(.semibold)
                            FontSize(.em(0.85))
                        }
                        .markdownMargin(top: 2, bottom: 2)
                }
                .markdownBlockStyle(\.list) { configuration in
                    configuration.label
                        .markdownMargin(top: 4, bottom: 8)
                }
                .markdownBlockStyle(\.listItem) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(bodyColor)
                        }
                        .relativeLineSpacing(.em(0.25))
                        .markdownMargin(top: .em(0.25))
                }
                .padding(.horizontal, Spacing.current.spaceXs)
                .padding(.vertical, Spacing.current.space2xs)
                .background(message.isUser ? Color("onBkgTextColor30") : Color("AppBkgColor"))
                .cornerRadius(Spacing.current.spaceS)
                .frame(maxWidth: message.isUser ? messageWidth : .infinity, alignment: message.isUser ? .trailing : .leading)
            if !message.isUser {
                Spacer()
            }
        }
        if !message.isUser {
            MessageReactions(message: message)
        }
        }
        .id(message.id)
        
        }
        else {
            ProgressView()
            .padding(.vertical, Spacing.current.spaceXs)
            .padding(.horizontal, Spacing.current.spaceXs)
                .frame(maxWidth: message.isUser ? messageWidth : .infinity, alignment: message.isUser ? .trailing : .leading)
            .id(message.id)
        }
    }
}

#Preview("Message Bubble") {
    VStack {
        MessageBubble(message: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false))
        MessageBubble(message: ChatMessage(text: "Parturient nisl curabitur condimentum imperdiet primis congue ex phasellus ridiculus enim blandit ipsum, aenean efficitur etiam diam feugiat senectus fermentum at egestas nunc.", isUser: true, isStreaming: false))
        MessageBubble(message: ChatMessage(text: "", isUser: false, isStreaming: true))
        MessageBubble(message: ChatMessage(text: "## Ridiculus tellus\n\nplacerat massa euismod arcu amet mus suscipit conubia cubilia nascetur, **taciti iaculis** augue leo curae sagittis laoreet parturient risus orci dictumst praesent\n\n- ut felis nullam ornare aptent aenean magna tempus dolor lectus\n\n- elitatea ac sapien nunc praesent etiam ultricies habitasse nisl habitant\n\n- suscipit vulputate, sed dis lobortis diam ut cubilia blandit aptent aenean quisque placerat.", isUser: false, isStreaming: false))
        MessageBubble(message: ChatMessage(text: "## Ridiculus tellus\n\n**Step 1**: \n\nplacerat massa euismod arcu amet mus suscipit conubia cubilia nascetur\n\n**Step 2**: \n\n**taciti iaculis** augue leo curae sagittis laoreet parturient risus orci dictumst praesent \n\n**Step 3**: \n\nfelis nullam ornare aptent aenean magna tempus dolor lectus", isUser: false, isStreaming: false))
    }
    .environmentObject(EventManager())
    .background(Color("AppBkgColor"))
    .padding(.horizontal, Spacing.current.space2xs)
}

// #Preview("Latest Message Bubble") {
//     VStack {
//         liveUpdateStack(message: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false), isExpanded: .constant(false), onDismiss: {})
//     }
//     .padding(.horizontal, Spacing.current.space2xs)
// }

