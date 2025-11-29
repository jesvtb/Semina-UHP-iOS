import SwiftUI

struct ChatDetailView: View {
    let messages: [ChatMessage]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        Text(message.text)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(message.id)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 8) // extra space above input bar
            }
            .onChange(of: messages.count) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .background(Color("onBkgTextColor60"))
        }
    }
}

