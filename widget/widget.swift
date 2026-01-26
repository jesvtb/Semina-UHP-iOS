//
//  widget.swift
//  widget
//
//  Created by Jessica Luo on 2025-12-10.
//

import WidgetKit
import SwiftUI
import CoreLocation
import Foundation

// Location tracking data structure for widget
struct LocationTrackingEntry: TimelineEntry {
    let date: Date
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?
    let timestamp: Date?
    let isAppInBackground: Bool
    let trackingMode: String? // "active", "background", "stopped", nil
    let hasLocation: Bool
}

struct Provider: TimelineProvider {
    // UserDefaults keys (matching LocationManager)
    // Note: StorageManager automatically adds "UHP." prefix, so we use keys without prefix
    private let lastDeviceLocationKey = "LastDeviceLocation"
    private let appStateIsInBackgroundKey = "AppState.isInBackground"
    private let trackingModeKey = "TrackingMode.current"
    
    func placeholder(in context: Context) -> LocationTrackingEntry {
        LocationTrackingEntry(
            date: Date(),
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: Date(),
            isAppInBackground: false,
            trackingMode: "active",
            hasLocation: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LocationTrackingEntry) -> ()) {
        #if DEBUG
        print("🔄 Widget: getSnapshot called at \(Date())")
        #endif
        let entry = loadLocationTrackingEntry()
        #if DEBUG
        print("🔄 Widget: Snapshot entry with isAppInBackground = \(entry.isAppInBackground)")
        #endif
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        #if DEBUG
        print("🔄 Widget: getTimeline called at \(Date())")
        #endif
        
        let entry = loadLocationTrackingEntry()
        
        #if DEBUG
        print("🔄 Widget: Created entry with isAppInBackground = \(entry.isAppInBackground)")
        #endif
        
        // Update every 30 seconds for frequent testing updates
        // Note: iOS may throttle updates, so actual refresh may be delayed
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        
        #if DEBUG
        print("🔄 Widget: Timeline created, next update scheduled for \(nextUpdate)")
        #endif
        
        completion(timeline)
    }
    
    // Helper function to load location and app state from UserDefaults
    // Uses StorageManager for consistent key prefixing and shared UserDefaults suite
    private func loadLocationTrackingEntry() -> LocationTrackingEntry {
        let currentDate = Date()
        
        // Read app state using StorageManager with fallback to direct UserDefaults access
        // This ensures we can read the value even if StorageManager has issues
        let fullKey = "UHP.\(appStateIsInBackgroundKey)"
        let sharedDefaults = UserDefaults(suiteName: "com.semina.unheardpath")
        
        // Try StorageManager first
        var isAppInBackground = StorageManager.loadFromUserDefaults(forKey: appStateIsInBackgroundKey, as: Bool.self)
        
        // Fallback to direct UserDefaults access if StorageManager returns nil
        if isAppInBackground == nil {
            isAppInBackground = sharedDefaults?.object(forKey: fullKey) as? Bool
        }
        
        // Default to false (foreground) if still nil
        let finalValue = isAppInBackground ?? false
        
        #if DEBUG
        // Enhanced debugging to see what's happening
        let storageManagerValue = StorageManager.loadFromUserDefaults(forKey: appStateIsInBackgroundKey, as: Bool.self)
        let directValue = sharedDefaults?.object(forKey: fullKey) as? Bool
        
        // Debug: List all keys in shared UserDefaults to see what's actually stored
        if let sharedDefaults = sharedDefaults {
            let allKeys = sharedDefaults.dictionaryRepresentation().keys
            let uhpKeys = allKeys.filter { $0.hasPrefix("UHP.") }.sorted()
            let allKeysList = Array(allKeys).sorted()
            
            print("📱 Widget: Reading app state...")
            print("   Key: \(fullKey)")
            print("   StorageManager result: \(storageManagerValue?.description ?? "nil")")
            print("   Direct UserDefaults result: \(directValue?.description ?? "nil")")
            print("   Final value used: \(finalValue)")
            print("   Total keys in shared suite: \(allKeys.count)")
            print("   UHP-prefixed keys: \(uhpKeys)")
            print("   ALL keys in shared suite: \(allKeysList.prefix(20))") // Show first 20 keys
            
            // Test: Try to write and read a test value to verify suite access
            let testKey = "UHP.WidgetTest.key"
            sharedDefaults.set("test_value", forKey: testKey)
            sharedDefaults.synchronize()
            let testRead = sharedDefaults.string(forKey: testKey)
            print("   Widget suite access test: write/read test key = \(testRead ?? "FAILED")")
            
            // Check if the key exists with different variations
            let keyVariations = [
                fullKey,
                appStateIsInBackgroundKey,
                "UHP.\(appStateIsInBackgroundKey)"
            ]
            for keyVar in keyVariations {
                if let value = sharedDefaults.object(forKey: keyVar) {
                    print("   ✅ Found key '\(keyVar)': \(value)")
                } else {
                    print("   ❌ Key '\(keyVar)' not found")
                }
            }
        } else {
            print("⚠️ Widget: Shared UserDefaults suite is nil! App Group may not be configured.")
        }
        
        if storageManagerValue == nil && directValue == nil {
            print("⚠️ Widget: App state key not found in UserDefaults, defaulting to false (foreground)")
        }
        #endif
        
        // Read tracking mode using StorageManager
        let trackingMode = StorageManager.loadFromUserDefaults(forKey: trackingModeKey, as: String.self)
        
        // Read location data from new format (single key with NewLocation structure)
        guard let newLocationString = StorageManager.loadFromUserDefaults(forKey: lastDeviceLocationKey, as: String.self),
              let newLocationDict = JSONValue.decodeFromString(newLocationString) else {
            return LocationTrackingEntry(
                date: currentDate,
                latitude: nil,
                longitude: nil,
                timestamp: nil,
                isAppInBackground: finalValue,
                trackingMode: trackingMode,
                hasLocation: false
            )
        }
        
        // Extract coordinate from NewLocation structure
        guard case .dictionary(let coordinateDict) = newLocationDict["coordinate"],
              case .double(let latitude) = coordinateDict["lat"],
              case .double(let longitude) = coordinateDict["lng"] else {
            return LocationTrackingEntry(
                date: currentDate,
                latitude: nil,
                longitude: nil,
                timestamp: nil,
                isAppInBackground: finalValue,
                trackingMode: trackingMode,
                hasLocation: false
            )
        }
        
        // Extract timestamp
        let timestamp: Date
        if case .double(let ts) = newLocationDict["timestamp"] {
            timestamp = Date(timeIntervalSince1970: ts)
        } else {
            // If timestamp missing, use current time as fallback
            timestamp = currentDate
        }
        
        // Validate coordinates are not zero
        guard latitude != 0.0 || longitude != 0.0 else {
            return LocationTrackingEntry(
                date: currentDate,
                latitude: nil,
                longitude: nil,
                timestamp: nil,
                isAppInBackground: finalValue,
                trackingMode: trackingMode,
                hasLocation: false
            )
        }
        
        return LocationTrackingEntry(
            date: currentDate,
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            isAppInBackground: finalValue,
            trackingMode: trackingMode,
            hasLocation: true
        )
    }
}

struct widgetEntryView: View {
    var entry: Provider.Entry
    
    // Helper to determine status color
    private var statusColor: Color {
        guard entry.hasLocation, let timestamp = entry.timestamp else {
            return .red
        }
        
        let age = Date().timeIntervalSince(timestamp)
        
        if age < 300 { // Less than 5 minutes
            return .green
        } else if age < 900 { // Less than 15 minutes
            return .yellow
        } else {
            return .red
        }
    }
    
    // Helper to format location age
    private func formatLocationAge(_ timestamp: Date) -> String {
        let age = Date().timeIntervalSince(timestamp)
        
        if age < 60 {
            return "\(Int(age))s ago"
        } else if age < 3600 {
            return "\(Int(age / 60))m ago"
        } else {
            return "\(Int(age / 3600))h ago"
        }
    }
    
    // Helper to format tracking mode display
    private func formatTrackingMode(_ mode: String?) -> String {
        guard let mode = mode else {
            return "Unknown"
        }
        
        switch mode {
        case "active":
            return "Active"
        case "background":
            return "Significant Changes"
        case "stopped":
            return "Stopped"
        default:
            return mode.capitalized
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with app state indicator
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: entry.isAppInBackground ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(entry.isAppInBackground ? .blue : .orange)
                    Text(entry.isAppInBackground ? "BACKGROUND MODE" : "FOREGROUND MODE")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(entry.isAppInBackground ? .blue : .orange)
                }
                
                #if DEBUG
                // Debug info: show raw value being read and key info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug: isInBackground = \(entry.isAppInBackground ? "true" : "false")")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    // Show what keys are available (for debugging)
                    let sharedDefaults = UserDefaults(suiteName: "com.semina.unheardpath")
                    if let sharedDefaults = sharedDefaults {
                        let allKeys = sharedDefaults.dictionaryRepresentation().keys
                        let uhpKeys = allKeys.filter { $0.hasPrefix("UHP.") && $0.contains("AppState") }
                        if !uhpKeys.isEmpty {
                            Text("Keys found: \(uhpKeys.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.green.opacity(0.7))
                        } else {
                            Text("No AppState keys found")
                                .font(.caption2)
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                }
                #endif
            }
            
            Divider()
            
            // Tracking mode badge
            if let trackingMode = entry.trackingMode {
                HStack {
                    Text("Mode:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatTrackingMode(trackingMode))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            trackingMode == "active" ? Color.green.opacity(0.2) :
                            trackingMode == "background" ? Color.blue.opacity(0.2) :
                            Color.red.opacity(0.2)
                        )
                        .cornerRadius(4)
                }
            }
            
            Divider()
            
            if entry.hasLocation, let lat = entry.latitude, let lon = entry.longitude {
                // Location coordinates
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latitude:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.6f", lat))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Text("Longitude:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.6f", lon))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                
                // Timestamp and age
                if let timestamp = entry.timestamp {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Update:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(timestamp, style: .time)
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        // Show age of location with color coding
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(formatLocationAge(timestamp))
                                .font(.caption2)
                                .foregroundColor(statusColor)
                        }
                    }
                }
            } else {
                // No location available
                VStack(alignment: .leading, spacing: 4) {
                    Text("No location data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Waiting for location update...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Widget timeline update info
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline: \(entry.date, style: .time)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Show time since last timeline update (helps verify iOS is refreshing)
                let timeSinceUpdate = Date().timeIntervalSince(entry.date)
                if timeSinceUpdate < 60 {
                    Text("Updated \(Int(timeSinceUpdate))s ago")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if timeSinceUpdate < 300 {
                    Text("Updated \(Int(timeSinceUpdate / 60))m ago")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                } else {
                    Text("Updated \(Int(timeSinceUpdate / 60))m ago")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
    }
}

struct widget: Widget {
    let kind: String = "widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                widgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                widgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Location Tracker")
        .description("Monitor background location tracking")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Preview requires iOS 17.0+ for the 'as:' parameter
// Deployment target is 16.6, so preview is conditionally available
// 
// IMPORTANT: The #Preview macro with 'as:' parameter has a known issue in Swift 6
// where the macro doesn't properly respect @available annotations.
// This is a Swift 6/Xcode limitation. The preview is commented out to avoid compilation errors.
// You can test widgets by running the app on a device or simulator.
//
// Uncomment the following when the Swift 6 availability issue is resolved:
/*
@available(iOSApplicationExtension 17.0, *)
#Preview(as: .systemSmall) {
    widget()
} timeline: {
    LocationTrackingEntry(date: .now, latitude: 37.7749, longitude: -122.4194, timestamp: .now, isAppInBackground: false, trackingMode: "active", hasLocation: true)
    LocationTrackingEntry(date: .now, latitude: 37.7749, longitude: -122.4194, timestamp: .now, isAppInBackground: true, trackingMode: "background", hasLocation: true)
    LocationTrackingEntry(date: .now, latitude: nil, longitude: nil, timestamp: nil, isAppInBackground: true, trackingMode: "stopped", hasLocation: false)
}
*/