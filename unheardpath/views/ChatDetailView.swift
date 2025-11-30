import SwiftUI

struct ChatDetailView: View {
    let messages: [ChatMessage]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        HStack {
                            if message.isUser {
                                Spacer()
                            }
                            
                            Text(message.text)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(message.isUser ? Color.blue : Color(.secondarySystemBackground))
                                .foregroundColor(message.isUser ? .white : .primary)
                                .cornerRadius(16)
                            
                            if !message.isUser {
                                Spacer()
                            }
                        }
                        .id(message.id)
                    }
                    // Bottom anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                }
                .padding(.top, 16)
                .padding(.horizontal, 8)
                .padding(.bottom, 8) // extra space above input bar
            }
            .onAppear {
                handleInitialScroll(proxy: proxy)
            }
            .onChange(of: messages.count) { _ in
                handleMessageCountChange(proxy: proxy)
            }
            .onChange(of: messages.last?.text) { _ in
                handleLastMessageTextChange(proxy: proxy)
            }
            .background(Color("onBkgTextColor60"))
        }
    }
    
    // MARK: - Scroll Handlers
    private func handleInitialScroll(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let lastMessage = messages.last {
                withAnimation {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            } else {
                withAnimation {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
        }
    }
    
    private func handleMessageCountChange(proxy: ScrollViewProxy) {
        guard !messages.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let lastMessage = messages.last {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func handleLastMessageTextChange(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

