//
//  LocationManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import SwiftUI

// struct LocationDetails

@MainActor  // Ensure all state mutations stay on the main actor to avoid data races with Swift 6 strict concurrency
// AppLifecycleHandler conformance is in a nonisolated extension with proper MainActor bridging
class LocationManager: ObservableObject {
    init() {}

    // MARK: - Location Persistence (Removed - now handled by EventManager)

    // All location persistence methods have been removed:
    // - saveDeviceLocation() - moved to EventManager
    // - saveLookupLocation() - moved to EventManager
    // - loadLastSavedDeviceLocation() - moved to EventManager
    // - loadLastSavedLookupLocation() - moved to EventManager
    // - @Published properties (deviceLocation, lookupLocation, locationDetails, lookupLocationDetails) - removed
    // - Location Data Access (latitude, longitude) - removed (deviceLocation moved to TrackingManager)
    // - reverseGeocodeLocation / reverseGeocodeUserLocation - removed; app uses Geocoder.geocodeReverse (LocationDict) in MainView+LocationHandling
    // - authorizationStatus / locationManagerDidChangeAuthorization - removed; TrackingManager owns location and auth status
    // - Debug helpers (debugPrintAllUserDefaults, debugClearAllCache) - moved to DebugVisualizer in debug/APITestUtilities.swift
}

