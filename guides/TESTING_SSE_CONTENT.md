# Testing SSE Content Events in InfoSheet

This guide explains how to test how different SSE event data will be displayed on the InfoSheet.

## Overview

The InfoSheet displays content that is updated via SSE (Server-Sent Events) from the backend. The content can be of three types:
- **Overview**: Markdown content
- **Location Detail**: Geographic location information
- **Points of Interest**: GeoJSON features representing POIs

## Testing Methods

### 1. Using the Debug Test View (Recommended)

In DEBUG builds, a test button appears in the top-right corner of MainView (next to the cache debug button). Tap it to open the SSE Content Test View.

**Features:**
- Select content type (overview, locationDetail, pointsOfInterest)
- Edit content data directly
- Simulate SSE events
- View current content state
- Clear content

**Steps:**
1. Run the app in DEBUG mode
2. Navigate to the Journey tab
3. Tap the document icon button in the top-right corner
4. Select a content type
5. Edit the content data
6. Tap "Simulate SSE Event"
7. Check the InfoSheet to see the content displayed

### 2. Using SwiftUI Previews

The `InfoSheetView.swift` file includes several preview examples:

```swift
#Preview("Standard Content") {
    // Shows InfoSheet with sample content
}
```

To test with your own data, modify the preview code or create a new preview.

### 3. Programmatic Testing

You can test programmatically using the helper functions:

```swift
#if DEBUG
// Test overview content
await SSEContentTestHelpers.testOverview(
    router: sseEventRouter,
    markdown: "# My Test\n\nContent here"
)

// Test location detail
await SSEContentTestHelpers.testLocationDetail(
    router: sseEventRouter,
    lat: 41.9028,
    lon: 12.4964
)

// Test all content types in sequence
await SSEContentTestHelpers.testAllContentTypes(router: sseEventRouter)
```

### 4. Testing with Real SSE Events

To test with actual SSE events from the backend:

1. **Using `/v1/chat` endpoint:**
   - Send a chat message
   - Backend can respond with content events
   - Events are automatically processed and displayed

2. **Using `/v1/orchestrator` endpoint:**
   - Update location (triggers orchestrator)
   - Backend can respond with content events
   - Events are automatically processed and displayed

## Content Type Examples

### Overview Content

**SSE Event Format:**
```json
{
  "event": "content",
  "data": "{\"type\": \"overview\", \"data\": \"# Welcome\\n\\nThis is markdown content.\"}"
}
```

**Test Data:**
```swift
let markdown = """
# Welcome to Ancient Rome

This is **bold** and this is *italic*.

## Features
- Feature 1
- Feature 2
"""
```

### Location Detail Content

**SSE Event Format:**
```json
{
  "event": "content",
  "data": "{\"type\": \"locationDetail\", \"data\": {\"latitude\": 41.9028, \"longitude\": 12.4964, \"altitude\": 0}}"
}
```

**Test Data:**
```swift
let location = CLLocation(
    coordinate: CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964),
    altitude: 0,
    horizontalAccuracy: 0,
    verticalAccuracy: 0,
    timestamp: Date()
)
```

### Points of Interest Content

**SSE Event Format:**
```json
{
  "event": "content",
  "data": "{\"type\": \"pointsOfInterest\", \"data\": {\"features\": [...]}}"
}
```

**Test Data:**
```swift
let features: [[String: JSONValue]] = [
    [
        "type": .string("Feature"),
        "geometry": .dictionary([
            "type": .string("Point"),
            "coordinates": .array([.double(12.4964), .double(41.9028)])
        ]),
        "properties": .dictionary([
            "title": .string("Colosseum"),
            "description": .string("Ancient Roman amphitheater")
        ])
    ]
]
```

## Testing Scenarios

### Scenario 1: Single Content Type
1. Open test view
2. Select "overview"
3. Enter markdown content
4. Tap "Simulate SSE Event"
5. Verify InfoSheet displays the overview

### Scenario 2: Multiple Content Types
1. Test overview first
2. Test location detail
3. Test points of interest
4. Verify all appear in correct order in InfoSheet

### Scenario 3: Content Updates
1. Add overview content
2. Update overview content with different markdown
3. Verify InfoSheet updates (replaces old content)

### Scenario 4: Content Removal
1. Add multiple content types
2. Use "Clear Selected Type" to remove one
3. Verify only that type is removed
4. Use "Clear All Content" to remove everything

### Scenario 5: Real SSE Stream
1. Send location update to `/v1/orchestrator`
2. Backend responds with content events
3. Verify content appears in InfoSheet automatically

## Debugging Tips

1. **Check Console Logs:**
   - Look for `📄 Processing content event` messages
   - Check for parsing errors
   - Verify content type recognition

2. **Verify ContentManager State:**
   - Use the test view's "Current Content" section
   - Check `contentManager.orderedSections` in debugger

3. **Check InfoSheet Rendering:**
   - Ensure `standardContent` binding is connected
   - Verify `ContentViewRegistry.view(for:)` is called
   - Check individual view components (OverviewView, LocationDetailView, etc.)

4. **Test Edge Cases:**
   - Empty markdown
   - Invalid coordinates
   - Missing POI properties
   - Malformed JSON

## Files Involved

- **SSEContentTestView.swift**: Debug test interface
- **SSEEventProcessor.swift**: Parses SSE events
- **SSEEventRouter.swift**: Routes events to ContentManager
- **ContentManager.swift**: Manages content sections
- **InfoSheetView.swift**: Displays content
- **ContentManager.swift**: Content type definitions and views

## Notes

- The test view is only available in DEBUG builds
- Content updates are immediate (no animation delay)
- Content is ordered: overview → locationDetail → pointsOfInterest
- Each content type can only appear once (updates replace previous content)
