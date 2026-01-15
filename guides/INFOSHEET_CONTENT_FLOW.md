# InfoSheet Content Update and Display Flow

## Overview

This document explains how content in the `InfoSheet` component is updated and displayed depending on content type. The InfoSheet displays journey-related content including overview, location details, and points of interest.

## Architecture

### Components

1. **ContentManager** (`StandardContentTypes.swift`)
   - `@MainActor` `ObservableObject` that manages content sections by type
   - Stores content in a dictionary keyed by `ContentViewType`
   - Provides `orderedSections` property that returns sections in display order

2. **InfoSheet** (`InfoSheetView.swift`)
   - Receives `standardContent: [ContentSection]?` as a parameter
   - Renders content using `ContentViewRegistry.view(for: section)`

3. **ContentViewRegistry** (`StandardContentTypes.swift`)
   - Static view builder that switches on content type and returns appropriate view

4. **MainView** (`MainView.swift`)
   - Owns `@StateObject private var contentManager = ContentManager()`
   - Passes `contentManager.orderedSections` to InfoSheet
   - Updates content manager based on various state changes

## Content Types

### 1. Overview (`ContentViewType.overview`)

**Data Structure:**
```swift
case overview(markdown: String)
```

**View Component:**
- `OverviewView` - Renders markdown using `MarkdownUI`

**Current Status:**
- ✅ Defined in `ContentViewType` enum
- ✅ View component exists (`OverviewView`)
- ✅ Registry handles it
- ❌ **NOT currently updated in real app flow** - only used in preview/JSON loading

**Where it should be updated:**
- Currently no mechanism exists to set overview content from API/SSE events
- Would need to add an SSE event handler (e.g., "overview" event type) or extract from chat response

### 2. Location Detail (`ContentViewType.locationDetail`)

**Data Structure:**
```swift
case locationDetail(location: CLLocation)
```

**View Component:**
- `LocationDetailView` - Displays latitude, longitude, and altitude

**Update Mechanism:**
```swift
// In MainView.swift, lines 206-223
.onChange(of: locationManager.deviceLocation) { newLocation in
    // Update content manager with location
    if let location = newLocation {
        contentManager.setContent(
            type: .locationDetail,
            data: .locationDetail(location: location)
        )
    } else {
        contentManager.removeContent(type: .locationDetail)
    }
    // ... rest of location handling
}
```

**Flow:**
1. `LocationManager` updates `deviceLocation` property
2. `MainView` observes this change via `.onChange`
3. Calls `contentManager.setContent()` with new location
4. `ContentManager` updates its internal dictionary
5. `orderedSections` computed property returns updated sections
6. InfoSheet re-renders with new content

### 3. Points of Interest (`ContentViewType.pointsOfInterest`)

**Data Structure:**
```swift
case pointsOfInterest(features: [PointFeature])
```

**View Components:**
- `ContentPoiItemView` - Single POI display (used when count == 1)
- `ContentPoiListView` - Multiple POIs with list header (used when count > 1)

**Update Mechanism:**
```swift
// In MainView.swift, lines 243-254
.onChange(of: mapFeaturesManager.geoJSONUpdateTrigger) { _ in
    // Update content manager with POIs when GeoJSON changes
    let pois = extractPOIs(from: mapFeaturesManager.poisGeoJSON)
    if !pois.isEmpty {
        contentManager.setContent(
            type: .pointsOfInterest,
            data: .pointsOfInterest(features: pois)
        )
    } else {
        contentManager.removeContent(type: .pointsOfInterest)
    }
}
```

**Flow:**
1. `MapFeaturesManager` receives GeoJSON updates (from SSE "map" events)
2. Updates `geoJSONUpdateTrigger` to signal change
3. `MainView` observes this change via `.onChange`
4. Extracts POIs from `mapFeaturesManager.poisGeoJSON` using `extractPOIs()`
5. Calls `contentManager.setContent()` with POI features
6. `ContentManager` updates its internal dictionary
7. `orderedSections` computed property returns updated sections
8. InfoSheet re-renders with new content

**POI Extraction:**
- `extractPOIs()` function converts GeoJSON features to `PointFeature` objects
- Located in `StandardContentTypes.swift` (line 270)

## Display Order

Content sections are displayed in a fixed order defined in `ContentManager`:

```swift
private let displayOrder: [ContentViewType] = [
    .overview,
    .locationDetail,
    .pointsOfInterest
]
```

The `orderedSections` computed property ensures sections appear in this order:

```swift
var orderedSections: [ContentSection] {
    displayOrder.compactMap { type in
        sections[type]
    }
}
```

## Rendering Flow

### InfoSheet Content Rendering

```swift
// In InfoSheetView.swift, lines 232-236
if let standardContent = standardContent, !standardContent.isEmpty {
    ForEach(standardContent) { section in
        ContentViewRegistry.view(for: section)
    }
}
```

### ContentViewRegistry View Selection

```swift
// In StandardContentTypes.swift, lines 81-94
static func view(for section: ContentSection) -> some View {
    switch section.data {
    case .overview(let markdown):
        OverviewView(markdown: markdown)
    case .locationDetail(let location):
        LocationDetailView(location: location)
    case .pointsOfInterest(let features):
        if features.count == 1, let feature = features.first {
            ContentPoiItemView(feature: feature)
        } else {
            ContentPoiListView(features: features)
        }
    }
}
```

**Key Behavior:**
- POIs use conditional rendering: single POI shows `ContentPoiItemView`, multiple show `ContentPoiListView` with header

## State Management

### ContentManager Properties

- `@Published private var sections: [ContentViewType: ContentSection] = [:]`
  - Dictionary ensures only one section per type
  - `@Published` triggers SwiftUI updates when changed

### MainView Integration

```swift
// MainView.swift, line 42
@StateObject private var contentManager = ContentManager()

// MainView.swift, lines 100-108
InfoSheet(
    selectedTab: $selectedTab,
    shouldHideTabBar: $shouldHideTabBar,
    sheetFullHeight: sheetFullHeight,
    bottomSafeAreaInsetHeight: bottomSafeAreaInsetHeight,
    sheetSnapPoint: $sheetSnapPoint,
    standardContent: contentManager.orderedSections,  // ← Passes ordered sections
    customBuilders: nil
)
```

## Update Triggers Summary

| Content Type | Update Trigger | Source |
|-------------|----------------|--------|
| Overview | ❌ Not implemented | Would need SSE "overview" event or chat extraction |
| Location Detail | `locationManager.deviceLocation` | GPS updates from `LocationManager` |
| Points of Interest | `mapFeaturesManager.geoJSONUpdateTrigger` | SSE "map" events → `MapFeaturesManager` |

## Reactive Updates

All content updates are reactive:

1. **Location Detail**: Updates automatically when GPS location changes
2. **POIs**: Updates automatically when GeoJSON features are received via SSE
3. **Overview**: Currently static (only in previews)

When `ContentManager.setContent()` is called:
- The `@Published` `sections` dictionary updates
- `orderedSections` computed property recalculates
- SwiftUI detects the change (via `@Published`)
- InfoSheet re-renders with new content
- `ContentViewRegistry` selects appropriate view for each section

## Notes

1. **Content ID Stability**: Each `ContentSection` uses `type.rawValue` as its `id`, ensuring SwiftUI doesn't recreate views unnecessarily when parent state changes.

2. **TestBody Always Rendered**: Currently, `TestBody()` is always rendered regardless of whether standard content exists (line 244 in InfoSheetView.swift). The commented code (lines 245-248) shows the intended behavior - `TestBody()` should only appear as a fallback when no content is provided. This appears to be a work-in-progress or debug state.

3. **Custom Builders**: InfoSheet supports `customBuilders` parameter, but it's currently commented out in the rendering logic (lines 238-243).

4. **Missing Overview Implementation**: Overview content type is fully defined but not connected to any data source in the real app flow. It would need:
   - SSE event handler for "overview" events, OR
   - Extraction from chat responses, OR
   - Separate API endpoint to fetch overview content

## Current Rendering Issue

**Location**: `InfoSheetView.swift`, lines 231-248

**Current Code:**
```swift
// Render standard content sections first
if let standardContent = standardContent, !standardContent.isEmpty {
    ForEach(standardContent) { section in
        ContentViewRegistry.view(for: section)
    }
}

// Custom builders commented out...

TestBody()  // ← Always rendered, even when content exists
```

**Intended Behavior** (from commented code):
```swift
// Fallback to TestBody if no content provided
if (standardContent?.isEmpty ?? true) && (customBuilders?.isEmpty ?? true) {
    TestBody()
}
```

This means `TestBody()` currently appears alongside real content, which is likely unintended.
