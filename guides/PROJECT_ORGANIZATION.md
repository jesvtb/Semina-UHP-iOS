# iOS App Project Organization Guide

## Overview

This document describes the project organization for the unheardpath iOS app. The app target lives under `unheardpath/`; shared logic and types live in the `core` Swift package (`03_apps/iosapp/core/`).

---

## Directory Structure

```
unheardpath/
├── views/                     # Screens and main UI
│   ├── MainView.swift
│   ├── MainView+LocationHandling.swift
│   ├── MapView.swift
│   ├── ChatTab.swift
│   ├── ContentManager.swift   # Content types, registry, ordered sections
│   ├── InfoSheetView.swift    # InfoSheet + ContentViewRegistry
│   ├── JourneyStart.swift
│   ├── ProfileTab.swift
│   ├── AuthView.swift
│   ├── TabBarView.swift
│   ├── Autocomplete.swift
│   ├── MapAnnotationViews.swift
│   ├── MapContent.swift
│   ├── MapPreview.swift
│   ├── SSEContentTestView.swift
│   └── ContentView.swift
│
├── services/                  # App-level services (API, auth, SSE, UI state)
│   ├── APIClient.swift        # UHPGateway + app API wrapper
│   ├── AuthManager.swift
│   ├── LocationManager.swift
│   ├── AutocompleteManager.swift
│   ├── MapFeaturesManager.swift
│   ├── ToastManager.swift
│   ├── AppLifecycleManager.swift
│   ├── SSEEventProcessor.swift
│   ├── SSEEventRouter.swift
│   ├── Supabase.swift
│   └── Mapbox.swift
│
├── core/                       # App “core” (event/session, tracking)
│   └── services/
│       ├── EventManager.swift   # Session, events, orchestrator stream
│       └── TrackingManager.swift # Location tracking only
│
├── viewmodels/
│   └── ChatManager.swift
│
├── components/                 # Reusable UI components
│   ├── AddrSearch.swift
│   ├── Buttons.swift
│   ├── Components.swift
│   ├── InputBar.swift
│   ├── LiveUpdateStack.swift
│   ├── MessageBubbles.swift
│   ├── Toast.swift
│   └── WebSearchResultItem.swift
│
├── schemas/                    # App data models
│   ├── Schema.swift           # User, UserManager, etc.
│   └── GeoJson.swift          # App GeoJSON types (if any beyond core)
│
├── identity/                   # Design tokens
│   ├── Color.swift
│   ├── Spacing.swift
│   └── Typography.swift
│
├── config/
│   └── basemap_style.json
│
├── debug/
│   └── APITestUtilities.swift
│
├── unheardpathApp.swift        # App entry, env objects
└── ContentView.swift           # Root content view
```

**Core package** (`03_apps/iosapp/core/`):

- `networking.swift`: `APIClient`, `processSSEStream`, `SSEEvent`, `SSEEventType`, request/stream helpers
- `storage.swift`: `Storage` (UserDefaults with key prefix, file/cache helpers)
- `geojson.swift`: GeoJSON parsing, feature extraction
- `logger.swift`: `Logger`, `InMemoryLogger`
- `learn.swift`, `events.swift`, `Geocoder.swift`, etc.

---

## Where to Put New Code

| Kind | Location |
|------|----------|
| New screen or main view | `unheardpath/views/` |
| New app service (auth, API, SSE, UI state) | `unheardpath/services/` |
| Event/session or tracking logic | `unheardpath/core/services/` |
| New view model | `unheardpath/viewmodels/` |
| Reusable UI piece | `unheardpath/components/` |
| Shared data models / schemas | `unheardpath/schemas/` |
| Design tokens | `unheardpath/identity/` |
| Config / static assets | `unheardpath/config/` |
| Debug helpers | `unheardpath/debug/` |
| Shared types, networking, storage, parsing | `core` package |

---

## File Naming

- **Views**: Descriptive name, often ending in `View` (e.g. `MapView.swift`, `ChatTab.swift`).
- **Services / view models**: `*Manager` or `*ViewModel` (e.g. `AuthManager`, `ChatManager`).
- **Gateways / clients**: `UHPGateway`, `APIClient` (in app and core as appropriate).

---

## Related Documentation

- [Concurrency_Handling.md](./Concurrency_Handling.md) – Swift 6 concurrency patterns
- [Async_Patterns.md](./Async_Patterns.md) – Async/await usage

---

**Last Updated**: February 2026
