# Debugging UserDefaults - Inspection Guide

## Storage Limits

### Official Limits
- **No hard limit** on total storage
- **Individual value**: ~1 MB (larger values may fail silently)
- **Practical limit**: ~1-2 MB total (performance degrades beyond this)
- **Best practice**: Keep individual values under 100 KB

### Current App Usage
- **Location data**: ~24 bytes (3 doubles: lat, lon, timestamp)
- **Cache entries**: Varies by location (features array + timestamp)
- **Wiki features**: Depends on JSON size per feature

## Method 1: Terminal (Simulator)

### Find Simulator Device ID
```bash
# List all simulators
xcrun simctl list devices

# Find your running simulator (look for "Booted")
# Example output: iPhone 16 Pro (ABC12345-1234-1234-1234-123456789ABC) (Booted)
```

### Inspect UserDefaults Plist
```bash
# Replace DEVICE_ID with your simulator's ID
xcrun simctl get_app_container DEVICE_ID com.semina.unheardpath data

# Or use the bundle identifier directly
xcrun simctl get_app_container booted com.semina.unheardpath data

# View the plist file
plutil -p ~/Library/Developer/CoreSimulator/Devices/DEVICE_ID/data/Containers/Data/Application/APP_ID/Library/Preferences/com.semina.unheardpath.plist

# Or use defaults command (easier)
defaults read ~/Library/Developer/CoreSimulator/Devices/DEVICE_ID/data/Containers/Data/Application/APP_ID/Library/Preferences/com.semina.unheardpath.plist
```

### Quick One-Liner (Current Booted Simulator)
```bash
# Find the plist file
find ~/Library/Developer/CoreSimulator/Devices -name "com.semina.unheardpath.plist" -type f 2>/dev/null | head -1 | xargs plutil -p
```

## Method 2: Xcode Debug Console

Add this debug function to your app and call it from Xcode's debug console:

```swift
// In LocationManager or a debug helper
func debugPrintAllUserDefaults() {
    let defaults = UserDefaults.standard
    let dict = defaults.dictionaryRepresentation()
    
    print("📦 UserDefaults Contents:")
    print("Total keys: \(dict.count)")
    print("---")
    
    // Filter to only our app's keys
    let appKeys = dict.keys.filter { key in
        key.hasPrefix("LocationManager.") || 
        key.hasPrefix("PlacesCache_") || 
        key.hasPrefix("wiki_")
    }
    
    for key in appKeys.sorted() {
        if let value = dict[key] {
            let size = "\(value)".data(using: .utf8)?.count ?? 0
            print("\(key): \(size) bytes")
            if size < 200 {  // Only print small values
                print("  Value: \(value)")
            } else {
                print("  Value: [Large object, \(size) bytes]")
            }
        }
    }
    
    // Calculate total size
    let totalSize = appKeys.compactMap { key -> Int? in
        guard let value = dict[key] else { return nil }
        return "\(value)".data(using: .utf8)?.count
    }.reduce(0, +)
    
    print("---")
    print("Total size: \(totalSize) bytes (~\(totalSize / 1024) KB)")
}
```

### Usage in Debug Console
```
# In Xcode debug console (pause execution, then type):
po LocationManager().debugPrintAllUserDefaults()

# Or for any UserDefaults key:
po UserDefaults.standard.dictionaryRepresentation()["LocationManager.lastLocation.latitude"]
```

## Method 3: Simulator Menu (Visual Inspection)

1. **Open Simulator**
2. **Device** → **Erase All Content and Settings** (to start fresh, optional)
3. **Run your app** and let it store data
4. **Quit Simulator**
5. **Navigate to**: `~/Library/Developer/CoreSimulator/Devices/`
6. **Find your device folder** (check modification dates)
7. **Navigate to**: `data/Containers/Data/Application/[APP_ID]/Library/Preferences/`
8. **Open**: `com.semina.unheardpath.plist` in Xcode or any plist editor

## Method 4: SwiftUI Debug View (For Xcode Preview)

Add this debug view to inspect UserDefaults in real-time:

```swift
struct UserDefaultsDebugView: View {
    @State private var userDefaultsContent: [String: Any] = [:]
    
    var body: some View {
        List {
            Section("All Keys") {
                Text("Total: \(userDefaultsContent.count) keys")
            }
            
            Section("App-Specific Keys") {
                let appKeys = userDefaultsContent.keys.filter { key in
                    key.hasPrefix("LocationManager.") || 
                    key.hasPrefix("PlacesCache_") || 
                    key.hasPrefix("wiki_")
                }.sorted()
                
                ForEach(Array(appKeys), id: \.self) { key in
                    VStack(alignment: .leading) {
                        Text(key).font(.headline)
                        if let value = userDefaultsContent[key] {
                            Text("\(String(describing: value))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section("Actions") {
                Button("Refresh") {
                    loadUserDefaults()
                }
                Button("Clear All App Data", role: .destructive) {
                    clearAppUserDefaults()
                }
            }
        }
        .onAppear {
            loadUserDefaults()
        }
    }
    
    private func loadUserDefaults() {
        userDefaultsContent = UserDefaults.standard.dictionaryRepresentation()
    }
    
    private func clearAppUserDefaults() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { key in
            key.hasPrefix("LocationManager.") || 
            key.hasPrefix("PlacesCache_") || 
            key.hasPrefix("wiki_")
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        loadUserDefaults()
    }
}
```

## Method 5: Command Line Script

Create a script to quickly inspect:

```bash
#!/bin/bash
# inspect_userdefaults.sh

BUNDLE_ID="com.semina.unheardpath"
DEVICE_ID=$(xcrun simctl list devices | grep Booted | head -1 | grep -o '[A-F0-9-]\{36\}')

if [ -z "$DEVICE_ID" ]; then
    echo "❌ No booted simulator found"
    exit 1
fi

PLIST_PATH=$(find ~/Library/Developer/CoreSimulator/Devices/$DEVICE_ID -name "${BUNDLE_ID}.plist" 2>/dev/null | head -1)

if [ -z "$PLIST_PATH" ]; then
    echo "❌ UserDefaults plist not found for $BUNDLE_ID"
    exit 1
fi

echo "📦 UserDefaults for $BUNDLE_ID"
echo "📍 Path: $PLIST_PATH"
echo "---"
plutil -p "$PLIST_PATH"
```

## Quick Tips

### Check Size of Specific Key
```swift
// In debug console
po UserDefaults.standard.object(forKey: "LocationManager.lastLocation.latitude")

// Check size
po "\(UserDefaults.standard.object(forKey: "PlacesCache_37.7749_-122.4194") ?? "")".data(using: .utf8)?.count
```

### Clear All App Data
```swift
// In debug console
UserDefaults.standard.removePersistentDomain(forName: "com.semina.unheardpath")
```

### Monitor in Real-Time
Add breakpoints in `saveLocation()` and `saveCachedLocationData()` to see when data is written.

