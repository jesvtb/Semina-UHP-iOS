# Services Architecture Analysis Report

**Date**: January 30, 2026  
**Scope**: `03_apps/iosapp/unheardpath/services/`  
**Goal**: Analyze architecture for separation of concerns and opportunities to move logic to `core/` for easier testing and faster compilation

---

## Executive Summary

The current services architecture has **12 service classes** that mix multiple concerns:
- **UI state management** (ObservableObject, @Published)
- **Business logic** (authentication, location processing, event routing)
- **Network communication** (API clients, SSE processing)
- **Platform dependencies** (SwiftUI, Supabase, PostHog, CoreLocation)

**Key Findings**:
- ✅ **Good**: Core package already provides networking, storage, logging, JSON utilities
- ⚠️ **Issue**: Services are tightly coupled to SwiftUI and platform-specific dependencies
- ⚠️ **Issue**: Business logic is mixed with UI state management
- ⚠️ **Issue**: Heavy use of `@MainActor` and `ObservableObject` makes testing difficult
- ⚠️ **Issue**: All services compile together, slowing incremental builds

**Recommendation**: Extract **pure business logic** and **platform-agnostic utilities** to `core/`, leaving only **UI state management** in services.

---

## Current Services Inventory

### 1. **AuthManager** (185 lines)
**Responsibilities**:
- Authentication state management (`isAuthenticated`, `isLoading`, `userID`)
- Supabase session checking and validation
- PostHog user identification and event tracking
- UserManager coordination

**Dependencies**:
- `SwiftUI` (ObservableObject, @Published)
- `Supabase` (auth client)
- `PostHog` (analytics)
- `UserManager` (app-specific)

**Can Move to Core**:
- ❌ None (too tightly coupled to Supabase/PostHog)

**Can Extract**:
- ✅ Session validation logic (pure function)
- ✅ PostHog event tracking (separate service)

---

### 2. **APIClient.swift / UHPGateway** (267 lines)
**Responsibilities**:
- Wraps `core.APIClient` with UHP-specific response parsing
- Adds authentication headers from Supabase
- Handles UHP response envelope format
- Provides convenience methods for streaming

**Dependencies**:
- `core.APIClient` ✅
- `Supabase` (for auth tokens)
- `SwiftUI` (ObservableObject - but not really needed)

**Can Move to Core**:
- ✅ `UHPResponse` struct and parsing logic (pure data structures)
- ✅ `UHPError` enum (pure error types)
- ✅ Response envelope validation logic

**Can Extract**:
- ✅ Authentication header building (protocol-based, injectable)
- ✅ Base URL configuration (environment-based)

**Note**: `UHPGateway` doesn't need to be `ObservableObject` - it's stateless.

---

### 3. **AppLifecycleManager** (312 lines)
**Responsibilities**:
- App lifecycle state (`isAppInBackground`)
- Handler registration for background/foreground events
- Widget timeline reloading
- UserDefaults persistence (via Storage)

**Dependencies**:
- `SwiftUI` (ObservableObject, @Published)
- `UIKit` (NotificationCenter)
- `WidgetKit` (timeline reloading)
- `core.Storage` ✅
- `core.Logger` ✅

**Can Move to Core**:
- ✅ Handler registration pattern (protocol-based, platform-agnostic)
- ✅ Lifecycle event types (pure enums)
- ❌ Platform-specific (UIKit notifications, WidgetKit)

**Can Extract**:
- ✅ Lifecycle handler protocol (can be in core as protocol)
- ✅ Handler management logic (weak references, cleanup)

---

### 4. **LocationManager** (980 lines)
**Responsibilities**:
- CLLocationManager delegate handling
- Geocoding (forward and reverse)
- Geofencing management
- Location data construction (device/lookup locations)
- UserDefaults persistence (via Storage)

**Dependencies**:
- `CoreLocation` (platform-specific)
- `SwiftUI` (ObservableObject, @Published)
- `UIKit` (for app lifecycle)
- `WidgetKit` (for widget state)
- `core.Storage` ✅
- `core.JSONValue` ✅

**Can Move to Core**:
- ✅ Location data construction logic (`constructDeviceLocation`, `constructLookupLocation`, `constructNewLocation`)
- ✅ Geocoding result parsing and formatting
- ✅ Location validation utilities

**Can Extract**:
- ✅ Location data models (pure structs)
- ✅ Geocoding service protocol (for testability)

**Note**: This is the largest service and has the most extractable pure logic.

---

### 5. **SSEEventProcessor** (359 lines)
**Responsibilities**:
- Parsing SSE events from streams
- Routing events to handlers
- GeoJSON feature extraction
- Content type parsing

**Dependencies**:
- `core.SSEEvent` ✅
- `core.JSONValue` ✅
- `core.Logger` ✅
- `SwiftUI` (@MainActor protocol)

**Can Move to Core**:
- ✅ SSE event parsing logic (pure functions)
- ✅ GeoJSON feature extraction (`parseGeoJSONFeatures`, `extractFeaturesFromArray`)
- ✅ Event type routing logic (enum-based)
- ✅ Content parsing utilities

**Can Extract**:
- ✅ `SSEEventHandler` protocol (can be in core, but handlers are @MainActor)
- ✅ Event processor (pure logic, no UI dependencies)

**Note**: The protocol can be in core, but handler implementations need @MainActor.

---

### 6. **SSEEventRouter** (80 lines)
**Responsibilities**:
- Routes SSE events to appropriate managers
- Coordinates between ChatViewModel, ContentManager, MapFeaturesManager, ToastManager

**Dependencies**:
- `SwiftUI` (@MainActor, ObservableObject)
- Multiple app-specific managers

**Can Move to Core**:
- ❌ None (too tightly coupled to app-specific managers)

**Can Extract**:
- ✅ Router pattern (protocol-based routing)

---

### 7. **MapFeaturesManager** (28 lines)
**Responsibilities**:
- GeoJSON state management
- Update trigger for UI

**Dependencies**:
- `SwiftUI` (ObservableObject, @Published)
- `core.GeoJSON` ✅

**Can Move to Core**:
- ❌ None (pure UI state)

**Can Extract**:
- ✅ State management pattern (could be protocol-based)

---

### 8. **ToastManager** (37 lines)
**Responsibilities**:
- Toast notification state management

**Dependencies**:
- `SwiftUI` (ObservableObject, @Published)

**Can Move to Core**:
- ❌ None (pure UI state)

**Can Extract**:
- ✅ Toast data model (can be in core)

---

### 9. **GeoapifyGateway** (171 lines)
**Responsibilities**:
- Geoapify API client wrapper
- City search with parallel requests
- Response merging

**Dependencies**:
- `core.APIClient` ✅
- `SwiftUI` (ObservableObject - not needed)
- `core.Logger` ✅

**Can Move to Core**:
- ✅ Geoapify response parsing
- ✅ Search result merging logic
- ✅ Error types

**Can Extract**:
- ✅ Gateway protocol (for testability)
- ✅ API key configuration (environment-based)

**Note**: Doesn't need `ObservableObject` - it's stateless.

---

### 10. **AddrSearchManager** (387 lines)
**Responsibilities**:
- MKLocalSearchCompleter integration
- Geoapify search coordination
- Result interleaving and merging
- MapKit delegate handling

**Dependencies**:
- `MapKit` (platform-specific)
- `SwiftUI` (ObservableObject, @Published)
- `CoreLocation`
- `GeoapifyGateway`
- `core.Logger` ✅
- `core.GeoJSON` ✅

**Can Move to Core**:
- ✅ Result interleaving algorithm (`interleaveResults`)
- ✅ Subtitle building logic (`buildSubtitle`)
- ✅ Search result data models

**Can Extract**:
- ✅ Search service protocol (for testability)

---

### 11. **Supabase.swift** (151 lines)
**Responsibilities**:
- Supabase client initialization
- Configuration validation
- SSL/TLS setup

**Dependencies**:
- `Supabase` (external SDK)
- `Foundation`

**Can Move to Core**:
- ✅ Configuration validation logic
- ✅ URL validation utilities
- ❌ Client initialization (Supabase-specific)

**Can Extract**:
- ✅ Configuration model (pure struct)

---

### 12. **Mapbox.swift** (55 lines)
**Responsibilities**:
- Mapbox token initialization and validation

**Dependencies**:
- `Foundation`

**Can Move to Core**:
- ✅ Token validation logic
- ✅ Configuration model

---

## Architecture Issues

### 1. **Tight Coupling to SwiftUI**
**Problem**: All services are `@MainActor` and `ObservableObject`, making them:
- Hard to test in isolation
- Require SwiftUI test environment
- Cannot be used in background contexts
- Force compilation of SwiftUI even when only business logic is needed

**Impact**: 
- Slower compilation (SwiftUI is heavy)
- Difficult unit testing
- Cannot reuse logic in widgets/extensions

**Solution**: Extract pure business logic to `core/` without SwiftUI dependencies.

---

### 2. **Mixed Concerns**
**Problem**: Services combine:
- UI state (`@Published` properties)
- Business logic (parsing, validation, computation)
- Platform integration (Supabase, PostHog, CoreLocation)

**Example**: `AuthManager` mixes:
- State management (`isAuthenticated`, `isLoading`)
- Business logic (session validation)
- Analytics (PostHog tracking)
- External integration (Supabase)

**Impact**:
- Hard to test business logic in isolation
- Changes to one concern affect others
- Cannot reuse business logic elsewhere

**Solution**: Separate into:
- **State managers** (services) - UI state only
- **Business logic** (core) - pure functions/structs
- **Integration adapters** (services) - platform-specific wrappers

---

### 3. **Heavy Platform Dependencies**
**Problem**: Services directly depend on:
- `Supabase` (auth, database)
- `PostHog` (analytics)
- `CoreLocation` (location services)
- `MapKit` (map services)
- `UIKit` (app lifecycle)

**Impact**:
- Cannot test without mocking entire platforms
- Changes to external SDKs require service changes
- Hard to swap implementations (e.g., different analytics provider)

**Solution**: Use protocol-based abstractions:
- `AuthProvider` protocol (implemented by Supabase wrapper)
- `AnalyticsProvider` protocol (implemented by PostHog wrapper)
- `LocationProvider` protocol (implemented by CoreLocation wrapper)

---

### 4. **Compilation Performance**
**Problem**: All services compile together because they're in the same module:
- Changes to one service trigger recompilation of all
- SwiftUI dependencies force heavy compilation
- `@MainActor` isolation adds compilation overhead

**Impact**:
- Slow incremental builds
- Long clean build times
- Developer productivity loss

**Solution**: 
- Move pure logic to `core/` (separate module, faster compilation)
- Keep only UI state in services
- Use protocol-based dependencies (faster type checking)

---

### 5. **Testing Difficulties**
**Problem**: Services are hard to test because:
- Require `@MainActor` test environment
- Depend on SwiftUI `ObservableObject`
- Have side effects (network calls, UserDefaults, PostHog)
- Tightly coupled to external SDKs

**Impact**:
- Slow test execution
- Flaky tests (network, timing)
- Cannot test business logic in isolation

**Solution**:
- Extract pure functions to `core/` (easy to test)
- Use dependency injection (protocol-based)
- Separate state from logic (test logic without UI)

---

## Recommended Refactoring Plan

### Phase 1: Extract Pure Data Structures and Utilities

**Move to `core/`**:

1. **Location Data Models** (`core/Sources/core/location.swift`)
   - `DeviceLocationData` struct
   - `LookupLocationData` struct
   - `NewLocationData` struct
   - Location construction utilities (pure functions)

2. **SSE Event Parsing** (`core/Sources/core/sse.swift`)
   - `parseGeoJSONFeatures` function
   - `extractFeaturesFromArray` function
   - Event type enums
   - Content parsing utilities

3. **API Response Models** (`core/Sources/core/apiResponse.swift`)
   - `UHPResponse` struct
   - `UHPError` enum
   - Response validation utilities

4. **Configuration Models** (`core/Sources/core/config.swift`)
   - `SupabaseConfig` struct
   - `MapboxConfig` struct
   - `GeoapifyConfig` struct
   - Validation utilities

5. **Search Utilities** (`core/Sources/core/search.swift`)
   - `interleaveResults` function
   - `buildSubtitle` function
   - Search result data models

**Benefits**:
- ✅ Faster compilation (core compiles independently)
- ✅ Easier testing (pure functions)
- ✅ Reusable across app/widgets

---

### Phase 2: Extract Business Logic Protocols

**Create in `core/`**:

1. **Location Service Protocol** (`core/Sources/core/locationService.swift`)
   ```swift
   public protocol LocationService: Sendable {
       func constructDeviceLocation(location: CLLocation, placemark: CLPlacemark?) -> [String: JSONValue]
       func constructLookupLocation(location: CLLocation, placemark: CLPlacemark, mapItemName: String?) -> [String: JSONValue]
       func constructNewLocation(from location: CLLocation) async throws -> [String: JSONValue]
   }
   ```

2. **Auth Service Protocol** (`core/Sources/core/authService.swift`)
   ```swift
   public protocol AuthService: Sendable {
       func getAccessToken() async throws -> String
       func validateSession() async throws -> Bool
   }
   ```

3. **Analytics Service Protocol** (`core/Sources/core/analyticsService.swift`)
   ```swift
   public protocol AnalyticsService: Sendable {
       func identify(userId: String, properties: [String: Any]?)
       func capture(event: String, properties: [String: Any])
       func reset()
   }
   ```

**Benefits**:
- ✅ Testable (mock implementations)
- ✅ Swappable (different providers)
- ✅ No platform dependencies

---

### Phase 3: Refactor Services to Use Core

**Services become thin wrappers**:

1. **LocationManager** → Uses `LocationService` protocol
2. **AuthManager** → Uses `AuthService` protocol
3. **UHPGateway** → Uses `AuthService` for tokens
4. **SSEEventProcessor** → Uses core parsing utilities

**Benefits**:
- ✅ Services focus on UI state only
- ✅ Business logic tested in core
- ✅ Easier to maintain

---

## Specific Recommendations by Service

### High Priority (Easy Wins)

#### 1. **UHPGateway** → Extract Response Models
- Move `UHPResponse` and `UHPError` to `core/`
- Remove `ObservableObject` (not needed)
- Keep only state management in service

**Impact**: ⭐⭐⭐ (High - pure data structures, easy to test)

#### 2. **LocationManager** → Extract Location Construction
- Move `constructDeviceLocation`, `constructLookupLocation`, `constructNewLocation` to `core/`
- Create `LocationService` protocol
- Keep only CLLocationManager coordination in service

**Impact**: ⭐⭐⭐ (High - largest service, most extractable logic)

#### 3. **SSEEventProcessor** → Extract Parsing Logic
- Move `parseGeoJSONFeatures`, `extractFeaturesFromArray` to `core/`
- Move event type routing to core
- Keep only handler coordination in service

**Impact**: ⭐⭐⭐ (High - pure parsing logic, heavily used)

#### 4. **GeoapifyGateway** → Extract Response Parsing
- Move response merging logic to `core/`
- Remove `ObservableObject` (not needed)
- Create gateway protocol

**Impact**: ⭐⭐ (Medium - smaller service, but good pattern)

---

### Medium Priority (Architectural Improvements)

#### 5. **AuthManager** → Extract Analytics
- Create `AnalyticsService` protocol
- Move PostHog calls to separate service
- Keep only auth state in AuthManager

**Impact**: ⭐⭐ (Medium - improves testability, allows analytics swapping)

#### 6. **AppLifecycleManager** → Extract Handler Pattern
- Move handler protocol to `core/`
- Keep platform-specific (UIKit) in service
- Create lifecycle event types in core

**Impact**: ⭐⭐ (Medium - improves testability)

---

### Low Priority (Nice to Have)

#### 7. **AddrSearchManager** → Extract Search Utilities
- Move `interleaveResults`, `buildSubtitle` to `core/`
- Create search result models in core

**Impact**: ⭐ (Low - smaller impact, but good for consistency)

#### 8. **Supabase/Mapbox** → Extract Configuration
- Move config validation to `core/`
- Create config models in core

**Impact**: ⭐ (Low - small utilities, but improves consistency)

---

## Testing Improvements

### Current State
- Services require `@MainActor` test environment
- Must mock entire platforms (Supabase, PostHog, CoreLocation)
- Slow test execution
- Flaky tests due to side effects

### After Refactoring
- **Core logic**: Pure functions, easy to test
- **Protocols**: Mock implementations for testing
- **Services**: Test UI state only, inject dependencies

**Example**:
```swift
// Before: Hard to test
func testAuthManager() {
    // Must set up Supabase, PostHog, UserManager
    // Must use @MainActor
    // Slow, flaky
}

// After: Easy to test
func testSessionValidation() {
    // Pure function in core
    let isValid = SessionValidator.validate(session: mockSession)
    XCTAssertTrue(isValid)
}

func testAuthManager() {
    // Mock AuthService protocol
    let mockAuth = MockAuthService()
    let manager = AuthManager(authService: mockAuth)
    // Test UI state only
}
```

---

## Compilation Performance

### Current State
- All services in same module
- SwiftUI dependencies everywhere
- `@MainActor` isolation overhead
- Changes trigger full recompilation

### After Refactoring
- **Core module**: Compiles independently, faster
- **Services module**: Smaller, less SwiftUI
- **Protocols**: Faster type checking
- **Incremental builds**: Only changed modules recompile

**Estimated Improvement**:
- Core changes: ~30% faster (no SwiftUI)
- Service changes: ~20% faster (less code)
- Overall incremental builds: ~25% faster

---

## Migration Strategy

### Step 1: Create Core Extensions (Non-Breaking)
1. Add new files to `core/` with extracted logic
2. Keep existing services unchanged
3. Services can gradually adopt core utilities

### Step 2: Refactor Services (Gradual)
1. Update one service at a time
2. Use core utilities where possible
3. Keep services as thin wrappers

### Step 3: Extract Protocols (Breaking)
1. Create protocols in `core/`
2. Update services to use protocols
3. Add dependency injection

### Step 4: Remove Duplication
1. Remove duplicate logic from services
2. Use core utilities exclusively
3. Update tests to use core

---

## Risk Assessment

### Low Risk
- ✅ Extracting pure data structures
- ✅ Extracting pure functions
- ✅ Creating utility functions

### Medium Risk
- ⚠️ Extracting protocols (requires service refactoring)
- ⚠️ Removing `ObservableObject` (requires view updates)
- ⚠️ Dependency injection (requires app setup changes)

### High Risk
- ❌ Major service restructuring (requires comprehensive testing)
- ❌ Changing `@MainActor` boundaries (requires concurrency review)

---

## Success Metrics

### Compilation
- [ ] Core module compiles in < 5 seconds (currently ~10s for services)
- [ ] Incremental builds 25% faster
- [ ] Clean builds 20% faster

### Testing
- [ ] Core utilities have 80%+ test coverage
- [ ] Service tests run 50% faster (less mocking)
- [ ] No flaky tests due to platform dependencies

### Code Quality
- [ ] Services are < 200 lines each (currently some are 300+)
- [ ] Business logic is in core (not services)
- [ ] Protocols used for all external dependencies

---

## Conclusion

The current services architecture has **good separation** between app-specific and core logic, but there are **significant opportunities** to improve:

1. **Extract pure business logic** to `core/` (location construction, SSE parsing, response models)
2. **Create protocol-based abstractions** for external dependencies (auth, analytics, location)
3. **Simplify services** to focus on UI state management only
4. **Improve testability** by separating logic from state
5. **Speed up compilation** by reducing SwiftUI dependencies

**Recommended Starting Point**: Extract `UHPResponse`, location construction utilities, and SSE parsing logic to `core/`. These are the highest-impact, lowest-risk changes.

**Estimated Effort**: 
- Phase 1 (Pure utilities): 2-3 days
- Phase 2 (Protocols): 3-4 days  
- Phase 3 (Service refactoring): 5-7 days
- **Total**: ~2 weeks for full migration

**Priority**: High - improves maintainability, testability, and developer experience.
