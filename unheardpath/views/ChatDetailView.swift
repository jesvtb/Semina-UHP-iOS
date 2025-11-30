import SwiftUI

struct ChatDetailView: View {
    let messages: [ChatMessage]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                    // Bottom anchor for scrolling
                    Color.clear
                        .frame(height: Spacing.current.spaceM)
                        .id("bottom-anchor")
                    
                    // Final anchor at the very bottom for spacing
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-spacer")
                }
                .padding(.top, Spacing.current.spaceM)
                .padding(.horizontal, Spacing.current.space2xs)
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
            .background(Color("AppBkgColor"))
        }
    }
    
    // MARK: - Scroll Handlers
    private func handleInitialScroll(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let lastMessage = messages.last {
                withAnimation {
                    proxy.scrollTo("bottom-spacer", anchor: .bottom)
                }
            } else {
                withAnimation {
                    proxy.scrollTo("bottom-spacer", anchor: .bottom)
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
                proxy.scrollTo("bottom-spacer", anchor: .bottom)
            }
        }
    }
}

