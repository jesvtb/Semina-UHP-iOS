# Guide: Adding New Content Types

This guide walks through the complete flow of adding a new content type that flows from backend SSE events, through parsing and routing, to display in `InfoSheetView`.

## Architecture Overview

The content flow follows this path:

```
Backend (router_chat.py)
  ↓ (SSE Event)
SSEEventProcessor (parsing)
  ↓ (onContent callback)
SSEEventRouter (routing)
  ↓ (setContent)
ContentManager (state management)
  ↓ (orderedSections)
InfoSheetView (rendering)
  ↓ (ContentViewRegistry)
Custom View Component
```

## Step-by-Step Guide

### Step 1: Define the Content Type Enum

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add your new content type to the `ContentViewType` enum:

```swift
enum ContentViewType: String, CaseIterable {
    case overview
    case locationDetail
    case pointsOfInterest
    case yourNewType  // Add here
}
```

**Important**: The `rawValue` must match the string sent from the backend in the SSE event's `type` field.

### Step 2: Define the Data Structure

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add a new case to the `ContentSection.ContentSectionData` enum:

```swift
enum ContentSectionData {
    case overview(markdown: String)
    case locationDetail(data: LocationDetailData)
    case pointsOfInterest(features: [PointFeature])
    case yourNewType(data: YourNewDataType)  // Add here
}
```

**Example**: If your new type needs structured data, create a data model:

```swift
struct YourNewDataType {
    let title: String
    let items: [String]
    let metadata: [String: String]
}
```

### Step 3: Update ContentManager Display Order

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add your new type to the `displayOrder` array in `ContentManager`:

```swift
private let displayOrder: [ContentViewType] = [
    .overview,
    .locationDetail,
    .pointsOfInterest,
    .yourNewType  // Add here in desired position
]
```

This determines the order in which content sections appear in `InfoSheetView`.

### Step 4: Add Parsing Logic in SSEEventProcessor

**File**: `03_apps/iosapp/unheardpath/services/SSEEventProcessor.swift`

In the `handleContentEvent` method, add a case to parse your new content type:

```swift
private func handleContentEvent(_ event: SSEEvent) async {
    // ... existing parsing code ...
    
    // Parse data based on content type
    let contentData: ContentSection.ContentSectionData
    switch contentType {
    case .overview:
        // ... existing code ...
        
    case .locationDetail:
        // ... existing code ...
        
    case .pointsOfInterest:
        // ... existing code ...
        
    case .yourNewType:  // Add here
        guard let dataDict = dataValue as? [String: Any],
              let title = dataDict["title"] as? String,
              let items = dataDict["items"] as? [String] else {
            #if DEBUG
            print("⚠️ Invalid yourNewType data format")
            #endif
            return
        }
        let metadata = dataDict["metadata"] as? [String: String] ?? [:]
        let yourNewData = YourNewDataType(
            title: title,
            items: items,
            metadata: metadata
        )
        contentData = .yourNewType(data: yourNewData)
    }
    
    await handler?.onContent(type: contentType, data: contentData)
}
```

**Note**: The parsing logic extracts data from the `data` field of the SSE event payload. The structure should match what your backend sends.

### Step 5: Create the View Component

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Create a SwiftUI view component for your content type:

```swift
struct YourNewTypeView: View {
    let data: YourNewDataType
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
            DisplayText(data.title, scale: .article2, color: Color("onBkgTextColor20"))
            
            ForEach(data.items, id: \.self) { item in
                Text(item)
                    .bodyText()
                    .foregroundColor(Color("onBkgTextColor30"))
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
}
```

**Design Guidelines**:
- Use `DisplayText` for section headers with appropriate scale and color
- Use `bodyText()` or `bodyParagraph()` modifiers for content text
- Follow the existing spacing patterns using `Spacing.current`
- Use semantic color names like `Color("onBkgTextColor20")` and `Color("onBkgTextColor30")`

### Step 6: Register the View in ContentViewRegistry

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add your view to the `ContentViewRegistry.view(for:)` method:

```swift
static func view(for section: ContentSection) -> some View {
    switch section.data {
    case .overview(let markdown):
        OverviewView(markdown: markdown)
    case .locationDetail(let locationData):
        LocationDetailView(location: locationData.location)
    case .pointsOfInterest(let features):
        if features.count == 1, let feature = features.first {
            ContentPoiItemView(feature: feature)
        } else {
            ContentPoiListView(features: features)
        }
    case .yourNewType(let data):  // Add here
        YourNewTypeView(data: data)
    }
}
```

### Step 7: Backend Implementation

**File**: `02_package/semina/api/routers/router_chat.py`

In your backend endpoint, yield an SSE event with the new content type:

```python
yield format_sse_response(
    event="overview",  # or "content" - both are supported
    data={
        "type": "yourNewType",  # Must match ContentViewType.rawValue
        "data": {
            "title": "Your Section Title",
            "items": ["Item 1", "Item 2", "Item 3"],
            "metadata": {
                "key1": "value1",
                "key2": "value2"
            }
        }
    },
)
```

**Event Name**: The SSE event name can be either `"overview"` or `"content"` - both are handled by `SSEEventProcessor.handleContentEvent()` (see line 167 in `SSEEventProcessor.swift`).

**Data Structure**: The `data` field must be a dictionary with:
- `type`: String matching your `ContentViewType.rawValue`
- `data`: The actual content data (structure depends on your content type)

## Complete Flow Example

Let's trace a complete example for a new `"timeline"` content type:

### 1. Backend (router_chat.py)

```python
timeline_data = {
    "type": "timeline",
    "data": {
        "events": [
            {"date": "2024-01-01", "title": "Event 1", "description": "Description 1"},
            {"date": "2024-01-02", "title": "Event 2", "description": "Description 2"},
        ]
    }
}

yield format_sse_response(
    event="content",
    data=timeline_data,
)
```

### 2. SSEEventProcessor Parsing

```swift
case .timeline:
    guard let dataDict = dataValue as? [String: Any],
          let eventsArray = dataDict["events"] as? [[String: Any]] else {
        #if DEBUG
        print("⚠️ Invalid timeline data format")
        #endif
        return
    }
    let events = eventsArray.compactMap { eventDict -> TimelineEvent? in
        guard let date = eventDict["date"] as? String,
              let title = eventDict["title"] as? String,
              let description = eventDict["description"] as? String else {
            return nil
        }
        return TimelineEvent(date: date, title: title, description: description)
    }
    contentData = .timeline(events: events)
```

### 3. SSEEventRouter (No Changes Needed)

The router automatically forwards `onContent` calls to `ContentManager.setContent()`. No changes required.

### 4. ContentManager Storage

```swift
// ContentManager automatically stores the content
contentManager.setContent(type: .timeline, data: .timeline(events: events))
```

### 5. InfoSheetView Rendering

```swift
// InfoSheetView automatically renders via ContentViewRegistry
ForEach(contentManager.orderedSections) { section in
    ContentViewRegistry.view(for: section)
}
```

### 6. View Display

```swift
case .timeline(let events):
    TimelineView(events: events)
```

## Testing Your New Content Type

### 1. Test Backend Event

Test that your backend correctly yields the SSE event:

```python
# In router_chat.py or test file
async def test_timeline_event():
    events = list(yield_timeline_event())
    assert len(events) == 1
    event = events[0]
    assert "event: content" in event or "event: overview" in event
    assert '"type": "timeline"' in event
```

### 2. Test Parsing

Add debug logging in `SSEEventProcessor.handleContentEvent()`:

```swift
case .timeline:
    # ... parsing code ...
    # Add debug print
    #if DEBUG
    print("✅ Timeline parsed: \(events.count) events")
    #endif
```

### 3. Test View Rendering

Create a preview in `ContentManager.swift`:

```swift
#Preview("Timeline View") {
    ScrollView {
        let events = [
            TimelineEvent(date: "2024-01-01", title: "Event 1", description: "Desc 1"),
            TimelineEvent(date: "2024-01-02", title: "Event 2", description: "Desc 2"),
        ]
        TimelineView(events: events)
            .padding()
    }
    .background(Color("AppBkgColor"))
}
```

## Common Patterns

### Pattern 1: Simple String Content

For content that's just a string (like overview):

```swift
// Data
case .simpleText(text: String)

// Parsing
case .simpleText:
    guard let text = dataValue as? String else { return }
    contentData = .simpleText(text: text)

// View
case .simpleText(let text):
    Text(text)
        .bodyParagraph(color: Color("onBkgTextColor30"))
```

### Pattern 2: List of Items

For content that's a list:

```swift
// Data
case .itemList(items: [String])

// Parsing
case .itemList:
    guard let items = dataValue as? [String] else { return }
    contentData = .itemList(items: items)

// View
case .itemList(let items):
    VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
        ForEach(items, id: \.self) { item in
            Text("• \(item)")
                .bodyText()
        }
    }
```

### Pattern 3: Conditional Rendering

For content that needs different views based on data:

```swift
// View (similar to pointsOfInterest)
case .yourNewType(let data):
    if data.items.count == 1, let item = data.items.first {
        SingleItemView(item: item)
    } else {
        MultipleItemsView(items: data.items)
    }
```

## Troubleshooting

### Content Not Appearing

1. **Check Event Name**: Ensure backend uses `"overview"` or `"content"` as the event name
2. **Check Type String**: Verify `type` field matches `ContentViewType.rawValue` exactly (case-sensitive)
3. **Check Parsing**: Add debug prints in `handleContentEvent` to see if parsing succeeds
4. **Check Display Order**: Verify your type is in `displayOrder` array
5. **Check View Registration**: Ensure your view case is added to `ContentViewRegistry`

### Parsing Errors

1. **Check Data Structure**: Verify backend `data` structure matches what parsing expects
2. **Add Type Guards**: Use `guard let` statements to safely unwrap optional values
3. **Add Debug Logging**: Print parsed values to verify they're correct

### View Not Rendering

1. **Check View Component**: Ensure your view component is properly defined
2. **Check Registry**: Verify the case is added to `ContentViewRegistry.view(for:)`
3. **Check Preview**: Test your view in isolation using SwiftUI previews

## Summary Checklist

When adding a new content type, ensure you:

- [ ] Add enum case to `ContentViewType`
- [ ] Add data case to `ContentSectionData`
- [ ] Add to `displayOrder` in `ContentManager`
- [ ] Add parsing logic in `SSEEventProcessor.handleContentEvent()`
- [ ] Create view component
- [ ] Register view in `ContentViewRegistry`
- [ ] Update backend to yield correct SSE event format
- [ ] Test parsing with debug logs
- [ ] Test view rendering with preview
- [ ] Verify end-to-end flow from backend to display

## Related Files

- **Backend**: `02_package/semina/api/routers/router_chat.py`
- **SSE Parsing**: `03_apps/iosapp/unheardpath/services/SSEEventProcessor.swift`
- **SSE Routing**: `03_apps/iosapp/unheardpath/services/SSEEventRouter.swift`
- **Content Management**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`
- **Display**: `03_apps/iosapp/unheardpath/views/InfoSheetView.swift`

## See Also

- `INFOSHEET_CONTENT_FLOW.md` - Detailed explanation of existing content types and update mechanisms
- `TESTING_SSE_CONTENT.md` - Guide for testing SSE content flow
