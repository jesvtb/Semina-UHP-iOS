import SwiftUI

// MARK: - Input Tab Selection
enum InputTabSelection: Int, CaseIterable {
    case journey = 0
    case map = 1
    case chat = 2
    case profile = 3
}

struct TestMainView: View {
    @State private var messages: [String] = ["Hello", "How can I help?"]
    @State private var draftMessage: String = ""
    @State private var selectedTab: InputTabSelection = .journey
    @FocusState private var isTextFieldFocused: Bool
    @State private var geoJSONData: [String: Any]?
    @State private var geoJSONUpdateTrigger: UUID = UUID()
    private let tabs: [(name: String, selectedIcon: String, unselectedIcon: String)] = [
        ("Journey", "signpost.right.and.left.fill", "signpost.right.and.left"),
        ("Map", "map.fill", "map"),
        ("Ask", "questionmark.bubble.fill", "questionmark.bubble"),
        ("You", "person.fill", "person")
    ]

    var body: some View {
        ZStack {
            // Background stays fixed
            // Color("AccentColor")
            //     .ignoresSafeArea(.container)
            //     .ignoresSafeArea(.keyboard)

            MapboxMapView(geoJSONData: $geoJSONData, geoJSONUpdateTrigger: $geoJSONUpdateTrigger)
                .ignoresSafeArea(.container)
                .ignoresSafeArea(.keyboard)
            // Main content (messages list)
            if selectedTab == .chat {
                VStack {
                    ChatDetailView(messages: messages)

                    Spacer(minLength: 0) // keeps list separate from inset
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Dismiss keyboard when tapping outside safeAreaInset
                    isTextFieldFocused = false
                }
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
                    .background(Color("onBkgTextColor60")),
                alignment: .top
            )
        }
    }

    private var tabSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(Array(InputTabSelection.allCases.enumerated()), id: \.element) { index, tabCase in
                let tab = tabs[index]
                TabBarButton(
                    selectedIcon: tab.selectedIcon,
                    unselectedIcon: tab.unselectedIcon,
                    label: tab.name,
                    isSelected: selectedTab == tabCase,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tabCase
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 8)
        .background(Color(.systemBackground).opacity(0.5))
    }
    
    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask any thing...", text: $draftMessage, axis: .vertical)
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