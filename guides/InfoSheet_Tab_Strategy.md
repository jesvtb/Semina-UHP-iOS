# InfoSheet Section Tabs: Strategy Examination

## Current Approach

- **SwiftUI `TabView`** with `.tabViewStyle(.page(indexDisplayMode: .never))` for horizontal paging between sections (Overview, Location, Cuisine, Points of Interest).
- **Custom tab bar** (`InfoSheetSectionTabBar`) above the TabView with pill highlight for the selected tab.
- **Two code paths**: when `orderedSections.isEmpty` → single ScrollView + TestBody; when not empty → tab bar + TabView with one ScrollView per section.
- **Workarounds**: `GeometryReader` + explicit `pageHeight = size.height - safeAreaInsets.bottom - 1` so each page is strictly smaller than the collection view’s usable height and the UICollectionViewFlowLayout warning is avoided.

## Costs of Current Approach

| Issue | Impact |
|-------|--------|
| **UICollectionViewFlowLayout** | TabView’s paging uses a UICollectionView; item height must be &lt; (height − insets). We rely on a `-1` and safe area to satisfy this; fragile across OS/safe area changes. |
| **Duplicate layout** | Header + tab bar are built twice: once in `safeAreaInset` (when full) and once in the VStack (when not full). |
| **Split content paths** | “Has sections” vs “no sections” are two different layouts (TabView vs single ScrollView), so scroll/offset logic and modifiers are split. |
| **ScrollOffsetTracker unused when tabbed** | When sections exist, we don’t use ScrollOffsetTracker; `isScrollAtTop` and drag-to-collapse still work via the Group’s gesture, but scroll-based tab bar hide doesn’t apply to tabbed pages. |

## Alternative Strategies

### 1. Single ScrollView with section headers (no horizontal paging)

**Idea:** One vertical ScrollView. Content: header, then for each section a small “section header” row (like a tab label) + that section’s content. User scrolls vertically through Overview → Location → Cuisine → POIs.

**Pros**

- No TabView, no UICollectionView, no layout warnings.
- One code path for “has sections” and “no sections” (same ScrollView; empty state = no sections in list).
- Header and “tab” strip can be shared (e.g. one sticky header that includes section labels or a single row of section titles).
- Simple, predictable, and easy to maintain.

**Cons**

- No horizontal swipe; section change is by scrolling or by tapping a section header if we make them tappable (scroll to section).

**Verdict:** Best if the product is okay with “one long vertical scroll with clear section breaks” instead of “swipe between full-screen section pages.”

---

### 2. Custom horizontal ScrollView with paging

**Idea:** Replace TabView with `ScrollView(.horizontal)` + `LazyHStack` (or `HStack`). Each page has `.frame(width: containerWidth)`. Use scroll position (e.g. `scrollPosition` id or preference) to drive `selectedSectionIndex`; on tab tap, scroll to the corresponding page. Use `scrollTargetLayout` / `scrollPosition` (iOS 17+) or a small timer/gesture to snap to page boundaries.

**Pros**

- No TabView, no UICollectionView, no framework layout constraints.
- Full control over sizing and behavior; no “item height &lt; …” hacks.
- Keeps “swipe between sections” and “tap tab to switch” UX.

**Cons**

- More code (snap behavior, index ↔ scroll position sync).
- Need to ensure accessibility (e.g. VoiceOver) is preserved.

**Verdict:** Best if horizontal swipe between sections is a hard requirement and we want to avoid TabView’s internals.

---

### 3. Keep TabView but isolate and document the workaround

**Idea:** Keep the current TabView + GeometryReader approach but move it into a dedicated view (e.g. `SectionPagedView`) and document why `pageHeight = height - safeAreaInsets.bottom - 1` is required.

**Pros**

- Minimal refactor; preserves current UX (swipe + tabs).
- Centralizes the fragile part in one type.

**Cons**

- Still depends on TabView’s internal layout and safe area; may break or warn again on different devices/OS.

**Verdict:** Acceptable short-term if we don’t want to change UX and are willing to own the workaround.

---

### 4. Segmented control + single content area (no swipe)

**Idea:** A `Picker` with `.segmented` style for the four sections. One ScrollView below; show only the selected section’s content (swap view by index). No horizontal paging.

**Pros**

- Very simple; no TabView, no paging layout.
- Clear “tap to switch section” model.

**Cons**

- No horizontal swipe; section change only by tap.

**Verdict:** Good if “swipe between sections” is not required.

---

## Latest Swift / SwiftUI relevance (Swift 6, iOS 17–18)

Research against current Swift 6 and SwiftUI documentation shows the following. **App deployment target is iOS 16.1**, so any iOS 17+ API requires raising the minimum.

### Option 2: Custom horizontal paging (iOS 17+)

- **`scrollPosition(id:anchor:)`** (iOS 17+) binds to which view is visible; use with a state ID to drive `selectedSectionIndex` and to programmatically scroll to a section.
- **`scrollTargetLayout()`** marks children as scroll targets; **`scrollTargetBehavior(.paging)`** gives full-page snapping. Together they replace TabView for horizontal paging without UICollectionView.
- **Caveats:** Prefer `LazyHStack` so the `scrollPosition` binding updates when the user scrolls. With irregular-sized pages, `viewAligned` behavior can be quirky in iOS 17 (improved in iOS 18). If we adopt Option 2 and can raise the deployment target to **iOS 17**, this is the supported, non-fragile way to get “swipe + tap tab” without TabView.

**Example pattern (iOS 17+):**

```swift
@State private var scrollPosition: ContentViewType?

ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        ForEach(orderedSections, id: \.self) { section in
            ContentViewRegistry.view(for: section)
                .containerRelativeFrame([.horizontal, .vertical])
                .id(section)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.paging)
.scrollPosition(id: $scrollPosition)
.onChange(of: scrollPosition) { _, newId in
    // sync selectedSectionIndex from newId
}
```

### TabView in iOS 18

- iOS 18 adds a type-safe `Tab` struct and sidebar/adaptable styles; these target **tab-bar** use (bottom tabs, iPad sidebar), not `.page(indexDisplayMode: .never)`.
- There is no documented change to the page-style TabView’s underlying UICollectionView or its item-height behavior, so the current workaround (GeometryReader + `pageHeight - 1`) remains relevant if we keep TabView on iOS 16.1.

### Swift 6 / Swift 6.2 language

- **Swift 6:** Data-race safety (opt-in), typed throws, noncopyable types; no direct impact on this layout choice.
- **Swift 6.2:** Default MainActor isolation, `@concurrent`, `nonisolated(nonsending)` — useful for future concurrency cleanup and avoiding unnecessary `@MainActor` annotations; not required to achieve the InfoSheet tab/section goal.

### Summary for our goal

| Goal | Best approach with current docs |
|------|----------------------------------|
| No TabView, no layout hacks, keep iOS 16.1 | **Option 1** (single vertical ScrollView with section headers). |
| Horizontal swipe + tap tab, willing to target iOS 17+ | **Option 2** using `scrollPosition(id:)` + `scrollTargetLayout()` + `scrollTargetBehavior(.paging)` (no TabView, no UICollectionView). |
| Keep current UX and iOS 16.1 | **Option 3** (isolate TabView workaround) or keep as-is; no new Swift/SwiftUI feature removes the need for the workaround on 16.1. |

---

## Recommendation

1. **Prefer Option 1 (single ScrollView with section headers)** if the product can accept “vertical scroll through sections” instead of “horizontal swipe between sections.” It removes TabView entirely, eliminates layout warnings, unifies the code path, and uses a common, reliable pattern. Section headers can still look like tabs and optionally scroll-to-section on tap.

2. **If horizontal swipe is required**, use **Option 2 (custom horizontal ScrollView with paging)** so we don’t depend on TabView’s UICollectionView and its item-height rules.

3. If we don’t want to change behavior or invest in Option 2 yet, **Option 3** (extract and document the TabView workaround) is a reasonable stopgap.

---

## Next Steps

- **If choosing Option 1:** Refactor InfoSheet to a single ScrollView; render header once, then a section header row (reusing or simplifying `InfoSheetSectionTabBar` as inline labels), then each section’s content in order. Remove TabView and the GeometryReader page-height workaround. Unify “has sections” and “no sections” into one scroll structure.
- **If choosing Option 2:** Implement a horizontal ScrollView + page-width frames + scroll-position ↔ `selectedSectionIndex` binding + snap, and replace the TabView block with this view.
- **If choosing Option 3:** Extract the current TabView + GeometryReader into `SectionPagedView`, add a short comment documenting the `pageHeight` formula and the UICollectionViewFlowLayout constraint.
