# Catalogue Persistence System - Implementation Guide

This document outlines the step-by-step implementation of the Catalogue Persistence System. Each section is an implementation step with code changes and verification steps.

**Reference Plan**: `.cursor/plans/catalogue-persistence-sqlite-improvements-d7f8e4a2.plan.md`

---

## Backend Contract: `_storage` Metadata

The backend guarantees that all persistable catalogue entities include `_storage` metadata. For nested content (like cuisines), the `_storage` is at the **subsection/entity level**, not per-item.

### Entity-Level `_storage` Schema (Nested Format)

For nested content like cuisines, each subsection is an entity with `_storage` at that level:

```json
{
  "California cuisine": {
    "qid": "Q12345",
    "markdown": "# California cuisine\n\nFresh and local.",
    "cards": [
      {"local_name": "Fish Tacos", "description": "Baja-style fish tacos"},
      {"local_name": "Avocado Toast", "description": "Classic California brunch"}
    ],
    "_storage": {
      "entity_id": "cuisine:Q12345",
      "scope": "locality",
      "ttl_hours": 168
    }
  },
  "American cuisine": {
    "qid": "Q67890",
    "markdown": "# American cuisine\n\nNational dishes.",
    "cards": [
      {"local_name": "Hamburger", "description": "Classic American burger"}
    ],
    "_storage": {
      "entity_id": "cuisine:Q67890",
      "scope": "country",
      "ttl_hours": 168
    }
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `entity_id` | string | Yes | Unique identifier for the entity (format: `{section}:{qid}`) |
| `scope` | string | Yes | Geographic scope: `country`, `adminarea`, `locality`, `sublocality`, `coordinate` |
| `ttl_hours` | number | No | Time-to-live in hours (defaults to 168 = 7 days) |

### Item-Level `_storage` Schema (Flat Format)

For flat content with individual items, each item can have its own `_storage`:

```json
{
  "content": {
    "items": [
      {
        "local_name": "Chinese Cuisine",
        "description": "Traditional Chinese food",
        "_storage": {
          "entity_id": "cuisine:chinese_cuisine",
          "scope": "country",
          "ttl_hours": 168
        }
      }
    ]
  }
}
```

### Content Formats Supported

The iOS persistence layer handles both formats:

1. **Nested format** (cuisines): `_storage` at subsection level, each cuisine is one entity
2. **Flat format** (items): `_storage` on each item in the array

---

## Step 1: Extend JSONValue with Manipulation Methods

**Goal**: Add pure utility methods to `JSONValue` that the persistence layer and `CatalogueManager` can share.

### Files to Modify

- `core/Sources/core/jsonUtil.swift`

### Code Changes

Add the following extension to `JSONValue`:

```swift
// MARK: - JSONValue Manipulation Extension
public extension JSONValue {
    
    /// Deep merge two JSONValue dictionaries (new values override existing)
    func merged(with new: JSONValue) -> JSONValue {
        guard case .dictionary(var existing) = self,
              case .dictionary(let newDict) = new else {
            return new
        }
        for (key, value) in newDict {
            if let existingValue = existing[key] {
                existing[key] = existingValue.merged(with: value)
            } else {
                existing[key] = value
            }
        }
        return .dictionary(existing)
    }
    
    /// Get value at a dot-separated path (e.g., "cards.items")
    func value(atPath path: String) -> JSONValue? {
        let components = path.split(separator: ".").map(String.init)
        return value(atPathComponents: components)
    }
    
    /// Get value at path components
    func value(atPathComponents components: [String]) -> JSONValue? {
        guard !components.isEmpty else { return self }
        guard case .dictionary(let dict) = self,
              let first = components.first,
              let value = dict[first] else {
            return nil
        }
        if components.count == 1 {
            return value
        }
        return value.value(atPathComponents: Array(components.dropFirst()))
    }
    
    /// Modify value at a path, returning a new JSONValue
    func modifying(atPath path: String?, transform: (JSONValue) -> JSONValue) -> JSONValue {
        guard let path = path, !path.isEmpty else {
            return transform(self)
        }
        let components = path.split(separator: ".").map(String.init)
        return modifying(atPathComponents: components, transform: transform)
    }
    
    /// Modify value at path components
    func modifying(atPathComponents components: [String], transform: (JSONValue) -> JSONValue) -> JSONValue {
        guard !components.isEmpty else {
            return transform(self)
        }
        guard case .dictionary(var dict) = self else {
            return self
        }
        let first = components.first!
        if components.count == 1 {
            let existing = dict[first] ?? .null
            dict[first] = transform(existing)
        } else {
            let existing = dict[first] ?? .dictionary([:])
            dict[first] = existing.modifying(atPathComponents: Array(components.dropFirst()), transform: transform)
        }
        return .dictionary(dict)
    }
    
    /// Append items to an array value
    func appending(_ items: JSONValue) -> JSONValue {
        guard case .array(var existing) = self else {
            if case .array(let newItems) = items {
                return items
            }
            return .array([items])
        }
        if case .array(let newItems) = items {
            existing.append(contentsOf: newItems)
        } else {
            existing.append(items)
        }
        return .array(existing)
    }
    
    /// Remove items from an array matching criteria
    func removing(matching match: JSONValue?) -> JSONValue {
        guard case .array(let existing) = self else { return self }
        guard let match = match, case .dictionary(let matchDict) = match else {
            return self
        }
        let filtered = existing.filter { item in
            guard case .dictionary(let itemDict) = item else { return true }
            for (key, matchValue) in matchDict {
                guard let itemValue = itemDict[key] else { return true }
                if !itemValue.equals(matchValue) { return true }
            }
            return false
        }
        return .array(filtered)
    }
    
    /// Check equality with another JSONValue
    func equals(_ other: JSONValue) -> Bool {
        switch (self, other) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.array(let a), .array(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.equals($1) }
        case (.dictionary(let a), .dictionary(let b)):
            guard a.keys.sorted() == b.keys.sorted() else { return false }
            return a.keys.allSatisfy { a[$0]?.equals(b[$0] ?? .null) ?? false }
        default: return false
        }
    }
}
```

### Tests to Add

Create or extend `core/Tests/coreTests/jsonUtilTests.swift`:

```swift
@Test("JSONValue merge: deep merge dictionaries")
func jsonValueMerge() throws {
    let base = JSONValue.dictionary([
        "a": .string("original"),
        "nested": .dictionary(["x": .int(1), "y": .int(2)])
    ])
    let updates = JSONValue.dictionary([
        "a": .string("updated"),
        "nested": .dictionary(["y": .int(99), "z": .int(3)])
    ])
    let merged = base.merged(with: updates)
    
    guard case .dictionary(let dict) = merged else {
        Issue.record("Expected dictionary")
        return
    }
    expect(dict["a"]?.stringValue == "updated")
    guard case .dictionary(let nested) = dict["nested"] else {
        Issue.record("Expected nested dictionary")
        return
    }
    expect(nested["x"]?.doubleValue == 1)
    expect(nested["y"]?.doubleValue == 99)
    expect(nested["z"]?.doubleValue == 3)
}

@Test("JSONValue path: get and modify at path")
func jsonValuePath() throws {
    let json = JSONValue.dictionary([
        "level1": .dictionary([
            "level2": .dictionary([
                "value": .string("deep")
            ])
        ])
    ])
    
    let value = json.value(atPath: "level1.level2.value")
    expect(value?.stringValue == "deep")
    
    let modified = json.modifying(atPath: "level1.level2.value") { _ in
        .string("modified")
    }
    expect(modified.value(atPath: "level1.level2.value")?.stringValue == "modified")
}

@Test("JSONValue append: append to array")
func jsonValueAppend() throws {
    let arr = JSONValue.array([.int(1), .int(2)])
    let appended = arr.appending(.array([.int(3), .int(4)]))
    
    guard case .array(let items) = appended else {
        Issue.record("Expected array")
        return
    }
    expect(items.count == 4)
}
```

### How to Test Success

1. Run: `swift test --filter jsonUtil` in the `core` directory
2. All new tests should pass
3. Existing `jsonUtilTests` should continue passing

---

## Step 2: Create Catalogue Models in Core

**Goal**: Move `CatalogueSection` and `CatalogueAction` from `CatalogueManager.swift` to core for reusability and testability.

### Files to Create

- `core/Sources/core/catalogueModels.swift`

### Code to Write

```swift
//
//  catalogueModels.swift
//  core
//
//  Shared catalogue data models for persistence and UI layers.
//

import Foundation

// MARK: - Catalogue Action

/// Actions that can be performed on catalogue sections
public enum CatalogueAction: String, Sendable, Codable {
    case replace
    case edit
}

// MARK: - Section Metadata (Single Source of Truth)

/// Shared metadata for section types - eliminates duplication between
/// CatalogueSection (UI model) and SectionIndex (storage + lazy placeholder)
public struct SectionMetadata: Codable, Sendable, Equatable {
    public let section: String
    public let displayTitle: String
    public let config: JSONValue?
    
    public init(
        section: String,
        displayTitle: String,
        config: JSONValue? = nil
    ) {
        self.section = section
        self.displayTitle = displayTitle
        self.config = config
    }
}

// MARK: - Catalogue Section

/// Represents a single catalogue section with dynamic content (UI model)
public struct CatalogueSection: Identifiable, Sendable, Codable {
    public let id: String
    public let metadata: SectionMetadata
    public let content: JSONValue
    
    // Convenience accessors
    public var section: String { metadata.section }
    public var displayTitle: String { metadata.displayTitle }
    public var config: JSONValue? { metadata.config }
    
    public init(
        id: String = UUID().uuidString,
        metadata: SectionMetadata,
        content: JSONValue
    ) {
        self.id = id
        self.metadata = metadata
        self.content = content
    }
    
    /// Convenience initializer with inline metadata
    public init(
        id: String = UUID().uuidString,
        section: String,
        displayTitle: String,
        config: JSONValue? = nil,
        content: JSONValue
    ) {
        self.id = id
        self.metadata = SectionMetadata(section: section, displayTitle: displayTitle, config: config)
        self.content = content
    }
    
    /// Create a copy with updated content
    public func withContent(_ newContent: JSONValue) -> CatalogueSection {
        CatalogueSection(id: id, metadata: metadata, content: newContent)
    }
    
    /// Create a copy with updated config
    public func withConfig(_ newConfig: JSONValue?) -> CatalogueSection {
        CatalogueSection(
            id: id,
            metadata: SectionMetadata(section: section, displayTitle: displayTitle, config: newConfig),
            content: content
        )
    }
}
```

### Files to Modify

- `unheardpath/views/CatalogueManager.swift` - Remove `CatalogueSection` and `CatalogueAction` definitions, add `import core`

Remove these lines from `CatalogueManager.swift`:

```swift
// DELETE: CatalogueAction enum (around line 7-10)
// DELETE: CatalogueSection struct (around line 15-28)
```

Add at top of file:

```swift
import core  // Add if not present - for SectionMetadata, CatalogueSection, CatalogueAction, JSONValue
```

### Tests to Add

Create `core/Tests/coreTests/catalogueModelsTests.swift`:

```swift
import Testing
import Foundation
@testable import core

@Suite("CatalogueModels tests")
struct CatalogueModelsTests {
    
    @Test("CatalogueSection: create and modify")
    func catalogueSectionBasic() throws {
        let section = CatalogueSection(
            section: "cuisine",
            displayTitle: "Regional Cuisine",
            config: .dictionary(["render_type": .string("dish")]),
            content: .dictionary(["cards": .array([])])
        )
        
        expect(section.section == "cuisine")
        expect(section.displayTitle == "Regional Cuisine")
        
        let updated = section.withContent(.dictionary(["cards": .array([.string("item1")])]))
        expect(updated.id == section.id)
        expect(updated.section == "cuisine")
    }
    
    @Test("CatalogueSection: Codable roundtrip")
    func catalogueSectionCodable() throws {
        let section = CatalogueSection(
            section: "heritage",
            displayTitle: "Heritage Sites",
            content: .dictionary(["sites": .array([.string("Yu Garden")])])
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(section)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CatalogueSection.self, from: data)
        
        expect(decoded.section == section.section)
        expect(decoded.displayTitle == section.displayTitle)
    }
    
    @Test("CatalogueAction: Codable roundtrip")
    func catalogueActionCodable() throws {
        let action = CatalogueAction.edit
        let encoder = JSONEncoder()
        let data = try encoder.encode(action)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CatalogueAction.self, from: data)
        
        expect(decoded == .edit)
    }
    
    @Test("SectionMetadata: shared across section types")
    func sectionMetadataShared() throws {
        let metadata = SectionMetadata(
            section: "cuisine",
            displayTitle: "Regional Cuisine",
            config: .dictionary(["render_type": .string("dish")])
        )
        
        // CatalogueSection uses metadata
        let catalogueSection = CatalogueSection(
            metadata: metadata,
            content: .dictionary(["items": .array([])])
        )
        expect(catalogueSection.section == "cuisine")
        expect(catalogueSection.displayTitle == "Regional Cuisine")
        
        // SectionIndex uses same metadata
        let sectionIndex = SectionIndex(
            metadata: metadata,
            entityRefs: [EntityRef(entityId: "cuisine:test", order: 0)]
        )
        expect(sectionIndex.section == "cuisine")
        expect(sectionIndex.metadata == metadata)  // Same metadata instance
    }
}
```

### How to Test Success

1. Run: `swift test --filter catalogueModels` in the `core` directory
2. All tests pass
3. Build the main app to ensure `CatalogueManager` compiles with imported models

---

## Step 3: Create Catalogue Content Manipulator in Core

**Goal**: Extract pure content manipulation logic from `CatalogueManager` into a testable core utility.

### Files to Create

- `core/Sources/core/catalogueContentManipulator.swift`

### Code to Write

```swift
//
//  catalogueContentManipulator.swift
//  core
//
//  Pure content manipulation utilities for catalogue sections.
//  These are stateless functions that operate on JSONValue.
//

import Foundation

// MARK: - Catalogue Content Manipulator

/// Pure utility functions for manipulating catalogue content
public enum CatalogueContentManipulator {
    
    /// Apply an edit operation to existing content
    /// - Parameters:
    ///   - existing: The existing section content
    ///   - new: The new content to apply
    ///   - config: Edit configuration with operation type and target path
    /// - Returns: The modified content
    public static func applyEdit(
        existing: JSONValue,
        new: JSONValue,
        config: JSONValue?
    ) -> JSONValue {
        let operation = config?["operation"]?.stringValue ?? "merge"
        let targetPath = config?["target_path"]?.stringValue
        
        switch operation {
        case "append":
            return appendContent(existing: existing, new: new, path: targetPath)
        case "remove":
            let match = config?["match"]
            return removeContent(existing: existing, path: targetPath, match: match)
        default: // "merge"
            return mergeContent(existing: existing, new: new)
        }
    }
    
    /// Deep merge two JSONValue dictionaries
    public static func mergeContent(existing: JSONValue, new: JSONValue) -> JSONValue {
        return existing.merged(with: new)
    }
    
    /// Append items to an array at the specified path
    public static func appendContent(existing: JSONValue, new: JSONValue, path: String?) -> JSONValue {
        return existing.modifying(atPath: path) { current in
            current.appending(new)
        }
    }
    
    /// Remove items from an array at the specified path
    public static func removeContent(existing: JSONValue, path: String?, match: JSONValue?) -> JSONValue {
        return existing.modifying(atPath: path) { current in
            current.removing(matching: match)
        }
    }
}
```

### Files to Modify

- `unheardpath/views/CatalogueManager.swift` - Replace inline manipulation methods with calls to `CatalogueContentManipulator`

In `CatalogueManager.editCatalogue`, replace the manipulation calls:

```swift
// BEFORE:
existingSection.content = mergeContent(existing: existingSection.content, new: content)
// ... other cases

// AFTER:
let updatedContent = CatalogueContentManipulator.applyEdit(
    existing: existingSection.content,
    new: content,
    config: config
)
existingSection = existingSection.withContent(updatedContent)
```

Remove the private manipulation methods from `CatalogueManager`:
- `mergeContent(existing:new:)`
- `appendContent(existing:new:path:)`
- `removeContent(existing:path:match:)`
- `modifyAtPath(_:pathComponents:modifier:)`
- `getValueAtPath(_:pathComponents:)`

### Tests to Add

Create `core/Tests/coreTests/catalogueContentManipulatorTests.swift`:

```swift
import Testing
import Foundation
@testable import core

@Suite("CatalogueContentManipulator tests")
struct CatalogueContentManipulatorTests {
    
    @Test("merge: deep merge dictionaries")
    func mergeContent() throws {
        let existing = JSONValue.dictionary([
            "cards": .array([.string("card1")]),
            "meta": .dictionary(["count": .int(1)])
        ])
        let new = JSONValue.dictionary([
            "cards": .array([.string("card2")]),
            "meta": .dictionary(["updated": .bool(true)])
        ])
        
        let result = CatalogueContentManipulator.mergeContent(existing: existing, new: new)
        
        guard case .dictionary(let dict) = result,
              case .dictionary(let meta) = dict["meta"] else {
            Issue.record("Expected dictionary structure")
            return
        }
        expect(meta["count"]?.doubleValue == 1)
        expect(meta["updated"]?.boolValue == true)
    }
    
    @Test("append: append items at path")
    func appendContent() throws {
        let existing = JSONValue.dictionary([
            "items": .array([.int(1), .int(2)])
        ])
        let new = JSONValue.array([.int(3)])
        
        let result = CatalogueContentManipulator.appendContent(
            existing: existing,
            new: new,
            path: "items"
        )
        
        let items = result.value(atPath: "items")
        guard case .array(let arr) = items else {
            Issue.record("Expected array")
            return
        }
        expect(arr.count == 3)
    }
    
    @Test("remove: remove matching items")
    func removeContent() throws {
        let existing = JSONValue.dictionary([
            "items": .array([
                .dictionary(["id": .string("a"), "value": .int(1)]),
                .dictionary(["id": .string("b"), "value": .int(2)]),
                .dictionary(["id": .string("a"), "value": .int(3)])
            ])
        ])
        let match = JSONValue.dictionary(["id": .string("a")])
        
        let result = CatalogueContentManipulator.removeContent(
            existing: existing,
            path: "items",
            match: match
        )
        
        let items = result.value(atPath: "items")
        guard case .array(let arr) = items else {
            Issue.record("Expected array")
            return
        }
        expect(arr.count == 1)
    }
    
    @Test("applyEdit: merge operation (default)")
    func applyEditMerge() throws {
        let existing = JSONValue.dictionary(["a": .int(1)])
        let new = JSONValue.dictionary(["b": .int(2)])
        let config = JSONValue.dictionary(["operation": .string("merge")])
        
        let result = CatalogueContentManipulator.applyEdit(
            existing: existing,
            new: new,
            config: config
        )
        
        expect(result.value(atPath: "a")?.doubleValue == 1)
        expect(result.value(atPath: "b")?.doubleValue == 2)
    }
    
    @Test("applyEdit: append operation")
    func applyEditAppend() throws {
        let existing = JSONValue.dictionary(["list": .array([.int(1)])])
        let new = JSONValue.int(2)
        let config = JSONValue.dictionary([
            "operation": .string("append"),
            "target_path": .string("list")
        ])
        
        let result = CatalogueContentManipulator.applyEdit(
            existing: existing,
            new: new,
            config: config
        )
        
        let list = result.value(atPath: "list")
        guard case .array(let arr) = list else {
            Issue.record("Expected array")
            return
        }
        expect(arr.count == 2)
    }
}
```

### How to Test Success

1. Run: `swift test --filter catalogueContentManipulator` in the `core` directory
2. All tests pass
3. Build and test the main app to ensure `CatalogueManager` works correctly with delegated manipulation

---

## Step 4: Create DivisionLevel Enum and StorageKey Utilities

**Goal**: Create the hierarchical division level enum and unified storage key derivation utilities.

### Files to Create

- `core/Sources/core/cataloguePersistence.swift` (partial - this step creates the foundation)

### Code to Write

```swift
//
//  cataloguePersistence.swift
//  core
//
//  Catalogue persistence coordinator with hierarchical context management.
//

import Foundation

// MARK: - Division Level

/// Geographic division levels for catalogue context hierarchy
/// Ordered from most specific to least specific
public enum DivisionLevel: String, CaseIterable, Sendable, Codable {
    case coordinate
    case sublocality
    case locality
    case adminarea
    case country
    
    /// All levels from most specific to least specific
    public static var hierarchyOrder: [DivisionLevel] {
        [.coordinate, .sublocality, .locality, .adminarea, .country]
    }
    
    /// Levels that are less specific than or equal to this level
    public var lessSpecificLevels: [DivisionLevel] {
        guard let index = Self.hierarchyOrder.firstIndex(of: self) else { return [] }
        return Array(Self.hierarchyOrder[index...])
    }
}

// MARK: - Storage Key

/// Unified utility for deriving storage keys (entity IDs and context keys)
public enum StorageKey {
    
    // MARK: - Shared Normalization
    
    /// Normalize a string component for use in keys
    /// - Lowercase, trim whitespace, replace spaces with underscores, remove diacritics
    public static func normalize(_ component: String?) -> String? {
        guard let component = component, !component.isEmpty else { return nil }
        return component
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ",", with: "")
            .folding(options: .diacriticInsensitive, locale: .current)
    }
    
    // MARK: - Entity Keys
    
    /// Entity ID format reference: "{section}:{normalized_key_label}"
    /// Note: Entity IDs are now provided by the backend via _storage.entity_id
    /// This function documents the expected format and can be used for validation
    public static func entityId(section: String, keyLabel: String) -> String {
        let normalized = normalize(keyLabel) ?? "unknown"
        return "\(section):\(normalized)"
    }
    
    /// Extract section from entity ID
    public static func extractSection(from entityId: String) -> String? {
        guard let colonIndex = entityId.firstIndex(of: ":") else { return nil }
        return String(entityId[..<colonIndex])
    }
    
    // MARK: - Context Keys
    
    /// Derive context key from location data at a specific division level
    public static func geoDivisionKey(
        from location: LocationDetailData,
        level: DivisionLevel
    ) -> String? {
        let country = normalize(location.countryCode)
        let admin = normalize(location.adminArea)
        let locality = normalize(location.locality)
        let sublocality = normalize(location.sublocality)
        
        switch level {
        case .country:
            return country
            
        case .adminarea:
            guard let c = country, let a = admin else { return nil }
            return "\(c)_\(a)"
            
        case .locality:
            guard let c = country, let a = admin, let l = locality else { return nil }
            return "\(c)_\(a)_\(l)"
            
        case .sublocality:
            guard let c = country, let a = admin, let l = locality, let s = sublocality else { return nil }
            return "\(c)_\(a)_\(l)_\(s)"
            
        case .coordinate:
            guard let lat = location.latitude, let lon = location.longitude else { return nil }
            // Round to 4 decimal places (~11m precision)
            let roundedLat = (lat * 10000).rounded() / 10000
            let roundedLon = (lon * 10000).rounded() / 10000
            return "\(roundedLat)_\(roundedLon)"
        }
    }
    
    /// Determine the most specific level available from location data
    public static func mostSpecificLevel(from location: LocationDetailData) -> DivisionLevel {
        if location.latitude != nil && location.longitude != nil {
            return .coordinate
        }
        if location.sublocality != nil && !location.sublocality!.isEmpty {
            return .sublocality
        }
        if location.locality != nil && !location.locality!.isEmpty {
            return .locality
        }
        if location.adminArea != nil && !location.adminArea!.isEmpty {
            return .adminarea
        }
        return .country
    }
    
    /// Map scope string to DivisionLevel
    public static func levelFromScope(_ scope: String) -> DivisionLevel? {
        switch scope.lowercased() {
        case "global": return nil // Global entities don't have a specific level
        case "country": return .country
        case "adminarea": return .adminarea
        case "locality": return .locality
        case "sublocality": return .sublocality
        case "coordinate": return .coordinate
        default: return nil
        }
    }
}
```

### Tests to Add

Create `core/Tests/coreTests/cataloguePersistenceTests.swift`:

```swift
import Testing
import Foundation
@testable import core

@Suite("CataloguePersistence tests")
struct CataloguePersistenceTests {
    
    // MARK: - DivisionLevel Tests
    
    @Test("DivisionLevel: hierarchy order")
    func divisionLevelHierarchy() throws {
        let order = DivisionLevel.hierarchyOrder
        expect(order.first == .coordinate)
        expect(order.last == .country)
        expect(order.count == 5)
    }
    
    @Test("DivisionLevel: lessSpecificLevels")
    func divisionLevelLessSpecific() throws {
        let localityLevels = DivisionLevel.locality.lessSpecificLevels
        expect(localityLevels.count == 3)
        expect(localityLevels.contains(.locality))
        expect(localityLevels.contains(.adminarea))
        expect(localityLevels.contains(.country))
        expect(!localityLevels.contains(.coordinate))
    }
    
    // MARK: - StorageKey Tests (Normalization)
    
    @Test("StorageKey: normalize components")
    func normalizeComponents() throws {
        expect(StorageKey.normalize("Shanghai") == "shanghai")
        expect(StorageKey.normalize("New York") == "new_york")
        expect(StorageKey.normalize("São Paulo") == "sao_paulo")
        expect(StorageKey.normalize("") == nil)
        expect(StorageKey.normalize(nil) == nil)
    }
    
    // MARK: - StorageKey Tests (Context Keys)
    
    @Test("StorageKey: derive country context key")
    func deriveCountryKey() throws {
        let location = LocationDetailData(
            latitude: 31.2304,
            longitude: 121.4737,
            locality: "Shanghai",
            sublocality: "Pudong",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let key = StorageKey.geoDivisionKey(from: location, level: .country)
        expect(key == "cn")
    }
    
    @Test("StorageKey: derive locality context key")
    func deriveLocalityKey() throws {
        let location = LocationDetailData(
            latitude: 31.2304,
            longitude: 121.4737,
            locality: "Shanghai",
            sublocality: "Pudong",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let key = StorageKey.geoDivisionKey(from: location, level: .locality)
        expect(key == "cn_shanghai_shanghai")
    }
    
    @Test("StorageKey: derive coordinate context key")
    func deriveCoordinateKey() throws {
        let location = LocationDetailData(
            latitude: 31.23045678,
            longitude: 121.47371234,
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let key = StorageKey.geoDivisionKey(from: location, level: .coordinate)
        expect(key == "31.2305_121.4737")
    }
    
    @Test("StorageKey: mostSpecificLevel")
    func mostSpecificLevel() throws {
        let fullLocation = LocationDetailData(
            latitude: 31.2304,
            longitude: 121.4737,
            locality: "Shanghai",
            sublocality: "Pudong",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        expect(StorageKey.mostSpecificLevel(from: fullLocation) == .coordinate)
        
        let noCoordLocation = LocationDetailData(
            locality: "Shanghai",
            sublocality: "Pudong",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        expect(StorageKey.mostSpecificLevel(from: noCoordLocation) == .sublocality)
        
        let localityOnlyLocation = LocationDetailData(
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        expect(StorageKey.mostSpecificLevel(from: localityOnlyLocation) == .locality)
    }
    
    @Test("StorageKey: levelFromScope")
    func levelFromScope() throws {
        expect(StorageKey.levelFromScope("country") == .country)
        expect(StorageKey.levelFromScope("locality") == .locality)
        expect(StorageKey.levelFromScope("COUNTRY") == .country)
        expect(StorageKey.levelFromScope("global") == nil)
        expect(StorageKey.levelFromScope("invalid") == nil)
    }
    
    // MARK: - StorageKey Tests (Entity Keys)
    
    @Test("StorageKey: derive entity ID")
    func deriveEntityId() throws {
        let id1 = StorageKey.entityId(section: "cuisine", keyLabel: "Chinese Cuisine")
        expect(id1 == "cuisine:chinese_cuisine")
        
        let id2 = StorageKey.entityId(section: "heritage", keyLabel: "Yu Garden, Shanghai")
        expect(id2 == "heritage:yu_garden_shanghai")
    }
    
    @Test("StorageKey: extract section from entity ID")
    func extractSection() throws {
        expect(StorageKey.extractSection(from: "cuisine:chinese_cuisine") == "cuisine")
        expect(StorageKey.extractSection(from: "heritage:yu_garden") == "heritage")
        expect(StorageKey.extractSection(from: "invalid") == nil)
    }
}
```

### How to Test Success

1. Run: `swift test --filter CataloguePersistence` in the `core` directory
2. All derivation tests pass
3. Verify key formats match expected patterns

---

## Step 5: Create Entity Store

**Goal**: Implement the entity storage layer for normalized entity management.

### Files to Create

- `core/Sources/core/entityStore.swift`

### Code to Write

```swift
//
//  entityStore.swift
//  core
//
//  Entity storage for normalized catalogue items.
//

import Foundation

// MARK: - Stored Entity

/// Represents a persisted catalogue entity
public struct StoredEntity: Codable, Sendable {
    public let entityId: String
    public let displayName: String
    public let section: String
    public let scope: String
    public let content: JSONValue
    public let sourceLocation: SourceLocation
    public let createdAt: Date
    public let expiresAt: Date
    
    public struct SourceLocation: Codable, Sendable {
        public let countryCode: String?
        public let adminArea: String?
        public let locality: String?
        public let sublocality: String?
        
        public init(
            countryCode: String? = nil,
            adminArea: String? = nil,
            locality: String? = nil,
            sublocality: String? = nil
        ) {
            self.countryCode = countryCode
            self.adminArea = adminArea
            self.locality = locality
            self.sublocality = sublocality
        }
        
        public init(from location: LocationDetailData) {
            self.countryCode = location.countryCode
            self.adminArea = location.adminArea
            self.locality = location.locality
            self.sublocality = location.sublocality
        }
    }
    
    public init(
        entityId: String,
        displayName: String,
        section: String,
        scope: String,
        content: JSONValue,
        sourceLocation: SourceLocation,
        createdAt: Date = Date(),
        expiresAt: Date
    ) {
        self.entityId = entityId
        self.displayName = displayName
        self.section = section
        self.scope = scope
        self.content = content
        self.sourceLocation = sourceLocation
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
    
    public var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Entity Store

/// Manages entity file storage with scope-based reuse logic
public final class EntityStore: Sendable {
    
    private let baseDirectory: URL
    private let defaultTTLHours: Double
    
    /// Initialize with base directory for entity storage
    /// - Parameters:
    ///   - baseDirectory: Base URL for entities (e.g., AppSupport/catalogue/entities/)
    ///   - defaultTTLHours: Default time-to-live in hours (default: 168 = 7 days)
    public init(baseDirectory: URL, defaultTTLHours: Double = 168) {
        self.baseDirectory = baseDirectory
        self.defaultTTLHours = defaultTTLHours
    }
    
    // MARK: - File Path Helpers
    
    private func directoryURL(for section: String) -> URL {
        baseDirectory.appendingPathComponent(section)
    }
    
    private func fileURL(for entityId: String, section: String) -> URL {
        let filename = entityId
            .replacingOccurrences(of: ":", with: "_")
            .appending(".json")
        return directoryURL(for: section).appendingPathComponent(filename)
    }
    
    // MARK: - Read Operations
    
    /// Load an entity by ID
    public func get(_ entityId: String) -> StoredEntity? {
        guard let section = StorageKey.extractSection(from: entityId) else { return nil }
        let fileURL = fileURL(for: entityId, section: section)
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let entity = try? JSONDecoder().decode(StoredEntity.self, from: data) else {
            return nil
        }
        
        return entity
    }
    
    /// Check if an entity exists (regardless of expiration)
    public func exists(_ entityId: String) -> Bool {
        guard let section = StorageKey.extractSection(from: entityId) else { return false }
        let fileURL = fileURL(for: entityId, section: section)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Write Operations
    
    /// Save an entity to storage
    @discardableResult
    public func write(
        entityId: String,
        displayName: String,
        section: String,
        scope: String,
        content: JSONValue,
        sourceLocation: LocationDetailData,
        ttlHours: Double? = nil
    ) throws -> StoredEntity {
        let entity = StoredEntity(
            entityId: entityId,
            displayName: displayName,
            section: section,
            scope: scope,
            content: content,
            sourceLocation: StoredEntity.SourceLocation(from: sourceLocation),
            expiresAt: Date().addingTimeInterval((ttlHours ?? defaultTTLHours) * 3600)
        )
        
        let dirURL = directoryURL(for: section)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        let fileURL = fileURL(for: entityId, section: section)
        let data = try JSONEncoder().encode(entity)
        try data.write(to: fileURL)
        
        return entity
    }
    
    /// Delete an entity
    public func delete(_ entityId: String) throws {
        guard let section = StorageKey.extractSection(from: entityId) else { return }
        let fileURL = fileURL(for: entityId, section: section)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Reuse Logic
    
    /// Parse scope string to DivisionLevel
    /// Returns nil for "global" scope (applies everywhere)
    private func parseScope(_ scope: String) -> DivisionLevel? {
        let normalized = scope.lowercased()
        if normalized == "global" { return nil }
        return DivisionLevel(rawValue: normalized)
    }
    
    /// Check if existing entity can be reused for current location
    /// Returns true if entity is valid and can be reused, false if new save needed
    public func canReuseExisting(
        entityId: String,
        scope: String,
        currentLocation: LocationDetailData
    ) -> Bool {
        guard let existing = get(entityId), !existing.isExpired else {
            return false // No existing or expired, cannot reuse
        }
        
        // Parse scope - nil means global (always reusable)
        guard let level = parseScope(scope) else {
            return true // Global scope: always reusable
        }
        
        // Check if entity's source location matches current location at scope level
        switch level {
        case .country:
            let existingCountry = existing.sourceLocation.countryCode?.lowercased()
            let currentCountry = currentLocation.countryCode?.lowercased()
            return existingCountry == currentCountry
            
        case .adminarea:
            let existingAdmin = existing.sourceLocation.adminArea?.lowercased()
            let currentAdmin = currentLocation.adminArea?.lowercased()
            let existingCountry = existing.sourceLocation.countryCode?.lowercased()
            let currentCountry = currentLocation.countryCode?.lowercased()
            return existingAdmin == currentAdmin && existingCountry == currentCountry
            
        case .locality:
            let existingLocality = existing.sourceLocation.locality?.lowercased()
            let currentLocality = currentLocation.locality?.lowercased()
            return existingLocality == currentLocality
            
        case .sublocality:
            let existingSublocality = existing.sourceLocation.sublocality?.lowercased()
            let currentSublocality = currentLocation.sublocality?.lowercased()
            return existingSublocality == currentSublocality
            
        case .coordinate:
            // Coordinate-level entities are not reusable across different coordinates
            return false
        }
    }
    
    // MARK: - Maintenance
    
    /// Remove all expired entities
    public func pruneExpired() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        
        let sectionDirs = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        )
        
        for sectionDir in sectionDirs where sectionDir.hasDirectoryPath {
            let entityFiles = try fileManager.contentsOfDirectory(
                at: sectionDir,
                includingPropertiesForKeys: nil
            )
            
            for fileURL in entityFiles where fileURL.pathExtension == "json" {
                if let data = try? Data(contentsOf: fileURL),
                   let entity = try? JSONDecoder().decode(StoredEntity.self, from: data),
                   entity.isExpired {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
    }
    
    /// List all entity IDs for a section
    public func listEntities(section: String) -> [String] {
        let dirURL = directoryURL(for: section)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> String? in
                guard let data = try? Data(contentsOf: url),
                      let entity = try? JSONDecoder().decode(StoredEntity.self, from: data) else {
                    return nil
                }
                return entity.entityId
            }
    }
}
```

### Tests to Add

Create `core/Tests/coreTests/entityStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import core

@Suite("EntityStore tests")
struct EntityStoreTests {
    
    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("entityStoreTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    @Test("EntityStore: write and read entity")
    func writeAndRead() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = EntityStore(baseDirectory: tempDir)
        let location = LocationDetailData(
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let entityId = "cuisine:chinese_cuisine"
        let content = JSONValue.dictionary(["name": .string("Chinese Cuisine")])
        
        try store.write(
            entityId: entityId,
            displayName: "Chinese Cuisine",
            section: "cuisine",
            scope: "country",
            content: content,
            sourceLocation: location
        )
        
        expect(store.exists(entityId))
        
        let loaded = store.get(entityId)
        expect(loaded != nil)
        expect(loaded?.entityId == entityId)
        expect(loaded?.section == "cuisine")
        expect(loaded?.scope == "country")
    }
    
    @Test("EntityStore: canReuseExisting for global scope")
    func canReuseExistingGlobalScope() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = EntityStore(baseDirectory: tempDir)
        let shanghai = LocationDetailData(
            locality: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let entityId = "general:travel_tips"
        try store.write(
            entityId: entityId,
            displayName: "Travel Tips",
            section: "general",
            scope: "global",
            content: .dictionary([:]),
            sourceLocation: shanghai
        )
        
        // Global scope - can reuse even for different location
        let tokyo = LocationDetailData(
            locality: "Tokyo",
            countryCode: "JP",
            countryName: "Japan"
        )
        expect(store.canReuseExisting(entityId: entityId, scope: "global", currentLocation: tokyo) == true)
    }
    
    @Test("EntityStore: canReuseExisting for country scope")
    func canReuseExistingCountryScope() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = EntityStore(baseDirectory: tempDir)
        let shanghai = LocationDetailData(
            locality: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let entityId = "cuisine:chinese_cuisine"
        try store.write(
            entityId: entityId,
            displayName: "Chinese Cuisine",
            section: "cuisine",
            scope: "country",
            content: .dictionary([:]),
            sourceLocation: shanghai
        )
        
        // Same country, different city - can reuse
        let guangzhou = LocationDetailData(
            locality: "Guangzhou",
            countryCode: "CN",
            countryName: "China"
        )
        expect(store.canReuseExisting(entityId: entityId, scope: "country", currentLocation: guangzhou) == true)
        
        // Different country - cannot reuse
        let tokyo = LocationDetailData(
            locality: "Tokyo",
            countryCode: "JP",
            countryName: "Japan"
        )
        expect(store.canReuseExisting(entityId: entityId, scope: "country", currentLocation: tokyo) == false)
    }
    
    @Test("EntityStore: canReuseExisting for locality scope")
    func canReuseExistingLocalityScope() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = EntityStore(baseDirectory: tempDir)
        let shanghai = LocationDetailData(
            locality: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let entityId = "cuisine:shanghai_cuisine"
        try store.write(
            entityId: entityId,
            displayName: "Shanghai Cuisine",
            section: "cuisine",
            scope: "locality",
            content: .dictionary([:]),
            sourceLocation: shanghai
        )
        
        // Same locality - can reuse
        expect(store.canReuseExisting(entityId: entityId, scope: "locality", currentLocation: shanghai) == true)
        
        // Different locality - cannot reuse
        let guangzhou = LocationDetailData(
            locality: "Guangzhou",
            countryCode: "CN",
            countryName: "China"
        )
        expect(store.canReuseExisting(entityId: entityId, scope: "locality", currentLocation: guangzhou) == false)
    }
    
    @Test("EntityStore: delete entity")
    func deleteEntity() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = EntityStore(baseDirectory: tempDir)
        let location = LocationDetailData(countryCode: "CN", countryName: "China")
        
        let entityId = "cuisine:test"
        try store.write(
            entityId: entityId,
            displayName: "Test",
            section: "cuisine",
            scope: "country",
            content: .dictionary([:]),
            sourceLocation: location
        )
        
        expect(store.exists(entityId))
        try store.delete(entityId)
        expect(store.exists(entityId) == false)
    }
    
    @Test("EntityStore: list entities for section")
    func listEntities() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = EntityStore(baseDirectory: tempDir)
        let location = LocationDetailData(countryCode: "CN", countryName: "China")
        
        try store.write(entityId: "cuisine:a", displayName: "A", section: "cuisine", scope: "country", content: .dictionary([:]), sourceLocation: location)
        try store.write(entityId: "cuisine:b", displayName: "B", section: "cuisine", scope: "country", content: .dictionary([:]), sourceLocation: location)
        try store.write(entityId: "heritage:c", displayName: "C", section: "heritage", scope: "country", content: .dictionary([:]), sourceLocation: location)
        
        let cuisineEntities = store.listEntities(section: "cuisine")
        expect(cuisineEntities.count == 2)
        expect(cuisineEntities.contains("cuisine:a"))
        expect(cuisineEntities.contains("cuisine:b"))
        
        let heritageEntities = store.listEntities(section: "heritage")
        expect(heritageEntities.count == 1)
    }
}
```

### How to Test Success

1. Run: `swift test --filter EntityStore` in the `core` directory
2. All entity storage tests pass
3. Verify file structure is created correctly in temp directory during tests

---

## Step 6: Create Context Store

**Goal**: Implement the context storage layer for location-specific section indices.

### Files to Create

- `core/Sources/core/contextStore.swift`

### Code to Write

```swift
//
//  contextStore.swift
//  core
//
//  Context storage for location-specific catalogue indices.
//

import Foundation

// MARK: - Entity Reference

/// Reference to an entity within a section
public struct EntityRef: Codable, Sendable, Equatable {
    public let entityId: String
    public let order: Int
    
    public init(entityId: String, order: Int) {
        self.entityId = entityId
        self.order = order
    }
}

// MARK: - Section Index

/// Index of a section within a context, with references to entities
/// Used for both storage and as lazy-loading placeholder (dual purpose)
public struct SectionIndex: Codable, Sendable, Identifiable {
    public let metadata: SectionMetadata
    public let entityRefs: [EntityRef]
    public let updatedAt: Date
    
    // Identifiable conformance - section name is unique within a context
    public var id: String { metadata.section }
    
    // Convenience accessors
    public var section: String { metadata.section }
    public var displayTitle: String { metadata.displayTitle }
    public var config: JSONValue? { metadata.config }
    public var entityCount: Int { entityRefs.count }
    
    public init(
        metadata: SectionMetadata,
        entityRefs: [EntityRef] = [],
        updatedAt: Date = Date()
    ) {
        self.metadata = metadata
        self.entityRefs = entityRefs
        self.updatedAt = updatedAt
    }
    
    /// Convenience initializer with inline metadata
    public init(
        section: String,
        displayTitle: String,
        config: JSONValue? = nil,
        entityRefs: [EntityRef] = [],
        updatedAt: Date = Date()
    ) {
        self.metadata = SectionMetadata(section: section, displayTitle: displayTitle, config: config)
        self.entityRefs = entityRefs
        self.updatedAt = updatedAt
    }
    
    /// Create copy with updated entity refs
    public func withEntityRefs(_ refs: [EntityRef]) -> SectionIndex {
        SectionIndex(metadata: metadata, entityRefs: refs, updatedAt: Date())
    }
    
    /// Create copy with added entity ref
    public func addingEntityRef(_ ref: EntityRef) -> SectionIndex {
        var newRefs = entityRefs
        // Check if entity already exists, update order if so
        if let existingIndex = newRefs.firstIndex(where: { $0.entityId == ref.entityId }) {
            newRefs[existingIndex] = ref
        } else {
            newRefs.append(ref)
        }
        return withEntityRefs(newRefs.sorted { $0.order < $1.order })
    }
}

// MARK: - Stored Context

/// Represents a persisted context (location-specific catalogue state)
public struct StoredContext: Codable, Sendable {
    public let geoDivisionKey: String
    public let level: DivisionLevel
    public let locationDetailData: LocationDetailData
    public let sections: [String: SectionIndex]
    public let sectionOrder: [String]
    public let createdAt: Date
    public let lastAccessed: Date
    
    public init(
        geoDivisionKey: String,
        level: DivisionLevel,
        locationDetailData: LocationDetailData,
        sections: [String: SectionIndex] = [:],
        sectionOrder: [String] = [],
        createdAt: Date = Date(),
        lastAccessed: Date = Date()
    ) {
        self.geoDivisionKey = geoDivisionKey
        self.level = level
        self.locationDetailData = locationDetailData
        self.sections = sections
        self.sectionOrder = sectionOrder
        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
    }
    
    /// Create copy with updated section
    public func withSection(_ sectionIndex: SectionIndex) -> StoredContext {
        var newSections = sections
        newSections[sectionIndex.section] = sectionIndex
        
        var newOrder = sectionOrder
        if !newOrder.contains(sectionIndex.section) {
            newOrder.append(sectionIndex.section)
        }
        
        return StoredContext(
            geoDivisionKey: geoDivisionKey,
            level: level,
            locationDetailData: locationDetailData,
            sections: newSections,
            sectionOrder: newOrder,
            createdAt: createdAt,
            lastAccessed: Date()
        )
    }
    
    /// Create copy with updated last accessed time
    public func touchingLastAccessed() -> StoredContext {
        StoredContext(
            geoDivisionKey: geoDivisionKey,
            level: level,
            locationDetailData: locationDetailData,
            sections: sections,
            sectionOrder: sectionOrder,
            createdAt: createdAt,
            lastAccessed: Date()
        )
    }
}

// MARK: - Context Store

/// Manages context file storage by division level
public final class ContextStore: Sendable {
    
    private let baseDirectory: URL
    
    /// Initialize with base directory for context storage
    /// - Parameter baseDirectory: Base URL for contexts (e.g., AppSupport/catalogue/contexts/)
    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }
    
    // MARK: - File Path Helpers
    
    private func directoryURL(for level: DivisionLevel) -> URL {
        baseDirectory.appendingPathComponent(level.rawValue)
    }
    
    private func fileURL(for key: String, level: DivisionLevel) -> URL {
        directoryURL(for: level).appendingPathComponent("\(key).json")
    }
    
    // MARK: - Read Operations
    
    /// Load a context by key and level
    public func load(key: String, level: DivisionLevel) -> StoredContext? {
        let fileURL = fileURL(for: key, level: level)
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let context = try? JSONDecoder().decode(StoredContext.self, from: data) else {
            return nil
        }
        
        return context
    }
    
    /// Check if a context exists
    public func exists(key: String, level: DivisionLevel) -> Bool {
        let fileURL = fileURL(for: key, level: level)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Write Operations
    
    /// Save a context to storage
    public func save(_ context: StoredContext) throws {
        let dirURL = directoryURL(for: context.level)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        let fileURL = fileURL(for: context.geoDivisionKey, level: context.level)
        let data = try JSONEncoder().encode(context)
        try data.write(to: fileURL)
    }
    
    /// Update a single section in a context (creates context if needed)
    public func updateSection(
        key: String,
        level: DivisionLevel,
        locationDetailData: LocationDetailData,
        sectionIndex: SectionIndex
    ) throws {
        let existing = load(key: key, level: level) ?? StoredContext(
            geoDivisionKey: key,
            level: level,
            locationDetailData: locationDetailData
        )
        
        let updated = existing.withSection(sectionIndex)
        try save(updated)
    }
    
    /// Delete a context
    public func delete(key: String, level: DivisionLevel) throws {
        let fileURL = fileURL(for: key, level: level)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Query Operations
    
    /// List all context keys for a level
    public func listContexts(level: DivisionLevel) -> [String] {
        let dirURL = directoryURL(for: level)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }
    
    /// Get all contexts for a location (at all applicable levels)
    public func getContextsForLocation(_ location: LocationDetailData) -> [StoredContext] {
        var contexts: [StoredContext] = []
        
        for level in DivisionLevel.hierarchyOrder {
            guard let key = StorageKey.geoDivisionKey(from: location, level: level),
                  let context = load(key: key, level: level) else {
                continue
            }
            contexts.append(context)
        }
        
        return contexts
    }
}
```

### Tests to Add

Create `core/Tests/coreTests/contextStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import core

@Suite("ContextStore tests")
struct ContextStoreTests {
    
    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("contextStoreTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    @Test("ContextStore: save and load context")
    func saveAndLoad() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = ContextStore(baseDirectory: tempDir)
        let location = LocationDetailData(
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let sectionIndex = SectionIndex(
            section: "cuisine",
            displayTitle: "Regional Cuisine",
            entityRefs: [
                EntityRef(entityId: "cuisine:chinese_cuisine", order: 0),
                EntityRef(entityId: "cuisine:shanghai_cuisine", order: 1)
            ]
        )
        
        let context = StoredContext(
            geoDivisionKey: "cn_shanghai_shanghai",
            level: .locality,
            locationDetailData: location,
            sections: ["cuisine": sectionIndex],
            sectionOrder: ["cuisine"]
        )
        
        try store.save(context)
        expect(store.exists(key: "cn_shanghai_shanghai", level: .locality))
        
        let loaded = store.load(key: "cn_shanghai_shanghai", level: .locality)
        expect(loaded != nil)
        expect(loaded?.geoDivisionKey == "cn_shanghai_shanghai")
        expect(loaded?.level == .locality)
        expect(loaded?.sections.count == 1)
        expect(loaded?.sectionOrder == ["cuisine"])
    }
    
    @Test("ContextStore: update section in existing context")
    func updateSection() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = ContextStore(baseDirectory: tempDir)
        let location = LocationDetailData(
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        // Create initial context with cuisine section
        let cuisineSection = SectionIndex(
            section: "cuisine",
            displayTitle: "Cuisine",
            entityRefs: [EntityRef(entityId: "cuisine:a", order: 0)]
        )
        
        try store.updateSection(
            key: "cn_shanghai_shanghai",
            level: .locality,
            locationDetailData: location,
            sectionIndex: cuisineSection
        )
        
        // Add heritage section
        let heritageSection = SectionIndex(
            section: "heritage",
            displayTitle: "Heritage",
            entityRefs: [EntityRef(entityId: "heritage:b", order: 0)]
        )
        
        try store.updateSection(
            key: "cn_shanghai_shanghai",
            level: .locality,
            locationDetailData: location,
            sectionIndex: heritageSection
        )
        
        let loaded = store.load(key: "cn_shanghai_shanghai", level: .locality)
        expect(loaded?.sections.count == 2)
        expect(loaded?.sections["cuisine"] != nil)
        expect(loaded?.sections["heritage"] != nil)
        expect(loaded?.sectionOrder.count == 2)
    }
    
    @Test("ContextStore: list contexts for level")
    func listContexts() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = ContextStore(baseDirectory: tempDir)
        let location = LocationDetailData(countryCode: "CN", countryName: "China")
        
        let context1 = StoredContext(geoDivisionKey: "cn", level: .country, locationDetailData: location)
        let context2 = StoredContext(geoDivisionKey: "jp", level: .country, locationDetailData: location)
        
        try store.save(context1)
        try store.save(context2)
        
        let keys = store.listContexts(level: .country)
        expect(keys.count == 2)
        expect(keys.contains("cn"))
        expect(keys.contains("jp"))
    }
    
    @Test("ContextStore: delete context")
    func deleteContext() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let store = ContextStore(baseDirectory: tempDir)
        let location = LocationDetailData(countryCode: "CN", countryName: "China")
        
        let context = StoredContext(geoDivisionKey: "cn", level: .country, locationDetailData: location)
        try store.save(context)
        
        expect(store.exists(key: "cn", level: .country))
        try store.delete(key: "cn", level: .country)
        expect(store.exists(key: "cn", level: .country) == false)
    }
    
    @Test("SectionIndex: add entity ref")
    func sectionIndexAddEntityRef() throws {
        let section = SectionIndex(
            section: "cuisine",
            displayTitle: "Cuisine",
            entityRefs: [EntityRef(entityId: "a", order: 0)]
        )
        
        let updated = section.addingEntityRef(EntityRef(entityId: "b", order: 1))
        expect(updated.entityRefs.count == 2)
        
        // Adding duplicate should update, not add
        let updated2 = updated.addingEntityRef(EntityRef(entityId: "a", order: 2))
        expect(updated2.entityRefs.count == 2)
        expect(updated2.entityRefs.first { $0.entityId == "a" }?.order == 2)
    }
    
    @Test("StoredContext: with section")
    func storedContextWithSection() throws {
        let location = LocationDetailData(countryCode: "CN", countryName: "China")
        let context = StoredContext(geoDivisionKey: "cn", level: .country, locationDetailData: location)
        
        let section = SectionIndex(section: "cuisine", displayTitle: "Cuisine")
        let updated = context.withSection(section)
        
        expect(updated.sections.count == 1)
        expect(updated.sectionOrder == ["cuisine"])
        
        let section2 = SectionIndex(section: "heritage", displayTitle: "Heritage")
        let updated2 = updated.withSection(section2)
        
        expect(updated2.sections.count == 2)
        expect(updated2.sectionOrder == ["cuisine", "heritage"])
    }
}
```

### How to Test Success

1. Run: `swift test --filter ContextStore` in the `core` directory
2. All context storage tests pass
3. Verify hierarchical directory structure is created correctly

---

## Step 7: Create Catalogue Persistence Coordinator

**Goal**: Implement the main coordinator that orchestrates entity and context stores.

### Files to Modify

- `core/Sources/core/cataloguePersistence.swift` (extend the file created in Step 4)

### Code to Add

Add the following to `cataloguePersistence.swift`:

```swift
// MARK: - Catalogue Persistence

/// Main coordinator for catalogue persistence
/// Orchestrates EntityStore and ContextStore to save and restore catalogue data
public final class CataloguePersistence: Sendable {
    
    private let entityStore: EntityStore
    private let contextStore: ContextStore
    private let activeLocationKey = "active_location_key"
    
    /// Initialize with base directory for all catalogue storage
    /// - Parameter baseDirectory: Base URL (e.g., AppSupport/catalogue/)
    public init(baseDirectory: URL) {
        self.entityStore = EntityStore(
            baseDirectory: baseDirectory.appendingPathComponent("entities")
        )
        self.contextStore = ContextStore(
            baseDirectory: baseDirectory.appendingPathComponent("contexts")
        )
    }
    
    /// Convenience initializer using Storage.appSupportURL
    public convenience init() {
        let baseURL = Storage.appSupportURL.appendingPathComponent("catalogue")
        self.init(baseDirectory: baseURL)
    }
    
    // MARK: - Active Location
    
    /// Save active location key to UserDefaults
    public func saveActiveLocation(_ location: LocationDetailData) {
        let level = StorageKey.mostSpecificLevel(from: location)
        guard let key = StorageKey.geoDivisionKey(from: location, level: level) else {
            return
        }
        let combined = "\(level.rawValue):\(key)"
        Storage.saveToUserDefaults(combined, forKey: activeLocationKey)
    }
    
    /// Load active location key from UserDefaults
    /// Returns tuple of (level, geoDivisionKey) or nil
    public func loadActiveLocationKey() -> (level: DivisionLevel, key: String)? {
        guard let combined: String = Storage.loadFromUserDefaults(forKey: activeLocationKey, as: String.self),
              let colonIndex = combined.firstIndex(of: ":") else {
            return nil
        }
        let levelString = String(combined[..<colonIndex])
        let key = String(combined[combined.index(after: colonIndex)...])
        
        guard let level = DivisionLevel(rawValue: levelString) else { return nil }
        return (level, key)
    }
    
    // MARK: - Persist Catalogue Content
    
    /// Persist a catalogue section with its content
    /// Extracts entities from content using _storage metadata, saves them, and updates context index
    public func persist(
        location: LocationDetailData,
        section: String,
        displayTitle: String,
        config: JSONValue?,
        content: JSONValue
    ) throws {
        let contextLevel = StorageKey.mostSpecificLevel(from: location)
        guard let geoDivisionKey = StorageKey.geoDivisionKey(from: location, level: contextLevel) else {
            return
        }
        
        var entityRefs: [EntityRef] = []
        var entityOrder = 0
        
        // Extract items array from content (backend standardizes on "items" key)
        let items: [JSONValue]
        if case .dictionary(let dict) = content,
           case .array(let arr) = dict["items"] {
            items = arr
        } else {
            items = []
        }
        
        for item in items {
            guard case .dictionary(let itemDict) = item else { continue }
            
            // Extract _storage metadata (guaranteed by backend contract)
            guard let storage = itemDict["_storage"],
                  case .dictionary(let storageDict) = storage,
                  let entityId = storageDict["entity_id"]?.stringValue,
                  let scope = storageDict["scope"]?.stringValue else {
                continue
            }
            
            // Get optional TTL from _storage
            let ttlHours = storageDict["ttl_hours"]?.doubleValue
            
            // Extract display name for entity metadata
            let displayName = itemDict["local_name"]?.stringValue
                ?? itemDict["title"]?.stringValue
                ?? itemDict["name"]?.stringValue
                ?? entityId
            
            // Skip saving if existing entity can be reused
            if !entityStore.canReuseExisting(entityId: entityId, scope: scope, currentLocation: location) {
                // Remove _storage from content before saving
                var cleanContent = itemDict
                cleanContent.removeValue(forKey: "_storage")
                
                try entityStore.write(
                    entityId: entityId,
                    displayName: displayName,
                    section: section,
                    scope: scope,
                    content: .dictionary(cleanContent),
                    sourceLocation: location,
                    ttlHours: ttlHours
                )
            }
            
            entityRefs.append(EntityRef(entityId: entityId, displayName: displayName, order: entityOrder))
            entityOrder += 1
        }
        
        // Create section index with entity references
        let sectionIndex = SectionIndex(
            section: section,
            displayTitle: displayTitle,
            config: config,
            entityRefs: entityRefs
        )
        
        // Update context store
        try contextStore.updateSection(
            key: geoDivisionKey,
            level: contextLevel,
            locationDetailData: location,
            sectionIndex: sectionIndex
        )
        
        // Save active location
        saveActiveLocation(location)
    }
    
    // MARK: - Restore Catalogue (Lazy Loading)
    
    /// Restore section indices only (fast, no entity file I/O)
    /// Use this for initial UI rendering - section headers visible immediately
    /// SectionIndex serves as both storage model and lazy-loading placeholder
    public func restoreSectionMetadata(location: LocationDetailData) -> [SectionIndex] {
        let contexts = contextStore.getContextsForLocation(location)
        guard let primaryContext = contexts.first else { return [] }
        
        return primaryContext.sectionOrder.compactMap { primaryContext.sections[$0] }
    }
    
    /// Load entity content for a specific section (call when section scrolls into view)
    /// Returns fully populated CatalogueSection or nil if entities expired/missing
    public func loadSectionContent(
        section: String,
        location: LocationDetailData
    ) -> CatalogueSection? {
        let contextLevel = StorageKey.mostSpecificLevel(from: location)
        guard let geoDivisionKey = StorageKey.geoDivisionKey(from: location, level: contextLevel),
              let context = contextStore.load(key: geoDivisionKey, level: contextLevel),
              let sectionIndex = context.sections[section] else {
            return nil
        }
        
        return composeSection(from: sectionIndex)
    }
    
    /// Restore from active location - metadata only (fast)
    public func restoreSectionMetadataFromActiveLocation() -> [SectionIndex]? {
        guard let (level, key) = loadActiveLocationKey(),
              let context = contextStore.load(key: key, level: level) else {
            return nil
        }
        
        return restoreSectionMetadata(location: context.locationDetailData)
    }
    
    /// Get the stored location for active context
    public func getActiveLocation() -> LocationDetailData? {
        guard let (level, key) = loadActiveLocationKey(),
              let context = contextStore.load(key: key, level: level) else {
            return nil
        }
        return context.locationDetailData
    }
    
    // MARK: - Compose Section (Internal)
    
    /// Resolve entity references to full content and compose a CatalogueSection
    /// This performs file I/O - use loadSectionContent() for lazy loading
    private func composeSection(from sectionIndex: SectionIndex) -> CatalogueSection? {
        var items: [JSONValue] = []
        
        for ref in sectionIndex.entityRefs.sorted(by: { $0.order < $1.order }) {
            if let entity = entityStore.get(ref.entityId), !entity.isExpired {
                items.append(entity.content)
            }
        }
        
        // Return nil if no valid entities (all expired or missing)
        guard !items.isEmpty else { return nil }
        
        return CatalogueSection(
            metadata: sectionIndex.metadata,
            content: .dictionary(["items": .array(items)])
        )
    }
    
    // MARK: - Cache Check
    
    /// Check if a location has cached context
    public func hasCachedContext(for location: LocationDetailData) -> Bool {
        let level = StorageKey.mostSpecificLevel(from: location)
        guard let key = StorageKey.geoDivisionKey(from: location, level: level) else {
            return false
        }
        return contextStore.exists(key: key, level: level)
    }
    
    // MARK: - Maintenance
    
    /// Prune expired entities
    public func pruneExpired() throws {
        try entityStore.pruneExpired()
    }
}
```

### Tests to Add

Add to `core/Tests/coreTests/cataloguePersistenceTests.swift`:

```swift
@Suite("CataloguePersistence Integration tests")
struct CataloguePersistenceIntegrationTests {
    
    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cataloguePersistenceIntTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    @Test("CataloguePersistence: persist and restore section")
    func persistAndRestore() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        // Configure Storage to use temp directory
        Storage.configure(appSupportURL: tempDir)
        
        let persistence = CataloguePersistence(baseDirectory: tempDir.appendingPathComponent("catalogue"))
        
        let location = LocationDetailData(
            latitude: 31.2304,
            longitude: 121.4737,
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        // Content with _storage metadata (guaranteed by backend contract)
        let content = JSONValue.dictionary([
            "items": .array([
                .dictionary([
                    "local_name": .string("Chinese Cuisine"),
                    "description": .string("Traditional Chinese food"),
                    "_storage": .dictionary([
                        "entity_id": .string("cuisine:chinese_cuisine"),
                        "scope": .string("country")
                    ])
                ]),
                .dictionary([
                    "local_name": .string("Shanghai Cuisine"),
                    "description": .string("Local Shanghai dishes"),
                    "_storage": .dictionary([
                        "entity_id": .string("cuisine:shanghai_cuisine"),
                        "scope": .string("locality")
                    ])
                ])
            ])
        ])
        
        try persistence.persist(
            location: location,
            section: "cuisine",
            displayTitle: "Regional Cuisine",
            config: .dictionary(["render_type": .string("dish")]),
            content: content
        )
        
        let restored = persistence.restore(location: location)
        expect(restored.count == 1)
        expect(restored.first?.section == "cuisine")
        expect(restored.first?.displayTitle == "Regional Cuisine")
    }
    
    @Test("CataloguePersistence: active location save and restore")
    func activeLocation() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        // Use unique prefix for this test
        let prefix = "test.\(UUID().uuidString)."
        Storage.configure(userDefaults: .standard, keyPrefix: prefix, appSupportURL: tempDir)
        
        let persistence = CataloguePersistence(baseDirectory: tempDir.appendingPathComponent("catalogue"))
        
        let location = LocationDetailData(
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        persistence.saveActiveLocation(location)
        
        let loaded = persistence.loadActiveLocationKey()
        expect(loaded != nil)
        expect(loaded?.level == .locality)
        expect(loaded?.key == "cn_shanghai_shanghai")
    }
    
    @Test("CataloguePersistence: has cached context")
    func hasCachedContext() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let persistence = CataloguePersistence(baseDirectory: tempDir.appendingPathComponent("catalogue"))
        
        let location = LocationDetailData(
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        expect(persistence.hasCachedContext(for: location) == false)
        
        try persistence.persist(
            location: location,
            section: "overview",
            displayTitle: "Overview",
            config: nil,
            content: .dictionary([:])
        )
        
        expect(persistence.hasCachedContext(for: location) == true)
    }
    
    @Test("CataloguePersistence: entity deduplication across locations")
    func entityDeduplication() throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }
        
        let persistence = CataloguePersistence(baseDirectory: tempDir.appendingPathComponent("catalogue"))
        
        let shanghai = LocationDetailData(
            locality: "Shanghai",
            adminArea: "Shanghai",
            countryCode: "CN",
            countryName: "China"
        )
        
        let guangzhou = LocationDetailData(
            locality: "Guangzhou",
            adminArea: "Guangdong",
            countryCode: "CN",
            countryName: "China"
        )
        
        // Persist for Shanghai - Chinese Cuisine is country-scoped
        let shanghaiContent = JSONValue.dictionary([
            "items": .array([
                .dictionary([
                    "local_name": .string("Chinese Cuisine"),
                    "_storage": .dictionary([
                        "entity_id": .string("cuisine:chinese_cuisine"),
                        "scope": .string("country")
                    ])
                ])
            ])
        ])
        
        try persistence.persist(
            location: shanghai,
            section: "cuisine",
            displayTitle: "Cuisine",
            config: nil,
            content: shanghaiContent
        )
        
        // Persist for Guangzhou (should reuse Chinese Cuisine entity since same country)
        let guangzhouContent = JSONValue.dictionary([
            "items": .array([
                .dictionary([
                    "local_name": .string("Chinese Cuisine"),
                    "_storage": .dictionary([
                        "entity_id": .string("cuisine:chinese_cuisine"),
                        "scope": .string("country")
                    ])
                ]),
                .dictionary([
                    "local_name": .string("Cantonese Cuisine"),
                    "_storage": .dictionary([
                        "entity_id": .string("cuisine:cantonese_cuisine"),
                        "scope": .string("locality")
                    ])
                ])
            ])
        ])
        
        try persistence.persist(
            location: guangzhou,
            section: "cuisine",
            displayTitle: "Cuisine",
            config: nil,
            content: guangzhouContent
        )
        
        // Both should restore properly
        let restoredShanghai = persistence.restore(location: shanghai)
        let restoredGuangzhou = persistence.restore(location: guangzhou)
        
        expect(restoredShanghai.count == 1)
        expect(restoredGuangzhou.count == 1)
    }
}
```

### How to Test Success

1. Run: `swift test --filter CataloguePersistence` in the `core` directory
2. All integration tests pass
3. Verify entity deduplication works across different locations

---

## Step 8: Integrate Persistence into CatalogueManager

**Goal**: Connect `CatalogueManager` to the persistence layer.

### Files to Modify

- `unheardpath/views/CatalogueManager.swift`

### Code Changes

1. Add property for persistence:

```swift
@MainActor
class CatalogueManager: ObservableObject {
    // ... existing properties ...
    
    /// Persistence coordinator for saving/restoring catalogue data
    private var persistence: CataloguePersistence?
    
    /// Initialize with optional persistence
    init(persistence: CataloguePersistence? = nil) {
        self.persistence = persistence
    }
    
    /// Set persistence coordinator
    func setPersistence(_ persistence: CataloguePersistence) {
        self.persistence = persistence
    }
```

2. Modify `handleCatalogue` to persist:

```swift
func handleCatalogue(
    section: String,
    displayTitle: String,
    action: CatalogueAction,
    config: JSONValue?,
    content: JSONValue
) {
    switch action {
    case .replace:
        replaceCatalogue(section: section, displayTitle: displayTitle, config: config, content: content)
    case .edit:
        editCatalogue(section: section, config: config, content: content)
    }
    
    // Persist after handling
    persistCurrentSection(section: section)
}

private func persistCurrentSection(section: String) {
    guard let persistence = persistence,
          let location = locationDetailData,
          let sectionData = sections[section] else {
        return
    }
    
    Task {
        do {
            try persistence.persist(
                location: location,
                section: sectionData.section,
                displayTitle: sectionData.displayTitle,
                config: sectionData.config,
                content: sectionData.content
            )
        } catch {
            Logger.shared.error("Failed to persist section \(section): \(error)")
        }
    }
}
```

3. Add lazy restore methods:

```swift
/// Section loading state for lazy loading UI
/// SectionIndex serves as placeholder (has metadata + entity count)
enum SectionLoadingState {
    case placeholder(SectionIndex)
    case loading
    case loaded(CatalogueSection)
    case failed
}

/// Published state for UI binding
@Published var sectionStates: [String: SectionLoadingState] = [:]

/// Restore section metadata only (fast, no entity I/O)
/// Call this on app launch - section headers appear immediately
func restoreSectionMetadata(for location: LocationDetailData? = nil) {
    guard let persistence = persistence else { return }
    
    let sectionIndices: [SectionIndex]
    if let location = location {
        sectionIndices = persistence.restoreSectionMetadata(location: location)
    } else {
        sectionIndices = persistence.restoreSectionMetadataFromActiveLocation() ?? []
    }
    
    // Populate section order and placeholder states
    for sectionIndex in sectionIndices {
        sectionStates[sectionIndex.section] = .placeholder(sectionIndex)
        if !sectionOrder.contains(sectionIndex.section) {
            sectionOrder.append(sectionIndex.section)
        }
    }
    
    // Restore location if not provided
    if location == nil, locationDetailData == nil {
        locationDetailData = persistence.getActiveLocation()
    }
}

/// Load section content when section scrolls into view
/// Call this from SwiftUI .onAppear or visibility detection
func loadSectionContent(section: String) {
    guard let persistence = persistence,
          let location = locationDetailData else { return }
    
    // Skip if already loaded or loading
    if case .loaded = sectionStates[section] { return }
    if case .loading = sectionStates[section] { return }
    
    sectionStates[section] = .loading
    
    Task {
        if let fullSection = persistence.loadSectionContent(section: section, location: location) {
            await MainActor.run {
                sections[section] = fullSection
                sectionStates[section] = .loaded(fullSection)
            }
        } else {
            await MainActor.run {
                sectionStates[section] = .failed
            }
        }
    }
}

/// Check if we have cached data for a location
func hasCachedData(for location: LocationDetailData) -> Bool {
    persistence?.hasCachedContext(for: location) ?? false
}
```

4. SwiftUI View usage for lazy loading:

```swift
struct CatalogueSectionView: View {
    let sectionKey: String
    @EnvironmentObject var catalogueManager: CatalogueManager
    
    var body: some View {
        Group {
            switch catalogueManager.sectionStates[sectionKey] {
            case .placeholder(let lazy):
                // Section header visible immediately
                VStack(alignment: .leading) {
                    Text(lazy.displayTitle)
                        .font(.headline)
                    ProgressView()
                        .frame(height: 100)
                }
                .onAppear {
                    // Load content when section scrolls into view
                    catalogueManager.loadSectionContent(section: sectionKey)
                }
                
            case .loading:
                VStack(alignment: .leading) {
                    Text(catalogueManager.sections[sectionKey]?.displayTitle ?? sectionKey)
                        .font(.headline)
                    ProgressView()
                        .frame(height: 100)
                }
                
            case .loaded(let section):
                // Full section content
                CatalogueContentView(section: section)
                
            case .failed, .none:
                EmptyView()
            }
        }
    }
}
```

### How to Test Success

1. Build the app successfully
2. Launch app, trigger catalogue events
3. Force quit app and relaunch
4. Verify section headers appear immediately (no loading delay)
5. Scroll to a section and verify content loads with brief loading indicator
6. Check Application Support folder has expected file structure:
   - `catalogue/entities/{section}/*.json`
   - `catalogue/contexts/{level}/*.json`

---

## Step 9: Initialize Persistence on App Launch

**Goal**: Wire up persistence initialization in the app entry point.

### Files to Modify

- `unheardpath/unheardpathApp.swift`

### Code Changes

1. Create persistence instance:

```swift
@main
struct UnheardPathApp: App {
    // ... existing properties ...
    
    /// Catalogue persistence coordinator
    private let cataloguePersistence = CataloguePersistence()
    
    init() {
        // ... existing init code ...
        
        // Initialize catalogue manager with persistence
        catalogueManager.setPersistence(cataloguePersistence)
        
        // Restore section metadata only (fast, no entity file I/O)
        // Section headers appear immediately, content loads lazily on scroll
        catalogueManager.restoreSectionMetadata()
    }
```

2. If using dependency injection / environment:

```swift
// If CatalogueManager is passed via environment, ensure persistence is set
.environmentObject(catalogueManager)
```

### How to Test Success

1. Build and run app
2. Navigate to trigger catalogue data loading
3. Check console for any persistence errors
4. Force quit app
5. Relaunch app
6. Verify catalogue data appears without network request
7. Use Finder to verify files in `~/Library/Application Support/unheardpath/catalogue/`

---

## Step 10: Add Cache Check in Location Switching Flow

**Goal**: Optimize location switching by checking cache before backend request.

### Files to Modify

- `unheardpath/views/MainView+LocationHandling.swift`

### Code Changes

In the location switch handler, add cache check with lazy loading:

```swift
func handleLocationSwitch(to location: LocationDetailData) {
    // Check if we have cached data
    if catalogueManager.hasCachedData(for: location) {
        // Restore section metadata from cache (fast, no entity I/O)
        // Section headers appear immediately, content loads lazily on scroll
        catalogueManager.restoreSectionMetadata(for: location)
        catalogueManager.setLocationData(location, isFromDeviceLocation: false)
        
        // Optionally still request fresh data in background
        // to update cache asynchronously
        Task {
            await requestFreshCatalogueData(for: location)
        }
        return
    }
    
    // No cache, request from backend
    requestCatalogueData(for: location)
}
```

### How to Test Success

1. Visit location A (data loads from backend)
2. Switch to location B (data loads from backend)
3. Switch back to location A:
   - Section headers appear immediately (from cache metadata)
   - Content loads as you scroll to each section
4. Monitor network tab to verify no request made for cached location
5. Check logs for "restored from cache" messages

---

## Design Simplifications (Backend Contract)

The following simplifications were made possible by the guaranteed `_storage` metadata contract with the backend:

| Removed Complexity | Reason | Impact |
|--------------------|--------|--------|
| Content array key guessing (`items`/`cards`/`data`) | Backend standardizes on `items` | Simpler content extraction |
| Key label fallback chain (`key_label`/`title`/`name`) | `_storage.entity_id` provided directly | No client-side entity ID generation |
| `contextContent` in `SectionIndex` | All persistable items have `_storage` | Simpler data model |
| `composeSection` fallback for empty entities | No non-entity content to handle | Cleaner restore logic |
| Unknown scope default case | Reuse `DivisionLevel` with `parseScope()` helper | Single source of truth for geographic levels |
| Duplicated `section`/`displayTitle`/`config` fields | `SectionMetadata` shared by section types | Single source of truth for section metadata |
| `LazyCatalogueSection` type | `SectionIndex` serves dual purpose (storage + placeholder) | Reduced type hierarchy from 3 to 2 |

### What iOS Expects from Backend

1. **`content.items`** - Always use `items` as the array key
2. **`_storage.entity_id`** - Pre-computed entity ID (format: `{section}:{normalized_key}`)
3. **`_storage.scope`** - Valid scope: `global`, `country`, `adminarea`, `locality`, `sublocality`, `coordinate`
4. **`_storage.ttl_hours`** - Optional TTL override (defaults to 168 hours)

### Entity ID Format

Entity IDs follow the pattern `{section}:{normalized_key}` where normalization means:
- Lowercase
- Spaces replaced with underscores
- Commas removed
- Diacritics removed

Example: `"Chinese Cuisine"` → `"cuisine:chinese_cuisine"`

---

## Performance: Lazy Loading Strategy

To avoid performance issues from reading many entity files on restore, the system uses **lazy loading**:

### Two-Phase Restore

| Phase | What Loads | File I/O | When |
|-------|------------|----------|------|
| **1. Metadata** | Section headers (title, config, entity count) | Context store only (1 file) | App launch |
| **2. Content** | Entity content for one section | Entity files for that section | Section scrolls into view |

### Data Flow

```
App Launch
    │
    ▼
restoreSectionMetadata()     ◄── Fast: reads context JSON only
    │
    ▼
UI shows section headers     ◄── Immediate: no waiting
with loading placeholders
    │
    ▼
User scrolls to section
    │
    ▼
loadSectionContent()         ◄── Reads entity files for that section only
    │
    ▼
Section content appears
```

### Benefits

- **Instant app launch** - Section headers visible immediately
- **Distributed I/O** - Entity reads spread across user scrolling
- **Memory efficient** - Only visible sections load content
- **Perceived performance** - Users see structure immediately

---

## Summary Checklist

| Step | Component | Key Files | Tests |
|------|-----------|-----------|-------|
| 1 | JSONValue Extensions | `jsonUtil.swift` | `jsonUtilTests.swift` |
| 2 | Catalogue Models | `catalogueModels.swift` | `catalogueModelsTests.swift` |
| 3 | Content Manipulator | `catalogueContentManipulator.swift` | `catalogueContentManipulatorTests.swift` |
| 4 | Key Derivation | `cataloguePersistence.swift` | `cataloguePersistenceTests.swift` |
| 5 | Entity Store | `entityStore.swift` | `entityStoreTests.swift` |
| 6 | Context Store | `contextStore.swift` | `contextStoreTests.swift` |
| 7 | Persistence Coordinator | `cataloguePersistence.swift` | Integration tests |
| 8 | CatalogueManager Integration | `CatalogueManager.swift` | Manual testing |
| 9 | App Launch | `unheardpathApp.swift` | Manual testing |
| 10 | Location Switch Cache | `MainView+LocationHandling.swift` | Manual testing |

---

## Running All Tests

```bash
cd 03_apps/iosapp/core
swift test
```

Or run specific test suites:

```bash
swift test --filter jsonUtil
swift test --filter catalogueModels
swift test --filter catalogueContentManipulator
swift test --filter CataloguePersistence
swift test --filter EntityStore
swift test --filter ContextStore
```
