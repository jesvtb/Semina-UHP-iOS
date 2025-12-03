import SwiftUI
import MapKit

// MARK: - Input Tab Selection
enum PreviewTabSelection: Int, CaseIterable {
    case journey = 0
    case map = 1
    case chat = 2
    case profile = 3
}

struct TestMainView: View {
    @EnvironmentObject var uhpGateway: UHPGateway
    @EnvironmentObject var locationManager: LocationManager
    
    // Preview values for preview purposes
    private let previewTab: PreviewTabSelection?
    private let previewMessages: [ChatMessage]?
    private let previewGeoJSONData: [String: Any]?
    private let previewLastMessage: ChatMessage?
    private let previewCurrentNotification: NotificationData?
    
    @State private var messages: [ChatMessage] = []
    @State private var draftMessage: String = ""
    @State private var inputLocation: String = ""
    @State private var selectedTab: PreviewTabSelection = .journey
    @State private var geoJSONData: [String: Any]?
    @State private var geoJSONUpdateTrigger: UUID = UUID()
    @State private var shouldHideTabBar: Bool = false
    @State private var lastMessage: ChatMessage?
    @State private var currentNotification: NotificationData?
    @State private var shouldDismissKeyboard: Bool = false
    @State private var isMessageExpanded: Bool = false
    
    // Location-related state
    @State private var isLoadingLocation = false
    @State private var lastSentLocation: (latitude: Double, longitude: Double)?
    @FocusState private var isTextFieldFocused: Bool
    
    // Autocomplete state for map tab
    @StateObject private var addressSearchManager = AddressSearchManager()
    @State private var shouldSearchAround: Bool = false
    @State private var targetLocation: TargetLocation?
    
    // Sheet snap point control - universal binding for bidirectional control
    @State private var sheetSnapPoint: SnapPoint = .partial
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
            // Background stays fixed
            // Color("AccentColor")
            //     .ignoresSafeArea(.container)
            //     .ignoresSafeArea(.keyboard)

            MapboxMapView(
                geoJSONData: $geoJSONData,
                geoJSONUpdateTrigger: $geoJSONUpdateTrigger,
                targetLocation: $targetLocation
            )
                .ignoresSafeArea(.container)
                .ignoresSafeArea(.keyboard)
                .contentShape(Rectangle())
                .onTapGesture {
                    isTextFieldFocused = false
                }
            // Main content (messages list)
            if selectedTab == .chat {
                VStack {
                    ChatDetailView(messages: messages)

                    Spacer(minLength: 0) // keeps list separate from inset
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isTextFieldFocused = false
                }
            }
            
            // Journey bottom sheet - positioned absolutely to avoid affecting layout
            if selectedTab == .journey {
                GeometryReader { geometry in
                    InfoSheet(
                        selectedTab: $selectedTab,
                        shouldHideTabBar: $shouldHideTabBar,
                        sheetFullHeight: sheetFullHeight,
                        bottomSafeAreaInsetHeight: bottomSafeAreaInsetHeight,
                        sheetSnapPoint: $sheetSnapPoint
                    )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height - (sheetFullHeight / 2) // Dynamic: half of actual sheet height
                        )
                } 
            }

            
            if let lastMessage = lastMessage, selectedTab != .chat {
                liveUpdateStack(
                    message: lastMessage,
                    currentNotificationBinding: $currentNotification,
                    isExpanded: $isMessageExpanded,
                    onDismiss: {
                        self.lastMessage = nil
                        self.isMessageExpanded = false
                    }
                )
                .opacity(shouldHideTabBar ? 0 : 1)
                .allowsHitTesting(!shouldHideTabBar)
            }
            
            // Show autocomplete results in map tab
            if selectedTab == .map && !addressSearchManager.results.isEmpty && !inputLocation.isEmpty {
                AddrSearchResultsList
                    .opacity(shouldHideTabBar ? 0 : 1)
                    .allowsHitTesting(!shouldHideTabBar)
            }
        }
        // Input bar pinned to bottom; moves with keyboard
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                chatInputBar
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
        }
        .onChange(of: shouldDismissKeyboard) { shouldDismiss in
            if shouldDismiss {
                isTextFieldFocused = false
            }
        }
        .onChange(of: locationManager.deviceLocation) { newLocation in
            // Only make API call when location is captured and change is significant
            // Skip if this is the initial load (handled by .task)
            if newLocation != nil {
                Task {
                    await loadLocationIfSignificant()
                }
            }
            // Update search completer region when location changes (if shouldSearchAround is true)
            if selectedTab == .map && shouldSearchAround {
                setupSearchCompleter()
            }
        }
        .onChange(of: inputLocation) { newValue in
            // Update autocomplete when typing in map tab
            if selectedTab == .map {
                updateAutocomplete(query: newValue)
            }
        }
        .onChange(of: selectedTab) { newTab in
            // Clear autocomplete results when switching away from map tab
            if newTab != .map {
                addressSearchManager.clearResults()
            } else {
                // Initialize search completer when entering map tab
                setupSearchCompleter()
            }
        }
        .onChange(of: shouldSearchAround) { _ in
            // Reconfigure search completer when shouldSearchAround changes
            if selectedTab == .map {
                setupSearchCompleter()
            }
        }
        .task { @MainActor in
            // Set preview values if provided (for preview purposes)
            if let previewTab = previewTab {
                selectedTab = previewTab
            }
            if let previewMessages = previewMessages {
                messages = previewMessages
            }
            if let previewGeoJSONData = previewGeoJSONData {
                geoJSONData = previewGeoJSONData
                geoJSONUpdateTrigger = UUID()
            }
            if let previewLastMessage = previewLastMessage {
                lastMessage = previewLastMessage
            }
            if let previewCurrentNotification = previewCurrentNotification {
                currentNotification = previewCurrentNotification
            }
            
            // Initialize search completer if starting in map tab
            if selectedTab == .map {
                setupSearchCompleter()
            }
            
            // Initial load: If location is already available, call immediately (first time)
            // Otherwise, wait for onChange to trigger when location is captured
            // Use a small delay to avoid race condition with onChange
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
            if locationManager.deviceLocation != nil {
                await loadLocationIfSignificant()
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

// MARK: - TestMainView: View Components
extension TestMainView {
    private func liveUpdateStack(message: ChatMessage, currentNotificationBinding: Binding<NotificationData?>, isExpanded: Binding<Bool>, onDismiss: @escaping () -> Void) -> some View {
        // Helper to check if text would exceed 3 lines
        let estimatedLineCount = Typography.estimateLineCount(for: message.text, font: UIFont.systemFont(ofSize: 15), maxWidth: UIScreen.main.bounds.width - 80)
        let shouldShowExpandButton = estimatedLineCount > 5
        let bkgColor = message.isUser ? Color("AccentColor") : Color("onBkgTextColor30")
        
        return VStack {
            Spacer()
            if let notification = currentNotificationBinding.wrappedValue {
                ProgressNotificationBanner(
                    notification: notification,
                    onNotificationDismiss: {
                        currentNotificationBinding.wrappedValue = nil
                    }
                )
            }
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
                            .lineLimit(isExpanded.wrappedValue ? nil : 5)
                            
                        
                        // Expand/Collapse button - only show if text is longer than 3 lines
                        if shouldShowExpandButton {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isExpanded.wrappedValue.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(isExpanded.wrappedValue ? "Show less" : "Show more")
                                            .bodyText(size: .articleMinus1)
                                        Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
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
                    
                    // Dismiss button positioned at upper right corner, overlapping the border
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onDismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("AppBkgColor"))
                            .padding(Spacing.current.space2xs)
                            .background(bkgColor)
                            .clipShape(Circle())
                    }
                    .padding(.top, -6)
                    .padding(.trailing, -6)
                }
                
                .padding(.horizontal, Spacing.current.spaceXs)
                Spacer()
            }
        }
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
        .background(Color.clear)
    }
    
    
    private var AddrSearchResultsList: some View {
        let searchResults = addressSearchManager.results
        let lastIndex = searchResults.count - 1
        
        return VStack {
            Spacer()
            VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                    let isMostRelevant = index == lastIndex
                    
                    AddrSearchResultItem(
                        result: result,
                        isMostRelevant: isMostRelevant,
                        onSelect: { selectedResult in
                            // Handle selection - geocode and update map
                            inputLocation = selectedResult.title
                            addressSearchManager.clearResults()
                            isTextFieldFocused = false
                            
                            // Geocode the selected location and fly to it
                            Task {
                                await geocodeAndFlyToLocation(completion: selectedResult)
                            }
                        }
                    )
                }
            }
            .padding(.top, Spacing.current.spaceXs)
            .padding(.horizontal, Spacing.current.spaceXs)
            .background(Color("AppBkgColor"))
        }
    }
    
    private var chatInputBar: some View {
        HStack(spacing: Spacing.current.spaceXs) {
            TextField(
                selectedTab == .map ? "Find any place..." : "Ask any thing...",
                text: selectedTab == .map ? $inputLocation : $draftMessage,
                axis: .vertical
            )
                .bodyText()
                .focused($isTextFieldFocused)
                .padding(.horizontal, Spacing.current.spaceXs)
                .padding(.vertical, Spacing.current.space2xs)
                .background(Color("AppBkgColor"))
                .cornerRadius(Spacing.current.spaceXs)

            if selectedTab != .chat && selectedTab != .map {
                Button(action: {
                    selectedTab = .chat
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .bodyText(size: .article0)
                        .foregroundColor(Color("onBkgTextColor30"))
                }
            }
            if selectedTab != .map {
                Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .bodyText(size: .article2)
                    .foregroundColor(draftMessage.isEmpty ? Color("onBkgTextColor30") : Color("onBkgTextColor10"))
                }
                .disabled(draftMessage.isEmpty)
            }
            // if selectedTab == .map {
            //     Button(action: {
            //         // Geocode the selected location and fly to it
            //         Task {
                        
            //         }
            //     }) {
            //     Image(systemName: "mappin.circle.fill")
            //         .bodyText(size: .article2)
            //         .foregroundColor(draftMessage.isEmpty ? Color("onBkgTextColor30") : Color("onBkgTextColor10"))
            //     }
            //     .disabled(draftMessage.isEmpty)
            // }
           
        }
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.space2xs)
        .background(
            Color("AppBkgColor")
                // .opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - TestMainView: Actions
extension TestMainView {
    private func sendMessage() {
        guard draftMessage.isEmpty == false else { return }
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        Task {
            await sendChatMessage(text)
        }
        
        draftMessage = ""
        isTextFieldFocused = false // Dismiss keyboard after sending
    }
    
    // MARK: - Chat Message Handling
    private func sendChatMessage(_ messageText: String) async {
        #if DEBUG
        print("🚀 sendChatMessage() called with message: '\(messageText)'")
        #endif
        
        // Validate message is not empty
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            #if DEBUG
            print("⚠️ sendChatMessage: Message is empty after trimming, not sending")
            #endif
            return
        }
        
        // Add user message to chat immediately on main actor
        await MainActor.run {
            let userMessage = ChatMessage(text: trimmedMessage, isUser: true, isStreaming: false)
            messages.append(userMessage)
            // Update lastMessage for the bubble display
            lastMessage = userMessage
            #if DEBUG
            print("✅ User message added to chat. Total messages: \(messages.count)")
            #endif
        }
        
        // Create assistant message placeholder for streaming
        await MainActor.run {
            messages.append(ChatMessage(text: "", isUser: false, isStreaming: true))
            #if DEBUG
            print("✅ Assistant placeholder added. Total messages: \(messages.count)")
            #endif
        }
        
        do {
            // Prepare request data (use trimmed message)
            var jsonDict: [String: Any] = [
                "message": trimmedMessage
            ]
            
            // Add device date, time, and day of week (separated)
            let now = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            
            // Date format: yyyy-MM-dd
            dateFormatter.dateFormat = "yyyy-MM-dd"
            jsonDict["current_date"] = dateFormatter.string(from: now)
            
            // Time format: HH:mm:ss
            dateFormatter.dateFormat = "HH:mm:ss"
            jsonDict["current_time"] = dateFormatter.string(from: now)
            
            // Day of week format: Full day name (Monday, Tuesday, etc.)
            dateFormatter.dateFormat = "EEEE"
            jsonDict["current_weekday"] = dateFormatter.string(from: now)
            
            // Add device language
            let languageCode: String
            if #available(iOS 16.0, *) {
                languageCode = Locale.current.language.languageCode?.identifier ?? "en"
            } else {
                languageCode = Locale.current.languageCode ?? "en"
            }
            jsonDict["device_lang"] = languageCode
            
            // Add location details from LocationManager
            // Use empty string if location details are not available
            if let deviceLocationDetails = locationManager.locationDetails {
                jsonDict["last_device_location"] = deviceLocationDetails
            } else {
                jsonDict["last_device_location"] = ""
            }
            
            if let lookupLocationDetails = locationManager.lookupLocationDetails {
                jsonDict["last_lookup_location"] = lookupLocationDetails
            } else {
                jsonDict["last_lookup_location"] = ""
            }
            
            #if DEBUG
            print("💬 Preparing API request:")
            print("   Endpoint: /v1/ask")
            print("   Method: POST")
            print("   Message: '\(trimmedMessage)'")
            print("   JSON Dict: \(jsonDict)")
            #endif
            
            // Use streaming API to receive notifications and content
            #if DEBUG
            print("📡 Calling uhpGateway.stream()...")
            #endif

            let stream = try await uhpGateway.stream(
                endpoint: "/v1/ask",
                jsonDict: jsonDict
            )
            #if DEBUG
            print("✅ Stream received from uhpGateway.stream()")
            #endif
            
            #if DEBUG
            print("✅ Stream created, starting to process events...")
            #endif
            
            var streamingContent = ""
            
            // Process SSE events from stream
            var eventCount = 0
            for try await event in stream {
                eventCount += 1
                #if DEBUG
                print("📨 SSE Event #\(eventCount) received:")
                print("   Event type: \(event.event ?? "nil")")
                print("   Data: \(event.data.prefix(100))...")
                #endif
                
                await handleChatStreamEvent(event: event, streamingContent: &streamingContent)
            }
            
            // Ensure the final assistant message is marked as not streaming
            await MainActor.run {
                if let lastIndex = messages.indices.last,
                   !messages[lastIndex].isUser {
                    let existingMessage = messages[lastIndex]
                    let updatedMessage = ChatMessage(
                        id: existingMessage.id,
                        text: existingMessage.text,
                        isUser: existingMessage.isUser,
                        isStreaming: false
                    )
                    messages[lastIndex] = updatedMessage
                    // Update lastMessage for the bubble display
                    lastMessage = updatedMessage
                    #if DEBUG
                    print("✅ Stream finished, marked last assistant message as not streaming")
                    #endif
                }
            }
            
            #if DEBUG
            print("✅ Stream processing completed. Total events: \(eventCount)")
            #endif
            
        } catch {
            #if DEBUG
            print("❌ Failed to send chat message:")
            print("   Error: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error localized description: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                print("   API Error message: \(apiError.message)")
                print("   API Error code: \(apiError.code ?? -1)")
            }
            #endif
            
            // Remove the streaming message placeholder on error
            await MainActor.run {
                if let lastIndex = messages.indices.last,
                   !messages[lastIndex].isUser,
                   messages[lastIndex].text.isEmpty {
                    messages.removeLast()
                    #if DEBUG
                    print("✅ Removed empty streaming message placeholder after error")
                    #endif
                }
            }
        }
    }
}



// MARK: - Scroll Offset Tracker
struct ScrollOffsetTracker: View {
    @Binding var offset: CGFloat
    @Binding var shouldHideTabBar: Bool
    let currentSnapPoint: SnapPoint
    let hideTabBarThreshold: CGFloat
    
    // Track previous offset to detect scroll direction
    @State private var previousOffset: CGFloat = 0
    // Track when tab bar was hidden (timestamp)
    @State private var tabBarHiddenTimestamp: Date?
    // Track if tab bar was just hidden (to handle state synchronization)
    @State private var wasTabBarHidden: Bool = false
    // Track if tab bar was just shown due to scroll up (to prevent immediate re-hiding)
    @State private var wasShownOnScrollUp: Bool = false
    // Time window for showing tab bar again when scrolling up (in seconds)
    private let showTabBarTimeWindow: TimeInterval = 2.0
    // Hysteresis: require scrolling down more than this amount after showing to hide again
    private let hideHysteresis: CGFloat = 10.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Invisible tracking element at the very top
            GeometryReader { geometry in
                let scrollOffset = geometry.frame(in: .named("scroll")).minY
                Color.clear
                    .preference(key: TestScrollOffsetPreferenceKey.self, value: scrollOffset)
            }
            .frame(height: 0) // Zero height for tracking only
            
            // Visual top edge marker
            // Rectangle()
            //     .fill(Color.blue)
            //     .frame(height: 2)
            //     .overlay(
            //         Text("TOP EDGE OF SCROLLVIEW")
            //             .font(.system(size: 8))
            //             .foregroundColor(.white)
            //             .padding(.horizontal, 4)
            //     )
        }
        .onPreferenceChange(TestScrollOffsetPreferenceKey.self) { newOffset in
            // Update state directly from GeometryReader offset
            if abs(offset - newOffset) > 0.01 {
                // Use current binding value as old offset (before update)
                let oldOffset = offset
                offset = newOffset
                
                // Only process if we're at full snap point
                guard currentSnapPoint == .full else {
                    previousOffset = newOffset
                    wasTabBarHidden = false
                    tabBarHiddenTimestamp = nil
                    return
                }
                
                // Detect scroll direction: scrolling up means offset is increasing (becoming less negative)
                let isScrollingUp = newOffset > oldOffset
                let isScrollingDownDirection = newOffset < oldOffset
                
                // Update our internal tracking of tab bar state
                let tabBarIsCurrentlyHidden = shouldHideTabBar || wasTabBarHidden
                
                // PRIORITY: If scrolling up and tab bar is currently hidden, check if we should show it again
                if isScrollingUp && tabBarIsCurrentlyHidden {
                    if let hiddenTimestamp = tabBarHiddenTimestamp {
                        let timeSinceHidden = Date().timeIntervalSince(hiddenTimestamp)
                        // Show tab bar if scrolling up within the time window
                        if timeSinceHidden <= showTabBarTimeWindow {
                            // Update immediately without animation to avoid opacity fade-in
                            shouldHideTabBar = false
                            tabBarHiddenTimestamp = nil
                            wasTabBarHidden = false
                            wasShownOnScrollUp = true
                            previousOffset = newOffset
                            #if DEBUG
                            print("📊 ScrollOffsetTracker: Showing tab bar on scroll up (time since hidden: \(String(format: "%.2f", timeSinceHidden))s, offset: \(String(format: "%.2f", newOffset)))")
                            #endif
                            return
                        } else {
                            // Time window expired, clear timestamp
                            tabBarHiddenTimestamp = nil
                            wasTabBarHidden = false
                            wasShownOnScrollUp = false
                            #if DEBUG
                            print("📊 ScrollOffsetTracker: Time window expired (time since hidden: \(String(format: "%.2f", timeSinceHidden))s)")
                            #endif
                        }
                    } else if newOffset >= hideTabBarThreshold {
                        // No timestamp recorded, but scrolling up above threshold - show it
                        // Update immediately without animation to avoid opacity fade-in
                        shouldHideTabBar = false
                        wasTabBarHidden = false
                        wasShownOnScrollUp = true
                        previousOffset = newOffset
                        #if DEBUG
                        print("📊 ScrollOffsetTracker: Showing tab bar on scroll up (no timestamp, but offset \(String(format: "%.2f", newOffset)) above threshold \(hideTabBarThreshold))")
                        #endif
                        return
                    }
                }
                
                // If tab bar was shown on scroll up, add hysteresis to prevent flickering
                // Only hide again if scrolling down significantly past the threshold
                let effectiveHideThreshold = wasShownOnScrollUp ? (hideTabBarThreshold - hideHysteresis) : hideTabBarThreshold
                let shouldHide = newOffset < effectiveHideThreshold
                
                // If scrolling down and we were shown on scroll up, clear that flag
                if isScrollingDownDirection && wasShownOnScrollUp {
                    // Only clear if we've scrolled down significantly
                    if newOffset < effectiveHideThreshold {
                        wasShownOnScrollUp = false
                    }
                }
                
                // If hiding the tab bar, record the timestamp
                if shouldHide {
                    if !wasTabBarHidden {
                        tabBarHiddenTimestamp = Date()
                        wasTabBarHidden = true
                        wasShownOnScrollUp = false
                        #if DEBUG
                        print("📊 ScrollOffsetTracker: Hiding tab bar at offset \(String(format: "%.2f", newOffset)), threshold: \(effectiveHideThreshold)")
                        #endif
                    }
                } else {
                    // Not scrolled down - clear tracking state
                    wasTabBarHidden = false
                    tabBarHiddenTimestamp = nil
                    // Keep wasShownOnScrollUp true if we're above threshold (user is still near top)
                    if newOffset >= hideTabBarThreshold {
                        wasShownOnScrollUp = false
                    }
                }
                
                // Update tab bar visibility
                withAnimation(.easeInOut(duration: 0.2)) {
                    shouldHideTabBar = shouldHide
                }
                
                previousOffset = newOffset
            }
        }
    }
}

// MARK: - Test Scroll Offset Preference Key
struct TestScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Autocomplete Management
extension TestMainView {
    /// Sets up the address search manager
    /// When shouldSearchAround is true: prioritizes results near the user's location
    /// When shouldSearchAround is false: searches globally without location bias
    private func setupSearchCompleter() {
        // Set region based on shouldSearchAround flag
        if shouldSearchAround {
            // Prioritize nearby results - use user's location if available
            if let latitude = locationManager.latitude,
               let longitude = locationManager.longitude {
                let userLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                // Set a moderate region around user location (50km radius)
                addressSearchManager.configureRegionSearch(center: userLocation, meters: 50_000)
            }
            // If location not available, region defaults to device location prioritization
        } else {
            // Global search - set a very large region to minimize location bias
            addressSearchManager.configureGlobalSearch()
        }
    }
    
    /// Updates autocomplete query
    private func updateAutocomplete(query: String) {
        addressSearchManager.updateQuery(query)
    }
    
    /// Geocodes a selected autocomplete result and flies to that location on the map
    /// Uses MKLocalSearch to get coordinates from MKLocalSearchCompletion
    private func geocodeAndFlyToLocation(completion: MKLocalSearchCompletion) async {
        #if DEBUG
        print("\n" + String(repeating: "=", count: 80))
        print("🔍 MKLocalSearchCompletion - All Available Properties")
        print(String(repeating: "=", count: 80))
        
        // Print title
        print("📝 title: String")
        print("   Value: \(completion.title)")
        
        // Print titleHighlightRanges
        print("\n✨ titleHighlightRanges: [NSValue]")
        print("   Count: \(completion.titleHighlightRanges.count)")
        for (index, rangeValue) in completion.titleHighlightRanges.enumerated() {
            let range = rangeValue.rangeValue
            let startIndex = completion.title.index(completion.title.startIndex, offsetBy: range.location)
            let endIndex = completion.title.index(startIndex, offsetBy: range.length)
            let highlightedText = String(completion.title[startIndex..<endIndex])
            print("   Range #\(index + 1): location=\(range.location), length=\(range.length)")
            print("   Highlighted text: \"\(highlightedText)\"")
        }
        
        // Print subtitle
        print("\n📄 subtitle: String")
        print("   Value: \(completion.subtitle)")
        
        // Print subtitleHighlightRanges
        print("\n✨ subtitleHighlightRanges: [NSValue]")
        print("   Count: \(completion.subtitleHighlightRanges.count)")
        for (index, rangeValue) in completion.subtitleHighlightRanges.enumerated() {
            let range = rangeValue.rangeValue
            let startIndex = completion.subtitle.index(completion.subtitle.startIndex, offsetBy: range.location)
            let endIndex = completion.subtitle.index(startIndex, offsetBy: range.length)
            let highlightedText = String(completion.subtitle[startIndex..<endIndex])
            print("   Range #\(index + 1): location=\(range.location), length=\(range.length)")
            print("   Highlighted text: \"\(highlightedText)\"")
        }
        
        print(String(repeating: "=", count: 80) + "\n")
        #endif
        
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            
            #if DEBUG
            print("\n" + String(repeating: "=", count: 80))
            print("🔍 MKLocalSearch.Response - All Available Properties")
            print(String(repeating: "=", count: 80))
            
            // Print mapItems
            print("📋 mapItems: [MKMapItem]")
            print("   Count: \(response.mapItems.count)")
            for (index, mapItem) in response.mapItems.enumerated() {
                print("   --- MapItem #\(index + 1) ---")
                print("   • Name: \(mapItem.name ?? "nil")")
                print("   • Phone Number: \(mapItem.phoneNumber ?? "nil")")
                print("   • URL: \(mapItem.url?.absoluteString ?? "nil")")
                let placemark = mapItem.placemark
                
                print("\n   📍 Placemark - Full Address Components:")
                print("   • Location: \(placemark.location?.coordinate.latitude ?? 0), \(placemark.location?.coordinate.longitude ?? 0)")
                print("   • Name: \(placemark.name ?? "nil")")
                
                // Street address components
                print("\n   🏠 Street Address:")
                print("   • Sub Thoroughfare (Street Number): \(placemark.subThoroughfare ?? "nil")")
                print("   • Thoroughfare (Street Name): \(placemark.thoroughfare ?? "nil")")
                print("   • Sub Locality: \(placemark.subLocality ?? "nil")")
                
                // City/Region components
                print("\n   🏙️ City/Region:")
                print("   • Locality (City): \(placemark.locality ?? "nil")")
                print("   • Sub Administrative Area: \(placemark.subAdministrativeArea ?? "nil")")
                print("   • Administrative Area (State/Province): \(placemark.administrativeArea ?? "nil")")
                print("   • Postal Code: \(placemark.postalCode ?? "nil")")
                
                // Country components
                print("\n   🌍 Country:")
                print("   • Country: \(placemark.country ?? "nil")")
                print("   • ISO Country Code: \(placemark.isoCountryCode ?? "nil")")
                
                // Additional placemark properties
                print("\n   📋 Additional Properties:")
                print("   • Areas of Interest: \(placemark.areasOfInterest?.joined(separator: ", ") ?? "nil")")
                print("   • Inland Water: \(placemark.inlandWater ?? "nil")")
                print("   • Ocean: \(placemark.ocean ?? "nil")")
                if let region = placemark.region as? CLCircularRegion {
                    print("   • Region Center: \(region.center.latitude), \(region.center.longitude)")
                    print("   • Region Radius: \(Int(region.radius))m")
                    print("   • Region Identifier: \(region.identifier)")
                }
                print("   • Timezone: \(placemark.timeZone?.identifier ?? "nil")")
                
                print("\n   🎯 MapItem Properties:")
                print("   • Point of Interest Category: \(mapItem.pointOfInterestCategory?.rawValue ?? "nil")")
                print("   • Is Current Location: \(mapItem.isCurrentLocation)")
            }
            
            // Print boundingRegion
            print("\n🌍 boundingRegion: MKCoordinateRegion")
            print("   • Center: \(response.boundingRegion.center.latitude), \(response.boundingRegion.center.longitude)")
            print("   • Span: \(response.boundingRegion.span.latitudeDelta) lat, \(response.boundingRegion.span.longitudeDelta) lon")
            print(String(repeating: "=", count: 80) + "\n")
            #endif
            
            guard let mapItem = response.mapItems.first,
                  let location = mapItem.placemark.location else {
                #if DEBUG
                print("⚠️ No location found for selected autocomplete result")
                #endif
                return
            }
            
            #if DEBUG
            print("✅ Geocoded '\(completion.title)' to: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            #endif
            
            // Construct lookup place dictionary and update lookupLocationDetails
            let placemark = mapItem.placemark
            let lookupDict = locationManager.constructLookupLocation(
                location: location,
                placemark: placemark,
                mapItemName: mapItem.name
            )
            locationManager.lookupLocationDetails = lookupDict
            
            #if DEBUG
            print("📦 Constructed lookup place dict: \(lookupDict)")
            print("✅ Updated lookupLocationDetails in LocationManager")
            if let fullAddress = lookupDict["full_address"] as? String {
                print("   Full address: \(fullAddress)")
            }
            #endif
            
            // Save lookup location to UserDefaults
            locationManager.saveLookupLocation(location)
            
            // Update target location to trigger map camera update and show marker
            let placeName = lookupDict["place"] as? String
            await MainActor.run {
                targetLocation = TargetLocation(location: location, name: placeName)
                // Clear autocomplete results and input location after flying to the location
                addressSearchManager.clearResults()
                inputLocation = ""
                isTextFieldFocused = false
            }
        } catch {
            #if DEBUG
            print("❌ Failed to geocode autocomplete result: \(error.localizedDescription)")
            #endif
        }
    }
}


// MARK: - Location Management
extension TestMainView {
    /// Checks if location change is significant (>= 0.001 for either coordinate)
    /// Returns true if change is significant or if this is the first location
    private func isLocationChangeSignificant(
        newLatitude: Double,
        newLongitude: Double
    ) -> Bool {
        // If we haven't sent a location before, always send it
        guard let lastSent = lastSentLocation else {
            return true
        }
        
        // Calculate differences
        let latDifference = abs(newLatitude - lastSent.latitude)
        let lonDifference = abs(newLongitude - lastSent.longitude)
        
        // Only make request if change is >= 0.001 (3rd decimal place) for either coordinate
        let threshold: Double = 0.001
        let isSignificant = latDifference >= threshold || lonDifference >= threshold
        
        #if DEBUG
        if isSignificant {
            print("📍 Significant location change detected:")
            print("   Old: [\(lastSent.latitude), \(lastSent.longitude)]")
            print("   New: [\(newLatitude), \(newLongitude)]")
            print("   Lat diff: \(latDifference), Lon diff: \(lonDifference)")
        } else {
            print("📍 Location change too small, skipping API call:")
            print("   Lat diff: \(latDifference), Lon diff: \(lonDifference) (threshold: \(threshold))")
        }
        #endif
        
        return isSignificant
    }
    
    /// Checks if location change is significant before making API call
    private func loadLocationIfSignificant() async {
        // Prevent concurrent API calls
        guard !isLoadingLocation else {
            #if DEBUG
            print("⏸️ API call already in progress, skipping duplicate request")
            #endif
            return
        }
        
        // Only proceed if location is actually available
        guard let latitude = locationManager.latitude,
              let longitude = locationManager.longitude else {
            #if DEBUG
            print("⚠️ Location not available yet, skipping API call")
            #endif
            return
        }
        
        // Check if location change is significant BEFORE reverse geocoding
        guard isLocationChangeSignificant(newLatitude: latitude, newLongitude: longitude) else {
            #if DEBUG
            print("⏸️ Location change not significant, skipping API call")
            #endif
            return
        }
        
        // Reverse geocode user location and get JSON dict
        #if DEBUG
        print("📍 Calling reverseGeocodeUserLocation() from loadLocationIfSignificant()")
        #endif
        
        let locationDict = await withCheckedContinuation { continuation in
            locationManager.reverseGeocodeUserLocation { dict, error in
                if let error = error {
                    #if DEBUG
                    print("⚠️ Reverse geocoding error: \(error.localizedDescription), using location only")
                    #endif
                    // Even if geocoding fails, dict should still have location data
                    continuation.resume(returning: dict)
                } else {
                    continuation.resume(returning: dict)
                }
            }
        }
        
        guard let locationDict = locationDict else {
            #if DEBUG
            print("❌ Failed to get location dict from reverse geocoding")
            #endif
            return
        }
        
        // Make the API call with the location dict
        await loadLocation(jsonDict: locationDict)
    }
    
    private func loadLocation(jsonDict: [String: Any]) async {
        isLoadingLocation = true
        defer { isLoadingLocation = false }
        
        // Extract latitude and longitude from jsonDict
        guard let userLat = jsonDict["latitude"] as? Double,
              let userLon = jsonDict["longitude"] as? Double else {
            #if DEBUG
            print("⚠️ Missing latitude or longitude in location dict")
            #endif
            return
        }
        
        // Check cache first
        if let cachedGeoJSON = locationManager.reconstructGeoJSONFromCache(userLat: userLat, userLon: userLon) {
            #if DEBUG
            print("✅ Using cached GeoJSON data")
            #endif
            // Update geoJSONData to trigger map update
            await MainActor.run {
                geoJSONData = cachedGeoJSON
                geoJSONUpdateTrigger = UUID()
            }
            // Update last sent location
            lastSentLocation = (latitude: userLat, longitude: userLon)
            return
        }
        
        // Cache miss - make API call
        do {
            #if DEBUG
            print("📍 Sending location to API: \(userLat), \(userLon)")
            print("📦 Full location dict: \(jsonDict)")
            #endif
            
            let response = try await uhpGateway.request(
                endpoint: "/v1/signed-in-home",
                method: "POST",
                jsonDict: jsonDict
            )
            
            // Update last sent location after successful API call
            lastSentLocation = (latitude: userLat, longitude: userLon)
            
            // Parse response: extract data field containing GeoJSON FeatureCollection
            // Response format: {result: {event: "map", data: {type: "FeatureCollection", features: [...]}}, status: "success", ...}
            guard let responseDict = response as? [String: Any],
                  let result = responseDict["result"] as? [String: Any],
                  let event = result["event"] as? String,
                  event == "map",
                  let data = result["data"] as? [String: Any],
                  let features = data["features"] as? [[String: Any]] else {
                #if DEBUG
                if let responseDict = response as? [String: Any] {
                    print("⚠️ Invalid response format. Available keys: \(responseDict.keys.joined(separator: ", "))")
                    if let result = responseDict["result"] as? [String: Any] {
                        print("   Result keys: \(result.keys.joined(separator: ", "))")
                    }
                } else {
                    print("⚠️ Invalid response format. Response is not a dictionary.")
                }
                #endif
                return
            }
            
            // Process features: extract idx and pageid, save to cache
            var featuresList: [[String: Any]] = []
            for feature in features {
                guard let properties = feature["properties"] as? [String: Any],
                      let idx = properties["idx"] as? Int,
                      let pageid = properties["pageid"] as? Int else {
                    continue
                }
                
                // Add to features list for location cache
                featuresList.append([
                    "idx": idx,
                    "pageid": pageid
                ])
                
                // Save individual feature to cache
                locationManager.saveCachedFeature(pageid: pageid, feature: feature)
            }
            
            // Save location cache with list of {idx, pageid}
            locationManager.saveCachedLocationData(userLat: userLat, userLon: userLon, features: featuresList)
            
            // Update geoJSONData to trigger map update
            // Format: {event: "map", data: {type: "FeatureCollection", features: [...]}}
            let geoJSONResponse: [String: Any] = [
                "event": event,
                "data": data
            ]
            await MainActor.run {
                geoJSONData = geoJSONResponse
                geoJSONUpdateTrigger = UUID()
            }
            
            #if DEBUG
            print("✅ GeoJSON data loaded and cached with \(featuresList.count) features")
            #endif
            
        } catch let apiError as APIError {
            #if DEBUG
            print("❌ API Error: \(apiError.message)")
            if let code = apiError.code {
                print("   Status Code: \(code)")
            }
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to load location: \(error.localizedDescription)")
            print("   Error type: \(type(of: error))")
            #endif
        }
    }
}

// MARK: - Chat SSE Workflows
extension TestMainView {
  
  /// Dispatches handling for different SSE event types coming from the chat stream.
  /// Keeps `sendChatMessage` focused on request/response orchestration while this
  /// function owns the per-event workflows.
  func handleChatStreamEvent(
    event: SSEEvent,
    streamingContent: inout String
  ) async {
    let eventType = (event.event ?? "").lowercased()
    
    switch eventType {
    case "notification":
      await handleNotificationEvent(event: event)
      
    case "content":
      await handleContentEvent(event: event, streamingContent: &streamingContent)
      
    case "finish":
      await handleSSEFinishEvent(event: event)
      
    case "map":
      await handleMapEvent()
      
    case "interface":
      await handleInterfaceEvent(event: event)
      
    default:
      #if DEBUG
      print("⚠️ Unknown or unsupported event type: \(event.event ?? "nil")")
      #endif
    }
  }
  
  /// Handles `finish` SSE events, which signal the end of streaming.
  /// Ensures the progress spinner is stopped and removed from the last
  /// assistant message by setting `isStreaming` to false or dropping an
  /// empty placeholder message.
  func handleSSEFinishEvent(event: SSEEvent) async {
    #if DEBUG
    print("🏁 Processing finish event")
    print("   Raw data: \(event.data)")
    #endif
    
    await MainActor.run {
      guard let lastIndex = messages.indices.last,
            !messages[lastIndex].isUser else {
        #if DEBUG
        print("⚠️ No assistant message found to finish")
        #endif
        return
      }
      
      let lastMsg = messages[lastIndex]
      
      if lastMsg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        // If it's just an empty streaming placeholder, remove it entirely
        messages.removeLast()
        #if DEBUG
        print("✅ Removed empty streaming assistant placeholder on finish event")
        #endif
      } else {
        // Otherwise, keep the content and just stop streaming
        messages[lastIndex] = ChatMessage(
          id: lastMsg.id,
          text: lastMsg.text,
          isUser: lastMsg.isUser,
          isStreaming: false
        )
        #if DEBUG
        print("✅ Marked last assistant message as not streaming on finish event")
        #endif
      }
      
      // Update lastMessage for the bubble display
      if let lastMsg = messages.last, !lastMsg.isUser {
        lastMessage = lastMsg
      }
    }
  }
  
  /// Handles `notification` SSE events by parsing the payload and updating
  /// `currentNotification`. The ProgressNotificationBanner handles its own auto-dismiss.
  func handleNotificationEvent(event: SSEEvent) async {
    #if DEBUG
    print("🔔 Processing notification event")
    #endif
    
    do {
      guard let dataDict = try event.parseJSONData() else {
        #if DEBUG
        print("⚠️ Failed to parse notification data as JSON")
        #endif
        return
      }
      
      guard let notification = NotificationData(from: dataDict) else {
        #if DEBUG
        print("⚠️ Failed to create notification from data: \(dataDict)")
        #endif
        return
      }
      
      await MainActor.run {
        #if DEBUG
        print("📬 Notification received: type=\(notification.type ?? "nil"), message=\(notification.message)")
        print("   Setting currentNotification...")
        #endif
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          currentNotification = notification
        }
        
        #if DEBUG
        print("   currentNotification set. Value: \(currentNotification?.message ?? "nil")")
        #endif
        // Note: ProgressNotificationBanner handles its own auto-dismiss
      }
    } catch {
      #if DEBUG
      print("❌ Error handling notification event: \(error)")
      #endif
    }
  }
  
  /// Handles `content` SSE events by updating the streaming assistant message.
  func handleContentEvent(
    event: SSEEvent,
    streamingContent: inout String
  ) async {
    #if DEBUG
    print("📝 Processing content event")
    #endif
    
    do {
      guard let dataDict = try event.parseJSONData() else {
        #if DEBUG
        print("⚠️ Failed to parse content data as JSON")
        #endif
        return
      }
      
      guard let content = dataDict["content"] as? String else {
        #if DEBUG
        print("⚠️ Content event payload missing 'content' field")
        #endif
        return
      }
      
      streamingContent += content
      #if DEBUG
      print("📝 Content chunk received: '\(content)'")
      print("   Total streaming content length: \(streamingContent.count)")
      #endif
      
      await MainActor.run {
        if let lastIndex = messages.indices.last,
           !messages[lastIndex].isUser {
          let existingMessage = messages[lastIndex]
          let isStreaming = dataDict["is_streaming"] as? Bool ?? true
          messages[lastIndex] = ChatMessage(
            id: existingMessage.id,
            text: streamingContent,
            isUser: false,
            isStreaming: isStreaming
          )
          #if DEBUG
          print("✅ Updated assistant message. isStreaming: \(isStreaming)")
          #endif
          
          // Update lastMessage for the bubble display
          lastMessage = messages[lastIndex]
        }
      }
    } catch {
      #if DEBUG
      print("❌ Error handling content event: \(error)")
      #endif
    }
  }
  
  /// Handles `map` SSE events by dismissing the keyboard and resetting
  /// the modal position in `ChatModalView`.
  func handleMapEvent() async {
    #if DEBUG
    print("🗺️ Processing map event - dismissing keyboard and resetting modal")
    #endif
    
    await MainActor.run {
      shouldDismissKeyboard = true
      // Reset the flag after a brief delay to allow the change to be detected
      Task {
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        await MainActor.run {
          shouldDismissKeyboard = false
        }
      }
    }
  }
  
  /// Handles `interface` SSE events by controlling UI elements like the info sheet.
  /// If message is "show info sheet", sets sheetSnapPoint to .full.
  func handleInterfaceEvent(event: SSEEvent) async {
    #if DEBUG
    print("🖥️ Processing interface event")
    #endif
    
    do {
      guard let dataDict = try event.parseJSONData() else {
        #if DEBUG
        print("⚠️ Failed to parse interface data as JSON")
        #endif
        return
      }
      
      guard let message = dataDict["message"] as? String else {
        #if DEBUG
        print("⚠️ Interface event payload missing 'message' field")
        #endif
        return
      }
      
      #if DEBUG
      print("🖥️ Interface message received: '\(message)'")
      #endif
      
      await MainActor.run {
        if message.lowercased() == "show info sheet" {
          #if DEBUG
          print("📋 Setting sheetSnapPoint to .full")
          #endif
          
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            sheetSnapPoint = .full
          }
        }
      }
    } catch {
      #if DEBUG
      print("❌ Error handling interface event: \(error)")
      #endif
    }
  }
}

// MARK: - Progress Notification Banner Component
/// A notification banner specifically for progress-related notifications in liveUpdateStack.
/// Auto-dismisses after 4 seconds. When a new notification arrives, SwiftUI automatically
/// removes this banner (onDisappear cancels the dismiss task).
/// Uses `onNotificationDismiss` (separate from the message bubble's `onDismiss`).
struct ProgressNotificationBanner: View {
    let notification: NotificationData
    let onNotificationDismiss: () -> Void
    @State private var dismissTask: Task<Void, Never>?
    
    /// Maps notification type to SF Symbol icon name
    private var iconName: String {
        guard let type = notification.type else {
            return "bell.fill" // Default icon for null type
        }
        
        switch type.lowercased() {
        case "info", "information":
            return "info.circle.fill"
        case "search", "search web":
            return "magnifyingglass"
        case "success", "completed":
            return "checkmark.circle.fill"
        case "warning", "alert":
            return "exclamationmark.triangle.fill"
        case "error", "failure":
            return "xmark.circle.fill"
        case "location", "gps":
            return "location.fill"
        case "journey", "trip":
            return "signpost.right.and.left.fill"
        case "message", "chat":
            return "message.fill"
        case "update", "refresh":
            return "arrow.clockwise.circle.fill"
        default:
            return "bell.fill" // Default icon for unknown types
        }
    }
    
    // The banner content itself
    private var bannerContent: some View {
        HStack(spacing: 12) {
            // Icon placeholder
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(.primary)
                .frame(width: 24, height: 24)
            
            // Notification message
            Text(notification.message)
                .bodyText()
                .foregroundColor(Color("onBkgTextColor20"))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)  // Inner padding: space between content and background
        .padding(.vertical, 12)     // Inner padding: space between content and background
        .background(
            Color("AppBkgColor")
                .opacity(0.95)
                .cornerRadius(Spacing.current.spaceS)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
    
    var body: some View {
        bannerContent
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Start auto-dismiss timer
                dismissTask = Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            onNotificationDismiss()
                        }
                    }
                }
            }
            .onDisappear {
                // Cancel dismiss task when view disappears (e.g., when new notification arrives)
                // SwiftUI automatically calls this when currentNotification changes
                dismissTask?.cancel()
            }
    }
}


#if DEBUG
#Preview("Map Tab with last user message") {
    TestMainView(previewTab: .map, previewLastMessage: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false))
        .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
        .environmentObject(APIClient())
        .environmentObject(UHPGateway())
        .environmentObject(LocationManager())
}

#Preview("Journey Tab with last assistant message") {
    TestMainView(previewTab: .journey, previewLastMessage: ChatMessage(text: "Maximus morbi habitasse dictumst curae aenean fermentum senectus nunc elementum quis pretium, dui feugiat gravida sem ad tempor conubia vehicula tortor volutpat, facilisis pulvinar nam fusce praesent ac commodo himenaeos donec lorem. Quis ullamcorper porttitor vitae placerat ad dis eu habitasse venenatis, rhoncus cursus suspendisse in adipiscing posuere mattis tristique donec, rutrum nostra congue velit mauris malesuada montes consequat. Mus est natoque nibh torquent hendrerit scelerisque phasellus consequat auctor praesent, diam neque venenatis quisque cursus vestibulum taciti curae congue, lorem etiam proin accumsan potenti montes tincidunt donec magna.", isUser: false, isStreaming: false))
        .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
        .environmentObject(APIClient())
        .environmentObject(UHPGateway())
        .environmentObject(LocationManager())
}
#endif


