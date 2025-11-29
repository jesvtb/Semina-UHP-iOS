import SwiftUI

struct TestMainView: View {
    @State private var messages: [String] = ["Hello", "How can I help?"]
    @State private var draftMessage: String = ""
    @State private var selectedTab: Int = 0
    @FocusState private var isTextFieldFocused: Bool
    
    private let tabs: [(name: String, icon: String)] = [
        ("Text", "text.bubble"),
        ("Voice", "mic.fill"),
        ("Image", "photo"),
        ("More", "ellipsis")
    ]

    var body: some View {
        ZStack {
            // Background stays fixed
            Color("AccentColor")
                .ignoresSafeArea(.container)
                .ignoresSafeArea(.keyboard)

            // Main content (messages list)
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                Text(message)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 8) // extra space above input bar
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(messages.indices.last, anchor: .bottom)
                        }
                    }
                }

                Spacer(minLength: 0) // keeps list separate from inset
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Dismiss keyboard when tapping outside safeAreaInset
                isTextFieldFocused = false
            }
        }
        // Input bar pinned to bottom; moves with keyboard
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // Tab selector
                
                // Chat input bar
                chatInputBar
                tabSelectorView
            }
            .background(.ultraThinMaterial)
            .overlay(
                Divider()
                    .background(Color(UIColor.separator)),
                alignment: .top
            )
        }
    }

    private var tabSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = index
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.name)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(selectedTab == index ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == index
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
                
                if index < tabs.count - 1 {
                    Divider()
                        .frame(height: 20)
                        .background(Color(UIColor.separator))
                }
            }
        }
        .padding(.horizontal, 8)
        .background(Color(.systemBackground).opacity(0.5))
    }
    
    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Gemini", text: $draftMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(draftMessage.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                    .clipShape(Circle())
            }
            .disabled(draftMessage.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color(.systemBackground)
                .opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func sendMessage() {
        guard draftMessage.isEmpty == false else { return }
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        messages.append(text)
        draftMessage = ""
        isTextFieldFocused = false // Dismiss keyboard after sending
    }
}