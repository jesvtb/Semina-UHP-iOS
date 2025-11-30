import SwiftUI

// MARK: - Input Tab Selection
enum InputTabSelection: Int, CaseIterable {
    case journey = 0
    case map = 1
    case chat = 2
    case profile = 3
}

struct TestMainView: View {
    @EnvironmentObject var uhpGateway: UHPGateway
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var messages: [ChatMessage] = []
    @State private var draftMessage: String = ""
    @State private var selectedTab: InputTabSelection = .journey
    @FocusState private var isTextFieldFocused: Bool
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
    private let tabs: [(name: String, selectedIcon: String, unselectedIcon: String)] = [
        ("Journey", "signpost.right.and.left.fill", "signpost.right.and.left"),
        ("Map", "map.fill", "map"),
        ("Ask", "questionmark.bubble.fill", "questionmark.bubble"),
        ("You", "person.fill", "person")
    ]

    var body: some View {
        ZStack {
            // Background stays fixed
            // Color("AccentColor")
            //     .ignoresSafeArea(.container)
            //     .ignoresSafeArea(.keyboard)

            MapboxMapView(geoJSONData: $geoJSONData, geoJSONUpdateTrigger: $geoJSONUpdateTrigger)
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
                    TestInfoSheet(
                        selectedTab: $selectedTab,
                        shouldHideTabBar: $shouldHideTabBar,
                        sheetFullHeight: sheetFullHeight,
                        bottomSafeAreaInsetHeight: bottomSafeAreaInsetHeight
                    )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height - (sheetFullHeight / 2) // Dynamic: half of actual sheet height
                        )
                } 
            }

                
            
            
            if let lastMessage = lastMessage, selectedTab != .chat {
                latestMsgBubble(
                    message: lastMessage,
                    isExpanded: $isMessageExpanded,
                    onDismiss: {
                        self.lastMessage = nil
                        self.isMessageExpanded = false
                    }
                )
                .opacity(shouldHideTabBar ? 0 : 1)
                .allowsHitTesting(!shouldHideTabBar)
            }
        }
        // Input bar pinned to bottom; moves with keyboard
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                chatInputBar
                tabSelectorView
            }
            .background(.ultraThinMaterial)
            .overlay(
                Divider()
                    .background(Color("onBkgTextColor60")),
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
        .onChange(of: locationManager.currentLocation) { newLocation in
            // Only make API call when location is captured and change is significant
            // Skip if this is the initial load (handled by .task)
            if newLocation != nil {
                Task {
                    await loadLocationIfSignificant()
                }
            }
        }
        .task { @MainActor in
            // Initial load: If location is already available, call immediately (first time)
            // Otherwise, wait for onChange to trigger when location is captured
            // Use a small delay to avoid race condition with onChange
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
            if locationManager.currentLocation != nil {
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
    
    /// Calculates the exact height of the bottom safe area inset (chatInputBar + tabSelectorView)
    private var bottomSafeAreaInsetHeight: CGFloat {
        // chatInputBar components:
        // - HStack vertical padding: 8 top + 8 bottom = 16 points
        // - TextField vertical padding: 10 top + 10 bottom = 20 points
        // - TextField content height (single line, system font ~17pt): ~20 points
        let chatInputBarHeight: CGFloat = 16 + 20 + 20 // 56 points minimum
        
        // tabSelectorView:
        // - Uses tabBarHeight constant = 49 points
        let tabSelectorHeight: CGFloat = 49
        
        // VStack spacing: 0 (no spacing between components)
        return chatInputBarHeight + tabSelectorHeight // 105 points total
    }
}

// MARK: - TestMainView: View Components
extension TestMainView {
    private func latestMsgBubble(message: ChatMessage, isExpanded: Binding<Bool>, onDismiss: @escaping () -> Void) -> some View {
        // Helper to check if text would exceed 3 lines
        let estimatedLineCount = estimateLineCount(for: message.text, font: UIFont.systemFont(ofSize: 15), maxWidth: UIScreen.main.bounds.width - 80)
        let shouldShowExpandButton = estimatedLineCount > 3
        
        return VStack {
            Spacer()
            HStack {
                
                // Message bubble with text and dismiss button overlay
                ZStack(alignment: .topTrailing) {
                    // Message bubble with text
                    VStack(alignment: .leading, spacing: 0) {
                        Text(message.text)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .lineLimit(isExpanded.wrappedValue ? nil : 3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        
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
                                            .font(.system(size: 11, weight: .medium))
                                        Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                }
                                .padding(.trailing, 12)
                                .padding(.bottom, 4)
                            }
                        }
                    }
                    .background(message.isUser ? Color.blue : Color(.systemGray3))
                    .cornerRadius(16)
                    
                    // Dismiss button positioned at upper right corner, overlapping the border
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onDismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .padding(.top, -6)
                    .padding(.trailing, -6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                Spacer()
            }
        }
        .background(Color.clear)
    }
    
    /// Estimates the number of lines needed to display text
    private func estimateLineCount(for text: String, font: UIFont, maxWidth: CGFloat) -> Int {
        let attributes = [NSAttributedString.Key.font: font]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let lineHeight = font.lineHeight
        let estimatedLines = Int(ceil(textSize.height / lineHeight))
        return estimatedLines
    }
    
    private var tabSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(Array(InputTabSelection.allCases.enumerated()), id: \.element) { index, tabCase in
                let tab = tabs[index]
                TabBarButton(
                    selectedIcon: tab.selectedIcon,
                    unselectedIcon: tab.unselectedIcon,
                    label: tab.name,
                    isSelected: selectedTab == tabCase,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tabCase
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 8)
        .background(Color("AppBkgColor"))
    }
    
    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask any thing...", text: $draftMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(draftMessage.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                    .clipShape(Circle())
            }
            .disabled(draftMessage.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
            
            // Add location and country from LocationManager's locationDetails
            // Always include these fields (use empty strings if not available) to satisfy backend requirements
            if let locationDetails = locationManager.locationDetails {
                if let location = locationDetails["location"] as? String {
                    jsonDict["current_location"] = location
                } else {
                    jsonDict["current_location"] = ""
                }
                // Check both country_name and country fields
                if let countryName = locationDetails["country_name"] as? String {
                    jsonDict["current_country"] = countryName
                } else if let country = locationDetails["country"] as? String {
                    jsonDict["current_country"] = country
                } else {
                    jsonDict["current_country"] = ""
                }
            } else {
                // If locationDetails is nil, provide empty strings
                jsonDict["current_location"] = ""
                jsonDict["current_country"] = ""
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

// MARK: - Test Info Sheet (Minimal version for testing)
struct TestInfoSheet: View {
    @Binding var selectedTab: InputTabSelection
    @Binding var shouldHideTabBar: Bool
    let sheetFullHeight: CGFloat
    let bottomSafeAreaInsetHeight: CGFloat
    
    // Snap points - visible heights
    private var fullHeight: CGFloat {
        sheetFullHeight
    }
    
    @State private var dragOffset: CGFloat = 0
    @State private var currentSnapPoint: SnapPoint = .partial
    @State private var scrollViewContentOffset: CGFloat = 0
    
    // Offset adjustment for sheet positioning (bottom safe area + optional padding)
    private var positionOffsetAdjustment: CGFloat {
        bottomSafeAreaInsetHeight + 45 // 105 (safe area) + 41 (padding) = 146
    }
    
    // Threshold for hiding tab bar (scrolled down by this amount)
    // Negative values mean scrolled down (content moved up)
    private let hideTabBarThreshold: CGFloat = -20
    
    enum SnapPoint {
        case collapsed
        case partial
        case full
        
        func height(fullHeight: CGFloat) -> CGFloat {
            switch self {
            case .collapsed: return 200
            case .partial: return 400
            case .full: return fullHeight
            }
        }
    }
    
    /// Calculates the vertical offset for a given snap point
    private func offsetForSnapPoint(_ snapPoint: SnapPoint) -> CGFloat {
        return fullHeight - snapPoint.height(fullHeight: fullHeight) + positionOffsetAdjustment
    }
    
    /// Updates scroll offset directly from GeometryReader
    private func updateScrollOffset(_ offset: CGFloat) {
        // Only update if value actually changed to avoid infinite loops
        if abs(scrollViewContentOffset - offset) > 0.01 {
            scrollViewContentOffset = offset
            
            // Hide tab bar when scrolled down significantly
            let isScrolledDown = offset < hideTabBarThreshold
            let shouldHide = currentSnapPoint == .full && isScrolledDown
            
            withAnimation(.easeInOut(duration: 0.2)) {
                shouldHideTabBar = shouldHide
            }
        }
    }
    
    /// Checks if scroll content is exactly at the top edge
    /// Uses the offset directly from GeometryReader
    private var isScrollAtTop: Bool {
        // Content is at top when offset is exactly 0 (or within 0.5 points for floating point precision)
        // Negative values mean content has been scrolled down
        // Positive values > 0.5 also mean content is not at top (might be bouncing or overscrolled)
        // let isAtTop = scrollViewContentOffset >= 0 && scrollViewContentOffset <= 0.5
        let isAtTop = scrollViewContentOffset >= 0 
        #if DEBUG
        if currentSnapPoint == .full && abs(scrollViewContentOffset) > 0.1 {
            print("🔍 isScrollAtTop check: offset=\(String(format: "%.2f", scrollViewContentOffset)), isAtTop=\(isAtTop)")
        }
        #endif
        return isAtTop
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                // Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Scroll offset tracker with visual top edge marker
                        // This must be at the very top of the scroll content
                        ScrollOffsetTracker(offset: $scrollViewContentOffset, shouldHideTabBar: $shouldHideTabBar, currentSnapPoint: currentSnapPoint, hideTabBarThreshold: hideTabBarThreshold)
                        
                        // Minimal test content
                        VStack(alignment: .leading, spacing: 16) {
                        Text("Journey Content")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        Text("This is a test view for the journey bottom sheet with snapping behavior.")
                            .padding(.horizontal)
                        
                        ForEach(0..<20, id: \.self) { index in
                            Text("Item \(index + 1) Bibendum ut euismod ultrices hendrerit cras, faucibus suspendisse mi curabitur. Amet sollicitudin nunc maximus diam curabitur imperdiet facilisi gravida, nullam enim velit maecenas lobortis condimentum tempus. Purus luctus aptent consectetur metus lacus venenatis taciti vestibulum nullam habitant magnis nulla magna rhoncus, litora condimentum dapibus montes nostra pretium sagittis vulputate facilisi varius dignissim justo proin. Mauris potenti molestie mattis sodales urna dui vitae donec duis, vivamus curabitur sollicitudin elit dolor vehicula et netus. Ultrices iaculis scelerisque pulvinar pharetra nulla praesent interdum blandit class, pretium egestas sed leo eros tincidunt turpis.")
                                .padding(.horizontal)
                        }
                        }
                        // .background(Color.red.opacity(0.3))
                        // .background(Color)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 100)
                    }
                }
                .coordinateSpace(name: "scroll")
                .scrollDisabled(currentSnapPoint != .full || (currentSnapPoint == .full && dragOffset > 0 && isScrollAtTop))
                .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Only allow drag to collapse when at full AND scroll is exactly at top
                        if currentSnapPoint == .full && value.translation.height > 0 {
                            guard isScrollAtTop else {
                                dragOffset = 0
                                return
                            }
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Handle swipe from .full to .collapsed (only if scroll is at top)
                        if currentSnapPoint == .full && value.translation.height > 0 {
                            guard isScrollAtTop else {
                                dragOffset = 0
                                return
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                currentSnapPoint = .collapsed
                                dragOffset = 0
                            }
                        }
                    }
                )
            }
            
            // Debug/Helper Visual Elements - Fixed position, unaffected by scrolling
            // DebugInfoView(
            //     scrollOffset: scrollViewContentOffset,
            //     isScrollAtTop: isScrollAtTop,
            //     currentSnapPoint: currentSnapPoint
            // )
        }
        .frame(width: UIScreen.main.bounds.width)
        .frame(height: fullHeight)
        .background(
            Color("AppBkgColor")
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: -5)
        )
        .offset(y: offsetForSnapPoint(currentSnapPoint) + dragOffset)
        .opacity(selectedTab == .journey ? 1 : 0)
        .ignoresSafeArea(edges: .bottom) // Extend to bottom of screen
        .gesture(
            DragGesture()
                .onChanged { value in
                    if currentSnapPoint == .full {
                        // Don't handle upward drags when at full - let content scroll
                        if value.translation.height <= 0 {
                            return
                        }
                        // CRITICAL: Only allow downward drag if scroll content is exactly at top
                        // If not at top, completely block any drag behavior
                        guard isScrollAtTop else {
                            #if DEBUG
                            print("🚫 Collapse blocked - scroll offset: \(scrollViewContentOffset), isAtTop: \(isScrollAtTop)")
                            #endif
                            // Reset any existing drag offset and prevent further drag
                            dragOffset = 0
                            return
                        }
                        // Only set drag offset if we're at top
                        dragOffset = value.translation.height
                    } else {
                        // Not at full - handle all drags
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // Handle swipe from .full to .collapsed (only if scroll is at top)
                    if currentSnapPoint == .full && value.translation.height > 0 {
                        guard isScrollAtTop else {
                            dragOffset = 0
                            return
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            currentSnapPoint = .collapsed
                            dragOffset = 0
                        }
                        return
                    }
                    
                    // Handle all other swipes
                    let newSnapPoint = determineSnapPoint(
                        dragDistance: value.translation.height
                    )
                    
                    // Only update if snap point changed
                    if newSnapPoint != currentSnapPoint {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            currentSnapPoint = newSnapPoint
                            dragOffset = 0
                        }
                    } else {
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            currentSnapPoint = .partial
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .journey {
                withAnimation(.easeOut(duration: 0.2)) {
                    currentSnapPoint = .partial
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    currentSnapPoint = .collapsed
                }
                // Reset tab bar visibility when leaving journey tab
                shouldHideTabBar = false
            }
        }
        .onChange(of: currentSnapPoint) { newSnapPoint in
            // Show tab bar when not at full snap point
            if newSnapPoint != .full {
                withAnimation(.easeInOut(duration: 0.2)) {
                    shouldHideTabBar = false
                }
            }
        }
    }
    
    private func determineSnapPoint(dragDistance: CGFloat) -> SnapPoint {
        // Swipe down (positive dragDistance)
        if dragDistance > 0 {
            switch currentSnapPoint {
            case .partial: return .collapsed
            case .full: return .collapsed  // Only if scroll is at top (checked in caller)
            case .collapsed: return .collapsed
            }
        }
        
        // Swipe up (negative dragDistance)
        if dragDistance < 0 {
            switch currentSnapPoint {
            case .partial: return .full
            case .collapsed: return .partial
            case .full: return .full
            }
        }
        
        // No drag: stay at current
        return currentSnapPoint
    }
}

// MARK: - Scroll Offset Tracker
struct ScrollOffsetTracker: View {
    @Binding var offset: CGFloat
    @Binding var shouldHideTabBar: Bool
    let currentSnapPoint: TestInfoSheet.SnapPoint
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
        
        // Extract user_lat and user_lon from jsonDict (LocationManager uses user_lat/user_lon)
        guard let userLat = jsonDict["user_lat"] as? Double,
              let userLon = jsonDict["user_lon"] as? Double else {
            #if DEBUG
            print("⚠️ Missing user_lat or user_lon in location dict")
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
  /// `currentNotification`, including auto-dismiss behavior.
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
        
        // Auto-dismiss after 5 seconds
        Task {
          try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
          await MainActor.run {
            #if DEBUG
            print("   Auto-dismissing notification after 5 seconds")
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              currentNotification = nil
            }
          }
        }
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
}

// MARK: - Debug Info View
struct DebugInfoView: View {
    let scrollOffset: CGFloat
    let isScrollAtTop: Bool
    let currentSnapPoint: TestInfoSheet.SnapPoint
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Scroll position indicator
            HStack {
                Text("Scroll Offset:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f", scrollOffset))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(scrollOffset >= 0 && scrollOffset <= 0.5 ? .green : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(8)
            
            // At-top indicator
            HStack {
                Circle()
                    .fill(isScrollAtTop ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isScrollAtTop ? "Content is AT TOP" : "Content is SCROLLED")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isScrollAtTop ? .green : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(8)
            
            // Snap point indicator
            HStack {
                Text("Snap Point:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(currentSnapPoint == .collapsed ? "Collapsed" : currentSnapPoint == .partial ? "Partial" : "Full")")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(8)
        }
        .padding(.top, 60) // Position below drag handle
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
