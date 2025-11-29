import SwiftUI

// MARK: - Input Tab Selection
enum InputTabSelection: Int, CaseIterable {
    case journey = 0
    case map = 1
    case chat = 2
    case profile = 3
}

struct TestMainView: View {
    @State private var messages: [String] = ["Hello", "How can I help?"]
    @State private var draftMessage: String = ""
    @State private var selectedTab: InputTabSelection = .journey
    @FocusState private var isTextFieldFocused: Bool
    @State private var geoJSONData: [String: Any]?
    @State private var geoJSONUpdateTrigger: UUID = UUID()
    @State private var shouldHideTabBar: Bool = false
    @State private var latestMsg: String?
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
            // Main content (messages list)
            if selectedTab == .chat {
                VStack {
                    ChatDetailView(messages: messages)

                    Spacer(minLength: 0) // keeps list separate from inset
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Dismiss keyboard when tapping outside safeAreaInset
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
        }
        // Input bar pinned to bottom; moves with keyboard
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // Sent message bubble (shown when message is sent) - transparent background
                if let latestMsg = latestMsg, selectedTab != .chat {
                    latestMsgBubble(message: latestMsg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .background(Color.clear)
                }
                
                // Chat input bar and tab selector with background
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
            }
            .opacity((!shouldHideTabBar || selectedTab != .journey) ? 1 : 0)
            // .opacity(0.2)
            .allowsHitTesting(!shouldHideTabBar || selectedTab != .journey)
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
    private func latestMsgBubble(message: String) -> some View {
        HStack {
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .cornerRadius(16)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Spacer()
        }
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

        messages.append(text)
        
        // Show sent message bubble above input bar
        withAnimation(.easeOut(duration: 0.2)) {
            latestMsg = text
        }
        
        draftMessage = ""
        isTextFieldFocused = false // Dismiss keyboard after sending
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
