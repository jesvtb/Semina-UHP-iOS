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
    @Published var inputLocation: String = ""
    @Published var cachedLocations: [LocationDetailData] = []
    @Published var autocompleteResults: [MapSearchResult] = []

    /// Whether the switch-to-chat button is visible.
    @Published var isChatButtonVisible: Bool = true
    /// Whether the switch-to-journey button is visible (shown when on chat tab).
    @Published var isJourneyButtonVisible: Bool = false

    /// Callback fired when the user submits a message in freestyle mode.
    var onSendMessage: (() -> Void)?
    /// Callback fired when the user taps the switch-to-chat button.
    var onSwitchToChat: (() -> Void)?
    /// Callback fired when the user taps the switch-to-journey button.
    var onSwitchToJourney: (() -> Void)?
    /// Callback fired when the user selects a cached location from the list.
    var onLocationSelected: ((LocationDetailData) -> Void)?
    /// Callback fired when the user selects an autocomplete search result.
    var onAutocompleteResultSelected: ((MapSearchResult) -> Void)?

    /// Loads cached `location_searched` events from the EventManager into `cachedLocations`.
    func loadCachedLocations(from eventManager: EventManager) {
        cachedLocations = eventManager.getSearchedLocations()
    }
}

// MARK: - LocationListMenu

struct LocationListMenu: View {
    let cachedLocations: [LocationDetailData]
    let autocompleteResults: [MapSearchResult]
    let onSelectCached: (LocationDetailData) -> Void
    let onSelectAutocomplete: (MapSearchResult) -> Void

    private var totalItemCount: Int {
        cachedLocations.count + autocompleteResults.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if !cachedLocations.isEmpty {
                Text("Recent Locations")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                    .foregroundColor(Color("onBkgTextColor30"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.current.spaceS)
                    .padding(.top, Spacing.current.spaceS)
                    .padding(.bottom, Spacing.current.spaceXs)

                Divider()
                    .padding(.leading, Spacing.current.spaceS)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Cached location rows
                    ForEach(
                        Array(cachedLocations.enumerated()),
                        id: \.offset
                    ) { index, location in
                        Button {
                            onSelectCached(location)
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

                        if index < cachedLocations.count - 1 || !autocompleteResults.isEmpty {
                            Divider()
                                .padding(.leading, Spacing.current.spaceS)
                        }
                    }

                    // Autocomplete result rows
                    ForEach(
                        Array(autocompleteResults.enumerated()),
                        id: \.offset
                    ) { index, result in
                        Button {
                            onSelectAutocomplete(result)
                        } label: {
                            HStack(spacing: Spacing.current.spaceXs) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("AccentColor"))

                                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                                    Text(result.name)
                                        .font(.custom(FontFamily.sansRegular, size: TypographyScale.article0.baseSize))
                                        .foregroundColor(Color("onBkgTextColor10"))

                                    if !result.address.isEmpty {
                                        Text(result.address)
                                            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                                            .foregroundColor(Color("onBkgTextColor30"))
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, Spacing.current.spaceS)
                            .padding(.vertical, Spacing.current.spaceXs)
                        }

                        if index < autocompleteResults.count - 1 {
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

    /// The active text binding: `inputLocation` in autocomplete mode, `draftMessage` in freestyle.
    private var activeText: Binding<String> {
        viewModel.inputMode == .autocomplete
            ? $viewModel.inputLocation
            : $draftMessage
    }

    /// Whether the autocomplete location list should be visible
    private var showAutocompleteList: Bool {
        viewModel.inputMode == .autocomplete
            && isEffectivelyStretched
            && (!viewModel.cachedLocations.isEmpty || !viewModel.autocompleteResults.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Autocomplete context menu (expands upward)
            if showAutocompleteList {
                LocationListMenu(
                    cachedLocations: viewModel.cachedLocations,
                    autocompleteResults: viewModel.autocompleteResults,
                    onSelectCached: { location in
                        viewModel.onLocationSelected?(location)
                        viewModel.inputLocation = ""
                        viewModel.autocompleteResults = []
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.isStretched = false
                        }
                    },
                    onSelectAutocomplete: { result in
                        viewModel.onAutocompleteResultSelected?(result)
                        viewModel.inputLocation = ""
                        viewModel.autocompleteResults = []
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.isStretched = false
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

            // MARK: Tab-switching buttons (above the input bar)
            if viewModel.isChatButtonVisible, let onSwitchToChat = viewModel.onSwitchToChat {
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

            if viewModel.isJourneyButtonVisible, let onSwitchToJourney = viewModel.onSwitchToJourney {
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

            // MARK: Input bar
            GeometryReader { geo in
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
                        text: activeText
                    )
                    .bodyText()
                    .focused($isTextFieldFocused)
                    .submitLabel(viewModel.inputMode == .autocomplete ? .search : .send)
                    .onSubmit {
                        if viewModel.inputMode == .freestyle && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.onSendMessage?()
                        }
                    }
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .padding(.trailing, viewModel.inputMode == .freestyle && !draftMessage.isEmpty
                        ? Spacing.current.spaceL : Spacing.current.spaceXs)
                    .padding(.vertical, Spacing.current.space2xs)
                    .background(Color("onBkgTextColor30"))
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
                                viewModel.onSendMessage?()
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 40)
        }
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
        @StateObject private var viewModel: StretchableInputViewModel = {
            let vm = StretchableInputViewModel()
            vm.cachedLocations = [
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
            }
            .padding()
            .background(Color("AppBkgColor"))
        }
    }

    return StretchableInputPreviewWrapper()
}
