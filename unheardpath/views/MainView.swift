import SwiftUI
@preconcurrency import MapKit

// MARK: - Input Tab Selection
enum PreviewTabSelection: Int, CaseIterable {
    case journey = 0
    case map = 1
    case chat = 2
    case profile = 3
}

struct TestMainView: View {
    @EnvironmentObject var uhpGateway: UHPGateway
    @EnvironmentObject var trackingManager: TrackingManager
    @EnvironmentObject var locationManager: LocationManager  // Still needed for geocoding/geofencing
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var authManager: AuthManager
    
    // Preview values for preview purposes
    private let previewTab: PreviewTabSelection?
    private let previewMessages: [ChatMessage]?
    private let previewGeoJSONData: [String: Any]?
    private let previewLastMessage: ChatMessage?
    private let previewCurrentToastData: ToastData?
    @State private var selectedTab: PreviewTabSelection = .journey
    @State private var shouldHideTabBar: Bool = false
    @StateObject var liveUpdateViewModel = LiveUpdateViewModel()
    @State var shouldDismissKeyboard: Bool = false
    
    // Location-related state
    @State private var isLoadingLocation = false
    @State private var lastSentLocation: (latitude: Double, longitude: Double)?
    
    // Map features are now managed by MapFeaturesManager (passed as @EnvironmentObject)
    @EnvironmentObject var mapFeaturesManager: MapFeaturesManager
    // Toast notifications are now managed by ToastManager (passed as @EnvironmentObject)
    @EnvironmentObject var toastManager: ToastManager
    @FocusState var isTextFieldFocused: Bool
    
    // Content management
    @EnvironmentObject var contentManager: ContentManager
    // SSE event router for handling events from both /v1/chat and /v1/orchestrator
    @EnvironmentObject var sseEventRouter: SSEEventRouter
    
    // Autocomplete state for map tab
    @StateObject var addressSearchManager = AddressSearchManager()
    @State var targetLocation: TargetLocation?
    @State private var selectedLocation: CLLocation?
    
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
            MapboxMapView(
                targetLocation: $targetLocation,
                selectedLocation: $selectedLocation
            )
                .ignoresSafeArea(.container)
                .ignoresSafeArea(.keyboard)
                .contentShape(Rectangle())
                .onTapGesture {
                    isTextFieldFocused = false
                }
            // Main content (messages list)
            if selectedTab == .chat {
                ChatTabView(
                    messages: chatViewModel.messages,
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
                        contentManager: contentManager
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

            
            if let lastMessage = chatViewModel.lastMessage, selectedTab != .chat {
                LiveUpdateStack(
                    message: lastMessage,
                    currentToastData: $toastManager.currentToastData,
                    isExpanded: $chatViewModel.isMessageExpanded,
                    onDismiss: {
                        chatViewModel.dismissLastMsg()
                    }
                )
                .opacity(shouldHideTabBar ? 0 : 1)
                .allowsHitTesting(!shouldHideTabBar)
                .animation(.easeInOut(duration: 0.2), value: shouldHideTabBar)
            }
            
            // Show autocomplete results in map tab
            if selectedTab == .map && !addressSearchManager.results.isEmpty && !liveUpdateViewModel.inputLocation.isEmpty {
                AddrSearchResultsList(
                    searchResults: addressSearchManager.results,
                    inputLocation: $liveUpdateViewModel.inputLocation,
                    isTextFieldFocused: $isTextFieldFocused,
                    onResultSelected: { result in
                        await geocodeAndFlyToLocation(result: result)
                    },
                    onClearResults: {
                        addressSearchManager.clearResults()
                    }
                )
                    .opacity(shouldHideTabBar ? 0 : 1)
                    .allowsHitTesting(!shouldHideTabBar)
            }
            
            // Debug cache button overlay
            #if DEBUG
            debugCacheButton
            debugSSEContentTestButton
            #endif
        }
        // Input bar pinned to bottom; moves with keyboard
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                ChatInputBar(
                    selectedTab: selectedTab,
                    draftMessage: $chatViewModel.draftMessage,
                    inputLocation: $liveUpdateViewModel.inputLocation,
                    isTextFieldFocused: $isTextFieldFocused,
                    isAuthenticated: authManager.isAuthenticated,
                    isLoading: authManager.isLoading,
                    onSendMessage: {
                        Task { @MainActor in
                            await chatViewModel.sendMessage()
                        }
                    },
                    onSwitchToChat: {
                        selectedTab = .chat
                    }
                )
                if !isTextFieldFocused {
                    TabsBarView(selectedTab: $selectedTab, tabs: tabs)
                }
            }
            .background(.ultraThinMaterial)
            .overlay(
                Divider()
                    .background(Color("onBkgTextColor30")),
                alignment: .top
            )
            .opacity((!shouldHideTabBar || selectedTab != .journey) ? 1 : 0)
            // .opacity(0.2)
            .allowsHitTesting(!shouldHideTabBar || selectedTab != .journey)
            .animation(.easeInOut(duration: 0.2), value: shouldHideTabBar)
        }
        .onChange(of: shouldDismissKeyboard) { shouldDismiss in
            if shouldDismiss {
                isTextFieldFocused = false
            }
        }
        .onChange(of: trackingManager.isLocationPermissionGranted) { isGranted in
            // When permission is granted, update location to UHP if already available
            // Location tracking will start automatically via TrackingManager's startLocationUpdates()
            if isGranted, let existingLocation = trackingManager.deviceLocation {
                Task {
                    await updateLocationToUHP(location: existingLocation, router: sseEventRouter)
                }
            }
        }
        .onChange(of: trackingManager.deviceLocation) { newLocation in
            #if DEBUG
            if let location = newLocation {
                print("📍 trackingManager.deviceLocation changed to: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            } else {
                print("📍 trackingManager.deviceLocation changed to: nil")
            }
            #endif
            
            // Remove content if location becomes nil
            // Full locationDetail update with metadata is handled in updateLocationToUHP
            guard let location = newLocation else {
                contentManager.removeContent(type: .locationDetail)
                return
            }
            
            Task {
                await updateLocationToUHP(location: location, router: sseEventRouter)
            }
        }
        .onChange(of: mapFeaturesManager.geoJSONUpdateTrigger) { _ in
            // Update content manager with POIs when GeoJSON changes
            let pois = extractPOIs(from: mapFeaturesManager.poisGeoJSON)
            if !pois.isEmpty {
                contentManager.setContent(
                    type: .pointsOfInterest,
                    data: .pointsOfInterest(features: pois)
                )
            } else {
                contentManager.removeContent(type: .pointsOfInterest)
            }
        }
        // .onReceive(locationManager.$shouldRefreshDevicePOIs) { shouldRefresh in
        //     if shouldRefresh {
        //         Task {
        //             await loadLocationFromGeofenceExit()
        //         }
        //     }
        // }
        .onChange(of: liveUpdateViewModel.inputLocation) { newValue in
            // Update autocomplete when typing in map tab
            if selectedTab == .map {
                updateAutocomplete(query: newValue)
            }
        }
        .onChange(of: selectedTab) { newTab in
            // Clear autocomplete results when switching away from map tab
            if newTab != .map {
                addressSearchManager.clearResults()
            }
        }
        #if DEBUG
        .sheet(isPresented: $showCacheDebugSheet) {
            cacheDebugSheet
        }
        .sheet(isPresented: $showSSEContentTestSheet) {
            SSEContentTestView()
        }
        #endif
        .onAppear {
            // Set up callbacks for ChatViewModel
            chatViewModel.onDismissKeyboard = {
                shouldDismissKeyboard = true
                // Reset the flag after a brief delay to allow the change to be detected
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    await MainActor.run {
                        shouldDismissKeyboard = false
                    }
                }
            }
            chatViewModel.onShowInfoSheet = {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    sheetSnapPoint = .full
                }
            }
            chatViewModel.onTextFieldFocusChange = { isFocused in
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
            
            // Set router reference in ChatViewModel
            chatViewModel.sseEventRouter = sseEventRouter
            // Also set ChatViewModel reference in router (bidirectional connection)
            sseEventRouter.setChatViewModel(chatViewModel)
        }
        .task { @MainActor in
            
            // Set preview values if provided (for preview purposes)
            if let previewTab = previewTab {
                selectedTab = previewTab
            }
            if let previewMessages = previewMessages {
                chatViewModel.messages = previewMessages
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
                chatViewModel.lastMessage = previewLastMessage
            }
            if let previewCurrentToastData = previewCurrentToastData {
                toastManager.show(previewCurrentToastData)
            }
            
            // When permission is granted, update location to UHP if already available
            // Location tracking will start automatically via TrackingManager's startLocationUpdates()
            if trackingManager.isLocationPermissionGranted, let existingLocation = trackingManager.deviceLocation {
                await updateLocationToUHP(location: existingLocation, router: sseEventRouter)
            }
            
            // Initial load: Check if geofence exists and is valid
            // If geofence is restored and valid, don't fetch data until user exits region
            // Use a small delay to avoid race condition with location initialization
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
            
            // Try to restore geofence from UserDefaults
            let geofenceRestored = locationManager.restoreDevicePOIsGeofenceIfValid()
            
            if geofenceRestored {
                #if DEBUG
                print("✅ Geofence restored from UserDefaults, skipping initial data load")
                #endif
                // Geofence should already be set up, but ensure it exists
                if let geofenceCenter = locationManager.getSavedGeofenceCenter() {
                    let userLat = geofenceCenter.latitude
                    let userLon = geofenceCenter.longitude
                    if !locationManager.isDevicePOIsGeofencingActive {
                        locationManager.setupDevicePOIsRefreshGeofence(centerLat: userLat, centerLon: userLon)
                    }
                }
            } else if trackingManager.deviceLocation != nil {
                // No valid geofence, load data from cache or API
                // await loadLocationFromGeofenceExit()
            }
        }
    }
    
}

// MARK: - TestMainView: Computed Properties
extension TestMainView {
    private var sheetFullHeight: CGFloat {
        UIScreen.main.bounds.height + 1
    }
    
    /// Calculates the exact height of the bottom safe area inset (chatInputBar + TabsBarView)
    private var bottomSafeAreaInsetHeight: CGFloat {
        // chatInputBar components:
        // - HStack vertical padding: 8 top + 8 bottom = 16 points
        // - TextField vertical padding: 10 top + 10 bottom = 20 points
        // - TextField content height (single line, system font ~17pt): ~20 points
        let chatInputBarHeight: CGFloat = 16 + 20 + 20 // 56 points minimum
        
        // TabsBarView:
        // - Uses tabBarHeight constant = 49 points
        let tabSelectorHeight: CGFloat = 49
        
        // VStack spacing: 0 (no spacing between components)
        return chatInputBarHeight + tabSelectorHeight // 105 points total
    }
}


// MARK: - TestMainView: Actions
extension TestMainView {
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



// MARK: - Debug Cache Components
#if DEBUG
extension TestMainView {
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
                .offset(y: 40) // Position below cache button
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
        }
    }
    
    private struct CacheDebugContentView: View {
        let onClearCache: () -> Void
        let onDismiss: () -> Void
        
        private var cacheInfo: (entryCount: Int, totalSize: Int, formattedSize: String, breakdown: [(key: String, size: Int, formattedSize: String)]) {
            getCacheInfo()
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                // Cache statistics
                VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                    Text("Cache Statistics")
                        .bodyText(size: .article1)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Cache Entries:")
                        Spacer()
                        Text("\(cacheInfo.entryCount)")
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
                                HStack {
                                    Text(item.key)
                                        .bodyText(size: .articleMinus1)
                                    Spacer()
                                    Text(item.formattedSize)
                                        .bodyText(size: .articleMinus1)
                                        .foregroundColor(Color("onBkgTextColor30"))
                                }
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
                
                Spacer()
                
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
        
        private func getCacheInfo() -> (entryCount: Int, totalSize: Int, formattedSize: String, breakdown: [(key: String, size: Int, formattedSize: String)]) {
            // Get all UHP keys using StorageManager
            let uhpKeysDict = StorageManager.getAllUHPKeys()
            
            var breakdown: [(key: String, size: Int, formattedSize: String)] = []
            var totalSize = 0
            
            for (key, value) in uhpKeysDict.sorted(by: { $0.key < $1.key }) {
                let valueString = "\(value)"
                let size = valueString.data(using: .utf8)?.count ?? 0
                totalSize += size
                
                // Remove "UHP." prefix for display
                let keyWithoutPrefix = key.hasPrefix("UHP.") ? String(key.dropFirst(4)) : key
                let formattedSize = formatBytes(size)
                breakdown.append((key: keyWithoutPrefix, size: size, formattedSize: formattedSize))
            }
            
            return (
                entryCount: uhpKeysDict.count,
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
        locationManager.debugClearAllCache()
        #if DEBUG
        print("✅ Cache cleared from debug button")
        #endif
    }
}

#Preview("Map Tab with last user message") {
    let uhpGateway = UHPGateway()
    let trackingManager = TrackingManager()
    let locationManager = LocationManager()  // Still needed for geocoding/geofencing
    let userManager = UserManager()
    let authManager = AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7")
    let chatViewModel = ChatViewModel(
        uhpGateway: uhpGateway,
        userManager: userManager
    )
    
    TestMainView(previewTab: .map, previewLastMessage: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false))
        .environmentObject(authManager)
        .environmentObject(APIClient())
        .environmentObject(uhpGateway)
        .environmentObject(trackingManager)
        .environmentObject(locationManager)
        .environmentObject(userManager)
        .environmentObject(chatViewModel)
}

#Preview("Journey Tab with last assistant message") {
    let uhpGateway = UHPGateway()
    let trackingManager = TrackingManager()
    let locationManager = LocationManager()  // Still needed for geocoding/geofencing
    let userManager = UserManager()
    let authManager = AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7")
    let chatViewModel = ChatViewModel(
        uhpGateway: uhpGateway,
        userManager: userManager
    )
    
    TestMainView(previewTab: .journey, previewLastMessage: ChatMessage(text: "Maximus morbi habitasse dictumst curae aenean fermentum senectus nunc elementum quis pretium, dui feugiat gravida sem ad tempor conubia vehicula tortor volutpat, facilisis pulvinar nam fusce praesent ac commodo himenaeos donec lorem. Quis ullamcorper porttitor vitae placerat ad dis eu habitasse venenatis, rhoncus cursus suspendisse in adipiscing posuere mattis tristique donec, rutrum nostra congue velit mauris malesuada montes consequat. Mus est natoque nibh torquent hendrerit scelerisque phasellus consequat auctor praesent, diam neque venenatis quisque cursus vestibulum taciti curae congue, lorem etiam proin accumsan potenti montes tincidunt donec magna.", isUser: false, isStreaming: false))
        .environmentObject(authManager)
        .environmentObject(APIClient())
        .environmentObject(uhpGateway)
        .environmentObject(trackingManager)
        .environmentObject(locationManager)
        .environmentObject(userManager)
        .environmentObject(chatViewModel)
}
#endif


