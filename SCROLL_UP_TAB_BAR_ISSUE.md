# Scroll-Up Tab Bar Animation Issue

## Problem Description

In the iOS app, there is an inconsistent animation behavior when showing/hiding the tab bar based on scroll direction:

- **Scroll Down (Hiding)**: Works smoothly ✅
  - When user scrolls down in the `JourneyContent` (InfoSheet), the tab bar hides smoothly with a clean animation
  - The animation is immediate and responsive
  - No jitter or glitchy behavior

- **Scroll Up (Showing)**: Does NOT work smoothly ❌
  - When user scrolls up in the `JourneyContent`, the tab bar should reappear, but the animation is jittery, glitchy, or delayed
  - The tab bar appearance feels inconsistent compared to the smooth hiding behavior
  - There's a noticeable difference in animation quality between scroll-down and scroll-up

## Technical Context

### Current Implementation

1. **ScrollOffsetTracker** (`MainView.swift`):
   - Tracks scroll offset using `GeometryReader` and `PreferenceKey`
   - Detects scroll direction (up vs down)
   - Controls `shouldHideTabBar` binding
   - Uses `withTransaction(Transaction(animation: .easeInOut(duration: 0.2)))` for animations
   - Scroll-down logic: Immediately sets `shouldHideTabBar = true` when `newOffset < hideTabBarThreshold`
   - Scroll-up logic: Immediately sets `shouldHideTabBar = false` when `isScrollingUp && tabBarIsCurrentlyHidden`

2. **Tab Bar Rendering** (`MainView.swift` line 227):
   - Tab bar opacity: `.opacity((!shouldHideTabBar || selectedTab != .journey) ? 1 : 0)`
   - Has explicit animation: `.animation(.easeInOut(duration: 0.2), value: shouldHideTabBar)`

3. **InfoSheetView** (`InfoSheetView.swift`):
   - Contains the `ScrollView` with content
   - Has `ScrollOffsetTracker` embedded inside the scroll content
   - Has `.onChange(of: sheetSnapPoint)` that also animates `shouldHideTabBar` using `Transaction`

4. **InfoSheetView Scroll Handling**:
   - Has `updateScrollOffset` function (currently unused)
   - Has `isScrolling` state and `scrollSettleTask` for debouncing
   - Has scroll offset tracking via `scrollViewContentOffset` state

### Key Observations

- Both scroll-down and scroll-up use the same animation style (`Transaction` with `.easeInOut(duration: 0.2)`)
- Both update `shouldHideTabBar` immediately when conditions are met
- The tab bar has explicit animation modifier
- Yet scroll-up feels jittery while scroll-down is smooth

### Potential Causes

1. **Conflicting Animation Contexts**: 
   - Multiple places might be animating `shouldHideTabBar` simultaneously
   - `ScrollOffsetTracker` uses `withTransaction`
   - `InfoSheetView.onChange` also uses `Transaction`
   - Tab bar has `.animation()` modifier
   - These might be creating competing animation contexts

2. **Scroll Event Frequency**:
   - Scroll events fire very frequently during scrolling
   - Scroll-up detection might be triggering multiple times rapidly
   - The `return` statement in scroll-up logic might not be preventing subsequent updates

3. **State Synchronization**:
   - `wasTabBarHidden` and `tabBarHiddenTimestamp` tracking might be interfering
   - The scroll-up logic checks `tabBarIsCurrentlyHidden = shouldHideTabBar || wasTabBarHidden`
   - This dual state might cause timing issues

4. **InfoSheet Scroll Handling**:
   - `InfoSheetView` has its own scroll offset tracking (`scrollViewContentOffset`)
   - `ScrollOffsetTracker` is embedded inside the scroll view
   - There might be a conflict between these two scroll tracking mechanisms

5. **Animation Timing**:
   - Scroll-down happens when scrolling actively (during scroll)
   - Scroll-up might be triggering at a different point in the scroll lifecycle
   - The animation might be starting/stopping at awkward times

## Expected Behavior

- Scroll-up should show the tab bar with the **same smooth, immediate animation** as scroll-down hiding
- No jitter, glitch, or delay
- Consistent animation quality regardless of scroll direction

## What We've Tried

1. ✅ Simplified scroll-up logic to be immediate (removed distance accumulation)
2. ✅ Unified animation style (all use `Transaction` with same duration)
3. ✅ Added explicit animation modifier to tab bar opacity
4. ✅ Changed `InfoSheetView.onChange` to use `Transaction` instead of `withAnimation`
5. ❌ Problem persists

## Questions to Investigate

1. Is there a competing animation happening when scroll-up triggers?
2. Are there multiple scroll offset tracking mechanisms conflicting?
3. Is the `return` statement in scroll-up logic actually preventing subsequent updates?
4. Is the tab bar opacity animation being overridden or interfered with?
5. Are there any implicit animations from SwiftUI that we're not aware of?
6. Is the scroll-up detection logic firing too frequently or at the wrong times?

## Files Involved

- `03_apps/iosapp/unheardpath/views/MainView.swift` (ScrollOffsetTracker, tab bar rendering)
- `03_apps/iosapp/unheardpath/views/InfoSheetView.swift` (ScrollView, scroll handling)
- `03_apps/iosapp/unheardpath/views/TabBarView.swift` (Tab bar component)

## Request

Please investigate why scroll-up tab bar showing animation is jittery/glitchy while scroll-down hiding is smooth, and fix the inconsistency. The goal is to make scroll-up showing as smooth and immediate as scroll-down hiding.

