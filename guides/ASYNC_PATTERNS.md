# SwiftUI Async Function Patterns Guide

Quick reference for async/await patterns in SwiftUI.

## 1. Defining Async Functions

### Basic Async Function
```swift
func loadData() async {
    // Async work here
}
```

### Async Function with Return Value
```swift
func fetchData() async -> String {
    return "result"
}
```

### Async Function That Throws
```swift
func fetchData() async throws -> Data {
    // Can throw errors
    return data
}
```

### Async Function with Parameters
```swift
func callAPI(url: String, method: String) async throws -> Any {
    // Use parameters
}
```

## 2. Calling Async Functions

### Pattern 1: Using `Task` (Most Common)
```swift
Button("Load") {
    Task {
        await loadData()
    }
}
```

### Pattern 2: Using `.task` Modifier
```swift
Text("Hello")
    .task {
        await loadData()  // Runs when view appears
    }
```

### Pattern 3: From Another Async Function
```swift
func parentFunction() async {
    await childFunction()  // Direct call
}
```

### Pattern 4: In Initializers
```swift
init() {
    Task {
        await checkInitialSession()
    }
}
```

## 3. Error Handling

### With `do/catch`
```swift
Task {
    do {
        let result = try await apiClient.asyncCallAPI(...)
        // Use result
    } catch {
        // Handle error
        print("Error: \(error)")
    }
}
```

### With `try?` (Optional Result)
```swift
Task {
    if let result = try? await apiClient.asyncCallAPI(...) {
        // Success
    } else {
        // Failed silently
    }
}
```

## 4. Updating UI from Async Functions

### Pattern 1: Using `MainActor.run`
```swift
func loadData() async {
    let result = await fetchFromAPI()
    
    await MainActor.run {
        self.data = result  // ✅ UI update on main thread
        self.isLoading = false
    }
}
```

### Pattern 2: Using `@MainActor` Annotation
```swift
@MainActor
func loadData() async {
    let result = await fetchFromAPI()
    self.data = result  // ✅ Automatically on main thread
}
```

### Pattern 3: Marking Property with `@MainActor`
```swift
@MainActor
@Published var data: String = ""  // ✅ All updates on main thread
```

## 5. Common SwiftUI Patterns

### Complete View Example
```swift
struct MyView: View {
    @State private var isLoading = false
    @State private var data: String = ""
    @EnvironmentObject var apiClient: APIClient
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView()
            } else {
                Text(data)
            }
            
            Button("Load") {
                Task {
                    await loadData()
                }
            }
        }
        .task {
            await loadData()  // Load on appear
        }
    }
    
    func loadData() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            // Build request data and convert to JSONValue for Sendable compliance
            var jsonDictAsAny: [String: Any] = ["query": "test"]
            guard let jsonDict = JSONValue.dictionary(from: jsonDictAsAny) else {
                return
            }
            
            let result = try await apiClient.asyncCallAPI(
                url: "https://api.example.com/endpoint",
                jsonDict: jsonDict  // ✅ Sendable-compliant
            )
            await MainActor.run {
                self.data = "\(result)"
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.data = "Error: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}
```

### Async Function in Class/Manager
```swift
class APIClient {
    // Note: jsonDict is [String: JSONValue] for Swift 6 Sendable compliance
    func asyncCallAPI(
        url: String,
        method: String = "POST",
        jsonDict: [String: JSONValue] = [:]
    ) async throws -> Any {
        // Implementation converts JSONValue to [String: Any] internally
        // for JSONSerialization
    }
}
```

### Async Function in View Extension
```swift
extension MyView {
    func helperFunction() async {
        // Helper logic
    }
}
```

## 6. Streaming/Async Sequences

### Using `for try await`
```swift
@MainActor
func processStream() async {
    // Build request data and convert to JSONValue
    var jsonDictAsAny: [String: Any] = ["message": "Hello"]
    guard let jsonDict = JSONValue.dictionary(from: jsonDictAsAny) else {
        return
    }
    
    // Stream API accepts [String: JSONValue] for Sendable compliance
    let stream = uhpGateway.stream(
        endpoint: "/v1/stream",
        jsonDict: jsonDict  // ✅ Sendable-compliant
    )
    
    for try await event in stream {
        // Process each event (already on MainActor)
        self.handleEvent(event)
    }
}
```

## 7. Swift 6 Sendable Compliance with JSONValue

### Why JSONValue?

In Swift 6 strict concurrency mode, `[String: Any]` is **not `Sendable`**, which causes data race warnings when passing data across concurrency boundaries (e.g., from `@MainActor` to `nonisolated` contexts). `JSONValue` is a type-safe, `Sendable`-compliant representation of JSON data.

### Converting from [String: Any] to [String: JSONValue]

When you receive data from JSON parsing or need to pass it to API methods:

```swift
// Pattern 1: Convert dictionary directly
let jsonDictAsAny: [String: Any] = [
    "message": "Hello",
    "count": 42,
    "isActive": true
]

guard let jsonDict = JSONValue.dictionary(from: jsonDictAsAny) else {
    print("❌ Failed to convert to JSONValue")
    return
}

// Now jsonDict is [String: JSONValue] and Sendable-compliant
```

### Using JSONValue in API Calls

All API methods (`UHPGateway.request()`, `UHPGateway.stream()`, `APIClient.asyncCallAPI()`, etc.) now accept `[String: JSONValue]`:

```swift
@MainActor
func sendChatMessage(_ messageText: String) async {
    // Build request data as [String: Any] first
    var jsonDictAsAny: [String: Any] = [
        "message": messageText,
        "msg_utc": ISO8601DateFormatter().string(from: Date()),
        "device_lang": Locale.current.languageCode ?? "en"
    ]
    
    // Convert to JSONValue for Swift 6 Sendable compliance
    guard let jsonDict = JSONValue.dictionary(from: jsonDictAsAny) else {
        print("❌ Failed to convert to JSONValue")
        return
    }
    
    // Pass JSONValue to API method (no data race warnings!)
    let stream = try await uhpGateway.stream(
        endpoint: "/v1/ask",
        jsonDict: jsonDict  // ✅ Sendable-compliant
    )
}
```

### Converting in Continuations

When using `withCheckedContinuation`, convert to `JSONValue` inside the continuation for Sendable compliance:

```swift
let jsonDict = await withCheckedContinuation { (continuation: CheckedContinuation<[String: JSONValue]?, Never>) in
    locationManager.reverseGeocodeUserLocation { dict, error in
        if let dict = dict {
            // Convert to JSONValue for Sendable compliance
            let jsonValue = JSONValue.dictionary(from: dict)
            continuation.resume(returning: jsonValue)
        } else {
            continuation.resume(returning: nil)
        }
    }
}
```

### Extracting Values from JSONValue

Use the convenience properties and subscript to extract values:

```swift
let properties: [String: JSONValue]? = // ... from API response

// Extract string value
if let titleValue = properties?["title"],
   let title = titleValue.stringValue {
    print("Title: \(title)")
}

// Extract nested dictionary
if let namesValue = properties?["names"],
   let names = namesValue.dictionaryValue {
    if let deviceLangValue = names["device_lang"],
       let deviceLang = deviceLangValue.stringValue {
        print("Device language: \(deviceLang)")
    }
}

// Direct subscript access (returns JSONValue?)
if let idx = properties?["idx"] {
    // idx is JSONValue, extract using pattern matching
    switch idx {
    case .int(let value):
        print("Index: \(value)")
    case .double(let value):
        print("Index: \(Int(value))")
    default:
        break
    }
}
```

### Converting Back to Any (for JSONSerialization)

When you need to use `JSONSerialization`, convert back using `asAny`:

```swift
let jsonDict: [String: JSONValue] = // ... from API

// Convert to [String: Any] for JSONSerialization
let jsonDictAsAny = jsonDict.mapValues { $0.asAny }

let jsonData = try JSONSerialization.data(withJSONObject: jsonDictAsAny)
```

### Complete Example: API Call with JSONValue

```swift
@MainActor
private func loadLocation(jsonDict: [String: JSONValue]) async {
    // Extract values from JSONValue
    guard let latValue = jsonDict["latitude"],
          let lonValue = jsonDict["longitude"] else {
        return
    }
    
    // Extract numeric values
    let userLat: CLLocationDegrees
    switch latValue {
    case .double(let value):
        userLat = value
    case .int(let value):
        userLat = CLLocationDegrees(value)
    default:
        return
    }
    
    // Make API call with JSONValue
    let response = try await uhpGateway.request(
        endpoint: "/v1/signed-in-home",
        method: "POST",
        jsonDict: jsonDict  // ✅ Sendable-compliant
    )
}
```

### JSONValue Helper Methods

The `JSONValue` type provides several convenience methods:

- `init?(from: Any)` - Convert from `Any` (from JSONSerialization)
- `static func dictionary(from: [String: Any]) -> [String: JSONValue]?` - Convert dictionary
- `var asAny: Any` - Convert back to `Any` for JSONSerialization
- `var stringValue: String?` - Extract string if this is a string case
- `var dictionaryValue: [String: JSONValue]?` - Extract dictionary if this is a dictionary case
- `subscript(key: String) -> JSONValue?` - Access dictionary values
- Pattern matching with `switch` - Extract values by case (recommended for numeric types)

### Best Practices for JSONValue

#### ✅ DO
- Convert `[String: Any]` to `[String: JSONValue]` **before** passing to API methods
- Use `JSONValue.dictionary(from:)` for dictionary conversion
- Extract values using `stringValue`, `dictionaryValue`, or pattern matching
- Convert back to `Any` only when needed for `JSONSerialization`

#### ❌ DON'T
- Don't pass `[String: Any]` directly to API methods (causes data race warnings)
- Don't mix `[String: Any]` and `[String: JSONValue]` in the same call chain
- Don't forget to handle conversion failures (use `guard let` or `if let`)

### Migration Pattern

When updating existing code:

1. **Identify** all places where `[String: Any]` is passed to API methods
2. **Convert** using `JSONValue.dictionary(from:)` before the API call
3. **Update** function signatures to accept `[String: JSONValue]` instead of `[String: Any]`
4. **Extract** values using JSONValue convenience methods instead of `as?` casting

## 8. Best Practices

### ✅ DO
- Use `Task { }` to call async functions from sync contexts
- Use `await MainActor.run { }` for UI updates
- Handle errors with `do/catch`
- Use `.task` modifier for view lifecycle async work
- **Convert `[String: Any]` to `[String: JSONValue]` before API calls** (Swift 6 Sendable compliance)
- Use `@MainActor` annotation on async functions in Views

### ❌ DON'T
- Don't call `await` directly in sync contexts (use `Task`)
- Don't update UI from background threads
- Don't forget error handling for throwing async functions
- Don't use `async` in computed properties
- **Don't pass `[String: Any]` directly to API methods** (causes data race warnings in Swift 6)
- Don't mix `[String: Any]` and `[String: JSONValue]` in the same call chain

## 9. Quick Reference

| Context | How to Call Async Function |
|---------|---------------------------|
| Button action | `Task { await func() }` |
| View appears | `.task { await func() }` |
| Initializer | `Task { await func() }` |
| Another async func | `await func()` directly |
| Class method | `await func()` or `Task { await func() }` |

## 10. Common Patterns from Codebase

### Pattern: Async Function in View with JSONValue
```swift
@MainActor
func sendMessage() async {
    // Build request data
    var jsonDictAsAny: [String: Any] = [
        "message": "Hello",
        "timestamp": Date().timeIntervalSince1970
    ]
    
    // Convert to JSONValue for Sendable compliance
    guard let jsonDict = JSONValue.dictionary(from: jsonDictAsAny) else {
        print("❌ Failed to convert to JSONValue")
        return
    }
    
    do {
        let response = try await uhpGateway.request(
            endpoint: "/v1/message",
            jsonDict: jsonDict  // ✅ Sendable-compliant
        )
        // Process response...
    } catch {
        // Handle error
    }
}
```

### Pattern: Async Function in Manager
```swift
class AuthManager {
    init() {
        Task {
            await checkInitialSession()
        }
    }
    
    private func checkInitialSession() async {
        // Async work
    }
}
```

### Pattern: Async Function with Callback
```swift
ChatInputBar(
    onSendMessage: { messageText in
        Task {
            await sendChatMessage(messageText)
        }
    }
)
```

---

**Last Updated**: Based on Swift 6.0+ async/await patterns with Sendable compliance

---

## Appendix: JSONValue Type Reference

### JSONValue Cases

```swift
enum JSONValue: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case dictionary([String: JSONValue])
    case null
}
```

### Common Conversion Patterns

```swift
// From [String: Any] to [String: JSONValue]
let dict: [String: Any] = ["key": "value"]
let jsonDict = JSONValue.dictionary(from: dict)

// From [String: JSONValue] to [String: Any]
let jsonDict: [String: JSONValue] = ["key": .string("value")]
let dict = jsonDict.mapValues { $0.asAny }

// Pattern matching for extraction
switch jsonValue {
case .string(let value):
    // Use string value
case .int(let value):
    // Use int value
case .dictionary(let value):
    // Use dictionary value
default:
    // Handle other cases
}
```



