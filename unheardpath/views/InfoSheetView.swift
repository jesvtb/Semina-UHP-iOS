import SwiftUI
import CoreLocation
import UIKit
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

// MARK: - Header Frame Preference Key
struct HeaderFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
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
/// Displays location hierarchy with adminArea/subAdminArea and locality/subLocality
struct InfoSheetHeaderView: View {
    let locationData: LocationDetailData?
    let isFromDeviceLocation: Bool
    let currentSnapPoint: SnapPoint
    var isDropdownOpen: Bool
    var onChangeLocation: (() -> Void)?
    
    init(
        locationData: LocationDetailData?,
        isFromDeviceLocation: Bool = true,
        currentSnapPoint: SnapPoint = .collapsed,
        isDropdownOpen: Bool = false,
        onChangeLocation: (() -> Void)? = nil
    ) {
        self.locationData = locationData
        self.isFromDeviceLocation = isFromDeviceLocation
        self.currentSnapPoint = currentSnapPoint
        self.isDropdownOpen = isDropdownOpen
        self.onChangeLocation = onChangeLocation
    }
    
    /// Caption text indicating location source
    private var locationSourceCaption: String {
        isFromDeviceLocation ? "CURRENT LOCATION" : "PLANNED LOCATION"
    }
    
    /// Whether we have any admin area info to display
    private var hasAdminAreaInfo: Bool {
        locationData?.adminArea != nil || locationData?.subAdminArea != nil
    }
    
    /// Whether we have any locality info to display
    private var hasLocalityInfo: Bool {
        locationData?.locality != nil || locationData?.subLocality != nil
    }
    
    /// Whether the header is in dropdown mode (at full or partial snap point)
    private var isDropdownMode: Bool {
        currentSnapPoint == .full || currentSnapPoint == .partial
    }
    
    /// Icon name based on location type
    private var locationTypeIcon: String {
        isFromDeviceLocation ? "mappin.and.ellipse" : "magnifyingglass"
    }
    
    var body: some View {
        Button {
            onChangeLocation?()
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    // Location source caption - hidden at full snap point
                    if !isDropdownMode {
                        Text(locationSourceCaption)
                            .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                            .foregroundColor(Color("onBkgTextColor30"))
                    }
                    
                    // Locality section
                    if hasLocalityInfo {
                        VStack(alignment: .leading, spacing: 0) {
                            // Admin area at top
                            // if let adminArea = locationData?.adminArea {
                            //     Text(adminArea.uppercased())
                            //         .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                            //         .tracking(2)
                            //         .foregroundColor(Color("onBkgTextColor30"))
                            // }
                            // Locality line with icons
                            HStack(spacing: Spacing.current.spaceXs) {
                                if let locality = locationData?.locality {
                                    Text(locality)
                                        .font(.custom(FontFamily.serifDisplay, size: TypographyScale.article2.baseSize))
                                        .foregroundColor(Color("onBkgTextColor10"))
                                }
                                Image(systemName: locationTypeIcon)
                                    .font(.system(size: TypographyScale.article0.baseSize, weight: .medium))
                                    .foregroundColor(Color("onBkgTextColor10"))
                                // Dropdown chevron when at full or partial snap point - rotates when open
                                if isDropdownMode {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: TypographyScale.article0.baseSize, weight: .medium))
                                        .foregroundColor(Color("onBkgTextColor30"))
                                        .rotationEffect(.degrees(isDropdownOpen ? -180 : 0))
                                        .animation(.easeOut(duration: 0.2), value: isDropdownOpen)
                                }
                            }
                            // Sublocality at bottom
                            if let subLocality = locationData?.subLocality {
                                Text(subLocality)
                                    .font(.custom(FontFamily.serifItalic, size: TypographyScale.articleMinus1.baseSize))
                                    .foregroundColor(Color("onBkgTextColor30"))
                            }
                        }
                    }
                    
                    // Fallback if no location data
                    if !hasAdminAreaInfo && !hasLocalityInfo {
                        HStack(spacing: Spacing.current.spaceXs) {
                            // Location type icon
                            Image(systemName: locationTypeIcon)
                                .font(.system(size: TypographyScale.article0.baseSize, weight: .medium))
                                .foregroundColor(Color("onBkgTextColor30"))
                            
                            Text("Journey Catalogue")
                                .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article2.baseSize))
                                .foregroundColor(Color("onBkgTextColor20"))
                            if isDropdownMode {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: TypographyScale.articleMinus1.baseSize, weight: .medium))
                                    .foregroundColor(Color("onBkgTextColor30"))
                                    .rotationEffect(.degrees(isDropdownOpen ? -180 : 0))
                                    .animation(.easeOut(duration: 0.2), value: isDropdownOpen)
                            }
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    if hasAdminAreaInfo {
                        if let countryCode = locationData?.countryCode,
                           let flagImage = CountryFlag.image(for: countryCode) {
                            flagImage
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: Spacing.current.spaceM)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onChangeLocation == nil)
    }
}

// MARK: - Location Dropdown
/// Dropdown overlay for selecting a different location, appears below the header
struct LocationDropdown: View {
    @Binding var isPresented: Bool
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: Spacing.current.spaceXs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(Color("onBkgTextColor30"))
                TextField("Search location...", text: $searchText)
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.article0.baseSize))
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color("onBkgTextColor30"))
                    }
                }
            }
            .padding(.horizontal, Spacing.current.spaceS)
            .padding(.vertical, Spacing.current.spaceXs)
            .background(Color("onBkgTextColor30").opacity(0.08))
            .cornerRadius(Spacing.current.spaceXs)
            .padding(.horizontal, Spacing.current.spaceS)
            .padding(.top, Spacing.current.spaceXs)
            
            Divider()
                .padding(.top, Spacing.current.spaceXs)
            
            // Results / Options
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Use current location option
                    Button {
                        // TODO: Trigger use current device location
                        isPresented = false
                    } label: {
                        HStack(spacing: Spacing.current.spaceXs) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color("AccentColor"))
                            Text("Use Current Location")
                                .font(.custom(FontFamily.sansRegular, size: TypographyScale.article0.baseSize))
                                .foregroundColor(Color("onBkgTextColor10"))
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.current.spaceS)
                        .padding(.vertical, Spacing.current.spaceS)
                    }
                    
                    Divider()
                        .padding(.leading, Spacing.current.spaceS)
                    
                    if searchText.isEmpty {
                        // Recent locations placeholder
                        Text("Recent Locations")
                            .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                            .foregroundColor(Color("onBkgTextColor30"))
                            .padding(.horizontal, Spacing.current.spaceS)
                            .padding(.top, Spacing.current.spaceS)
                            .padding(.bottom, Spacing.current.spaceXs)
                        
                        // TODO: Show recent locations from history
                        Text("No recent locations")
                            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                            .foregroundColor(Color("onBkgTextColor30").opacity(0.6))
                            .padding(.horizontal, Spacing.current.spaceS)
                            .padding(.vertical, Spacing.current.spaceXs)
                    } else {
                        // TODO: Integrate with AutocompleteManager for search results
                        Text("Searching for \"\(searchText)\"...")
                            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                            .foregroundColor(Color("onBkgTextColor30"))
                            .padding(.horizontal, Spacing.current.spaceS)
                            .padding(.vertical, Spacing.current.spaceS)
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .background(Color("AppBkgColor"))
        .cornerRadius(Spacing.current.spaceS)
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        .padding(.horizontal, Spacing.current.spaceS)
        .onAppear {
            isSearchFocused = true
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

// MARK: - Info Sheet Section Tab Bar
/// Upper bar with tabs for switching between content sections (Overview, Location, Cuisine, Points of Interest).
struct InfoSheetSectionTabBar: View {
    let sections: [CatalogueSection]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.current.spaceXs) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    let isSelected = index == selectedIndex
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex = index
                        }
                    } label: {
                        Text(section.type.sectionTabTitle)
                            .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                            .padding(.horizontal, Spacing.current.space3xs)
                            .foregroundColor(isSelected ? Color("onBkgTextColor10") : Color("onBkgTextColor30"))
                            .padding(.vertical, Spacing.current.spaceXs)
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Rectangle()
                                        .fill(Color("onBkgTextColor10"))
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Spacing.current.spaceS)
        .background(Color("AppBkgColor"))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color("onBkgTextColor30").opacity(0.15))
                .frame(height: 1)
        }
    }
}

// MARK: - Section Paged Scroll View (Option 2: custom horizontal paging, iOS 17+)
/// Replaces TabView with ScrollView + scrollPosition/scrollTargetLayout so we avoid UICollectionView and layout warnings.
@available(iOS 17.0, *)
struct SectionPagedScrollView: View {
    let sections: [CatalogueSection]
    @Binding var selectedIndex: Int
    /// When true, disables both horizontal paging and vertical scroll so drag-up-to-expand wins.
    var isScrollDisabled: Bool = false
    /// Explicit content height - when provided, uses this instead of GeometryReader inference
    var contentHeight: CGFloat?

    @State private var scrollPositionId: CatalogueSectionType?

    var body: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            let pageHeight: CGFloat = {
                if let contentHeight = contentHeight {
                    return contentHeight
                } else {
                    return max(1, geo.size.height - geo.safeAreaInsets.bottom)
                }
            }()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(sections) { section in
                        ScrollView {
                            CatalogueViewRegistry.view(for: section)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.current.spaceS)
                                .padding(.bottom, 100)
                        }
                        .scrollDisabled(isScrollDisabled)
                        .frame(width: pageWidth, height: pageHeight)
                        .id(section.type)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(isScrollDisabled) // Disable horizontal paging when not at full height so drag-up wins
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPositionId)
            .onAppear {
                if scrollPositionId == nil, sections.indices.contains(selectedIndex) {
                    scrollPositionId = sections[selectedIndex].type
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if sections.indices.contains(newIndex) {
                    let type = sections[newIndex].type
                    if type != scrollPositionId {
                        scrollPositionId = type
                    }
                }
            }
            .onChange(of: scrollPositionId) { _, newId in
                guard let newId else { return }
                if let idx = sections.firstIndex(where: { $0.type == newId }), idx != selectedIndex {
                    selectedIndex = idx
                }
            }
        }
        // .frame(maxHeight: contentHeight ?? .infinity)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Legacy Paged Scroll View (iOS 16 and below)
/// Custom UIScrollView paging to avoid TabView's UICollectionViewFlowLayout warnings.
struct LegacyPagedScrollView: UIViewRepresentable {
    let sections: [CatalogueSection]
    @Binding var selectedIndex: Int
    var isScrollDisabled: Bool = false

    private func makePageView(for section: CatalogueSection) -> AnyView {
        AnyView(
            ScrollView {
                CatalogueViewRegistry.view(for: section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.current.spaceS)
                    .padding(.bottom, 100)
            }
            .disabled(isScrollDisabled)
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.delegate = context.coordinator
        scrollView.isScrollEnabled = !isScrollDisabled
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        scrollView.isScrollEnabled = !isScrollDisabled

        let pageWidth = scrollView.bounds.width
        let pageHeight = scrollView.bounds.height
        let contentSize = CGSize(width: pageWidth * CGFloat(sections.count), height: pageHeight)
        scrollView.contentSize = contentSize

        if context.coordinator.hostingControllers.count != sections.count {
            context.coordinator.hostingControllers.forEach { controller in
                controller.view.removeFromSuperview()
            }
            context.coordinator.hostingControllers = sections.map { section in
                let controller = UIHostingController(rootView: makePageView(for: section))
                controller.view.backgroundColor = .clear
                scrollView.addSubview(controller.view)
                return controller
            }
        } else {
            for (index, section) in sections.enumerated() {
                context.coordinator.hostingControllers[index].rootView = makePageView(for: section)
            }
        }

        for (index, controller) in context.coordinator.hostingControllers.enumerated() {
            let originX = CGFloat(index) * pageWidth
            controller.view.frame = CGRect(x: originX, y: 0, width: pageWidth, height: pageHeight)
        }

        let targetOffset = CGPoint(x: CGFloat(selectedIndex) * pageWidth, y: 0)
        if scrollView.contentOffset != targetOffset {
            scrollView.setContentOffset(targetOffset, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var selectedIndex: Int
        var hostingControllers: [UIHostingController<AnyView>] = []

        init(selectedIndex: Binding<Int>) {
            self._selectedIndex = selectedIndex
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateSelectedIndex(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                updateSelectedIndex(scrollView)
            }
        }

        private func updateSelectedIndex(_ scrollView: UIScrollView) {
            let pageWidth = max(scrollView.bounds.width, 1)
            let newIndex = Int(round(scrollView.contentOffset.x / pageWidth))
            let maxIndex = max(hostingControllers.count - 1, 0)
            let clampedIndex = min(max(newIndex, 0), maxIndex)
            if clampedIndex != selectedIndex {
                selectedIndex = clampedIndex
            }
        }
    }
}

// MARK: - Info Sheet
struct InfoSheet: View {
    @Binding var selectedTab: PreviewTabSelection
    @Binding var shouldHideTabBar: Bool
    let sheetFullHeight: CGFloat
    let bottomSafeAreaInsetHeight: CGFloat
    @Binding var sheetSnapPoint: SnapPoint
    
    // Catalogue management
    @ObservedObject var catalogueManager: CatalogueManager
    
    init(
        selectedTab: Binding<PreviewTabSelection>,
        shouldHideTabBar: Binding<Bool>,
        sheetFullHeight: CGFloat,
        bottomSafeAreaInsetHeight: CGFloat,
        sheetSnapPoint: Binding<SnapPoint>,
        catalogueManager: CatalogueManager
    ) {
        self._selectedTab = selectedTab
        self._shouldHideTabBar = shouldHideTabBar
        self.sheetFullHeight = sheetFullHeight
        self.bottomSafeAreaInsetHeight = bottomSafeAreaInsetHeight
        self._sheetSnapPoint = sheetSnapPoint
        self.catalogueManager = catalogueManager
    }
    
    /// Extracts LocationDetailData from CatalogueManager
    private var locationDetailData: LocationDetailData? {
        catalogueManager.locationDetailData
    }
    
    // Snap points - visible heights
    private var fullHeight: CGFloat {
        sheetFullHeight
    }
    
    @State private var dragOffset: CGFloat = 0
    @State private var scrollViewContentOffset: CGFloat = 0
    @State private var isScrolling: Bool = false
    @State private var scrollSettleTask: Task<Void, Never>?
    @State private var selectedSectionIndex: Int = 0
    @State private var isShowingLocationPicker: Bool = false
    @State private var headerFrame: CGRect = .zero
    
    // Offset adjustment for sheet positioning (bottom safe area + optional padding)
    private var positionOffsetAdjustment: CGFloat {
        bottomSafeAreaInsetHeight + 45 // 105 (safe area) + 41 (padding) = 146
    }
    
    // Threshold for hiding tab bar (scrolled down by this amount)
    // Negative values mean scrolled down (content moved up)
    private let hideTabBarThreshold: CGFloat = -20
    
    /// Minimum vertical drag (pt) before we treat the gesture as sheet collapse.
    /// Avoids interpreting a slightly tilted horizontal swipe (paging) as a downward drag.
    private let minVerticalDragForCollapse: CGFloat = 20
    
    /// True when the drag is predominantly vertical (height > width).
    /// Used so horizontal paging swipes are not interpreted as sheet collapse.
    private func isPredominantlyVerticalDown(_ translation: CGSize) -> Bool {
        translation.height > 0 && translation.height > abs(translation.width)
    }
    
    // Fixed UI element heights for content height calculation
    private let dragHandleHeight: CGFloat = 21 // 5 (height) + 12 (top padding) + 4 (bottom padding)
    private let estimatedHeaderTabBarHeight: CGFloat = 120 // Estimated combined height of header + tab bar when visible
    
    /// Computes explicit paging container height based on current snap point
    /// This is used for the SectionPagedScrollView (iOS 17+)
    private var pagingContainerHeight: CGFloat {
        let currentHeight = sheetSnapPoint.height(fullHeight: fullHeight)
        
        if sheetSnapPoint == .full {
            // At full height, header/tab bar are in safeAreaInset (overlay), so content can use more space
            // Subtract drag handle and bottom safe area
            return max(1, currentHeight - dragHandleHeight - bottomSafeAreaInsetHeight)
        } else {
            // At partial/collapsed, header and tab bar are in VStack above content
            // Subtract drag handle and header+tab bar (no bottom safe area needed as sheet doesn't extend to bottom)
            return max(1, currentHeight - dragHandleHeight - estimatedHeaderTabBarHeight)
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
                    .padding(.bottom, 4)
                
                // Content: tabbed sections when we have sections, else single scroll
                // Root layout: always drag handle → header → tab bar (when sections) → paging/scroll.
                // No overlay/safeAreaInset so spacing is explicit and no extra gap.
                Group {
                    if !catalogueManager.orderedSections.isEmpty {
                        VStack(spacing: 0) {
                            // Header and tab bar always in flow (full and non-full)
                            VStack(spacing: 0) {
                                InfoSheetHeaderView(
                                    locationData: locationDetailData,
                                    isFromDeviceLocation: catalogueManager.isCatalogueFromDeviceLocation,
                                    currentSnapPoint: sheetSnapPoint,
                                    isDropdownOpen: isShowingLocationPicker,
                                    onChangeLocation: {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            isShowingLocationPicker.toggle()
                                        }
                                    }
                                )
                                .padding(.top, Spacing.current.space2xs)
                                .padding(.bottom, Spacing.current.spaceXs)
                                .padding(.horizontal, Spacing.current.spaceS)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(key: HeaderFramePreferenceKey.self, value: geo.frame(in: .named("sheetContent")))
                                    }
                                )
                                InfoSheetSectionTabBar(sections: catalogueManager.orderedSections, selectedIndex: $selectedSectionIndex)
                            }
                            
                            if #available(iOS 17.0, *) {
                                SectionPagedScrollView(
                                    sections: catalogueManager.orderedSections,
                                    selectedIndex: $selectedSectionIndex,
                                    isScrollDisabled: sheetSnapPoint != .full
                                )
                            } else {
                                LegacyPagedScrollView(
                                    sections: catalogueManager.orderedSections,
                                    selectedIndex: $selectedSectionIndex,
                                    isScrollDisabled: sheetSnapPoint != .full
                                )
                                .frame(maxHeight: .infinity)
                            }
                        }
                        .coordinateSpace(name: "sheetContent")
                        .onPreferenceChange(HeaderFramePreferenceKey.self) { frame in
                            headerFrame = frame
                        }
                        .overlay {
                            // Dropdown overlay - on top of everything
                            if isShowingLocationPicker && (sheetSnapPoint == .full || sheetSnapPoint == .partial) {
                                ZStack(alignment: .top) {
                                    // Dismiss backdrop
                                    Color.black.opacity(0.001)
                                        .onTapGesture {
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                isShowingLocationPicker = false
                                            }
                                        }
                                    
                                    // Dropdown positioned below header
                                    LocationDropdown(isPresented: $isShowingLocationPicker)
                                        .padding(.horizontal, Spacing.current.spaceS)
                                        .padding(.top, headerFrame.maxY + 4)
                                }
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: isShowingLocationPicker)
                    } else {
                        VStack(spacing: 0) {
                            // Header fixed at top (same as sections layout)
                            InfoSheetHeaderView(
                                locationData: locationDetailData,
                                isFromDeviceLocation: catalogueManager.isCatalogueFromDeviceLocation,
                                currentSnapPoint: sheetSnapPoint,
                                isDropdownOpen: isShowingLocationPicker,
                                onChangeLocation: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isShowingLocationPicker.toggle()
                                    }
                                }
                            )
                            .padding(.top, Spacing.current.space2xs)
                            .padding(.bottom, Spacing.current.spaceXs)
                            .padding(.horizontal, Spacing.current.spaceS)
                            
                            ScrollView {
                                VStack(spacing: 0) {
                                    ScrollOffsetTracker(offset: $scrollViewContentOffset, shouldHideTabBar: $shouldHideTabBar, currentSnapPoint: sheetSnapPoint, hideTabBarThreshold: hideTabBarThreshold)
                                    VStack(alignment: .leading, spacing: 0) {
                                        TestBody()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, Spacing.current.spaceS)
                                    .padding(.bottom, 100)
                                }
                            }
                            .scrollDisabled(sheetSnapPoint != .full || (sheetSnapPoint == .full && dragOffset > 0 && isScrollAtTop))
                        }
                    }
                }
                .compositingGroup()
                .coordinateSpace(name: "scroll")
                .scrollDisabled(sheetSnapPoint != .full || (sheetSnapPoint == .full && dragOffset > 0 && isScrollAtTop))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if sheetSnapPoint == .full,
                               value.translation.height > minVerticalDragForCollapse,
                               isPredominantlyVerticalDown(value.translation) {
                                guard isScrollAtTop else {
                                    dragOffset = 0
                                    return
                                }
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if sheetSnapPoint == .full,
                               value.translation.height > minVerticalDragForCollapse,
                               isPredominantlyVerticalDown(value.translation) {
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
                        // Only treat as collapse when predominantly vertical and past threshold
                        // so horizontal paging swipes (slight tilt) are not interpreted as sheet drag
                        guard value.translation.height > minVerticalDragForCollapse,
                              isPredominantlyVerticalDown(value.translation) else {
                            dragOffset = 0
                            return
                        }
                        // Only allow downward drag if scroll content is exactly at top
                        guard isScrollAtTop else {
                            #if DEBUG
                            print("🚫 Collapse blocked - scroll offset: \(scrollViewContentOffset), isAtTop: \(isScrollAtTop)")
                            #endif
                            dragOffset = 0
                            return
                        }
                        dragOffset = value.translation.height
                    } else {
                        // Not at full - handle all drags
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // Handle swipe from .full to .collapsed only when predominantly vertical
                    if sheetSnapPoint == .full,
                       value.translation.height > minVerticalDragForCollapse,
                       isPredominantlyVerticalDown(value.translation) {
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
                    
                    // Handle all other swipes (non-full or non-vertical)
                    let newSnapPoint = determineSnapPoint(
                        dragDistance: value.translation.height
                    )
                    
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
            // Close dropdown when snap point changes to collapsed
            if newSnapPoint == .collapsed && isShowingLocationPicker {
                withAnimation(.easeOut(duration: 0.15)) {
                    isShowingLocationPicker = false
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isShowingLocationPicker)
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

#if DEBUG
/// Preview that loads an array of `{"event": "...", "data": {...}}` from `sse_preview_events.json`,
/// stringifies each `data` to simulate an SSE stream, and replays via SSEEventProcessor so CatalogueManager is populated by the router.
#Preview("SSE Catalogue") {
    SSEPreviewWrapper(snapPoint: .full)
}

#Preview("SSE Catalogue - Partial") {
    SSEPreviewWrapper(snapPoint: .partial)
}

private struct SSEPreviewWrapper: View {
    @StateObject private var catalogueManager = CatalogueManager()
    let snapPoint: SnapPoint

    var body: some View {
        InfoSheet(
            selectedTab: .constant(.journey),
            shouldHideTabBar: .constant(false),
            sheetFullHeight: 1000,
            bottomSafeAreaInsetHeight: 0,
            sheetSnapPoint: .constant(snapPoint),
            catalogueManager: catalogueManager
        )
        .task {
            await replaySSEPreviewEvents(into: catalogueManager)
        }
    }
}

/// Load SSE preview events from JSON: array of `{"event": "<type>", "data": <object or string>}`.
/// Uses Bundle.main (like coreTests uses Bundle.module for test resources). Tries `config/` subdirectory then bundle root.
private func loadSSEPreviewEventsFromJSON() -> [[String: Any]]? {
    var url = Bundle.main.url(forResource: "sse_preview_events", withExtension: "json", subdirectory: "config")
    if url == nil {
        url = Bundle.main.url(forResource: "sse_preview_events", withExtension: "json")
    }
    guard let url,
          let data = try? Data(contentsOf: url),
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return nil
    }
    return array
}

/// Stringify `data` for SSEEventProcessor.processEvent(event:data:id:) — the data line must be a string.
private func stringifySSEData(_ value: Any?) -> String {
    guard let value else { return "{}" }
    if let string = value as? String { return string }
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

/// Replay loaded SSE events through SSEEventProcessor so CatalogueManager is updated via SSEEventRouter.
@MainActor
private func replaySSEPreviewEvents(into catalogueManager: CatalogueManager) async {
    guard let events = loadSSEPreviewEventsFromJSON() else { return }
    
    // Set up sample location data for the header (similar to updateLocationToUHP)
    let sampleLocation = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964),
        altitude: 0,
        horizontalAccuracy: 0,
        verticalAccuracy: -1,
        timestamp: Date()
    )
    let locationData = LocationDetailData(
        location: sampleLocation,
        placeName: "Ancient Rome",
        subdivisions: "Rome, Lazio",
        countryName: "Italy",
        countryCode: "IT",
        adminArea: "Lazio",
        locality: "Rome"
    )
    catalogueManager.setLocationData(locationData, isFromDeviceLocation: true)
    
    let chatManager = ChatManager(uhpGateway: UHPGateway(), userManager: UserManager())
    let router = SSEEventRouter(
        chatManager: chatManager,
        catalogueManager: catalogueManager,
        mapFeaturesManager: nil,
        toastManager: nil
    )
    let processor = SSEEventProcessor(router: router)
    for item in events {
        let eventString = item["event"] as? String
        let dataString = stringifySSEData(item["data"])
        await processor.processEvent(event: eventString, data: dataString, id: nil)
    }
}
#endif