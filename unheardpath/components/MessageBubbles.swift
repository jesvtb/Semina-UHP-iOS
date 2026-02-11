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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.current.spaceXs)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var selectedURL: URL?

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

    /// Distinctive color for hyperlinks so they stand out from body text.
    private var linkColor: Color {
        message.isUser ? Color("AppBkgColor") : Color("AccentColor")
    }

    /// Convert an integer to Unicode superscript digits (e.g. 1 → "¹", 12 → "¹²").
    private func superscriptNumber(_ n: Int) -> String {
        let superscripts: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]
        return String(String(n).map { superscripts[$0] ?? $0 })
    }

    /// Preprocessed markdown: adds superscript footnote numbers to inline
    /// links, and appends a numbered "Sources" reference section at the bottom.
    private var formattedText: String {
        guard !message.isUser else { return message.text }

        let linkPattern = /\[([^\]]+)\]\(([^\)]+)\)/
        let matches = Array(message.text.matches(of: linkPattern))

        guard !matches.isEmpty else { return message.text }

        // Replace inline links with superscript reference number
        var result = ""
        var lastEnd = message.text.startIndex
        for (index, match) in matches.enumerated() {
            result += message.text[lastEnd..<match.range.lowerBound]
            result += "[\(match.1) \(superscriptNumber(index + 1))](\(match.2))"
            lastEnd = match.range.upperBound
        }
        result += message.text[lastEnd...]

        // Append numbered references footer
        result += "\n\n---\n\n**Sources**\n\n"
        for (index, match) in matches.enumerated() {
            result += "\(index + 1). [\(match.1)](\(match.2))\n"
        }

        return result
    }

    /// Custom MarkdownUI theme built from the bubble's color properties.
    /// Using `Theme` avoids long View modifier chains that hit the Swift type-checker limit.
    private var markdownTheme: Theme {
        Theme()
            .text {
                ForegroundColor(bodyColor)
            }
            .code {
                ForegroundColor(bodyColor)
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .link {
                ForegroundColor(linkColor)
                UnderlineStyle(.single)
            }
            .strong {
                ForegroundColor(emphasisColor)
                FontWeight(.semibold)
            }
            .emphasis {
                ForegroundColor(emphasisColor)
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: 0, bottom: 8)
            }
            .blockquote { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.bodyColor)
                    }
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.emphasisColor)
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.emphasisColor)
                        FontWeight(.semibold)
                        FontSize(.em(1.25))
                    }
                    .markdownMargin(top: 6, bottom: 6)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.emphasisColor)
                        FontWeight(.semibold)
                        FontSize(.em(1.1))
                    }
                    .markdownMargin(top: 4, bottom: 2)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.emphasisColor)
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 4, bottom: 2)
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.emphasisColor)
                        FontWeight(.semibold)
                        FontSize(.em(0.9))
                    }
                    .markdownMargin(top: 2, bottom: 2)
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.emphasisColor)
                        FontWeight(.semibold)
                        FontSize(.em(0.85))
                    }
                    .markdownMargin(top: 2, bottom: 2)
            }
            .thematicBreak {
                Divider()
                    .markdownMargin(top: 8, bottom: 4)
            }
            .list { configuration in
                configuration.label
                    .markdownMargin(top: 4, bottom: 8)
            }
            .listItem { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(self.bodyColor)
                    }
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: .em(0.25))
            }
    }

    var body: some View {
        if !message.text.isEmpty {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: Spacing.current.space2xs) {
        HStack(spacing: 0) {
            if message.isUser {
                Spacer()
            }
            Markdown(formattedText)
                .markdownTheme(markdownTheme)
                .environment(\.openURL, OpenURLAction { url in
                    selectedURL = url
                    return .handled
                })
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
        .sheet(isPresented: Binding(
            get: { selectedURL != nil },
            set: { if !$0 { selectedURL = nil } }
        )) {
            if let url = selectedURL {
                SafariView(url: url)
            }
        }
        
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
        MessageBubble(message: ChatMessage(text: "", isUser: false, isStreaming: true))
        MessageBubble(message: ChatMessage(text: "Parturient nisl curabitur condimentum imperdiet primis congue ex phasellus ridiculus enim blandit ipsum, aenean efficitur etiam diam feugiat senectus fermentum at egestas nunc.", isUser: true, isStreaming: false))
        MessageBubble(message: ChatMessage(text: "## Ridiculus tellus\n\nplacerat massa euismod arcu amet mus suscipit conubia cubilia nascetur, **taciti iaculis** augue leo curae sagittis laoreet parturient risus orci dictumst praesent\n\n- [Duck Duck Go](https://duckduckgo.com) magna tempus dolor lectus\n\n- elitatea ac sapien nunc praesent etiam ultricies habitasse nisl habitant\n\n- suscipit vulputate, sed dis lobortis diam ut cubilia blandit aptent aenean quisque placerat.", isUser: false, isStreaming: false))
        MessageBubble(message: ChatMessage(text: "Parturient nisl curabitur condimentum imperdiet primis congue ex phasellus ridiculus enim blandit ipsum, aenean efficitur etiam diam feugiat senectus fermentum at egestas nunc.", isUser: true, isStreaming: false))
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

