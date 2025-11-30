import SwiftUI


struct MessageBubble: View {
    let message: ChatMessage
    
    private var messageWidth: CGFloat {
        UIScreen.main.bounds.width - Spacing.current.spaceXl
    }

    var body: some View {
        if !message.text.isEmpty {
        HStack(spacing: 0) {
            if message.isUser {
                Spacer()
            }
            Text(message.text)
                .bodyText()
                .padding(.horizontal, Spacing.current.spaceXs)
                .padding(.vertical, Spacing.current.space2xs)
                .foregroundColor(message.isUser ? Color("AppBkgColor") : Color("onBkgTextColor20"))
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
        MessageBubble(message: ChatMessage(text: "Ridiculus tellus placerat massa euismod arcu amet mus suscipit conubia cubilia nascetur, taciti iaculis augue leo curae sagittis laoreet parturient risus orci dictumst praesent, ut felis nullam ornare aptent aenean magna tempus dolor lectus. Magna platea ac sapien nunc praesent etiam ultricies habitasse nisl habitant suscipit vulputate, sed dis lobortis diam ut cubilia blandit aptent aenean quisque placerat.", isUser: false, isStreaming: false))
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

