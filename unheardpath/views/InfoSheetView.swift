import SwiftUI

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

// MARK: - Test Info Sheet
struct InfoSheet: View {
    @Binding var selectedTab: PreviewTabSelection
    @Binding var shouldHideTabBar: Bool
    let sheetFullHeight: CGFloat
    let bottomSafeAreaInsetHeight: CGFloat
    @Binding var sheetSnapPoint: SnapPoint
    
    // Snap points - visible heights
    private var fullHeight: CGFloat {
        sheetFullHeight
    }
    
    @State private var dragOffset: CGFloat = 0
    @State private var scrollViewContentOffset: CGFloat = 0
    
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
            
            // Hide tab bar when scrolled down significantly
            let isScrolledDown = offset < hideTabBarThreshold
            let shouldHide = sheetSnapPoint == .full && isScrolledDown
            
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
        if sheetSnapPoint == .full && abs(scrollViewContentOffset) > 0.1 {
            print("🔍 isScrollAtTop check: offset=\(String(format: "%.2f", scrollViewContentOffset)), isAtTop=\(isAtTop)")
        }
        #endif
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
                        
                        // Minimal test content
                        VStack(alignment: .leading) {
                        // Text("Journey Content")
                            // .heading(size: .article2)
                        
                        DisplayText("Journey Content", scale: .article2,  color: Color("onBkgTextColor20"))
                            .padding(.top, sheetSnapPoint == .full ? Spacing.current.spaceXl : Spacing.current.spaceXs)
                            .padding(.bottom, Spacing.current.spaceM)
                            
                        
                        ForEach(0..<20, id: \.self) { index in
                            Text("Item \(index + 1) Bibendum ut euismod ultrices hendrerit cras, faucibus suspendisse mi curabitur. Amet sollicitudin nunc maximus diam curabitur imperdiet facilisi gravida, nullam enim velit maecenas lobortis condimentum tempus. Purus luctus aptent consectetur metus lacus venenatis taciti vestibulum nullam habitant magnis nulla magna rhoncus, litora condimentum dapibus montes nostra pretium sagittis vulputate facilisi varius dignissim justo proin. Mauris potenti molestie mattis sodales urna dui vitae donec duis, vivamus curabitur sollicitudin elit dolor vehicula et netus. Ultrices iaculis scelerisque pulvinar pharetra nulla praesent interdum blandit class, pretium egestas sed leo eros tincidunt turpis.")
                                .bodyParagraph(color: Color("onBkgTextColor30"))
                        }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.current.spaceS)
                        .padding(.bottom, 100)
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