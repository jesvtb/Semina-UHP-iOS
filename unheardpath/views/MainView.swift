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
    @State var showCacheDebugSheet: Bool = false
    @State var showSSEContentTestSheet: Bool = false
    @State var showPersistenceDebugSheet: Bool = false
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

            
            LiveUpdateStack(
                message: chatManager.lastMessage,
                currentToastData: $toastManager.currentToastData,
                isExpanded: $chatManager.isMessageExpanded,
                onDismiss: {
                    chatManager.dismissLastMsg()
                },
                stretchableInputVM: stretchableInputVM,
                onLocationSelected: { locationDetail in
                    mapFeaturesManager.flyToLocation = FlyToLocation(locationDetail: locationDetail)
                    autocompleteManager.clearSearchResults()
                    stretchableInputVM.inputLocation = ""
                },
                onAutocompleteResultSelected: { result in
                    Task { @MainActor in
                        await flyToLocation(result: result)
                    }
                },
                isChatButtonVisible: selectedTab != .chat,
                onSwitchToChat: {
                    selectedTab = .chat
                },
                isJourneyButtonVisible: selectedTab == .chat,
                onSwitchToJourney: {
                    selectedTab = .journey
                }
            )
            .opacity(shouldHideTabBar ? 0 : 1)
            .allowsHitTesting(!shouldHideTabBar)
            .animation(.easeInOut(duration: 0.2), value: shouldHideTabBar)
            
            // Avatar / profile button overlay
            avatarButton
            
            // Debug cache button overlay
            #if DEBUG
            debugCacheButton
            debugSSEContentTestButton
            debugPersistenceButton
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
            // .background(Color.red)
            // .overlay(
            //     Divider()
            //         .background(Color("onBkgTextColor30")),
            //     alignment: .top 
            // )
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
        .sheet(isPresented: $showPersistenceDebugSheet) {
            CataloguePersistenceDebugView()
                .environmentObject(catalogueManager)
                .environmentObject(eventManager)
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
            if newMode != .autocomplete {
                // Clear autocomplete state when leaving autocomplete mode
                autocompleteManager.clearSearchResults()
                stretchableInputVM.inputLocation = ""
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
