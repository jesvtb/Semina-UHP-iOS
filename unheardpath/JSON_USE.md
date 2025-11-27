# JSON Files Usage Guide

## Setup

### File Locations

**App files** (configuration, runtime data):
```
unheardpath/
  ├── config.json
  ├── basemap_style.json
  └── around_me_example.json
```

**Test files** (mock data):
```
unheardpathTests/
  └── Mocks/
      ├── mock_user_data.json
      └── mock_api_response.json
```

### Add to Xcode Target

1. Right-click file → "Get Info" (or `Cmd + I`)
2. Under "Target Membership":
   - App files: check `unheardpath`
   - Test files: check `unheardpathTests`

**Important:** Files must be added to target to be included in bundle.

---

## Loading Methods

### Method 1: App Bundle (for app code)

```swift
func loadJSON<T: Decodable>(filename: String, as type: T.Type) throws -> T {
    guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
        throw NSError(domain: "JSONLoader", code: 404, 
                     userInfo: [NSLocalizedDescriptionKey: "File \(filename).json not found"])
    }
    
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: data)
}

// Usage:
let places = try loadJSON(filename: "around_me_example", as: PlacesResponse.self)
```

### Method 2: Test Bundle (for unit tests)

```swift
func loadTestJSON<T: Decodable>(filename: String, as type: T.Type) throws -> T {
    guard let url = Bundle(for: type(of: self)).url(forResource: filename, withExtension: "json") else {
        throw NSError(domain: "TestJSONLoader", code: 404,
                     userInfo: [NSLocalizedDescriptionKey: "Test file \(filename).json not found"])
    }
    
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: data)
}

// Usage in test:
@Test func testWithMockData() async throws {
    let mockData = try loadTestJSON(filename: "mock_user_data", as: User.self)
    #expect(mockData.username != nil)
}
```

### Method 3: Reusable Utility

```swift
// Helpers/JSONLoader.swift
import Foundation

struct JSONLoader {
    static func load<T: Decodable>(
        filename: String,
        as type: T.Type,
        bundle: Bundle = .main
    ) throws -> T {
        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            throw JSONLoaderError.fileNotFound(filename)
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw JSONLoaderError.decodingError(error)
        }
    }
}

enum JSONLoaderError: Error {
    case fileNotFound(String)
    case decodingError(Error)
    
    var localizedDescription: String {
        switch self {
        case .fileNotFound(let filename):
            return "JSON file '\(filename).json' not found in bundle"
        case .decodingError(let error):
            return "Failed to decode JSON: \(error.localizedDescription)"
        }
    }
}
```

---

## Examples

### Example 1: Loading Mock Data in Tests

```swift
// unheardpathTests/UnitTests/PlacesTests.swift
import Testing
@testable import unheardpath

struct PlacesTests {
    @Test func testPlacesParsing() async throws {
        let mockPlaces = try JSONLoader.load(
            filename: "around_me_example",
            as: PlacesResponse.self,
            bundle: Bundle(for: Self.self)
        )
        
        #expect(mockPlaces.data.features.count > 0)
    }
}
```

### Example 2: Loading Configuration in App

```swift
// services/ConfigLoader.swift
struct AppConfig: Decodable {
    let apiBaseURL: String
    let timeout: Double
    let features: FeatureFlags
}

struct FeatureFlags: Decodable {
    let enableChat: Bool
    let enableLocation: Bool
}

// Load at app startup
let config = try JSONLoader.load(filename: "config", as: AppConfig.self)
```

### Example 3: Error Handling

```swift
do {
    let data = try JSONLoader.load(filename: "config", as: Config.self)
} catch JSONLoaderError.fileNotFound(let filename) {
    // Handle missing file
    print("Config file not found: \(filename)")
} catch JSONLoaderError.decodingError(let error) {
    // Handle parsing error
    print("Failed to parse JSON: \(error)")
}
```

---

## Best Practices

1. **File Organization:**
   - App config: `unheardpath/config.json`
   - Mock data: `unheardpathTests/Mocks/`
   - Example data: `unheardpath/examples/`

2. **Naming Conventions:**
   - Config: `config.json`, `api_config.json`
   - Mocks: `mock_*.json` or `*_mock.json`
   - Examples: `*_example.json`

3. **Conditional Loading (Debug):**
   ```swift
   #if DEBUG
   let mockData = try JSONLoader.load(filename: "mock_data", as: Data.self)
   #endif
   ```

---

## Quick Reference

| Use Case | Location | Bundle | Example |
|----------|----------|--------|---------|
| App Config | `unheardpath/` | `Bundle.main` | `config.json` |
| Runtime Data | `unheardpath/` | `Bundle.main` | `basemap_style.json` |
| Unit Test Mocks | `unheardpathTests/Mocks/` | `Bundle(for: TestClass.self)` | `mock_user.json` |
| UI Test Fixtures | `unheardpathUITests/Fixtures/` | `Bundle(for: TestClass.self)` | `test_data.json` |

---

## Current Implementation

Your existing `basemap_style.json` loading pattern:

```swift
if let localStyleURL = Bundle.main.url(forResource: "basemap_style", withExtension: "json") {
    mapView.styleURL = localStyleURL
}
```

Use the same approach for other JSON files. For test files, use `Bundle(for: TestClass.self)` instead of `Bundle.main`.

