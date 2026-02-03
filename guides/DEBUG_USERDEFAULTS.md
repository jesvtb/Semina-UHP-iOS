# Debugging UserDefaults (Storage API)

## Storage API

The app uses **core.Storage** for UserDefaults. Storage is configured at app/widget launch with a **key prefix** (e.g. `"UHP."`). All keys are stored with that prefix; `Storage.saveToUserDefaults` / `Storage.loadFromUserDefaults` apply it automatically. Do **not** add the prefix manually when calling these APIs.

- **Prefix**: `Storage.keyPrefix` (e.g. `"UHP."`)
- **Inspect**: Use Storage helpers so you only see app keys.

## Storage Limits

- **Individual value**: ~1 MB (larger may fail silently)
- **Practical total**: ~1–2 MB (performance degrades beyond)
- **Best practice**: Keep values under 100 KB

## Inspecting App Keys

### 1. In Code / Debug Console

```swift
import core

// Print all keys with configured prefix (e.g. UHP.*)
Storage.printUserDefaultsKeysWithPrefix()

// Get all prefixed key-value pairs
let keysWithPrefix = Storage.allUserDefaultsKeysWithPrefix()
// keysWithPrefix keys are full keys (e.g. "UHP.sessionId", "UHP.lastDeviceLocation")
```

MainView’s debug cache sheet uses `Storage.allUserDefaultsKeysWithPrefix()` and `Storage.keyPrefix` to list and display app storage.

### 2. Clear All App Storage

```swift
Storage.clearUserDefaultsKeysWithPrefix()
```

### 3. Terminal (Simulator)

Find the plist for the running simulator:

```bash
find ~/Library/Developer/CoreSimulator/Devices -name "com.semina.unheardpath.plist" -type f 2>/dev/null | head -1 | xargs plutil -p
```

If using App Groups, the app may use a shared suite; the plist path can differ. Prefer `Storage.printUserDefaultsKeysWithPrefix()` so you see exactly what the app reads/writes.

### 4. Xcode Debug Console

```text
# After app has run and Storage.configure() was called:
po Storage.printUserDefaultsKeysWithPrefix()

# Or inspect the dictionary:
po Storage.allUserDefaultsKeysWithPrefix()
```

## Current App Usage

Storage (with UHP. prefix) is used for:

- Session and event state (EventManager)
- Tracking mode (TrackingManager)
- App-in-background flag (App Lifecycle / widget)
- Last device/search location strings
- Bookmarks and other small app state

Keys are logical names (e.g. sessionId, lastDeviceLocation); the prefix is added by Storage.

## Related

- **Rule**: Use Storage for UserDefaults; see `.cursor/rules/user-default.mdc`.
- **API**: `core/Sources/core/storage.swift` — `configure`, `keyPrefix`, `saveToUserDefaults`, `loadFromUserDefaults`, `allUserDefaultsKeysWithPrefix`, `printUserDefaultsKeysWithPrefix`, `clearUserDefaultsKeysWithPrefix`.
