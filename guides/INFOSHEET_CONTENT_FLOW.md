# InfoSheet Content Update and Display Flow

## Overview

InfoSheet shows journey-related content (overview, location detail, points of interest). Content is managed by `ContentManager` and updated from SSE events and location/POI state.

## Architecture

### Components

1. **ContentManager** (`views/ContentManager.swift`)
   - `@MainActor` `ObservableObject`; stores sections by `ContentViewType`
   - `orderedSections`: sections in display order
   - `locationDetailData`: derived from `.locationDetail` section for header
   - Content types and display order are defined via `ContentTypeRegistry` and `displayOrder`

2. **InfoSheet** (`views/InfoSheetView.swift`)
   - Takes `contentManager: ContentManager` (not a raw sections array)
   - Renders `contentManager.orderedSections` via `ContentViewRegistry.view(for: section)`
   - Uses `contentManager.locationDetailData` for header

3. **MainView**
   - Receives `contentManager` as `@EnvironmentObject` (created in app root)
   - Passes `contentManager` into InfoSheet
   - Updates content when location or POIs change (see Update Triggers)

## Content Types

### Overview (`ContentViewType.overview`)

- **Data**: `overview(markdown: String)`
- **View**: `OverviewView` (markdown)
- **Update**: Via SSE `content` / `overview` events; ContentTypeRegistry parses and calls `ContentManager.setContent`.

### Location Detail (`ContentViewType.locationDetail`)

- **Data**: `ContentSectionData.locationDetail(dict: LocationDict)` (geocoded location dictionary)
- **View**: `LocationDetailView`
- **Update**: Set in `MainView+LocationHandling.updateLocationToUHP`: after reverse geocode, `contentManager.setContent(type: .locationDetail, data: .locationDetail(dict: locationDict))`. Flow: location → EventManager (e.g. `location_detected`) → SSE stream → or direct update from geocoder in `updateLocationToUHP`.

### Points of Interest (`ContentViewType.pointsOfInterest`)

- **Data**: `pointsOfInterest(features: [PointFeature])`
- **View**: `ContentPoiItemView` (single) or `ContentPoiListView` (multiple)
- **Update**: In `MainView`, `.onChange(of: mapFeaturesManager.geoJSONUpdateTrigger)`: extract POIs from `mapFeaturesManager.poisGeoJSON` and call `contentManager.setContent(type: .pointsOfInterest, data: .pointsOfInterest(features: pois))` or `removeContent(type: .pointsOfInterest)`.

## Display Order

Defined in `ContentManager` via `displayOrder`; `orderedSections` returns sections in that order.

## Rendering

- InfoSheet: `if !contentManager.orderedSections.isEmpty { ForEach(contentManager.orderedSections) { ContentViewRegistry.view(for: $0) } }`
- `ContentViewRegistry.view(for:)` (in ContentManager) switches on section data and returns the appropriate view (OverviewView, LocationDetailView, POI views).

## Update Triggers Summary

| Content Type      | Update Trigger                         | Source |
|-------------------|----------------------------------------|--------|
| Overview          | SSE `content` / `overview`             | ContentTypeRegistry → ContentManager |
| Location Detail   | `updateLocationToUHP` (geocoder + setContent) | MainView+LocationHandling |
| Points of Interest| `mapFeaturesManager.geoJSONUpdateTrigger` | MainView `.onChange`; POIs from `poisGeoJSON` |

## Notes

- **Content ID**: Sections use stable ids (e.g. type rawValue) so SwiftUI doesn’t recreate views unnecessarily.
- **TestBody**: A `TestBody()` view is still rendered in InfoSheet (e.g. for debug); content and TestBody can both appear.
- **New content types**: Add type, data case, and a `ContentTypeDefinition`; register in ContentTypeRegistry and add to display order. See [Adding_New_Content_Types.md](./Adding_New_Content_Types.md).
