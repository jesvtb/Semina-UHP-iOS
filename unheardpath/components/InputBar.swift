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

// MARK: - StretchableInput

enum InputMode: String {
    case freestyle
    case autocomplete
}

@MainActor
class StretchableInputViewModel: ObservableObject {
    @Published var isStretched: Bool = false
    @Published var inputMode: InputMode = .freestyle
    @Published var locations: [LocationDetailData] = []
}

// MARK: - LocationListMenu

struct LocationListMenu: View {
    let locations: [LocationDetailData]
    let onSelect: (LocationDetailData) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Recent Locations")
                .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                .foregroundColor(Color("onBkgTextColor30"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.current.spaceS)
                .padding(.top, Spacing.current.spaceS)
                .padding(.bottom, Spacing.current.spaceXs)

            Divider()
                .padding(.leading, Spacing.current.spaceS)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(
                        Array(locations.enumerated()),
                        id: \.offset
                    ) { index, location in
                        Button {
                            onSelect(location)
                        } label: {
                            HStack(spacing: Spacing.current.spaceXs) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("AccentColor"))

                                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                                    Text(location.placeName ?? "Unknown place")
                                        .font(.custom(FontFamily.sansRegular, size: TypographyScale.article0.baseSize))
                                        .foregroundColor(Color("onBkgTextColor10"))

                                    if let subdivisions = location.subdivisions {
                                        Text(subdivisions)
                                            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                                            .foregroundColor(Color("onBkgTextColor30"))
                                    }
                                }

                                Spacer()

                                if let countryCode = location.countryCode,
                                   let flagImage = CountryFlag.image(for: countryCode) {
                                    flagImage
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: Spacing.current.spaceS)
                                }
                            }
                            .padding(.horizontal, Spacing.current.spaceS)
                            .padding(.vertical, Spacing.current.spaceXs)
                        }

                        if index < locations.count - 1 {
                            Divider()
                                .padding(.leading, Spacing.current.spaceS)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .background(Color("AppBkgColor"))
        .cornerRadius(Spacing.current.spaceS)
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: -4)
    }
}

// MARK: - StretchableInput

struct StretchableInput: View {
    @ObservedObject var viewModel: StretchableInputViewModel
    @Binding var draftMessage: String
    @FocusState private var isTextFieldFocused: Bool

    /// Stretched TextField width as a fraction of the parent
    private let stretchedTextFieldWidthFraction: CGFloat = 0.80
    /// Default (collapsed) TextField width as a fraction of the parent
    private let defaultTextFieldWidthFraction: CGFloat = 0.30

    private var isEffectivelyStretched: Bool {
        viewModel.isStretched || isTextFieldFocused
    }

    /// Whether the autocomplete location list should be visible
    private var showAutocompleteList: Bool {
        viewModel.inputMode == .autocomplete
            && isEffectivelyStretched
            && !viewModel.locations.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // MARK: Autocomplete context menu (expands upward)
                if showAutocompleteList {
                    LocationListMenu(
                        locations: viewModel.locations,
                        onSelect: { location in
                            draftMessage = location.placeName ?? ""
                        }
                    )
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .padding(.bottom, Spacing.current.space3xs)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.0, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.0, anchor: .bottom).combined(with: .opacity)
                    ))
                }

                // MARK: Input bar
                HStack(spacing: Spacing.current.spaceXs) {
                    // Map / Autocomplete toggle button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.inputMode = viewModel.inputMode == .autocomplete
                                ? .freestyle
                                : .autocomplete
                        }
                    } label: {
                        Image(systemName: viewModel.inputMode == .autocomplete ? "map.fill" : "map")
                            .bodyText(size: .article0)
                            .foregroundColor(
                                viewModel.inputMode == .autocomplete
                                    ? Color("onBkgTextColor10")
                                    : Color("onBkgTextColor30")
                            )
                    }

                    // Text field — stretches/collapses based on focus
                    TextField(
                        viewModel.inputMode == .autocomplete
                            ? "Locate..."
                            : "Ask...",
                        text: $draftMessage
                    )
                    .bodyText()
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .padding(.trailing, viewModel.inputMode == .freestyle && !draftMessage.isEmpty
                        ? Spacing.current.spaceL : Spacing.current.spaceXs)
                    .padding(.vertical, Spacing.current.space2xs)
                    .background(Color("onBkgTextColor30").opacity(0.15))
                    .cornerRadius(Spacing.current.spaceM)
                    .frame(
                        width: isEffectivelyStretched
                            ? geo.size.width * stretchedTextFieldWidthFraction
                            : geo.size.width * defaultTextFieldWidthFraction
                    )
                    .overlay(alignment: .trailing) {
                        // Send button — inside the text field, trailing edge
                        if viewModel.inputMode == .freestyle && !draftMessage.isEmpty {
                            Button {
                                // Send action placeholder
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .bodyText(size: .article2)
                                    .foregroundColor(Color("onBkgTextColor10"))
                            }
                            .padding(.trailing, Spacing.current.spaceXs)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: draftMessage.isEmpty)
                }
                .padding(.horizontal, Spacing.current.space3xs)
                .padding(.vertical, Spacing.current.space3xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.easeInOut(duration: 0.25), value: isEffectivelyStretched)
            .animation(.easeInOut(duration: 0.25), value: showAutocompleteList)
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
}

// MARK: - StretchableInput Preview

#Preview("StretchableInput") {
    struct StretchableInputPreviewWrapper: View {
        @StateObject private var viewModel: StretchableInputViewModel = {
            let vm = StretchableInputViewModel()
            vm.locations = [
                LocationDetailData(
                    location: CLLocation(latitude: 48.8566, longitude: 2.3522),
                    placeName: "Eiffel Tower",
                    subdivisions: "Paris, Île-de-France",
                    countryName: "France",
                    countryCode: "FR"
                ),
                LocationDetailData(
                    location: CLLocation(latitude: 41.8902, longitude: 12.4922),
                    placeName: "Colosseum",
                    subdivisions: "Rome, Lazio",
                    countryName: "Italy",
                    countryCode: "IT"
                ),
                LocationDetailData(
                    location: CLLocation(latitude: 35.6762, longitude: 139.6503),
                    placeName: "Shibuya Crossing",
                    subdivisions: "Shibuya, Tokyo",
                    countryName: "Japan",
                    countryCode: "JP"
                ),
                LocationDetailData(
                    location: CLLocation(latitude: 40.7484, longitude: -73.9857),
                    placeName: "Empire State Building",
                    subdivisions: "Manhattan, New York",
                    countryName: "United States",
                    countryCode: "US"
                ),
                LocationDetailData(
                    location: CLLocation(latitude: -33.8568, longitude: 151.2153),
                    placeName: "Sydney Opera House",
                    subdivisions: "Sydney, New South Wales",
                    countryName: "Australia",
                    countryCode: "AU"
                )
            ]
            return vm
        }()
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
                .frame(height: 300)
            }
            .padding()
            .background(Color("AppBkgColor"))
        }
    }

    return StretchableInputPreviewWrapper()
}
