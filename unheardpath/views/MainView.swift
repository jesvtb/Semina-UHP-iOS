import SwiftUI
@preconcurrency import MapKit

// MARK: - Input Tab Selection
enum PreviewTabSelection: Int, CaseIterable {
    case journey = 0
    case map = 1
    case chat = 2
    case profile = 3
}

// MARK: - Chat State
/// Manages chat-related state: messages and draft message
@MainActor
class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draftMessage: String = ""
}

struct TestMainView: View {
    @EnvironmentObject var uhpGateway: UHPGateway
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var userManager: UserManager
    
    // Preview values for preview purposes
    private let previewTab: PreviewTabSelection?
    private let previewMessages: [ChatMessage]?
    private let previewGeoJSONData: [String: Any]?
    private let previewLastMessage: ChatMessage?
    private let previewCurrentNotification: NotificationData?
    
    @StateObject var chatState = ChatState()
    @State private var selectedTab: PreviewTabSelection = .journey
    @State var geoJSONUpdateTrigger: UUID = UUID()
    @State private var shouldHideTabBar: Bool = false
    @StateObject var liveUpdateViewModel = LiveUpdateViewModel()
    @State var shouldDismissKeyboard: Bool = false
    
    // Location-related state
    @State private var isLoadingLocation = false
    @State private var lastSentLocation: (latitude: Double, longitude: Double)?
    @State var poisGeoJSON = GeoJSON()
    @State private var hasReceivedFirstGPSUpdate = false
    @FocusState var isTextFieldFocused: Bool
    
    // Autocomplete state for map tab
    @StateObject var addressSearchManager = AddressSearchManager()
    @State var targetLocation: TargetLocation?
    @State private var selectedLocation: CLLocation?
    
    // Debug cache overlay state
    #if DEBUG
    @State private var showCacheDebugSheet: Bool = false
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
        previewCurrentNotification: NotificationData? = nil
    ) {
        self.previewTab = previewTab
        self.previewMessages = previewMessages
        self.previewGeoJSONData = previewGeoJSONData
        self.previewLastMessage = previewLastMessage
        self.previewCurrentNotification = previewCurrentNotification
    }

    var body: some View {
        ZStack {
            MapboxMapView(
                poisGeoJSON: $poisGeoJSON,
                geoJSONUpdateTrigger: $geoJSONUpdateTrigger,
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
                    messages: chatState.messages,
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
                        standardContent: buildContentSections(),
                        customBuilders: nil
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

            
            if let lastMessage = liveUpdateViewModel.lastMessage, selectedTab != .chat {
                LiveUpdateStack(
                    message: lastMessage,
                    currentNotification: $liveUpdateViewModel.currentNotification,
                    isExpanded: $liveUpdateViewModel.isMessageExpanded,
                    onDismiss: {
                        liveUpdateViewModel.dismissMessage()
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
            #endif
        }
        // Input bar pinned to bottom; moves with keyboard
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                ChatInputBar(
                    selectedTab: selectedTab,
                    draftMessage: $chatState.draftMessage,
                    inputLocation: $liveUpdateViewModel.inputLocation,
                    isTextFieldFocused: $isTextFieldFocused,
                    onSendMessage: {
                        Task { @MainActor in
                            await sendMessage()
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
        .onChange(of: locationManager.isLocationPermissionGranted) { isGranted in
            // Request one-time location when permission is granted
            if isGranted && !hasReceivedFirstGPSUpdate {
                locationManager.requestOneTimeLocation()
            }
        }
        .onChange(of: locationManager.deviceLocation) { newLocation in
            // Call refreshPOIList only once when one-time location request completes
            // This handles the response from requestOneTimeLocation() (not continuous tracking)
            if let location = newLocation,
               !hasReceivedFirstGPSUpdate,
               location.horizontalAccuracy > 0,  // Positive accuracy means it's a real GPS reading
               location.horizontalAccuracy <= 100,  // Within 100m accuracy
               abs(location.timestamp.timeIntervalSinceNow) < 10 {  // Location is recent (within 10 seconds), not cached
                hasReceivedFirstGPSUpdate = true
                Task {
                    await refreshPOIListOnOneTimeLocation(location: location)
                }
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
        #endif
        .task { @MainActor in
            // Set preview values if provided (for preview purposes)
            if let previewTab = previewTab {
                selectedTab = previewTab
            }
            if let previewMessages = previewMessages {
                chatState.messages = previewMessages
            }
            if let previewGeoJSONData = previewGeoJSONData {
                // Extract features from preview data and set to poisGeoJSON
                do {
                    let features = try GeoJSON.extractFeatures(from: previewGeoJSONData)
                    poisGeoJSON.setFeatures(features)
                    geoJSONUpdateTrigger = UUID()
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to extract features from preview GeoJSON data: \(error)")
                    #endif
                }
            }
            if let previewLastMessage = previewLastMessage {
                liveUpdateViewModel.lastMessage = previewLastMessage
            }
            if let previewCurrentNotification = previewCurrentNotification {
                liveUpdateViewModel.currentNotification = previewCurrentNotification
            }
            
            // Request one-time location update for initial POI list refresh
            // This is more battery-efficient than continuous updates
            if locationManager.isLocationPermissionGranted {
                locationManager.requestOneTimeLocation()
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
            } else if locationManager.deviceLocation != nil {
                // No valid geofence, load data from cache or API
                // await loadLocationFromGeofenceExit()
            }
        }
    }
    
    // MARK: - Content Building
    /// Builds content sections from current state
    private func buildContentSections() -> [ContentSection] {
        var sections: [ContentSection] = []
        
        // Add location detail section if device location is available
        if let deviceLocation = locationManager.deviceLocation {
            sections.append(ContentSection(
                type: .locationDetail,
                data: .locationDetail(location: deviceLocation)
            ))
        }
        
        // Extract POIs from GeoJSON and add points of interest section
        let pois = extractPOIs(from: poisGeoJSON)
        if !pois.isEmpty {
            sections.append(ContentSection(
                type: .pointsOfInterest,
                data: .pointsOfInterest(features: pois)
            ))
        }
        
        return sections
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
            let defaults = UserDefaults.standard
            let dict = defaults.dictionaryRepresentation()
            
            // Filter cache keys (PlacesCache_ and wiki_)
            let cacheKeys = dict.keys.filter { key in
                key.hasPrefix("UHP.") && (
                    key.contains("PlacesCache_") || key.contains("wiki_")
                )
            }
            
            var breakdown: [(key: String, size: Int, formattedSize: String)] = []
            var totalSize = 0
            
            for key in cacheKeys.sorted() {
                if let value = dict[key] {
                    let valueString = "\(value)"
                    let size = valueString.data(using: .utf8)?.count ?? 0
                    totalSize += size
                    
                    let keyWithoutPrefix = key.hasPrefix("UHP.") ? String(key.dropFirst(4)) : key
                    let formattedSize = formatBytes(size)
                    breakdown.append((key: keyWithoutPrefix, size: size, formattedSize: formattedSize))
                }
            }
            
            return (
                entryCount: cacheKeys.count,
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
    TestMainView(previewTab: .map, previewLastMessage: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false))
        .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
        .environmentObject(APIClient())
        .environmentObject(UHPGateway())
        .environmentObject(LocationManager())
        .environmentObject(UserManager())
}

#Preview("Journey Tab with last assistant message") {
    TestMainView(previewTab: .journey, previewLastMessage: ChatMessage(text: "Maximus morbi habitasse dictumst curae aenean fermentum senectus nunc elementum quis pretium, dui feugiat gravida sem ad tempor conubia vehicula tortor volutpat, facilisis pulvinar nam fusce praesent ac commodo himenaeos donec lorem. Quis ullamcorper porttitor vitae placerat ad dis eu habitasse venenatis, rhoncus cursus suspendisse in adipiscing posuere mattis tristique donec, rutrum nostra congue velit mauris malesuada montes consequat. Mus est natoque nibh torquent hendrerit scelerisque phasellus consequat auctor praesent, diam neque venenatis quisque cursus vestibulum taciti curae congue, lorem etiam proin accumsan potenti montes tincidunt donec magna.", isUser: false, isStreaming: false))
        .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
        .environmentObject(APIClient())
        .environmentObject(UHPGateway())
        .environmentObject(LocationManager())
        .environmentObject(UserManager())
}
#endif


