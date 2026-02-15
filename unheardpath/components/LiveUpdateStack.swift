import SwiftUI
import core

struct LiveUpdateStack: View {
    let message: ChatMessage?
    @Binding var currentToastData: ToastData?
    @Binding var isExpanded: Bool
    let onDismiss: () -> Void

    @ObservedObject var stretchableInputVM: StretchableInputViewModel
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var autocompleteManager: AutocompleteManager

    /// Callback fired when the user selects a cached location from the list.
    let onLocationSelected: (LocationDetailData) -> Void
    /// Callback fired when the user selects an autocomplete search result.
    let onAutocompleteResultSelected: (MapSearchResult) -> Void

    /// Whether the switch-to-chat button is visible.
    let isChatButtonVisible: Bool
    /// Callback fired when the user taps the switch-to-chat button.
    let onSwitchToChat: () -> Void
    /// Whether the switch-to-journey button is visible.
    let isJourneyButtonVisible: Bool
    /// Callback fired when the user taps the switch-to-journey button.
    let onSwitchToJourney: () -> Void

    /// Horizontal drag offset for swipe-to-dismiss on the message bubble.
    @State private var messageDragOffset: CGFloat = 0

    /// Whether the autocomplete location list should be visible
    private var showAutocompleteList: Bool {
        stretchableInputVM.inputMode == .autocomplete
            && stretchableInputVM.isStretched
            && (!eventManager.getSearchedLocations().isEmpty || !autocompleteManager.searchResults.isEmpty)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: Tab-switching buttons (bottom z-layer, hidden when overlays appear)
            VStack {
                Spacer()
                if isChatButtonVisible {
                    HStack {
                        Spacer()
                        Button(action: onSwitchToChat) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .bodyText(size: .article0)
                                .foregroundColor(Color("onBkgTextColor30"))
                        }
                    }
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .padding(.bottom, Spacing.current.space3xs)
                    .transition(.scale.combined(with: .opacity))
                }

                if isJourneyButtonVisible {
                    HStack {
                        Spacer()
                        Button(action: onSwitchToJourney) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .bodyText(size: .article0)
                                .foregroundColor(Color("onBkgTextColor30"))
                        }
                    }
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .padding(.bottom, Spacing.current.space3xs)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // MARK: Overlays (top z-layer — covers tab buttons when visible)
            VStack {
                Spacer()

                // MARK: Toast
                if let toastData = currentToastData {
                    ToastView(
                        toastData: toastData,
                        onToastDimiss: {
                            currentToastData = nil
                        }
                    )
                }

                // MARK: Message bubble
                if let message = message {
                    messageBubble(message: message)
                }

                // MARK: Autocomplete context menu (expands upward above input bar)
                if showAutocompleteList {
                    LocationListMenu(
                        cachedLocations: eventManager.getSearchedLocations(),
                        autocompleteResults: autocompleteManager.searchResults,
                        onSelectCached: { location in
                            onLocationSelected(location)
                            stretchableInputVM.inputLocation = ""
                            withAnimation(.easeInOut(duration: 0.25)) {
                                stretchableInputVM.isStretched = false
                            }
                        },
                        onSelectAutocomplete: { result in
                            onAutocompleteResultSelected(result)
                            stretchableInputVM.inputLocation = ""
                            withAnimation(.easeInOut(duration: 0.25)) {
                                stretchableInputVM.isStretched = false
                            }
                        }
                    )
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .padding(.bottom, Spacing.current.space3xs)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.0, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.0, anchor: .bottom).combined(with: .opacity)
                    ))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showAutocompleteList)
        .background(Color.clear)
    }

    // MARK: - Message Bubble

    /// Threshold (in points) beyond which the swipe commits to dismiss.
    private let swipeDismissThreshold: CGFloat = 80

    @ViewBuilder
    private func messageBubble(message: ChatMessage) -> some View {
        let estimatedLineCount = Typography.estimateLineCount(for: message.text, font: UIFont.systemFont(ofSize: 15), maxWidth: UIScreen.main.bounds.width - 80)
        let shouldShowExpandButton = estimatedLineCount > 5
        let bkgColor = message.isUser ? Color("AccentColor") : Color("onBkgTextColor30")

        HStack {
            // Message bubble with text and dismiss button overlay
            ZStack(alignment: .topTrailing) {
                // Message bubble with text
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.text)
                        .bodyText()
                        .padding(.horizontal, Spacing.current.spaceXs)
                        .padding(.vertical, Spacing.current.space2xs)
                        .foregroundColor(Color("AppBkgColor"))
                        .background(bkgColor)
                        .cornerRadius(Spacing.current.spaceS)
                        .lineLimit(isExpanded ? nil : 5)

                    // Expand/Collapse button - only show if text is longer than 5 lines
                    if shouldShowExpandButton {
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isExpanded.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(isExpanded ? "Show less" : "Show more")
                                        .bodyText(size: .articleMinus1)
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .bodyText(size: .articleMinus1)
                                }
                                .foregroundColor(Color("onBkgTextColor10"))
                                .padding(.horizontal, Spacing.current.space2xs)
                                .padding(.vertical, Spacing.current.space3xs)
                            }
                            .padding(.trailing, Spacing.current.space2xs)
                            .padding(.bottom, Spacing.current.space3xs)
                        }
                    }
                }
                .background(bkgColor)
                .cornerRadius(Spacing.current.spaceXs)

                // Dismiss button – contrasting dark circle for clear visibility
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .padding(.top, -8)
                .padding(.trailing, -8)
            }
            .padding(.horizontal, Spacing.current.spaceXs)
            Spacer()
        }
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
        // Swipe-to-dismiss: drag left to dismiss
        .offset(x: messageDragOffset)
        .opacity(1 - min(abs(messageDragOffset) / (swipeDismissThreshold * 2), 0.6))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    // Only allow leftward drag
                    if value.translation.width < 0 {
                        messageDragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width < -swipeDismissThreshold {
                        // Commit dismiss: slide fully off-screen then call onDismiss
                        withAnimation(.easeOut(duration: 0.2)) {
                            messageDragOffset = -UIScreen.main.bounds.width
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                            messageDragOffset = 0
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            messageDragOffset = 0
                        }
                    }
                }
        )
    }
}
