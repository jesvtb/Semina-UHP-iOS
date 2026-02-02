# iOS App Project Organization Guide

## Overview

This document describes the project organization structure for the unheardpath iOS app. The structure follows a **hybrid approach** that combines feature-based organization with layer-based shared services, providing the best balance of maintainability, scalability, and clarity.

---

## Architecture Philosophy

### Hybrid Approach: Feature-Based + Layer-Based

Our project structure uses:
- **Feature-based organization** for user-facing features (Map, Chat, Profile, Journey, Auth)
- **Layer-based organization** for shared services and infrastructure (Core, UI, Navigation)

This hybrid approach provides:
- ✅ Clear feature boundaries for user-facing code
- ✅ Organized shared services that are easy to discover
- ✅ Scalability without premature optimization
- ✅ Better testability through clear separation of concerns
- ✅ Easier onboarding for new developers

---

## Directory Structure

```
unheardpath/
├── features/                    # Feature-based organization
│   ├── Map/
│   │   ├── MapView.swift
│   │   ├── MapViewModel.swift
│   │   ├── MapAnnotationViews.swift
│   │   └── MapFeaturesManager.swift
│   ├── Chat/
│   │   ├── ChatTab.swift
│   │   ├── ChatViewModel.swift
│   │   └── ChatInputBar.swift
│   ├── Journey/
│   │   ├── JourneyStart.swift
│   │   ├── ContentManager.swift
│   │   └── InfoSheetView.swift
│   ├── Profile/
│   │   └── ProfileTab.swift
│   └── Auth/
│       └── AuthView.swift
│
├── core/                        # Shared layer-based services
│   ├── services/
│   │   ├── TrackingManager.swift      # Location tracking only
│   │   ├── LocationManager.swift      # Geocoding, geofencing, lookup location
│   │   ├── AuthManager.swift
│   │   ├── APIClient.swift
│   │   ├── SSEEventProcessor.swift
│   │   ├── SSEEventRouter.swift
│   │   └── StorageManager.swift
│   ├── networking/
│   │   └── UHPGateway.swift
│   └── models/                 # Shared data models
│       ├── Schema.swift
│       ├── GeoJson.swift
│       └── UserEvent.swift
│
├── ui/                          # Shared UI layer
│   ├── components/             # Truly shared UI components
│   │   ├── Buttons.swift
│   │   ├── Toast.swift
│   │   └── Components.swift
│   └── design/                 # Design system
│       ├── Color.swift
│       ├── Spacing.swift
│       └── Typography.swift
│
├── navigation/                  # Navigation/routing
│   └── TabBarView.swift
│
├── shared/                      # Utilities and configuration
│   ├── config/
│   │   └── basemap_style.json
│   └── mock/                   # Mock data for testing
│       ├── around_me_example.json
│       └── custom_content_preview.json
│
├── identity/                    # Design system (legacy location, consider moving to ui/design)
│   ├── Color.swift
│   ├── Spacing.swift
│   └── Typography.swift
│
├── ContentView.swift            # Root content view
└── unheardpathApp.swift         # App entry point
```

---

## Directory Guidelines

### 1. Features Directory (`features/`)

**Purpose**: Self-contained feature modules that represent distinct user-facing functionality.

**Structure**:
- Each feature has its own folder
- Feature folders contain Views, ViewModels, and feature-specific logic
- Features should be as independent as possible

**What belongs here**:
- ✅ Feature-specific views (e.g., `MapView`, `ChatTab`)
- ✅ Feature-specific view models (e.g., `MapViewModel`, `ChatViewModel`)
- ✅ Feature-specific components used only within that feature
- ✅ Feature-specific state management

**What doesn't belong here**:
- ❌ Shared services (use `core/services/`)
- ❌ Shared UI components (use `ui/components/`)
- ❌ Navigation logic (use `navigation/`)
- ❌ Data models used by multiple features (use `core/models/`)

**Example - Map Feature**:
```
features/Map/
├── MapView.swift              # Main map view
├── MapViewModel.swift         # Map-specific state and logic
├── MapAnnotationViews.swift   # Map annotation UI components
└── MapFeaturesManager.swift  # Map-specific feature management
```

**Example - Chat Feature**:
```
features/Chat/
├── ChatTab.swift             # Main chat tab view
├── ChatViewModel.swift       # Chat state and message handling
└── ChatInputBar.swift        # Chat input component (only used in chat)
```

---

### 2. Core Directory (`core/`)

**Purpose**: Shared business logic, services, and infrastructure that support the entire app.

#### 2.1 Core Services (`core/services/`)

**What belongs here**:
- ✅ Services used by multiple features
- ✅ Business logic managers (e.g., `AuthManager`, `TrackingManager`)
- ✅ Data persistence services (e.g., `StorageManager`)
- ✅ Event processing services (e.g., `SSEEventProcessor`)

**Service Organization Principles**:
- **Single Responsibility**: Each service should have one clear purpose
- **Dependency Injection**: Services should accept dependencies via initializer
- **Protocol-Oriented**: Define protocols for services to enable testing

**Example Services**:
```
core/services/
├── TrackingManager.swift      # Location tracking (permissions, GPS updates)
├── LocationManager.swift      # Geocoding, geofencing, lookup location
├── AuthManager.swift          # Authentication and user session
├── APIClient.swift            # HTTP networking
└── StorageManager.swift       # UserDefaults persistence
```

#### 2.2 Core Networking (`core/networking/`)

**What belongs here**:
- ✅ API gateways and clients
- ✅ Network request builders
- ✅ API-specific error handling

**Example**:
```
core/networking/
└── UHPGateway.swift          # Backend API gateway
```

#### 2.3 Core Models (`core/models/`)

**What belongs here**:
- ✅ Data models used by multiple features
- ✅ Shared schemas and data structures
- ✅ API response models

**Example**:
```
core/models/
├── Schema.swift              # Shared data schemas
├── GeoJson.swift             # GeoJSON data structures
└── UserEvent.swift           # User event models
```

---

### 3. UI Directory (`ui/`)

**Purpose**: Shared UI components and design system.

#### 3.1 UI Components (`ui/components/`)

**What belongs here**:
- ✅ Reusable UI components used across multiple features
- ✅ Generic UI elements (buttons, toasts, etc.)

**What doesn't belong here**:
- ❌ Feature-specific components (belongs in `features/[Feature]/`)
- ❌ Components used in only one feature

**Example**:
```
ui/components/
├── Buttons.swift             # Reusable button styles
├── Toast.swift               # Toast notification component
└── Components.swift          # Other shared components
```

#### 3.2 UI Design System (`ui/design/`)

**What belongs here**:
- ✅ Design tokens (colors, spacing, typography)
- ✅ Design system utilities

**Note**: The `identity/` directory currently contains design system files. Consider migrating to `ui/design/` for consistency.

---

### 4. Navigation Directory (`navigation/`)

**Purpose**: App-wide navigation and routing logic.

**What belongs here**:
- ✅ Tab bar components
- ✅ Navigation coordinators (if using coordinator pattern)
- ✅ Deep linking handlers
- ✅ Route definitions

**Example**:
```
navigation/
├── TabBarView.swift          # Main tab bar
└── Routes.swift              # Route definitions (if needed)
```

---

### 5. Shared Directory (`shared/`)

**Purpose**: Utilities, configuration, and test data.

**What belongs here**:
- ✅ Configuration files
- ✅ Mock data for testing
- ✅ Utility functions used across the app

---

## File Naming Conventions

### Views
- Use descriptive names ending in `View`: `MapView.swift`, `ChatTab.swift`
- For feature-specific views, include feature context: `MapAnnotationViews.swift`

### ViewModels
- Use descriptive names ending in `ViewModel`: `MapViewModel.swift`, `ChatViewModel.swift`

### Services
- Use descriptive names ending in `Manager` or `Service`: `TrackingManager.swift`, `AuthManager.swift`
- For gateways/clients: `UHPGateway.swift`, `APIClient.swift`

### Models
- Use descriptive names matching the data structure: `Schema.swift`, `GeoJson.swift`

---

## Decision Guidelines

### Where should this file go?

Use this decision tree:

1. **Is it a user-facing feature?**
   - Yes → `features/[FeatureName]/`
   - No → Continue

2. **Is it shared across multiple features?**
   - Yes → Continue
   - No → `features/[FeatureName]/`

3. **Is it a service or business logic?**
   - Yes → `core/services/` or `core/networking/`
   - No → Continue

4. **Is it a UI component?**
   - Yes → `ui/components/` (if shared) or `features/[FeatureName]/` (if feature-specific)
   - No → Continue

5. **Is it a data model?**
   - Yes → `core/models/`
   - No → Continue

6. **Is it navigation/routing?**
   - Yes → `navigation/`
   - No → `shared/` (utilities, config, mocks)

---

## Migration Strategy

### Phase 1: Create Directory Structure
1. Create `features/`, `core/`, `ui/`, `navigation/` directories
2. Create feature subdirectories: `Map/`, `Chat/`, `Journey/`, `Profile/`, `Auth/`

### Phase 2: Move Views to Features
1. Move view files to appropriate feature folders
2. Update imports if needed
3. Test that app still compiles

### Phase 3: Organize Shared Services
1. Create `core/services/` and move shared services
2. Create `core/networking/` and move API clients
3. Create `core/models/` and move shared models

### Phase 4: Organize UI Components
1. Move shared components to `ui/components/`
2. Consider migrating `identity/` to `ui/design/`

### Phase 5: Extract ViewModels
1. Create ViewModels for complex views
2. Move business logic out of views into ViewModels

---

## Benefits of This Structure

### 1. Clear Feature Boundaries
- Easy to find all code related to a specific feature
- Reduces cross-feature coupling
- Enables feature flags and A/B testing

### 2. Organized Shared Code
- Shared services are easy to discover
- Clear separation between feature code and infrastructure
- Better dependency management

### 3. Scalability
- Easy to add new features without affecting existing ones
- Supports team parallelization (different developers work on different features)
- Reduces merge conflicts

### 4. Testability
- Features can be tested in isolation
- Shared services can be mocked easily
- Clear boundaries make unit testing straightforward

### 5. Maintainability
- Predictable file locations
- Easier onboarding for new developers
- Better code organization reduces cognitive load

---

## Anti-Patterns to Avoid

### ❌ Don't: Put feature-specific code in shared directories
```swift
// ❌ BAD: Chat-specific component in shared UI
ui/components/ChatInputBar.swift

// ✅ GOOD: Chat component in Chat feature
features/Chat/ChatInputBar.swift
```

### ❌ Don't: Create too many nested directories
```swift
// ❌ BAD: Too deep
features/Map/Views/Components/Annotations/MapAnnotationViews.swift

// ✅ GOOD: Flat structure
features/Map/MapAnnotationViews.swift
```

### ❌ Don't: Mix feature code with infrastructure
```swift
// ❌ BAD: Feature-specific logic in core service
core/services/LocationManager.swift  // Contains Map-specific geofencing

// ✅ GOOD: Separate concerns
core/services/TrackingManager.swift  // Generic tracking
features/Map/MapGeofenceManager.swift // Map-specific geofencing
```

### ❌ Don't: Create circular dependencies
```swift
// ❌ BAD: Features depending on each other
features/Chat/ChatViewModel.swift  // Imports MapViewModel
features/Map/MapViewModel.swift     // Imports ChatViewModel

// ✅ GOOD: Features depend on shared services, not each other
features/Chat/ChatViewModel.swift   // Imports core/services/APIClient
features/Map/MapViewModel.swift     // Imports core/services/APIClient
```

---

## Examples

### Example 1: Adding a New Feature

**Scenario**: Adding a "Settings" feature

**Steps**:
1. Create `features/Settings/` directory
2. Create `SettingsView.swift` and `SettingsViewModel.swift`
3. If settings need shared services, use `core/services/`
4. If settings have shared UI components, use `ui/components/`

**Result**:
```
features/Settings/
├── SettingsView.swift
└── SettingsViewModel.swift
```

### Example 2: Adding a Shared Service

**Scenario**: Adding a notification service

**Steps**:
1. Create `core/services/NotificationManager.swift`
2. Define protocol if needed for testing
3. Use dependency injection to provide to features

**Result**:
```
core/services/
└── NotificationManager.swift
```

### Example 3: Extracting a Shared Component

**Scenario**: A button style used in multiple features

**Steps**:
1. Move to `ui/components/Buttons.swift` (or add to existing file)
2. Update imports in features using it
3. Ensure component is truly generic (no feature-specific logic)

**Result**:
```
ui/components/
└── Buttons.swift  // Contains reusable button styles
```

---

## Future Considerations

### When to Consider Full Modularization (SPM Packages)

Consider moving to Swift Package Manager modules when:
- ✅ Build times become slow (>30 seconds for incremental builds)
- ✅ Team grows to 8+ developers
- ✅ App reaches 50+ views
- ✅ Need to share code with other apps/projects

**Current Status**: Not needed yet. The hybrid folder structure provides good organization without the overhead of SPM modules.

---

## Related Documentation

- [Refactoring Assessment](./REFACTORING_ASSESSMENT.md) - Detailed refactoring opportunities
- [Concurrency Handling](./CONCURRENCY_HANDLING.md) - Swift 6 concurrency patterns
- [Async Patterns](./ASYNC_PATTERNS.md) - Async/await best practices

---

## Questions?

If you're unsure where a file should go, ask:
1. Is this code specific to one feature?
2. Is this code shared across multiple features?
3. Is this infrastructure/business logic or UI?

When in doubt, start with feature-specific organization and refactor to shared when you see duplication.

---

**Last Updated**: January 2025  
**Maintained By**: iOS Development Team
