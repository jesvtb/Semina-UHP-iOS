# Guide: Adding New Content Types

This guide walks through adding a new content type using the **Protocol + Registry** pattern. With this architecture, adding a new content type requires changes in **only 2 places** instead of 7+.

## Architecture Overview

The content flow follows this path:

```
Backend (router_chat.py)
  ↓ (SSE Event with event="content" or "overview")
SSEEventProcessor.handleContentEvent()
  ↓ (parses JSON, extracts type and data)
ContentTypeRegistry.shared().parse() [@MainActor]
  ↓ (calls ContentTypeDefinition.parse())
ContentTypeDefinition.parse() → ContentSectionData
  ↓ (onContent callback with parsed data)
SSEEventRouter.onContent()
  ↓ (routes to ContentManager)
ContentManager.setContent()
  ↓ (stores in sections dictionary)
ContentManager.orderedSections
  ↓ (returns sections in displayOrder)
InfoSheetView
  ↓ (ForEach over orderedSections)
ContentViewRegistry.view(for: section)
  ↓ (calls ContentTypeRegistry.createView())
ContentTypeDefinition.createView()
  ↓ (creates SwiftUI view)
Custom View Component
```

## New Protocol-Based Approach

With the new architecture, adding a content type is **much simpler**:

1. **Add enum case** to `ContentViewType` (if new type)
2. **Add data case** to `ContentSectionData` (if new data structure)
3. **Create one struct** that conforms to `ContentTypeDefinition` protocol
4. **Register it** in `ContentTypeRegistry.init()` by adding to `tempDefinitions`
5. **Add to display order** array in `ContentTypeRegistry`

That's it! No need to modify parsing switches, view switches, or multiple files.

## Step-by-Step Guide

### Step 1: Define the Content Type Enum (if new type)

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add your new content type to the `ContentViewType` enum:

```swift
enum ContentViewType: String, CaseIterable, Sendable {
    case overview
    case locationDetail
    case pointsOfInterest
    case countryOverview
    case subdivisionsOverview
    case neighborhoodOverview
    case cultureOverview
    case regionalCuisine
    case yourNewType  // Add here
}
```

**Important Notes**:
- The `rawValue` must match the string sent from the backend in the SSE event's `type` field (case-sensitive)
- The enum is `Sendable` for Swift 6 concurrency safety
- Multiple overview variants (`.countryOverview`, `.subdivisionsOverview`, `.neighborhoodOverview`, `.cultureOverview`) all use the same `OverviewContentType` - they're registered together in the registry

### Step 2: Define the Data Structure (if new data structure)

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add a new case to the `ContentSection.ContentSectionData` enum:

```swift
enum ContentSectionData {
    case overview(markdown: String)
    case locationDetail(data: LocationDetailData)
    case pointsOfInterest(features: [PointFeature])
    case regionalCuisine(data: RegionalCuisineData)
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

### Step 3: Create the View Component

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

### Step 4: Create Content Type Definition (THE KEY STEP)

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Create a struct that conforms to `ContentTypeDefinition` protocol. This **single struct** contains all the logic for your content type:

```swift
struct YourNewTypeContentType: ContentTypeDefinition {
    static var type: ContentViewType { .yourNewType }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let dataDict = dataValue as? [String: Any],
              let title = dataDict["title"] as? String,
              let items = dataDict["items"] as? [String] else {
            return nil
        }
        let metadata = dataDict["metadata"] as? [String: String] ?? [:]
        let yourNewData = YourNewDataType(
            title: title,
            items: items,
            metadata: metadata
        )
        return .yourNewType(data: yourNewData)
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .yourNewType(let yourNewData) = data {
            return AnyView(YourNewTypeView(data: yourNewData))
        }
        return AnyView(EmptyView())
    }
}
```

**Key Points**:
- `parse(from:)` extracts and validates data from the SSE event payload
  - Called from `@MainActor` context (via `ContentTypeRegistry.parse()`)
  - Must handle `Any` type from JSON parsing
  - Should return `nil` if data is invalid
- `createView(for:)` creates the SwiftUI view from parsed data
  - Can be called from any context (not `@MainActor`)
  - Receives already-parsed `ContentSectionData` enum
  - Must return `AnyView` wrapped view
- Both methods are static (no instance needed)
- All logic for this content type is in one place!

### Step 5: Register the Content Type

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add your type to the registry's `init()` method in `ContentTypeRegistry`:

```swift
fileprivate init() {
    var tempDefinitions: [ContentViewType: any ContentTypeDefinition.Type] = [:]
    
    // Register overview and all its variants
    let overviewTypes: [ContentViewType] = [.overview, .countryOverview, .subdivisionsOverview, .neighborhoodOverview, .cultureOverview]
    for type in overviewTypes {
        tempDefinitions[type] = OverviewContentType.self
    }
    
    // Register remaining content types
    tempDefinitions[.locationDetail] = LocationDetailContentType.self
    tempDefinitions[.pointsOfInterest] = PointsOfInterestContentType.self
    tempDefinitions[.regionalCuisine] = RegionalCuisineContentType.self
    tempDefinitions[.yourNewType] = YourNewTypeContentType.self  // Add here
    
    self.definitions = tempDefinitions
}
```

**Note**: If you're creating a variant of an existing type (like overview variants), you can register multiple `ContentViewType` cases to the same `ContentTypeDefinition`. Just add your new enum case to the appropriate array in the init method. For example, if you create `.cityOverview`, you would add it to the `overviewTypes` array.

### Step 6: Add to Display Order

**File**: `03_apps/iosapp/unheardpath/views/ContentManager.swift`

Add your type to the `displayOrder` array in `ContentTypeRegistry`:

```swift
let displayOrder: [ContentViewType] = [
    .overview,
    .locationDetail,
    .regionalCuisine,
    .yourNewType,  // Add here in desired position
    .pointsOfInterest
]
```

**To reorder**: Simply move items in this array - no renumbering needed!

### Step 7: Backend Implementation

**File**: `02_package/semina/api/routers/router_chat.py`

In your backend endpoint, yield an SSE event with the new content type:

```python
yield format_sse_response(
    event="content",  # or "overview" - both are supported
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

**Event Name**: The SSE event name can be either `"overview"` or `"content"` - both are handled by `SSEEventProcessor.handleContentEvent()`.

**Data Structure**: The `data` field must be a dictionary with:
- `type`: String matching your `ContentViewType.rawValue`
- `data`: The actual content data (structure depends on your content type)

## Creating New Data Types for SSE Events and Display

This section explains how to design and implement new data types that flow from backend SSE events through to SwiftUI display.

### Understanding the Data Flow

When creating a new content type, you need to define data structures at three levels:

1. **Backend SSE Event Format** (Python dictionary)
2. **Swift Data Model** (structs/classes)
3. **SwiftUI View** (displays the data)

The flow is:
```
Backend JSON → SSEEventProcessor → ContentTypeDefinition.parse() → Swift Data Model → ContentTypeDefinition.createView() → SwiftUI View
```

### Step-by-Step: Creating a New Data Type

#### 1. Design Your Backend Data Structure

First, decide what data your backend will send. The SSE event should follow this structure:

```python
# In router_chat.py
yield format_sse_response(
    event="content",  # or "overview"
    data={
        "type": "yourNewType",  # Must match ContentViewType.rawValue
        "data": {
            # Your custom data structure here
            "title": "Section Title",
            "items": [
                {"id": 1, "name": "Item 1", "value": 100},
                {"id": 2, "name": "Item 2", "value": 200}
            ],
            "metadata": {
                "source": "api",
                "timestamp": "2024-01-01T00:00:00Z"
            }
        }
    }
)
```

**Key Points**:
- The outer `data` dict must have `type` and `data` fields
- The inner `data` field contains your custom structure
- Use JSON-serializable types (strings, numbers, booleans, arrays, dicts)
- Keep the structure flat when possible for easier parsing

#### 2. Create Swift Data Models

Create Swift structs that represent your data. These should be:
- **Immutable** (use `let` properties)
- **Type-safe** (use proper Swift types, not `Any`)
- **Sendable** (for Swift 6 concurrency)

```swift
// Simple data model
struct YourNewItem {
    let id: Int
    let name: String
    let value: Double
}

// Container data model
struct YourNewDataType {
    let title: String
    let items: [YourNewItem]
    let metadata: [String: String]
}
```

**Best Practices**:
- Use descriptive names that match your domain
- Make properties non-optional when data is required
- Use optionals (`String?`, `URL?`) for optional fields
- Consider using enums for constrained values
- Add computed properties for derived data if needed

#### 3. Add to ContentSectionData Enum

Add a case to the `ContentSection.ContentSectionData` enum in `ContentManager.swift`:

```swift
enum ContentSectionData {
    case overview(markdown: String)
    case locationDetail(data: LocationDetailData)
    case pointsOfInterest(features: [PointFeature])
    case regionalCuisine(data: RegionalCuisineData)
    case yourNewType(data: YourNewDataType)  // Add your new case
}
```

**Important**: The associated value type must match your Swift data model.

#### 4. Implement Parsing Logic

In your `ContentTypeDefinition.parse()` method, convert the raw `Any` data from the SSE event into your Swift data model:

**Important**: The `parse()` method is called from `@MainActor` context via `ContentTypeRegistry.parse()`, which is called from `SSEEventProcessor.handleContentEvent()`. The method receives the `data` field value directly from the parsed JSON (not the entire event payload).

```swift
static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
    // Step 1: Cast to dictionary
    // Note: dataValue is the "data" field from the SSE event payload
    guard let dataDict = dataValue as? [String: Any] else {
        #if DEBUG
        print("⚠️ YourNewType: Expected dictionary, got \(type(of: dataValue))")
        #endif
        return nil
    }
    
    // Step 2: Extract required fields
    guard let title = dataDict["title"] as? String,
          let itemsArray = dataDict["items"] as? [[String: Any]] else {
        #if DEBUG
        print("⚠️ YourNewType: Missing required fields")
        #endif
        return nil
    }
    
    // Step 3: Parse nested structures
    let items = itemsArray.compactMap { itemDict -> YourNewItem? in
        guard let id = itemDict["id"] as? Int,
              let name = itemDict["name"] as? String,
              let value = itemDict["value"] as? Double else {
            return nil
        }
        return YourNewItem(id: id, name: name, value: value)
    }
    
    // Step 4: Extract optional fields
    let metadata = dataDict["metadata"] as? [String: String] ?? [:]
    
    // Step 5: Create and return data model
    let yourNewData = YourNewDataType(
        title: title,
        items: items,
        metadata: metadata
    )
    
    return .yourNewType(data: yourNewData)
}
```

**Parsing Guidelines**:
- Always use `guard let` for required fields
- Use `compactMap` for arrays that may contain invalid items
- Provide default values for optional fields (e.g., `?? []`, `?? [:]`)
- Add debug logging to help troubleshoot parsing issues
- Return `nil` if required data is missing or invalid
- Handle type mismatches gracefully
- Remember: `dataValue` is the inner `data` field from the SSE event, not the entire payload
- **Concurrency Note**: While `parse()` is called from `@MainActor` context, the method itself doesn't need to be marked `@MainActor` because it only performs data transformation (no UI access). However, if you need to access `@MainActor` properties, you may need to mark it `@MainActor`.

**How Parsing is Called**:
```swift
// In SSEEventProcessor.handleContentEvent() (line 373-374)
let contentData = await MainActor.run {
    ContentTypeRegistry.shared().parse(type: contentType, dataValue: dataValue)
}
// ContentTypeRegistry.parse() is @MainActor and calls your parse() method
```

#### 5. Create the SwiftUI View

Design your view to display the data model:

```swift
struct YourNewTypeView: View {
    let data: YourNewDataType
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
            // Header
            DisplayText(data.title, scale: .article2, color: Color("onBkgTextColor20"))
            
            // Content
            ForEach(data.items, id: \.id) { item in
                HStack {
                    Text(item.name)
                        .bodyText()
                        .foregroundColor(Color("onBkgTextColor20"))
                    Spacer()
                    Text("\(item.value, specifier: "%.0f")")
                        .bodyText()
                        .foregroundColor(Color("onBkgTextColor30"))
                }
            }
            
            // Optional metadata display
            if !data.metadata.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                    ForEach(Array(data.metadata.keys.sorted()), id: \.self) { key in
                        if let value = data.metadata[key] {
                            Text("\(key): \(value)")
                                .bodyText()
                                .foregroundColor(Color("onBkgTextColor30"))
                                .font(.caption)
                        }
                    }
                }
                .padding(.top, Spacing.current.spaceXs)
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
}
```

**View Guidelines**:
- Use semantic spacing from `Spacing.current`
- Use semantic colors from your color palette
- Follow existing design patterns in other content views
- Make views responsive to different data sizes
- Handle empty states gracefully
- Use appropriate text styles (`.bodyText()`, `.bodyParagraph()`, etc.)

#### 6. Connect Parsing to View

In your `ContentTypeDefinition.createView()` method, extract the data and create the view:

```swift
static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
    if case .yourNewType(let yourNewData) = data {
        return AnyView(YourNewTypeView(data: yourNewData))
    }
    return AnyView(EmptyView())
}
```

**Important Notes**:
- Always use pattern matching with `if case` to extract the associated value from the enum case
- The method is **not** `@MainActor` - it can be called from any context (used by SwiftUI view builders)
- Must return `AnyView` - wrap your view in `AnyView()`
- Return `AnyView(EmptyView())` if the data case doesn't match (shouldn't happen if registered correctly)

### Data Type Examples

#### Example 1: Simple List with Strings

**Backend**:
```python
data={
    "type": "simpleList",
    "data": ["Item 1", "Item 2", "Item 3"]
}
```

**Swift**:
```swift
// No separate data model needed - use String array directly
case simpleList(items: [String])

static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
    guard let items = dataValue as? [String] else { return nil }
    return .simpleList(items: items)
}
```

#### Example 2: Complex Nested Structure

**Backend**:
```python
data={
    "type": "weatherForecast",
    "data": {
        "location": "San Francisco",
        "forecasts": [
            {
                "date": "2024-01-01",
                "high": 72,
                "low": 55,
                "condition": "sunny"
            }
        ]
    }
}
```

**Swift**:
```swift
struct WeatherForecast {
    let date: String
    let high: Int
    let low: Int
    let condition: String
}

struct WeatherForecastData {
    let location: String
    let forecasts: [WeatherForecast]
}

case weatherForecast(data: WeatherForecastData)

static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
    guard let dataDict = dataValue as? [String: Any],
          let location = dataDict["location"] as? String,
          let forecastsArray = dataDict["forecasts"] as? [[String: Any]] else {
        return nil
    }
    
    let forecasts = forecastsArray.compactMap { dict -> WeatherForecast? in
        guard let date = dict["date"] as? String,
              let high = dict["high"] as? Int,
              let low = dict["low"] as? Int,
              let condition = dict["condition"] as? String else {
            return nil
        }
        return WeatherForecast(date: date, high: high, low: low, condition: condition)
    }
    
    return .weatherForecast(data: WeatherForecastData(location: location, forecasts: forecasts))
}
```

#### Example 3: Data with Optional Fields

**Backend**:
```python
data={
    "type": "article",
    "data": {
        "title": "Article Title",
        "content": "Article content...",
        "author": "John Doe",
        "image_url": "https://example.com/image.jpg",  # Optional
        "tags": ["swift", "ios"]  # Optional, defaults to []
    }
}
```

**Swift**:
```swift
struct ArticleData {
    let title: String
    let content: String
    let author: String
    let imageURL: URL?
    let tags: [String]
}

case article(data: ArticleData)

static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
    guard let dataDict = dataValue as? [String: Any],
          let title = dataDict["title"] as? String,
          let content = dataDict["content"] as? String,
          let author = dataDict["author"] as? String else {
        return nil
    }
    
    // Handle optional fields with defaults
    let imageURLString = dataDict["image_url"] as? String
    let imageURL = imageURLString.flatMap { URL(string: $0) }
    let tags = dataDict["tags"] as? [String] ?? []
    
    return .article(data: ArticleData(
        title: title,
        content: content,
        author: author,
        imageURL: imageURL,
        tags: tags
    ))
}
```

### Data Type Design Best Practices

1. **Keep Structures Flat When Possible**: Avoid deep nesting (more than 2-3 levels)
2. **Use Strong Types**: Prefer specific types (`Int`, `String`, `URL`) over `Any`
3. **Validate Early**: Check data validity in `parse()`, not in views
4. **Handle Missing Data**: Use optionals or default values for optional fields
5. **Make Models Immutable**: Use `let` properties to prevent accidental mutations
6. **Add Computed Properties**: For derived data (e.g., `fullName` from `firstName` + `lastName`)
7. **Consider Enums**: For constrained values (e.g., `Status` enum instead of `String`)
8. **Document Complex Structures**: Add comments explaining the data model's purpose

### Testing Your Data Type

1. **Test Parsing**: Create test data matching your backend format and verify parsing succeeds
2. **Test Edge Cases**: Empty arrays, missing fields, invalid types, null values
3. **Test View Rendering**: Use SwiftUI previews with sample data
4. **Test End-to-End**: Send real SSE events from backend and verify display

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

### 2. iOS Implementation (ContentManager.swift)

**All in one place!** Create the content type definition:

```swift
// Data model
struct TimelineEvent {
    let date: String
    let title: String
    let description: String
}

struct TimelineData {
    let events: [TimelineEvent]
}

// View component
struct TimelineView: View {
    let data: TimelineData
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
            DisplayText("Timeline", scale: .article2, color: Color("onBkgTextColor20"))
            ForEach(data.events, id: \.date) { event in
                VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                    Text(event.date)
                        .bodyText()
                        .foregroundColor(Color("onBkgTextColor30"))
                    Text(event.title)
                        .bodyText()
                        .foregroundColor(Color("onBkgTextColor20"))
                    Text(event.description)
                        .bodyParagraph(color: Color("onBkgTextColor30"))
                }
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
}

// Content type definition (THE KEY PART)
struct TimelineContentType: ContentTypeDefinition {
    static var type: ContentViewType { .timeline }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let dataDict = dataValue as? [String: Any],
              let eventsArray = dataDict["events"] as? [[String: Any]] else {
            return nil
        }
        let events = eventsArray.compactMap { eventDict -> TimelineEvent? in
            guard let date = eventDict["date"] as? String,
                  let title = eventDict["title"] as? String,
                  let description = eventDict["description"] as? String else {
                return nil
            }
            return TimelineEvent(date: date, title: title, description: description)
        }
        return .timeline(data: TimelineData(events: events))
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .timeline(let timelineData) = data {
            return AnyView(TimelineView(data: timelineData))
        }
        return AnyView(EmptyView())
    }
}
```

### 3. Register and Add to Display Order

```swift
// In ContentTypeRegistry.init()
fileprivate init() {
    var tempDefinitions: [ContentViewType: any ContentTypeDefinition.Type] = [:]
    
    // ... existing registrations ...
    tempDefinitions[.timeline] = TimelineContentType.self  // Add here
    
    self.definitions = tempDefinitions
}

// In ContentTypeRegistry.displayOrder
let displayOrder: [ContentViewType] = [
    .overview,
    .locationDetail,
    .regionalCuisine,
    .timeline,  // Add here
    .pointsOfInterest
]
```

### 4. Automatic Flow

Once registered, the system automatically:
- **SSEEventProcessor.handleContentEvent()** receives SSE event and extracts `type` and `data` fields
- **ContentTypeRegistry.shared().parse()** is called from `@MainActor` context to parse the data
- **YourContentType.parse()** converts raw `Any` data into `ContentSectionData` enum
- **SSEEventRouter.onContent()** receives parsed data and routes to ContentManager
- **ContentManager.setContent()** stores the content in the sections dictionary
- **ContentManager.orderedSections** returns sections in the order defined by `displayOrder`
- **InfoSheetView** iterates over `orderedSections` and calls `ContentViewRegistry.view(for:)`
- **ContentViewRegistry.view(for:)** is a wrapper that calls `ContentTypeRegistry.shared().createView(for:)`
- **YourContentType.createView()** creates the SwiftUI view from the parsed data

**No manual switch statements needed!** The registry pattern handles all routing automatically.

## Testing Your New Content Type

### 1. Test Parsing Logic

Add debug logging in your content type's `parse` method:

```swift
static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
    guard let dataDict = dataValue as? [String: Any] else {
        #if DEBUG
        print("⚠️ Timeline: Invalid data format")
        #endif
        return nil
    }
    // ... parsing code ...
    #if DEBUG
    print("✅ Timeline parsed: \(events.count) events")
    #endif
    return .timeline(data: TimelineData(events: events))
}
```

### 2. Test View Rendering

Create a preview in `ContentManager.swift`:

```swift
#Preview("Timeline View") {
    ScrollView {
        let events = [
            TimelineEvent(date: "2024-01-01", title: "Event 1", description: "Desc 1"),
            TimelineEvent(date: "2024-01-02", title: "Event 2", description: "Desc 2"),
        ]
        TimelineView(data: TimelineData(events: events))
            .padding()
    }
    .background(Color("AppBkgColor"))
}
```

### 3. Test End-to-End

Use the test view or send a real SSE event from the backend and verify:
- Parsing succeeds (check debug logs)
- Content appears in InfoSheetView
- View renders correctly
- Display order is correct

## Common Patterns

### Pattern 1: Simple String Content

For content that's just a string (like overview):

```swift
struct SimpleTextContentType: ContentTypeDefinition {
    static var type: ContentViewType { .simpleText }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let text = dataValue as? String else { return nil }
        return .simpleText(text: text)
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .simpleText(let text) = data {
            return AnyView(Text(text).bodyParagraph(color: Color("onBkgTextColor30")))
        }
        return AnyView(EmptyView())
    }
}
```

### Pattern 2: List of Items

For content that's a list:

```swift
struct ItemListContentType: ContentTypeDefinition {
    static var type: ContentViewType { .itemList }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let items = dataValue as? [String] else { return nil }
        return .itemList(items: items)
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .itemList(let items) = data {
            return AnyView(
                VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                    ForEach(items, id: \.self) { item in
                        Text("• \(item)")
                            .bodyText()
                    }
                }
            )
        }
        return AnyView(EmptyView())
    }
}
```

### Pattern 3: Conditional Rendering

For content that needs different views based on data (like pointsOfInterest):

```swift
static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
    if case .yourNewType(let yourData) = data {
        if yourData.items.count == 1, let item = yourData.items.first {
            return AnyView(SingleItemView(item: item))
        } else {
            return AnyView(MultipleItemsView(items: yourData.items))
        }
    }
    return AnyView(EmptyView())
}
```

## Reordering Content Types

To change the display order of content types, simply modify the `displayOrder` array in `ContentTypeRegistry`:

```swift
// Move regionalCuisine before locationDetail
let displayOrder: [ContentViewType] = [
    .overview,
    .regionalCuisine,  // Moved up
    .locationDetail,    // Moved down
    .pointsOfInterest
]
```

**No renumbering needed!** Just move items in the array.

## Troubleshooting

### Content Not Appearing

1. **Check Event Name**: Ensure backend uses `"overview"` or `"content"` as the event name
2. **Check Type String**: Verify `type` field matches `ContentViewType.rawValue` exactly (case-sensitive)
3. **Check Registration**: Verify your type is registered in `ContentTypeRegistry.init()` by checking `tempDefinitions[.yourNewType]`
4. **Check Display Order**: Verify your type is in `displayOrder` array in `ContentTypeRegistry`
5. **Check Parsing**: Add debug prints in your `parse` method to see if parsing succeeds

### Parsing Errors

1. **Check Data Structure**: Verify backend `data` structure matches what your `parse` method expects
2. **Add Type Guards**: Use `guard let` statements to safely unwrap optional values
3. **Add Debug Logging**: Print parsed values in your `parse` method to verify they're correct
4. **Return nil on failure**: Your `parse` method should return `nil` if data is invalid

### View Not Rendering

1. **Check View Component**: Ensure your view component is properly defined
2. **Check createView method**: Verify your `createView` method correctly extracts data from the enum case
3. **Check Preview**: Test your view in isolation using SwiftUI previews
4. **Verify AnyView wrapping**: Ensure you're wrapping your view in `AnyView()`

## Summary Checklist

When adding a new content type, ensure you:

- [ ] Add enum case to `ContentViewType` (if new type)
- [ ] Add data case to `ContentSectionData` (if new data structure)
- [ ] Create data model struct (if needed)
- [ ] Create view component
- [ ] Create content type definition struct (conforms to `ContentTypeDefinition`)
- [ ] Register type in `ContentTypeRegistry.init()` by adding to `tempDefinitions`
- [ ] Add to `displayOrder` array in `ContentTypeRegistry`
- [ ] Update backend to yield correct SSE event format
- [ ] Test parsing with debug logs
- [ ] Test view rendering with preview
- [ ] Verify end-to-end flow from backend to display

## Benefits of New Approach

**Before** (7+ files to modify):
- ❌ Add enum case
- ❌ Add data case
- ❌ Update displayOrder array
- ❌ Add parsing case in SSEEventProcessor
- ❌ Add view case in ContentViewRegistry
- ❌ Create view component
- ❌ Update backend

**After** (2-3 files to modify):
- ✅ Add enum case (if new)
- ✅ Add data case (if new)
- ✅ Create one struct with all logic (parsing + view)
- ✅ Register it
- ✅ Add to display order
- ✅ Update backend

**Result**: Single source of truth, easier maintenance, compile-time safety!

## Related Files

- **Backend**: `02_package/semina/api/routers/router_chat.py` - SSE event generation
- **SSE Parsing**: `03_apps/iosapp/unheardpath/services/SSEEventProcessor.swift` - Handles SSE events, calls `ContentTypeRegistry.parse()`
- **SSE Routing**: `03_apps/iosapp/unheardpath/services/SSEEventRouter.swift` - Routes parsed content to `ContentManager`
- **Content Management**: `03_apps/iosapp/unheardpath/views/ContentManager.swift` - Contains:
  - `ContentViewType` enum
  - `ContentSectionData` enum
  - `ContentTypeDefinition` protocol
  - `ContentTypeRegistry` class
  - `ContentManager` class
  - `ContentViewRegistry` struct (wrapper for registry)
  - All content type definitions and views
- **Display**: `03_apps/iosapp/unheardpath/views/InfoSheetView.swift` - Renders content using `ContentViewRegistry.view(for:)`

## See Also

- `INFOSHEET_CONTENT_FLOW.md` - Detailed explanation of existing content types and update mechanisms
- `TESTING_SSE_CONTENT.md` - Guide for testing SSE content flow
