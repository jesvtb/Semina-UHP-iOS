import SwiftUI
import MarkdownUI


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
    .background(Color("AppBkgColor"))
    .padding(.horizontal, Spacing.current.space2xs)
}

// #Preview("Latest Message Bubble") {
//     VStack {
//         liveUpdateStack(message: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false), isExpanded: .constant(false), onDismiss: {})
//     }
//     .padding(.horizontal, Spacing.current.space2xs)
// }

