import SwiftUI
import CoreLocation
import core

// MARK: - Scroll Offset Tracker
struct ScrollOffsetTracker: View {
    @Binding var offset: CGFloat
    @Binding var shouldHideTabBar: Bool
    let currentSnapPoint: SnapPoint
    let hideTabBarThreshold: CGFloat
    
    // Animation is controlled by .animation() modifiers on the views (tab bar, liveUpdateStack).
    // This tracker only updates shouldHideTabBar state - no animation logic here.
    
    // Minimum scroll delta to consider it a real direction change (filters micro-reversals)
    private let minScrollDelta: CGFloat = 3.0
    // Track accumulated scroll in each direction to filter noise
    @State private var accumulatedUpScroll: CGFloat = 0
    @State private var accumulatedDownScroll: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Invisible tracking element at the very top
            GeometryReader { geometry in
                let scrollOffset = geometry.frame(in: .named("scroll")).minY
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: scrollOffset)
            }
            .frame(height: 0) // Zero height for tracking only
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
            // Update offset binding
            if abs(offset - newOffset) > 0.01 {
                let oldOffset = offset
                let delta = newOffset - oldOffset
                offset = newOffset
                
                // Only process tab bar visibility if we're at full snap point
                guard currentSnapPoint == .full else {
                    accumulatedUpScroll = 0
                    accumulatedDownScroll = 0
                    return
                }
                
                let isCurrentlyHidden = shouldHideTabBar
                
                // Accumulate scroll in each direction, reset the other
                if delta > 0 {
                    // Scrolling up
                    accumulatedUpScroll += delta
                    accumulatedDownScroll = 0
                } else {
                    // Scrolling down
                    accumulatedDownScroll += abs(delta)
                    accumulatedUpScroll = 0
                }
                
                // Show tab bar when accumulated upward scroll exceeds threshold
                if isCurrentlyHidden && accumulatedUpScroll >= minScrollDelta {
                    shouldHideTabBar = false
                    accumulatedUpScroll = 0
                    #if DEBUG
                    print("📊 ScrollOffsetTracker: Showing tab bar on scroll up (offset: \(String(format: "%.2f", newOffset)))")
                    #endif
                    return
                }
                
                // Hide tab bar when scrolled past threshold (with accumulated down scroll)
                if !isCurrentlyHidden && newOffset < hideTabBarThreshold && accumulatedDownScroll >= minScrollDelta {
                    shouldHideTabBar = true
                    accumulatedDownScroll = 0
                    #if DEBUG
                    print("📊 ScrollOffsetTracker: Hiding tab bar (offset: \(String(format: "%.2f", newOffset)), threshold: \(hideTabBarThreshold))")
                    #endif
                }
            }
        }
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Snap Point
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

// MARK: - Info Sheet Header View
/// Intelligently constructs header with DisplayText for smallest regions and body text for larger regions
/// All header text computation logic is consolidated in LocationDetailData
struct InfoSheetHeaderView: View {
    let locationData: LocationDetailData?
    
    init(locationData: LocationDetailData?) {
        self.locationData = locationData
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
            // Body text (larger regions) on top if available
            if let bodyText = locationData?.bodyText, !bodyText.isEmpty {
                Text(bodyText)
                    .bodyText(size: .article0)
                    .foregroundColor(Color("onBkgTextColor30"))
            }
            
            // DisplayText (smallest regions) below
            DisplayText(locationData?.displayText ?? "Journey Content", scale: .article2, color: Color("onBkgTextColor20"))
        }
    }
}

// MARK: - Test Body
struct TestBody: View {
    var body: some View {
        ForEach(0..<20, id: \.self) { index in
            Text("Item \(index + 1) Bibendum ut euismod ultrices hendrerit cras, faucibus suspendisse mi curabitur. Amet sollicitudin nunc maximus diam curabitur imperdiet facilisi gravida, nullam enim velit maecenas lobortis condimentum tempus. Purus luctus aptent consectetur metus lacus venenatis taciti vestibulum nullam habitant magnis nulla magna rhoncus, litora condimentum dapibus montes nostra pretium sagittis vulputate facilisi varius dignissim justo proin. Mauris potenti molestie mattis sodales urna dui vitae donec duis, vivamus curabitur sollicitudin elit dolor vehicula et netus. Ultrices iaculis scelerisque pulvinar pharetra nulla praesent interdum blandit class, pretium egestas sed leo eros tincidunt turpis.")
                .bodyParagraph(color: Color("onBkgTextColor30"))
        }
    }
}

// MARK: - Test Info Sheet
struct InfoSheet: View {
    @Binding var selectedTab: PreviewTabSelection
    @Binding var shouldHideTabBar: Bool
    let sheetFullHeight: CGFloat
    let bottomSafeAreaInsetHeight: CGFloat
    @Binding var sheetSnapPoint: SnapPoint
    
    // Content management
    @ObservedObject var contentManager: ContentManager
    
    init(
        selectedTab: Binding<PreviewTabSelection>,
        shouldHideTabBar: Binding<Bool>,
        sheetFullHeight: CGFloat,
        bottomSafeAreaInsetHeight: CGFloat,
        sheetSnapPoint: Binding<SnapPoint>,
        contentManager: ContentManager
    ) {
        self._selectedTab = selectedTab
        self._shouldHideTabBar = shouldHideTabBar
        self.sheetFullHeight = sheetFullHeight
        self.bottomSafeAreaInsetHeight = bottomSafeAreaInsetHeight
        self._sheetSnapPoint = sheetSnapPoint
        self.contentManager = contentManager
    }
    
    /// Extracts LocationDetailData from ContentManager
    private var locationDetailData: LocationDetailData? {
        contentManager.locationDetailData
    }
    
    // Snap points - visible heights
    private var fullHeight: CGFloat {
        sheetFullHeight
    }
    
    @State private var dragOffset: CGFloat = 0
    @State private var scrollViewContentOffset: CGFloat = 0
    @State private var isScrolling: Bool = false
    @State private var scrollSettleTask: Task<Void, Never>?
    
    // Offset adjustment for sheet positioning (bottom safe area + optional padding)
    private var positionOffsetAdjustment: CGFloat {
        bottomSafeAreaInsetHeight + 45 // 105 (safe area) + 41 (padding) = 146
    }
    
    // Threshold for hiding tab bar (scrolled down by this amount)
    // Negative values mean scrolled down (content moved up)
    private let hideTabBarThreshold: CGFloat = -20
    
    /// Calculates the vertical offset for a given snap point
    private func offsetForSnapPoint(_ snapPoint: SnapPoint) -> CGFloat {
        return fullHeight - snapPoint.height(fullHeight: fullHeight) + positionOffsetAdjustment
    }
    
    /// Updates scroll offset directly from GeometryReader
    private func updateScrollOffset(_ offset: CGFloat) {
        // Only update if value actually changed to avoid infinite loops
        if abs(scrollViewContentOffset - offset) > 0.01 {
            scrollViewContentOffset = offset
            
            // Mark as actively scrolling to prevent animation jitter
            isScrolling = true
            scrollSettleTask?.cancel()
            
            // During active scrolling, update without animation to prevent jitter
            // The ScrollOffsetTracker will handle the actual tab bar visibility with proper logic
            // We just update the offset here without triggering animations
            
            // Debounce: consider scroll "settled" after 100ms of no updates
            scrollSettleTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                isScrolling = false
            }
        }
    }
    
    /// Checks if scroll content is exactly at the top edge
    /// Uses the offset directly from GeometryReader
    private var isScrollAtTop: Bool {
        let isAtTop = scrollViewContentOffset >= 0 
        return isAtTop
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: Spacing.current.space3xs)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                // Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Scroll offset tracker with visual top edge marker
                        // This must be at the very top of the scroll content
                        ScrollOffsetTracker(offset: $scrollViewContentOffset, shouldHideTabBar: $shouldHideTabBar, currentSnapPoint: sheetSnapPoint, hideTabBarThreshold: hideTabBarThreshold)
                        
                        // Content rendering
                        VStack(alignment: .leading, spacing: 0) {
                            // Header - only shown when not at full (at full, it's sticky via safeAreaInset)
                            if sheetSnapPoint != .full {
                                InfoSheetHeaderView(locationData: locationDetailData)
                                    .padding(.top, Spacing.current.spaceXs)
                                    .padding(.bottom, Spacing.current.spaceXs)
                            }
                            
                            // Render standard content sections
                            if !contentManager.orderedSections.isEmpty {
                                ForEach(contentManager.orderedSections) { section in
                                    ContentViewRegistry.view(for: section)
                                }
                            }
                            
                            TestBody()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.current.spaceS)
                        .padding(.bottom, 100)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Sticky header bar - only visible when at full snap point
                    if sheetSnapPoint == .full {
                        VStack(spacing: 0) {
                            InfoSheetHeaderView(locationData: locationDetailData)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.current.spaceS)
                                .padding(.top, Spacing.current.spaceM)
                                .padding(.bottom, Spacing.current.spaceXs)
                                .background(Color("AppBkgColor"))
                                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: -5)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .scrollDisabled(sheetSnapPoint != .full || (sheetSnapPoint == .full && dragOffset > 0 && isScrollAtTop))
                .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Only allow drag to collapse when at full AND scroll is exactly at top
                        if sheetSnapPoint == .full && value.translation.height > 0 {
                            guard isScrollAtTop else {
                                dragOffset = 0
                                return
                            }
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Handle swipe from .full to .collapsed (only if scroll is at top)
                        if sheetSnapPoint == .full && value.translation.height > 0 {
                            guard isScrollAtTop else {
                                dragOffset = 0
                                return
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                sheetSnapPoint = .collapsed
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
            //     currentSnapPoint: sheetSnapPoint
            // )
        }
        .frame(width: UIScreen.main.bounds.width)
        .frame(height: fullHeight)
        .background(
            Color("AppBkgColor")
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: Spacing.current.spaceM,
                            bottomLeading: 0,
                            bottomTrailing: 0,
                            topTrailing: Spacing.current.spaceM
                        )
                    )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: -5)
        )
        .offset(y: offsetForSnapPoint(sheetSnapPoint) + dragOffset)
        .opacity(selectedTab == .journey ? 1 : 0)
        .ignoresSafeArea(edges: .bottom) // Extend to bottom of screen
        .gesture(
            DragGesture()
                .onChanged { value in
                    if sheetSnapPoint == .full {
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
                    if sheetSnapPoint == .full && value.translation.height > 0 {
                        guard isScrollAtTop else {
                            dragOffset = 0
                            return
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            sheetSnapPoint = .collapsed
                            dragOffset = 0
                        }
                        return
                    }
                    
                    // Handle all other swipes
                    let newSnapPoint = determineSnapPoint(
                        dragDistance: value.translation.height
                    )
                    
                    // Only update if snap point changed
                    if newSnapPoint != sheetSnapPoint {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            sheetSnapPoint = newSnapPoint
                            dragOffset = 0
                        }
                    } else {
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                sheetSnapPoint = .partial
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .journey {
                withAnimation(.easeOut(duration: 0.2)) {
                    sheetSnapPoint = .partial
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    sheetSnapPoint = .collapsed
                }
                // Reset tab bar visibility when leaving journey tab
                shouldHideTabBar = false
            }
        }
        .onChange(of: sheetSnapPoint) { newSnapPoint in
            // Show tab bar when not at full snap point
            // Set directly without animation - ScrollOffsetTracker owns the animation
            // Using withTransaction here conflicts with ScrollOffsetTracker causing flicker
            if newSnapPoint != .full {
                shouldHideTabBar = false
            }
        }
    }
    
    private func determineSnapPoint(dragDistance: CGFloat) -> SnapPoint {
        // Swipe down (positive dragDistance)
        if dragDistance > 0 {
            switch sheetSnapPoint {
            case .partial: return .collapsed
            case .full: return .collapsed  // Only if scroll is at top (checked in caller)
            case .collapsed: return .collapsed
            }
        }
        
        // Swipe up (negative dragDistance)
        if dragDistance < 0 {
            switch sheetSnapPoint {
            case .partial: return .full
            case .collapsed: return .partial
            case .full: return .full
            }
        }
        
        // No drag: stay at current
        return sheetSnapPoint
    }
}

#Preview("Full Height") {
    let contentManager = ContentManager()
    let locationData = LocationDetailData(
        location: CLLocation(latitude: 41.9028, longitude: 12.4964),
        placeName: "Colosseum",
        subdivisions: "Rome, Lazio",
        countryName: "Italy"
    )
    contentManager.setContent(type: .locationDetail, data: .locationDetail(data: locationData))
    
    return InfoSheet(
        selectedTab: .constant(.journey),
        shouldHideTabBar: .constant(false),
        sheetFullHeight: 1000,
        bottomSafeAreaInsetHeight: 0,
        sheetSnapPoint: .constant(.full),
        contentManager: contentManager
    )
}

#if DEBUG
#Preview("Standard Content") {
    let sections = loadStandardContentFromJSON()
    let contentManager = ContentManager()
    let locationData = LocationDetailData(
        location: CLLocation(latitude: 41.9028, longitude: 12.4964),
        placeName: "Ancient Rome",
        subdivisions: "Lazio",
        countryName: "Italy"
    )
    contentManager.setContent(type: .locationDetail, data: .locationDetail(data: locationData))
    
    // Add sections from JSON to contentManager
    for section in sections {
        contentManager.setContent(type: section.type, data: section.data)
    }
    
    return InfoSheet(
        selectedTab: .constant(.journey),
        shouldHideTabBar: .constant(false),
        sheetFullHeight: 1000,
        bottomSafeAreaInsetHeight: 0,
        sheetSnapPoint: .constant(.full),
        contentManager: contentManager
    )
}


#Preview("Mixed Content") {
    let sections = loadStandardContentFromJSON()
    let contentManager = ContentManager()
    let locationData = LocationDetailData(
        location: CLLocation(latitude: 40.7128, longitude: -74.0060),
        placeName: nil,
        subdivisions: "Mixed Content Location",
        countryName: nil
    )
    contentManager.setContent(type: .locationDetail, data: .locationDetail(data: locationData))
    
    // Add sections from JSON to contentManager
    for section in sections {
        contentManager.setContent(type: section.type, data: section.data)
    }
    
    return InfoSheet(
        selectedTab: .constant(.journey),
        shouldHideTabBar: .constant(false),
        sheetFullHeight: 1000,
        bottomSafeAreaInsetHeight: 0,
        sheetSnapPoint: .constant(.full),
        contentManager: contentManager
    )
}

// Helper function to load standard content from JSON file
private func loadStandardContentFromJSON() -> [ContentSection] {
    guard let url = Bundle.main.url(forResource: "standard_content_preview", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
    }
    
    var sections: [ContentSection] = []
    
    // Load overview if available
    if let overview = json["overview"] as? String {
        sections.append(ContentSection(
            type: .overview,
            data: .overview(markdown: overview)
        ))
    }
    
    // Load location detail if available
    if let locationDict = json["locationDetail"] as? [String: Any],
       let lat = locationDict["latitude"] as? Double,
       let lon = locationDict["longitude"] as? Double {
        let altitude = locationDict["altitude"] as? Double ?? 0
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: altitude,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            timestamp: Date()
        )
        let placeName = locationDict["place_name"] as? String
        let subdivisions = locationDict["subdivisions"] as? String
        let countryName = locationDict["country_name"] as? String
        let locationDetailData = LocationDetailData(
            location: location,
            placeName: placeName,
            subdivisions: subdivisions,
            countryName: countryName
        )
        sections.append(ContentSection(
            type: .locationDetail,
            data: .locationDetail(data: locationDetailData)
        ))
    }
    
    // Load POIs if available
    if let poisArray = json["pointsOfInterest"] as? [[String: Any]] {
        let features = poisArray.compactMap { poiDict -> PointFeature? in
            // Convert dictionary to JSONValue format
            guard let geometryDict = poiDict["geometry"] as? [String: Any],
                  let coordinatesArray = geometryDict["coordinates"] as? [Double],
                  coordinatesArray.count >= 2,
                  let propertiesDict = poiDict["properties"] as? [String: Any] else {
                return nil
            }
            
            // Convert to JSONValue format
            let feature: [String: JSONValue] = [
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array(coordinatesArray.map { .double($0) })
                ]),
                "properties": .dictionary(convertToJSONValue(propertiesDict))
            ]
            
            return PointFeature(from: feature)
        }
        
        if !features.isEmpty {
            sections.append(ContentSection(
                type: .pointsOfInterest,
                data: .pointsOfInterest(features: features)
            ))
        }
    }
    
    return sections
}

// Helper function to convert [String: Any] to [String: JSONValue]
private func convertToJSONValue(_ dict: [String: Any]) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    
    for (key, value) in dict {
        result[key] = convertAnyToJSONValue(value)
    }
    
    return result
}

private func convertAnyToJSONValue(_ value: Any) -> JSONValue {
    switch value {
    case let string as String:
        return .string(string)
    case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        } else if number.isInt {
            return .int(number.intValue)
        } else {
            return .double(number.doubleValue)
        }
    case let dict as [String: Any]:
        return .dictionary(convertToJSONValue(dict))
    case let array as [Any]:
        return .array(array.map { convertAnyToJSONValue($0) })
    default:
        return .string("\(value)")
    }
}

extension NSNumber {
    var isInt: Bool {
        let type = CFNumberGetType(self as CFNumber)
        return type == .sInt8Type || type == .sInt16Type || type == .sInt32Type || type == .sInt64Type || type == .intType
    }
}
#endif