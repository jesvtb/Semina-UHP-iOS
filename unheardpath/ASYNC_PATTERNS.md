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
            let result = try await apiClient.asyncCallAPI(...)
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
    func asyncCallAPI(
        url: String,
        method: String = "POST"
    ) async throws -> Any {
        // Implementation
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
func processStream() async {
    let stream = apiClient.streamAPI(...)
    
    for try await event in stream {
        await MainActor.run {
            // Process each event
            self.handleEvent(event)
        }
    }
}
```

## 7. Best Practices

### ✅ DO
- Use `Task { }` to call async functions from sync contexts
- Use `await MainActor.run { }` for UI updates
- Handle errors with `do/catch`
- Use `.task` modifier for view lifecycle async work

### ❌ DON'T
- Don't call `await` directly in sync contexts (use `Task`)
- Don't update UI from background threads
- Don't forget error handling for throwing async functions
- Don't use `async` in computed properties

## 8. Quick Reference

| Context | How to Call Async Function |
|---------|---------------------------|
| Button action | `Task { await func() }` |
| View appears | `.task { await func() }` |
| Initializer | `Task { await func() }` |
| Another async func | `await func()` directly |
| Class method | `await func()` or `Task { await func() }` |

## 9. Common Patterns from Codebase

### Pattern: Async Function in View
```swift
func getInitialProfile() async {
    do {
        let profile = try await supabase.from("profiles").select()...
        await MainActor.run {
            self.username = profile.username ?? ""
        }
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

**Last Updated**: Based on Swift 5.5+ async/await patterns



