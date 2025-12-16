import SwiftUI

struct ChatInputBar: View {
    let selectedTab: PreviewTabSelection
    @Binding var draftMessage: String
    @Binding var inputLocation: String
    @FocusState.Binding var isTextFieldFocused: Bool
    let isAuthenticated: Bool
    let isLoading: Bool
    let onSendMessage: () -> Void
    let onSwitchToChat: () -> Void
    
    // Computed property to determine if send button should be disabled
    private var isSendDisabled: Bool {
        draftMessage.isEmpty || !isAuthenticated || isLoading
    }
    
    var body: some View {
        HStack(spacing: Spacing.current.spaceXs) {
            TextField(
                selectedTab == .map ? "Find any place..." : "Ask any thing...",
                text: selectedTab == .map ? $inputLocation : $draftMessage
            )
                .bodyText()
                .focused($isTextFieldFocused)
                .submitLabel(selectedTab == .map ? .search : .send)
                .onSubmit {
                    if selectedTab != .map && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSendMessage()
                    }
                }
                .padding(.horizontal, Spacing.current.spaceXs)
                .padding(.vertical, Spacing.current.space2xs)
                .background(Color("AppBkgColor"))
                .cornerRadius(Spacing.current.spaceXs)

            if selectedTab != .chat && selectedTab != .map {
                Button(action: onSwitchToChat) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .bodyText(size: .article0)
                        .foregroundColor(Color("onBkgTextColor30"))
                }
            }
            if selectedTab != .map {
                Button(action: onSendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .bodyText(size: .article2)
                        .foregroundColor(isSendDisabled ? Color("onBkgTextColor30") : Color("onBkgTextColor10"))
                }
                .disabled(isSendDisabled)
            }
        }
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.space2xs)
        .background(
            Color("AppBkgColor")
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

