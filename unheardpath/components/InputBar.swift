import SwiftUI
import CoreLocation
import core

struct InputBar: View {
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
                        isTextFieldFocused = false
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
                Button(action: {
                    isTextFieldFocused = false
                    onSendMessage()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .bodyText(size: .article2)
                        .foregroundColor(isSendDisabled ? Color("onBkgTextColor30") : Color("onBkgTextColor10"))
                }
                .disabled(isSendDisabled)
            }
        }
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.space2xs)
        .padding(.horizontal, Spacing.current.spaceS)
        .padding(.vertical, Spacing.current.spaceXs)
        .background(
            RoundedRectangle(cornerRadius: Spacing.current.spaceM)
                .fill(Color("AppBkgColor"))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
                .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: -4)
        )
    }
}

// MARK: - StretchableInput

enum InputMode: String {
    case freestyle
    case autocomplete
}

@MainActor
class StretchableInputViewModel: ObservableObject {
    @Published var isStretched: Bool = false
    @Published var inputMode: InputMode = .freestyle
    @Published var inputLocation: String = ""

    /// Callback fired when the user submits a message in freestyle mode.
    var onSendMessage: (() -> Void)?
}

// MARK: - StretchableInput

struct StretchableInput: View {
    @ObservedObject var viewModel: StretchableInputViewModel
    @Binding var draftMessage: String
    @FocusState private var isTextFieldFocused: Bool
    @State private var containerWidth: CGFloat = 0

    /// Stretched TextField width as a fraction of the parent
    private let stretchedTextFieldWidthFraction: CGFloat = 0.95
    /// Default (collapsed) TextField width as a fraction of the parent
    private let defaultTextFieldWidthFraction: CGFloat = 0.45

    private var isEffectivelyStretched: Bool {
        viewModel.isStretched || isTextFieldFocused
    }

    /// The active text binding: `inputLocation` in autocomplete mode, `draftMessage` in freestyle.
    private var activeText: Binding<String> {
        viewModel.inputMode == .autocomplete
            ? $viewModel.inputLocation
            : $draftMessage
    }
    
    private var mapToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if viewModel.inputMode == .autocomplete {
                    // Switching from autocomplete to freestyle
                    draftMessage = viewModel.inputLocation
                    viewModel.inputMode = .freestyle
                } else {
                    // Switching from freestyle to autocomplete
                    viewModel.inputLocation = draftMessage
                    viewModel.inputMode = .autocomplete
                }
            }
        } label: {
            Image(systemName: viewModel.inputMode == .autocomplete ? "map.fill" : "map")
                .bodyText(size: .article0)
                .foregroundColor(
                    viewModel.inputMode == .autocomplete
                        ? Color("onReverseBkgColor10")
                        : Color("onReverseBkgColor50")
                )
        }
        .frame(maxHeight: .infinity, alignment: isEffectivelyStretched ? .bottom : .center)
        .padding(.bottom, isEffectivelyStretched ? Spacing.current.space3xs : 0)
        .animation(.easeInOut(duration: 0.25), value: isEffectivelyStretched)
    }
    
    private var textField: some View {
        TextField(
            viewModel.inputMode == .autocomplete
                ? "Locate..."
                : "Ask...",
            text: activeText,
            prompt: Text(viewModel.inputMode == .autocomplete ? "Locate..." : "Ask...")
                .foregroundColor(Color("onReverseBkgColor50")),
            axis: .vertical
        )
        .lineLimit(isEffectivelyStretched ? 1...6 : 1...1)
        .bodyText()
        .foregroundColor(Color("onReverseBkgColor10"))
        .tint(Color("AccentColor"))
        .focused($isTextFieldFocused)
        .submitLabel(viewModel.inputMode == .autocomplete ? .search : .send)
        .onSubmit {
            if viewModel.inputMode == .freestyle && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isTextFieldFocused = false
                viewModel.onSendMessage?()
            }
        }
        .padding(.trailing, viewModel.inputMode == .freestyle && !draftMessage.isEmpty && isEffectivelyStretched
            ? Spacing.current.spaceL : 0)
        .overlay(alignment: .trailing) {
            // Send button — inside the text field, aligned to trailing edge
            if viewModel.inputMode == .freestyle && !draftMessage.isEmpty && isEffectivelyStretched {
                Button {
                    isTextFieldFocused = false
                    viewModel.onSendMessage?()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .bodyText(size: .article2)
                        .foregroundColor(Color("onReverseBkgColor10"))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, Spacing.current.space3xs)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: draftMessage.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: isEffectivelyStretched)
    }
    
    private var inputContent: some View {
        HStack(spacing: Spacing.current.spaceXs) {
            mapToggleButton
            textField
            
            // Invisible spacer to balance the map button on the left
            if !isEffectivelyStretched {
                Image(systemName: "map")
                    .bodyText(size: .article0)
                    .hidden()
            }
        }
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.spaceXs)
    }

    var body: some View {
        inputContent
        .frame(
            width: containerWidth > 0
                ? containerWidth * (isEffectivelyStretched
                    ? stretchedTextFieldWidthFraction
                    : defaultTextFieldWidthFraction)
                : nil
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Spacing.current.spaceM)
                .fill(Color("ReverseBkgColor"))
                .shadow(
                    color: Color.black.opacity(isTextFieldFocused ? 0.35 : 0.20),
                    radius: isTextFieldFocused ? 12 : 8,
                    x: 0,
                    y: isTextFieldFocused ? 4 : 2
                )
        )
        .frame(maxWidth: .infinity, minHeight: Spacing.current.spaceXl, alignment: .bottom)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { newWidth in
                        containerWidth = newWidth
                    }
            }
        )
        .animation(.easeInOut(duration: 0.25), value: isEffectivelyStretched)
        .animation(.easeInOut(duration: 0.25), value: isTextFieldFocused)
        .onChange(of: isTextFieldFocused) { isFocused in
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.isStretched = isFocused
            }
        }
        .onChange(of: viewModel.isStretched) { isStretched in
            if !isStretched {
                isTextFieldFocused = false
            }
        }
        .onChange(of: viewModel.inputMode) { inputMode in
            if inputMode == .autocomplete {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.isStretched = true
                }
                isTextFieldFocused = true
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.isStretched = true
            }
            isTextFieldFocused = true
        }
    }
   
}

// MARK: - StretchableInput Preview

#Preview("StretchableInput") {
    struct StretchableInputPreviewWrapper: View {
        @StateObject private var viewModel = StretchableInputViewModel()
        @State private var draftMessage: String = ""

        var body: some View {
            VStack(spacing: Spacing.current.spaceM) {
                Spacer()

                Text("isStretched: \(viewModel.isStretched ? "true" : "false")")
                    .font(.caption)
                Text("inputMode: \(viewModel.inputMode.rawValue)")
                    .font(.caption)

                Toggle("Stretch externally", isOn: $viewModel.isStretched)
                    .padding(.horizontal)

                Toggle("Autocomplete mode", isOn: Binding(
                    get: { viewModel.inputMode == .autocomplete },
                    set: { viewModel.inputMode = $0 ? .autocomplete : .freestyle }
                ))
                .padding(.horizontal)

                StretchableInput(
                    viewModel: viewModel,
                    draftMessage: $draftMessage
                )
            }
            .padding()
            .background(Color.white)
        }
    }

    return StretchableInputPreviewWrapper()
}
