import SwiftUI
@preconcurrency import MapKit
import core

// MARK: - Input Tab Selection
enum PreviewTabSelection: Int, CaseIterable {
    case journey = 0
    case map = 1
    case chat = 2
    case profile = 3
}

struct MainView: View {
    @EnvironmentObject var uhpGateway: UHPGateway
    @EnvironmentObject var trackingManager: TrackingManager
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    
    // Preview values for preview purposes
    private let previewTab: PreviewTabSelection?
    private let previewMessages: [ChatMessage]?
    private let previewGeoJSONData: [String: Any]?
    private let previewLastMessage: ChatMessage?
    private let previewCurrentToastData: ToastData?
    @State private var selectedTab: PreviewTabSelection = .journey
    @State private var previousTab: PreviewTabSelection = .journey
    @State private var shouldHideTabBar: Bool = false
    @StateObject var liveUpdateViewModel = LiveUpdateViewModel()
    @StateObject var stretchableInputVM = StretchableInputViewModel()
    @State var shouldDismissKeyboard: Bool = false
    
    // Location-related state
    @State private var isLoadingLocation = false
    @State private var lastSentLocation: (latitude: Double, longitude: Double)?
    
    // Map features are now managed by MapFeaturesManager (passed as @EnvironmentObject)
    @EnvironmentObject var mapFeaturesManager: MapFeaturesManager
    // Toast notifications are now managed by ToastManager (passed as @EnvironmentObject)
    @EnvironmentObject var toastManager: ToastManager
    @FocusState var isTextFieldFocused: Bool
    
    // Catalogue management
    @EnvironmentObject var catalogueManager: CatalogueManager
    // SSE event router for handling events from both /v1/chat and /v1/orchestrator
    @EnvironmentObject var sseEventRouter: SSEEventRouter
    // Event manager for event-driven location tracking
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var autocompleteManager: AutocompleteManager
    @Environment(\.geocoder) var geocoder: Geocoder
    // Debug cache overlay state
    #if DEBUG
    @State private var showCacheDebugSheet: Bool = false
    @State private var showSSEContentTestSheet: Bool = false
    #endif
    
    // Sheet snap point control - universal binding for bidirectional control
    @State var sheetSnapPoint: SnapPoint = .partial
    private let tabs: [(name: String, selectedIcon: String, unselectedIcon: String)] = [
        ("Journey", "signpost.right.and.left.fill", "signpost.right.and.left"),
        ("Locate", "mappin.circle.fill", "mappin.and.ellipse"),
        ("Ask", "questionmark.bubble.fill", "questionmark.bubble"),
        ("You", "person.fill", "person")
    ]
    
    init(
        previewTab: PreviewTabSelection? = nil,
        previewMessages: [ChatMessage]? = nil,
        previewGeoJSONData: [String: Any]? = nil,
        previewLastMessage: ChatMessage? = nil,
        previewCurrentToastData: ToastData? = nil
    ) {
        self.previewTab = previewTab
        self.previewMessages = previewMessages
        self.previewGeoJSONData = previewGeoJSONData
        self.previewLastMessage = previewLastMessage
        self.previewCurrentToastData = previewCurrentToastData
    }

    var body: some View {
        ZStack {
            MapboxMapView()
                .ignoresSafeArea(.container)
                .ignoresSafeArea(.keyboard)
                .contentShape(Rectangle())
                .onTapGesture {
                    isTextFieldFocused = false
                    stretchableInputVM.isStretched = false
                }
            // Main content (messages list)
            if selectedTab == .chat {
                ChatTabView(
                    messages: chatManager.messages,
                    isTextFieldFocused: $isTextFieldFocused
                )
            }
            
            // Journey bottom sheet - positioned absolutely to avoid affecting layout
            if selectedTab == .journey {
                GeometryReader { geometry in
                    InfoSheet(
                        selectedTab: $selectedTab,
                        shouldHideTabBar: $shouldHideTabBar,
                        sheetFullHeight: sheetFullHeight,
                        bottomSafeAreaInsetHeight: bottomSafeAreaInsetHeight,
                        sheetSnapPoint: $sheetSnapPoint,
                        catalogueManager: catalogueManager,
                        onActivateLocationSearch: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                stretchableInputVM.inputMode = .autocomplete
                            }
                        }
                    )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height - (sheetFullHeight / 2) // Dynamic: half of actual sheet height
                        )
                } 
            }
            
            // Profile tab - scrollable view
            if selectedTab == .profile {
                ProfileTabView(
                    onLogout: handleLogout,
                    isTextFieldFocused: $isTextFieldFocused
                )
            }

            
            if let lastMessage = chatManager.lastMessage {
                LiveUpdateStack(
                    message: lastMessage,
                    currentToastData: $toastManager.currentToastData,
                    isExpanded: $chatManager.isMessageExpanded,
                    onDismiss: {
                        chatManager.dismissLastMsg()
                    }
                )
                .opacity(shouldHideTabBar ? 0 : 1)
                .allowsHitTesting(!shouldHideTabBar)
                .animation(.easeInOut(duration: 0.2), value: shouldHideTabBar)
            }
            
            // Avatar / profile button overlay
            avatarButton
            
            // Debug cache button overlay
            #if DEBUG
            debugCacheButton
            debugSSEContentTestButton
            #endif
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                if stretchableInputVM.isStretched {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        stretchableInputVM.isStretched = false
                    }
                }
            }
        )
        // Input bar pinned to bottom; moves with keyboard
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                StretchableInput(
                    viewModel: stretchableInputVM,
                    draftMessage: $chatManager.draftMessage
                )
                // if !stretchableInputVM.isStretched {
                //     TabsBarView(selectedTab: $selectedTab, tabs: tabs)
                // }
            }
            .background(.ultraThinMaterial)
            .overlay(
                Divider()
                    .background(Color("onBkgTextColor30")),
                alignment: .top
            )
            // .opacity((!shouldHideTabBar || selectedTab != .journey) ? 1 : 0)
            // .allowsHitTesting(!shouldHideTabBar || selectedTab != .journey)
            // .animation(.easeInOut(duration: 0.2), value: shouldHideTabBar)
        }
        #if DEBUG
        .sheet(isPresented: $showCacheDebugSheet) {
            cacheDebugSheet
        }
        .sheet(isPresented: $showSSEContentTestSheet) {
            SSEContentTestView()
        }
        #endif
        .onChange(of: shouldDismissKeyboard) { shouldDismiss in
            if shouldDismiss {
                isTextFieldFocused = false
            }
        }
        .onChange(of: trackingManager.deviceLocation) { newLocation in
            guard let location = newLocation else {
                return
            }
            
            Task {
                await updateLocationToUHP(location: location, router: sseEventRouter)
            }
        }
        .onChange(of: mapFeaturesManager.flyToLocation) { newFlyTo in
            guard let flyTo = newFlyTo else {
                return
            }
            Task {
                await updateLookupLocationToUHP(flyTo: flyTo, router: sseEventRouter)
            }
        }
        .onChange(of: stretchableInputVM.inputLocation) { newValue in
            // Update autocomplete when typing in autocomplete mode
            if stretchableInputVM.inputMode == .autocomplete {
                updateAutocomplete(query: newValue)
            }
        }
        .onChange(of: stretchableInputVM.inputMode) { newMode in
            if newMode == .autocomplete {
                // Load cached locations when entering autocomplete mode
                stretchableInputVM.loadCachedLocations(from: eventManager)
            } else {
                // Clear autocomplete state when leaving autocomplete mode
                autocompleteManager.clearSearchResults()
                stretchableInputVM.autocompleteResults = []
                stretchableInputVM.inputLocation = ""
            }
        }
        .onReceive(autocompleteManager.$searchResults) { newResults in
            // Feed autocomplete results into the StretchableInput view model
            if stretchableInputVM.inputMode == .autocomplete {
                stretchableInputVM.autocompleteResults = newResults
            }
        }
        .onChange(of: stretchableInputVM.isStretched) { isStretched in
            // Sync MainView's isTextFieldFocused with StretchableInput's stretch state
            isTextFieldFocused = isStretched
        }
        .onChange(of: selectedTab) { newTab in
            // Track the previous non-profile tab for profile close navigation
            if newTab != .profile {
                previousTab = newTab
            }
            // Hide chat button when already on the chat tab
            stretchableInputVM.isChatButtonVisible = (newTab != .chat)
            // Show journey button when on the chat tab
            stretchableInputVM.isJourneyButtonVisible = (newTab == .chat)
            // Clear autocomplete results when switching tabs
            if stretchableInputVM.inputMode == .autocomplete {
                stretchableInputVM.inputMode = .freestyle
            }
        }
        .onAppear {
            // Set up callbacks for ChatManager
            chatManager.onDismissKeyboard = {
                shouldDismissKeyboard = true
                // Reset the flag after a brief delay to allow the change to be detected
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    await MainActor.run {
                        shouldDismissKeyboard = false
                    }
                }
            }
            chatManager.onShowInfoSheet = {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    sheetSnapPoint = .full
                }
            }
            chatManager.onTextFieldFocusChange = { isFocused in
                isTextFieldFocused = isFocused
            }
            
            // Set router callbacks for view coordination
            sseEventRouter.onShowInfoSheet = {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    sheetSnapPoint = .full
                }
            }
            sseEventRouter.onDismissKeyboard = {
                isTextFieldFocused = false
            }
            
            // Set router reference in ChatManager (router already holds chatManager from app init)
            chatManager.sseEventRouter = sseEventRouter
            
            // Set up StretchableInput callbacks
            stretchableInputVM.onSendMessage = {
                Task { @MainActor in
                    await chatManager.sendMessage()
                }
            }
            stretchableInputVM.onSwitchToChat = {
                selectedTab = .chat
            }
            stretchableInputVM.onSwitchToJourney = {
                selectedTab = .journey
            }
            stretchableInputVM.isChatButtonVisible = (selectedTab != .chat)
            stretchableInputVM.isJourneyButtonVisible = (selectedTab == .chat)
            stretchableInputVM.onLocationSelected = { [weak stretchableInputVM] locationDetail in
                mapFeaturesManager.flyToLocation = FlyToLocation(locationDetail: locationDetail)
                autocompleteManager.clearSearchResults()
                stretchableInputVM?.inputLocation = ""
                stretchableInputVM?.autocompleteResults = []
            }
            stretchableInputVM.onAutocompleteResultSelected = { [weak stretchableInputVM] result in
                Task { @MainActor in
                    await flyToLocation(result: result)
                    stretchableInputVM?.autocompleteResults = []
                }
            }
        }
        .task { @MainActor in
            
            // Set preview values if provided (for preview purposes)
            if let previewTab = previewTab {
                selectedTab = previewTab
            }
            if let previewMessages = previewMessages {
                chatManager.messages = previewMessages
            }
            if let previewGeoJSONData = previewGeoJSONData {
                // Extract features from preview data and set to mapFeaturesManager
                do {
                    let features = try GeoJSON.extractFeatures(from: previewGeoJSONData)
                    mapFeaturesManager.apply(features: features)
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to extract features from preview GeoJSON data: \(error)")
                    #endif
                }
            }
            if let previewLastMessage = previewLastMessage {
                chatManager.lastMessage = previewLastMessage
            }
            if let previewCurrentToastData = previewCurrentToastData {
                toastManager.show(previewCurrentToastData)
            }
            
            // When permission is granted, update location to UHP if already available
            // Location tracking will start automatically via TrackingManager's startLocationUpdates()
            if trackingManager.isLocationPermissionGranted, let existingLocation = trackingManager.deviceLocation {
                await updateLocationToUHP(location: existingLocation, router: sseEventRouter)
            }
        }
    }
}

// MARK: - MainView: Computed Properties
extension MainView {
    private var sheetFullHeight: CGFloat {
        UIScreen.main.bounds.height + 1
    }
    
    /// Calculates the exact height of the bottom safe area inset (InputBar + TabsBarView)
    private var bottomSafeAreaInsetHeight: CGFloat {
        // InputBar components:
        // - HStack vertical padding: 8 top + 8 bottom = 16 points
        // - TextField vertical padding: 10 top + 10 bottom = 20 points
        // - TextField content height (single line, system font ~17pt): ~20 points
        let InputBarHeight: CGFloat = 16 + 20 + 20 // 56 points minimum
        
        // TabsBarView:
        // - Uses tabBarHeight constant = 49 points
        let tabSelectorHeight: CGFloat = 49
        
        // VStack spacing: 0 (no spacing between components)
        return InputBarHeight + tabSelectorHeight // 105 points total
    }
}


// MARK: - MainView: Actions
extension MainView {
    func handleLogout() {
        Task {
            do {
                try await supabase.auth.signOut()
            } catch {
                #if DEBUG
                print("❌ Logout error: \(error.localizedDescription)")
                #endif
            }
        }
    }
}



// MARK: - MainView: Avatar Button
extension MainView {
    var avatarButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    if selectedTab == .profile {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = previousTab
                        }
                    } else {
                        previousTab = selectedTab
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = .profile
                        }
                    }
                }) {
                    Image(systemName: selectedTab == .profile ? "xmark.circle.fill" : "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundColor(Color("onBkgTextColor30"))
                        .background(
                            Circle()
                                .fill(Color("AppBkgColor").opacity(0.8))
                        )
                        .clipShape(Circle())
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            Spacer()
        }
    }
}

// MARK: - Debug Cache Components
#if DEBUG
extension MainView {
    private var debugCacheButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    showCacheDebugSheet = true
                }) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 12))
                        .foregroundColor(Color("onBkgTextColor30"))
                        .padding(8)
                        .background(
                            Color("AppBkgColor")
                                .opacity(0.8)
                                .cornerRadius(8)
                        )
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
                .offset(y: 48) // Position below avatar button
            }
            Spacer()
        }
    }
    
    private var debugSSEContentTestButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    showSSEContentTestSheet = true
                }) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color("onBkgTextColor30"))
                        .padding(8)
                        .background(
                            Color("AppBkgColor")
                                .opacity(0.8)
                                .cornerRadius(8)
                        )
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
                .offset(y: 88) // Position below cache button
            }
            Spacer()
        }
    }
    
    private var cacheDebugSheet: some View {
        NavigationView {
            CacheDebugContentView(
                onClearCache: {
                    clearCache()
                    showCacheDebugSheet = false
                },
                onDismiss: {
                    showCacheDebugSheet = false
                }
            )
            .environmentObject(eventManager)
        }
    }
    
    private struct CacheDebugContentView: View {
        @EnvironmentObject var eventManager: EventManager
        let onClearCache: () -> Void
        let onDismiss: () -> Void
        
        @State private var isThisSessionEventsExpanded = false
        @State private var isLastDeviceLocationExpanded = false
        @State private var isLastLookupLocationExpanded = false
        
        private var cacheInfo: (entryCount: Int, totalSize: Int, formattedSize: String, breakdown: [(key: String, size: Int, formattedSize: String, value: Any?)]) {
            getCacheInfo()
        }
        
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                    // Cache statistics
                    VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                        Text("Cache Statistics")
                            .bodyText(size: .article1)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Text("Cache Entries:")
                            Spacer()
                            Text(verbatim: String(cacheInfo.entryCount))
                                .foregroundColor(Color("onBkgTextColor30"))
                        }
                        .bodyText()
                        
                        HStack {
                            Text("Total Size:")
                            Spacer()
                            Text(cacheInfo.formattedSize)
                                .foregroundColor(Color("onBkgTextColor30"))
                        }
                        .bodyText()
                        
                        if cacheInfo.entryCount > 0 {
                            Divider()
                                .padding(.vertical, Spacing.current.space2xs)
                            
                            // Cache entry breakdown
                            VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                                Text("Cache Breakdown")
                                    .bodyText(size: .articleMinus1)
                                    .fontWeight(.semibold)
                                    .padding(.bottom, Spacing.current.space3xs)
                                
                                ForEach(cacheInfo.breakdown, id: \.key) { item in
                                    cacheBreakdownRow(item: item)
                                }
                            }
                        }
                    }
                    .padding(Spacing.current.spaceS)
                    .background(
                        Color("onBkgTextColor30")
                            .opacity(0.1)
                            .cornerRadius(Spacing.current.spaceXs)
                    )
                    
                    // EventManager.thisSession events - expandable
                    expandableSection(
                        title: "This Session Events",
                        isExpanded: $isThisSessionEventsExpanded,
                        isEmpty: eventManager.thisSession.isEmpty,
                        emptyMessage: "No events in this session"
                    ) {
                        if !eventManager.thisSession.isEmpty {
                            let totalCount = eventManager.thisSession.count
                            ForEach(Array(eventManager.thisSession.reversed().enumerated()), id: \.offset) { index, event in
                                thisSessionEventSection(index: totalCount - index, event: event)
                            }
                        }
                    }
                    
                    // LastDeviceLocation - expandable
                    expandableSection(
                        title: "LastDeviceLocation",
                        isExpanded: $isLastDeviceLocationExpanded,
                        isEmpty: eventManager.latestDeviceLocation == nil,
                        emptyMessage: "No device location available"
                    ) {
                        if let deviceLocation = eventManager.latestDeviceLocation {
                            locationJsonView(json: deviceLocation)
                        }
                    }
                    
                    // LastLookupLocation - expandable
                    expandableSection(
                        title: "LastLookupLocation",
                        isExpanded: $isLastLookupLocationExpanded,
                        isEmpty: eventManager.latestLookupLocation == nil,
                        emptyMessage: "No lookup location available"
                    ) {
                        if let lookupLocation = eventManager.latestLookupLocation {
                            locationJsonView(json: lookupLocation)
                        }
                    }
                    
                    // Clear cache button
                    Button(action: onClearCache) {
                        HStack {
                            Spacer()
                            Text("Clear Cache")
                                .bodyText()
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, Spacing.current.space2xs)
                        .background(
                            Color.red
                                .cornerRadius(Spacing.current.spaceXs)
                        )
                    }
                }
                .padding(Spacing.current.spaceS)
            }
            .navigationTitle("Debug Cache")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        
        private func expandableSection<Content: View>(
            title: String,
            isExpanded: Binding<Bool>,
            isEmpty: Bool,
            emptyMessage: String,
            @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                Button(action: {
                    withAnimation {
                        isExpanded.wrappedValue.toggle()
                    }
                }) {
                    HStack {
                        Text(title)
                            .bodyText(size: .article1)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Color("onBkgTextColor30"))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                if isExpanded.wrappedValue {
                    if isEmpty {
                        Text(emptyMessage)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor30"))
                            .padding(Spacing.current.spaceS)
                    } else {
                        content()
                    }
                }
            }
            .padding(Spacing.current.spaceS)
            .background(
                Color("onBkgTextColor30")
                    .opacity(0.1)
                    .cornerRadius(Spacing.current.spaceXs)
            )
        }
        
        private func locationJsonView(json: [String: JSONValue]) -> some View {
            Text(JSONValue.prettyDict(json))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color("onBkgTextColor30"))
                .padding(Spacing.current.space2xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color("onBkgTextColor30")
                        .opacity(0.06)
                        .cornerRadius(Spacing.current.space3xs)
                )
        }
        
        private func cacheBreakdownRow(item: (key: String, size: Int, formattedSize: String, value: Any?)) -> some View {
            HStack {
                Text(item.key)
                    .bodyText(size: .articleMinus1)
                Spacer()
                
                // Show simple values inline
                if let value = item.value {
                    if let boolValue = value as? Bool {
                        Text(verbatim: boolValue ? "true" : "false")
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor30"))
                            .padding(.trailing, Spacing.current.space2xs)
                    } else if let stringValue = value as? String, stringValue.count < 50 {
                        Text(stringValue)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor30"))
                            .lineLimit(1)
                            .padding(.trailing, Spacing.current.space2xs)
                    }
                }
                
                Text(item.formattedSize)
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor30"))
            }
        }
        
        private func thisSessionEventSection(index: Int, event: UserEvent) -> some View {
            VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                Text(verbatim: "Event \(index)")
                    .bodyText(size: .articleMinus1)
                    .fontWeight(.semibold)
                    .foregroundColor(Color("onBkgTextColor30"))
                
                // Structured keys (non–evt_data)
                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    structuredRow(label: "evt_utc", value: event.evt_utc)
                    if let tz = event.evt_timezone {
                        structuredRow(label: "evt_timezone", value: tz)
                    }
                    structuredRow(label: "evt_type", value: event.evt_type)
                    if let sid = event.session_id {
                        let sidDisplay = sid.count >= 6 ? String(sid.suffix(6)) : sid
                        structuredRow(label: "session_id", value: sidDisplay)
                    }
                }
                
                // evt_data as JSON
                Text("evt_data")
                    .bodyText(size: .articleMinus1)
                    .fontWeight(.medium)
                Text(JSONValue.prettyDict(event.evt_data))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color("onBkgTextColor30"))
                    .padding(Spacing.current.space2xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color("onBkgTextColor30")
                            .opacity(0.06)
                            .cornerRadius(Spacing.current.space3xs)
                    )
            }
            .padding(Spacing.current.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color("onBkgTextColor30")
                    .opacity(0.08)
                    .cornerRadius(Spacing.current.spaceXs)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.current.spaceXs)
                    .stroke(Color("onBkgTextColor30").opacity(0.2), lineWidth: 1)
            )
        }
        
        private func structuredRow(label: String, value: String) -> some View {
            HStack(alignment: .top) {
                Text(verbatim: "\(label):")
                    .bodyText(size: .articleMinus1)
                    .fontWeight(.medium)
                Text(value)
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor30"))
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
        }
        
        private func getCacheInfo() -> (entryCount: Int, totalSize: Int, formattedSize: String, breakdown: [(key: String, size: Int, formattedSize: String, value: Any?)]) {
            let prefixedKeysDict = Storage.allUserDefaultsKeysWithPrefix()
            
            var breakdown: [(key: String, size: Int, formattedSize: String, value: Any?)] = []
            var totalSize = 0
            let prefix = Storage.keyPrefix
            
            for (key, value) in prefixedKeysDict.sorted(by: { $0.key < $1.key }) {
                let valueString = "\(value)"
                let size = valueString.data(using: .utf8)?.count ?? 0
                totalSize += size
                
                let keyWithoutPrefix = prefix.isEmpty ? key : (key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key)
                let formattedSize = formatBytes(size)
                breakdown.append((key: keyWithoutPrefix, size: size, formattedSize: formattedSize, value: value))
            }
            
            return (
                entryCount: prefixedKeysDict.count,
                totalSize: totalSize,
                formattedSize: formatBytes(totalSize),
                breakdown: breakdown
            )
        }
        
        private func formatBytes(_ bytes: Int) -> String {
            if bytes < 1024 {
                return "\(bytes) B"
            } else if bytes < 1024 * 1024 {
                return String(format: "%.1f KB", Double(bytes) / 1024.0)
            } else {
                return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
            }
        }
    }
    
    private func clearCache() {
        #if DEBUG
        DebugVisualizer.clearAllCache()
        print("✅ Cache cleared from debug button")
        #endif
    }
}

#Preview("Map Tab with last user message") {
    let uhpGateway = UHPGateway()
    let trackingManager = TrackingManager()
    let userManager = UserManager()
    let authManager = AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7")
    let chatManager = ChatManager(
        uhpGateway: uhpGateway,
        userManager: userManager
    )
    let mapFeaturesManager = MapFeaturesManager()
    let toastManager = ToastManager()
    let catalogueManager = CatalogueManager()
    let sseEventRouter = SSEEventRouter(chatManager: chatManager, catalogueManager: catalogueManager, mapFeaturesManager: mapFeaturesManager, toastManager: toastManager)
    let eventManager = EventManager()
    let autocompleteManager = AutocompleteManager(geoapifyApiKey: "")
    MainView(previewTab: .map, previewLastMessage: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false))
        .environmentObject(authManager)
        .environmentObject(uhpGateway)
        .environmentObject(trackingManager)
        .environmentObject(userManager)
        .environmentObject(chatManager)
        .environmentObject(mapFeaturesManager)
        .environmentObject(toastManager)
        .environmentObject(catalogueManager)
        .environmentObject(sseEventRouter)
        .environmentObject(eventManager)
        .environmentObject(autocompleteManager)
        .environment(\.geocoder, Geocoder(geoapifyApiKey: ""))
}

#Preview("Journey Tab with last assistant message") {
    let uhpGateway = UHPGateway()
    let trackingManager = TrackingManager()
    let userManager = UserManager()
    let authManager = AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7")
    let chatManager = ChatManager(
        uhpGateway: uhpGateway,
        userManager: userManager
    )
    let mapFeaturesManager = MapFeaturesManager()
    let toastManager = ToastManager()
    let catalogueManager = CatalogueManager()
    let sseEventRouter = SSEEventRouter(chatManager: chatManager, catalogueManager: catalogueManager, mapFeaturesManager: mapFeaturesManager, toastManager: toastManager)
    let eventManager = EventManager()
    let autocompleteManager = AutocompleteManager(geoapifyApiKey: "")
    MainView(previewTab: .journey, previewLastMessage: ChatMessage(text: "Maximus morbi habitasse dictumst curae aenean fermentum senectus nunc elementum quis pretium, dui feugiat gravida sem ad tempor conubia vehicula tortor volutpat, facilisis pulvinar nam fusce praesent ac commodo himenaeos donec lorem. Quis ullamcorper porttitor vitae placerat ad dis eu habitasse venenatis, rhoncus cursus suspendisse in adipiscing posuere mattis tristique donec, rutrum nostra congue velit mauris malesuada montes consequat. Mus est natoque nibh torquent hendrerit scelerisque phasellus consequat auctor praesent, diam neque venenatis quisque cursus vestibulum taciti curae congue, lorem etiam proin accumsan potenti montes tincidunt donec magna.", isUser: false, isStreaming: false))
        .environmentObject(authManager)
        .environmentObject(uhpGateway)
        .environmentObject(trackingManager)
        .environmentObject(userManager)
        .environmentObject(chatManager)
        .environmentObject(mapFeaturesManager)
        .environmentObject(toastManager)
        .environmentObject(catalogueManager)
        .environmentObject(sseEventRouter)
        .environmentObject(eventManager)
        .environmentObject(autocompleteManager)
        .environment(\.geocoder, Geocoder(geoapifyApiKey: ""))
}
#endif


