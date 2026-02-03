# Core Package Migration Review

**Date:** January 30, 2026  
**Purpose:** Review and recommend which code should be moved from `unheardpath/` to the `core/` package vs what should remain app-specific.

## Executive Summary

This document provides a comprehensive analysis of code separation between the reusable `core` package and the app-specific `unheardpath` implementation. The goal is to identify generic, reusable utilities that can be shared across multiple apps while keeping app-specific business logic, UI components, and third-party integrations in the app layer.

---

## Current State

### Core Package (`core/`)
Currently contains:
- ✅ `logger.swift` - Logger protocol and NoOpLogger implementation
- ✅ `networking.swift` - APIClient, APIError, SSEEvent, SSE stream processing
- ✅ `jsonUtil.swift` - JSONValue type and conversion utilities
- ✅ `core.swift` - Empty placeholder file
- ✅ `testUtil.swift` - Test utilities

**Dependencies:** Foundation only (SwiftUI import in logger.swift should be removed)

### App Layer (`unheardpath/`)
Contains:
- Services (14 files)
- Schemas (3 files)
- Views (15+ files)
- Components (9 files)
- Core services (2 files in `unheardpath/core/services/`)

---

## Recommendations

### ✅ **MOVE TO CORE** - Generic Utilities

These are framework-agnostic utilities that can be reused across any iOS app.

#### 1. **StorageManager.swift** → `core/storage.swift`
**Rationale:** Generic storage utilities (UserDefaults, file operations) are reusable across apps.

**What to move:**
- ✅ All UserDefaults helper methods (with configurable key prefix)
- ✅ File storage methods (Documents, Caches, AppSupport, Temporary)
- ✅ Cache management utilities
- ✅ File size utilities
- ✅ Directory listing methods

**What to keep in app:**
- ❌ App Group suite name (`"group.com.semina.unheardpath"`) - make this configurable
- ❌ Debug helpers that print app-specific keys

**Changes needed:**
- Make App Group suite name a parameter (default to `UserDefaults.standard`)
- Remove app-specific key prefix logic (or make it configurable)
- Remove SwiftUI dependencies if any

**Dependencies:** Foundation only ✅

---

#### 2. **UserEvent.swift** → `core/events.swift`
**Rationale:** Generic event model structure that could be reused for analytics/event tracking.

**What to move:**
- ✅ `UserEvent` struct (generic event structure)
- ✅ `UserEventBuilder` enum (UTC/timezone generation utilities)

**What to keep in app:**
- ❌ App-specific event types (`"location_detected"`, `"chat_sent"`, etc.) - these are business logic

**Changes needed:**
- Keep event structure generic (evt_utc, evt_timezone, evt_type, evt_data, session_id)
- Event types remain app-specific

**Dependencies:** Foundation, core (JSONValue) ✅

---

#### 3. **GeoJSON Utilities** (from `GeoJson.swift`) → `core/geojson.swift`
**Rationale:** GeoJSON parsing and manipulation is a standard format, reusable across apps.

**What to move:**
- ✅ `GeoJSON` struct (FeatureCollection management)
- ✅ `PointFeature` struct (Point geometry validation and property extraction)
- ✅ `GeoJSON.extractFeatures()` static method
- ✅ Coordinate rounding utilities
- ✅ Coordinate extraction methods

**What to keep in app:**
- ❌ App-specific property accessors (e.g., `title` with device_lang priority) - move to app extension
- ❌ Mapbox-specific conversion (`toMapboxString()`) - move to app layer

**Changes needed:**
- Extract generic GeoJSON handling
- Create app-specific extensions for business logic
- Remove CoreLocation dependency if possible (use generic coordinate types)

**Dependencies:** Foundation, core (JSONValue) ✅

---

### ⚠️ **CONSIDER MOVING** - With Modifications

These could be moved but require refactoring to remove app-specific dependencies.

#### 4. **AppLifecycleManager Logger Implementation** → `core/logger.swift`
**Rationale:** The logger implementation in `AppLifecycleManager.swift` (DefaultAppLifecycleLogger) is more feature-rich than NoOpLogger.

**What to move:**
- ✅ `DefaultAppLifecycleLogger` class (in-memory log storage)
- ✅ `LogEntry` struct (already in core, but app has enhanced version)
- ✅ `AppLifecycleLogger` protocol (if different from core.Logger)

**What to keep in app:**
- ❌ `AppLifecycleManager` class (app lifecycle management)
- ❌ WidgetKit integration
- ❌ UserDefaults persistence for widget state

**Changes needed:**
- Merge `AppLifecycleLogger` protocol with `core.Logger` protocol
- Remove SwiftUI, UIKit, WidgetKit dependencies
- Make log storage size configurable
- Keep widget-specific code in app

**Dependencies:** Foundation only (remove SwiftUI, UIKit, WidgetKit) ⚠️

**Status:** ✅ **COMPLETED** - Logger implementation has been migrated to `core/logger.swift` as `InMemoryLogger`. The `AppLifecycleLogger` protocol has been merged with `core.Logger`, and `LogEntry`/`LogLevel` now use core types. All app code has been updated to use `core.Logger`. See `Logger_Usage.md` for usage documentation.

---

### ❌ **KEEP IN APP** - App-Specific Code

These contain business logic, UI dependencies, or third-party integrations specific to this app.

#### 1. **APIClient.swift** (UHPGateway)
**Status:** ✅ Already correctly structured
- Type aliases to `core.APIClient` - good
- `UHPGateway` class - app-specific backend integration
- `UHPResponse` - app-specific response envelope format
- Supabase auth integration

**Reason:** App-specific API gateway with business logic.

---

#### 2. **AppLifecycleManager.swift**
**Status:** ❌ Keep in app
- App lifecycle event handling
- WidgetKit integration
- UserDefaults persistence for widget
- SwiftUI/UIKit dependencies

**Reason:** Tightly coupled to app lifecycle and widget extensions.

---

#### 3. **SSEEventProcessor.swift** & **SSEEventRouter.swift**
**Status:** ❌ Keep in app
- App-specific event types (`toast`, `chat`, `map`, `hook`, `content`)
- Routes to app-specific managers (ChatViewModel, ContentManager, etc.)
- SwiftUI dependencies

**Reason:** Business logic for app-specific SSE event handling.

---

#### 4. **AuthManager.swift**
**Status:** ❌ Keep in app
- Supabase integration
- PostHog analytics integration
- App-specific authentication flow

**Reason:** Third-party service integration (Supabase, PostHog).

---

#### 5. **LocationManager.swift**
**Status:** ❌ Keep in app
- CoreLocation integration
- Geofencing (app-specific business logic)
- Geocoding with app-specific data structures
- SwiftUI/UIKit dependencies
- WidgetKit integration

**Reason:** App-specific location services with business logic.

---

#### 6. **TrackingManager.swift**
**Status:** ❌ Keep in app
- CoreLocation integration
- App-specific tracking strategies
- App lifecycle integration
- WidgetKit integration

**Reason:** App-specific location tracking implementation.

---

#### 7. **EventManager.swift**
**Status:** ❌ Keep in app
- App-specific event deduplication logic
- Session management (app-specific business rules)
- Location derivation from events
- UHPGateway integration

**Reason:** Business logic for app-specific event management.

---

#### 8. **ToastManager.swift**
**Status:** ❌ Keep in app
- SwiftUI ObservableObject
- UI-specific toast display logic

**Reason:** UI component, not a utility.

---

#### 9. **AddrSearchManager.swift**
**Status:** ❌ Keep in app
- MapKit integration
- Geoapify integration
- SwiftUI dependencies
- App-specific search result merging logic

**Reason:** App-specific search functionality with UI dependencies.

---

#### 10. **Supabase.swift** & **Mapbox.swift**
**Status:** ❌ Keep in app
- Third-party SDK initialization
- App-specific configuration

**Reason:** Third-party service configuration.

---

#### 11. **MapFeaturesManager.swift**
**Status:** ❌ Keep in app
- SwiftUI ObservableObject
- App-specific map state management

**Reason:** UI state management.

---

#### 12. **Schema.swift**
**Status:** ❌ Keep in app
- App-specific models (ChatMessage, ToastData, TabSelection, User, UserManager)
- SwiftUI dependencies

**Reason:** App-specific data models.

---

#### 13. **TrackingManager.swift** & **EventManager.swift** (in `unheardpath/core/services/`)
**Status:** ❌ Keep in app
- Already in app-specific location
- Business logic for tracking and events

**Reason:** App-specific business logic.

---

## Migration Priority

### Phase 1: High Priority (Low Risk, High Reusability)
1. ✅ **StorageManager** → `core/storage.swift`
   - High reusability
   - Low dependencies
   - Clear separation

2. ✅ **UserEvent** → `core/events.swift`
   - Generic structure
   - Already uses core.JSONValue
   - Minimal dependencies

### Phase 2: Medium Priority (Requires Refactoring)
3. ⚠️ **GeoJSON Utilities** → `core/geojson.swift`
   - Requires removing app-specific property accessors
   - May need CoreLocation abstraction

4. ⚠️ **Logger Implementation** → `core/logger.swift`
   - Requires removing SwiftUI/UIKit dependencies
   - Merge protocols

### Phase 3: Low Priority (Evaluate Need)
5. Consider if other apps will use these utilities before migrating

---

## Implementation Guidelines

### For Code Moving to Core:

1. **Remove App Dependencies:**
   - ❌ No SwiftUI imports
   - ❌ No UIKit imports (unless absolutely necessary)
   - ❌ No WidgetKit imports
   - ❌ No third-party SDK imports (Supabase, PostHog, MapKit, etc.)
   - ✅ Foundation only (or minimal system frameworks)

2. **Make Configuration Flexible:**
   - Use dependency injection for app-specific values
   - Provide sensible defaults
   - Use protocols for extensibility

3. **Keep Generic:**
   - Avoid app-specific business logic
   - Use generic types where possible
   - Provide extension points for app-specific behavior

4. **Maintain Backward Compatibility:**
   - Update app code to use new core APIs
   - Test thoroughly before removing old code

### For Code Staying in App:

1. **Use Core Types:**
   - Import and use `core` types (APIClient, JSONValue, Logger)
   - Extend core types with app-specific behavior

2. **Clear Separation:**
   - Keep business logic in app layer
   - Keep UI components in app layer
   - Keep third-party integrations in app layer

---

## Testing Strategy

### Before Migration:
1. ✅ Ensure all existing tests pass
2. ✅ Document current behavior
3. ✅ Identify test coverage gaps

### During Migration:
1. ✅ Create tests for core package utilities
2. ✅ Update app tests to use new core APIs
3. ✅ Run integration tests

### After Migration:
1. ✅ Verify app functionality unchanged
2. ✅ Verify core package can be used independently
3. ✅ Update documentation

---

## File Structure After Migration

### Core Package (`core/Sources/core/`)
```
core/
├── logger.swift          (existing + enhanced logger)
├── networking.swift      (existing)
├── jsonUtil.swift        (existing)
├── storage.swift         (NEW - from StorageManager)
├── events.swift          (NEW - from UserEvent)
├── geojson.swift         (NEW - from GeoJson)
└── testUtil.swift        (existing)
```

### App Layer (`unheardpath/`)
```
unheardpath/
├── services/
│   ├── APIClient.swift           (UHPGateway - keep)
│   ├── AppLifecycleManager.swift (keep)
│   ├── SSEEventProcessor.swift   (keep)
│   ├── SSEEventRouter.swift      (keep)
│   ├── AuthManager.swift          (keep)
│   ├── LocationManager.swift      (keep)
│   ├── TrackingManager.swift     (keep)
│   ├── EventManager.swift         (keep)
│   ├── ToastManager.swift         (keep)
│   ├── AddrSearchManager.swift   (keep)
│   ├── Supabase.swift             (keep)
│   ├── Mapbox.swift               (keep)
│   └── MapFeaturesManager.swift   (keep)
├── schemas/
│   ├── Schema.swift               (keep)
│   ├── GeoJson.swift              (keep - app-specific extensions)
│   └── UserEvent.swift            (REMOVE - moved to core)
└── core/services/
    ├── EventManager.swift         (keep)
    └── TrackingManager.swift      (keep)
```

---

## Dependencies Summary

### Core Package Dependencies (Target)
- ✅ Foundation
- ✅ core (internal)

### App Dependencies (Current)
- SwiftUI
- UIKit
- WidgetKit
- CoreLocation
- MapKit
- Supabase
- PostHog
- core (package)

---

## Notes

1. **Logger Protocol:** Consider merging `AppLifecycleLogger` with `core.Logger` to have a single protocol.

2. **StorageManager App Group:** The App Group suite name should be configurable, not hardcoded.

3. **GeoJSON CoreLocation:** Consider creating a generic coordinate type to avoid CoreLocation dependency in core package.

4. **Testing:** Ensure core package tests don't depend on app-specific code.

5. **Documentation:** Update README for core package with usage examples.

---

## Conclusion

The recommended migration focuses on **3-4 high-value utilities** that are:
- ✅ Framework-agnostic
- ✅ Highly reusable
- ✅ Low risk to migrate
- ✅ Clear separation of concerns

The majority of app code should remain in the app layer due to:
- Business logic dependencies
- UI framework dependencies
- Third-party service integrations
- App-specific functionality

This approach maintains a clean separation between reusable utilities (core) and app-specific implementation (app layer).
