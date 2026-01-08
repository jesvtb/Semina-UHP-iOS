//
//  LocationManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import CoreLocation
import SwiftUI
import UIKit
import WidgetKit

// struct LocationDetails

@MainActor  // Ensure all state mutations stay on the main actor to avoid data races with Swift 6 strict concurrency
// AppLifecycleHandler conformance is in a nonisolated extension with proper MainActor bridging
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var deviceLocation: CLLocation?
    @Published var lookupLocation: CLLocation?
    @Published var isLocationPermissionGranted: Bool = false
    
    // Geocoding state
    @Published var isGeocoding: Bool = false
    @Published var geocodingError: Error?
    @Published var locationDetails: [String: JSONValue]?
    @Published var lookupLocationDetails: [String: JSONValue]?
    
    // Tracking mode state
    private var isTrackingActive = false
    private var isUsingSignificantChanges = false
    private var isAppInBackground = false
    
    // App lifecycle manager (optional, set after initialization)
    weak var appLifecycleManager: AppLifecycleManager?
    
    // Configuration constants (Google Maps strategy)
    private let activeDistanceFilter: CLLocationDistance = 50.0  // Update every 50 meters when active
    private let backgroundDistanceFilter: CLLocationDistance = 100.0  // Update every 100 meters in background
    private let activeAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters  // Moderate accuracy when active
    private let backgroundAccuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer  // Lower accuracy in background
    private let highAccuracyMode: CLLocationAccuracy = kCLLocationAccuracyBest  // High accuracy for navigation
    
    // UserDefaults keys for persisting location
    // Note: StorageManager will automatically add "UHP." prefix
    private let lastDeviceLatKey = "LastDeviceCoord.latitude"
    private let lastDeviceLonKey = "LastDeviceCoord.longitude"
    private let lastDeviceCoordTimestamp = "LastDeviceCoord.timestamp"
    private let lastLookupLatKey = "LastLookupCoord.latitude"
    private let lastLookupLonKey = "LastLookupCoord.longitude"
    private let lastLookupCoordTimestamp = "LastLookupCoord.timestamp"
    private let lastDeviceLocationKey = "LastDeviceLocation"
    private let lastLookupLocationKey = "LastLookupLocation"
    
    // UserDefaults keys for widget state
    // Note: StorageManager will automatically add "UHP." prefix
    private let appStateIsInBackgroundKey = "AppState.isInBackground"
    private let trackingModeKey = "TrackingMode.current"
    
    // Geofencing management
    private var monitoredGeofences: [String: CLCircularRegion] = [:]  // Track all geofences by identifier
    
    // Device POIs geofencing
    private var devicePOIsRefreshRegion: CLCircularRegion?
    private var devicePOIsRefreshRadius: CLLocationDistance = 2000.0  // Default radius, will be updated from backend response
    @Published var shouldRefreshDevicePOIs: Bool = false
    
    // UserDefaults keys for geofence persistence
    private let devicePOIsGeofenceLatKey = "DevicePOIsGeofence.latitude"
    private let devicePOIsGeofenceLonKey = "DevicePOIsGeofence.longitude"
    private let devicePOIsGeofenceRadiusKey = "DevicePOIsGeofence.radius"
    
    override init() {
        super.init()
        locationManager.delegate = self
        // Start with moderate accuracy (Google Maps strategy)
        locationManager.desiredAccuracy = activeAccuracy
        locationManager.distanceFilter = activeDistanceFilter
        authorizationStatus = locationManager.authorizationStatus
        isLocationPermissionGranted = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        
        // Initialize app state in UserDefaults (defaults to foreground)
        // This ensures widget always has a valid value to read
        if !StorageManager.existsInUserDefaults(forKey: appStateIsInBackgroundKey) {
            StorageManager.saveToUserDefaults(false, forKey: appStateIsInBackgroundKey)
            #if DEBUG
            print("💾 Initialized app state in UserDefaults: isInBackground = false")
            #endif
        }
        
        // Load last saved locations immediately
        loadLastSavedDeviceLocation()
        loadLastSavedLookupLocation()
    }
    
    func requestLocationPermission() {
        let currentStatus = locationManager.authorizationStatus
        
        switch currentStatus {
        case .notDetermined:
            // Request "when in use" authorization first
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission already granted, request precise location if needed
            requestPreciseLocationIfNeeded()
            startLocationUpdates()
        case .denied, .restricted:
            print("❌ Location permission denied or restricted")
        @unknown default:
            print("❓ Unknown location authorization status")
        }
    }
    
    private func requestPreciseLocationIfNeeded() {
        // iOS 14+ supports reduced accuracy mode
        // Request precise location if available
        if #available(iOS 14.0, *) {
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "NSLocationTemporaryUsageDescription") { [weak self] error in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let error = error {
                            print("❌ Failed to request precise location: \(error.localizedDescription)")
                        } else {
                            print("✅ Precise location permission granted")
                            self.startLocationUpdates()
                        }
                    }
                }
            } else {
                print("✅ Precise location already authorized")
            }
        }
    }
    
    // MARK: - Location Tracking Methods
    
    /// Requests a one-time location update with 100m accuracy
    /// This is more battery-efficient than continuous updates for initial location
    /// The location will be delivered via didUpdateLocations delegate method
    func requestOneTimeLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            #if DEBUG
            print("⚠️ Cannot request one-time location - permission not granted")
            #endif
            return
        }
        
        // Set desired accuracy to 100m for the one-time request
        locationManager.desiredAccuracy = kCLLocationAccuracyBest  // kCLLocationAccuracyHundredMeters
        
        #if DEBUG
        print("📍 Requesting one-time location with 100m accuracy")
        #endif
        
        locationManager.requestLocation()
    }
    
    /// Starts location updates with adaptive strategy based on app state
    private func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        if isAppInBackground {
            switchToBackgroundTracking()
        } else {
            switchToActiveTracking()
        }
    }
    
    /// Switches to active tracking mode (app in foreground)
    /// Uses continuous GPS with moderate accuracy and distance filter
    private func switchToActiveTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        // Stop significant location changes if active
        if isUsingSignificantChanges {
            locationManager.stopMonitoringSignificantLocationChanges()
            isUsingSignificantChanges = false
            print("🔄 Stopped significant location changes")
        }
        
        // Configure for active tracking (Google Maps strategy)
        // locationManager.desiredAccuracy = activeAccuracy
        locationManager.desiredAccuracy = kCLLocationAccuracyBest  
        locationManager.distanceFilter = activeDistanceFilter
        
        // Start continuous updates
        if !isTrackingActive {
            locationManager.startUpdatingLocation()
            isTrackingActive = true
            print("📡 Started active location tracking (accuracy: \(activeAccuracy)m, filter: \(activeDistanceFilter)m)")
        } else {
            print("📡 Updated active tracking configuration")
        }
        
        // Save tracking mode to UserDefaults for widget
        StorageManager.saveToUserDefaults("active", forKey: trackingModeKey)
    }
    
    /// Switches to background tracking mode (app in background)
    /// Uses significant location changes for battery efficiency
    private func switchToBackgroundTracking() {
        // Stop continuous updates if active (always do this when switching to background)
        if isTrackingActive {
            locationManager.stopUpdatingLocation()
            isTrackingActive = false
            print("🔄 Stopped continuous location updates")
        }
        
        // Check authorization - iOS will prevent significant changes without "Always" permission
        // but we need to update widget state accordingly
        guard authorizationStatus == .authorizedAlways else {
            StorageManager.saveToUserDefaults("stopped", forKey: trackingModeKey)
            print("⏸️ Background tracking requires 'Always' permission")
            return
        }
        
        // Start significant location changes if available
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            print("⚠️ Significant location change monitoring not available")
            StorageManager.saveToUserDefaults("stopped", forKey: trackingModeKey)
            return
        }
        
        if !isUsingSignificantChanges {
            locationManager.startMonitoringSignificantLocationChanges()
            isUsingSignificantChanges = true
            print("📍 Switching to significant location change monitoring")
        }
        
        StorageManager.saveToUserDefaults("background", forKey: trackingModeKey)
    }
    
    /// Stops all location tracking
    func stopLocationUpdates() {
        if isTrackingActive {
            locationManager.stopUpdatingLocation()
            isTrackingActive = false
            print("⏸️ Stopped continuous location updates")
        }
        
        if isUsingSignificantChanges {
            locationManager.stopMonitoringSignificantLocationChanges()
            isUsingSignificantChanges = false
            print("⏸️ Stopped significant location changes")
        }
        
        // Also stop all geofence monitoring
        stopAllGeofences()
        devicePOIsRefreshRegion = nil
    }
    
    // MARK: - App Lifecycle Methods
    
    /// Called when the app enters the background
    /// Switches to battery-efficient tracking mode
    /// This method is called from @MainActor context (AppLifecycleManager is @MainActor)
    func appDidEnterBackground() {
        isAppInBackground = true
        
        // Save app state to UserDefaults for widget
        StorageManager.saveToUserDefaults(true, forKey: appStateIsInBackgroundKey)
        #if DEBUG
        // Verify the value was saved correctly
        let savedValue = StorageManager.loadFromUserDefaults(forKey: appStateIsInBackgroundKey, as: Bool.self)
        print("💾 Set UserDefaults: isInBackground = \(savedValue ?? false))")
        #endif
        
        switchToBackgroundTracking()
        
        // Trigger widget refresh (DEBUG only)
        // Note: Widget refresh happens after both app state and tracking mode are saved
        // Use a small delay to ensure UserDefaults write completes across process boundaries
        #if DEBUG
        Task { @MainActor in
            // Small delay to ensure UserDefaults synchronization completes
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            WidgetCenter.shared.reloadAllTimelines()
            print("🔄 Triggered widget refresh")
        }
        #endif
    }
    
    /// Called when the app is about to enter the foreground
    /// Switches to active tracking mode
    /// This method is called from @MainActor context (AppLifecycleManager is @MainActor)
    func appWillEnterForeground() {
        isAppInBackground = false
        
        // Save app state to UserDefaults for widget
        StorageManager.saveToUserDefaults(false, forKey: appStateIsInBackgroundKey)
        #if DEBUG
        // Verify the value was saved correctly
        let savedValue = StorageManager.loadFromUserDefaults(forKey: appStateIsInBackgroundKey, as: Bool.self)
        print("💾 Set UserDefaults: isInBackground = \(savedValue ?? true))")
        #endif
        
        switchToActiveTracking()
        
        // Trigger widget refresh (DEBUG only)
        // Note: Widget refresh happens after both app state and tracking mode are saved
        // Use a small delay to ensure UserDefaults write completes across process boundaries
        #if DEBUG
        Task { @MainActor in
            // Small delay to ensure UserDefaults synchronization completes
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Use specific widget kind for more reliable refresh
            WidgetCenter.shared.reloadTimelines(ofKind: "widget")
            // Also reload all as fallback
            WidgetCenter.shared.reloadAllTimelines()
            print("🔄 Triggered widget refresh (kind: widget)")
        }
        #endif
    }
    
    /// Enables high accuracy mode (e.g., for navigation)
    /// Call this when you need precise location tracking
    func enableHighAccuracyMode() {
        locationManager.desiredAccuracy = highAccuracyMode
        locationManager.distanceFilter = kCLDistanceFilterNone  // No distance filter for high accuracy
        print("🎯 Enabled high accuracy mode (navigation-level precision)")
        
        // Restart tracking if it was active
        if !isTrackingActive && !isAppInBackground {
            startLocationUpdates()
        }
    }
    
    /// Disables high accuracy mode and returns to adaptive strategy
    func disableHighAccuracyMode() {
        if isAppInBackground {
            locationManager.desiredAccuracy = backgroundAccuracy
            locationManager.distanceFilter = backgroundDistanceFilter
        } else {
            locationManager.desiredAccuracy = activeAccuracy
            locationManager.distanceFilter = activeDistanceFilter
        }
        print("🚫 Disabled high accuracy mode, returned to adaptive strategy")
        
        // Restart tracking if it was active
        if !isTrackingActive && !isAppInBackground {
            startLocationUpdates()
        }
    }
    
    // MARK: - Location Persistence
    
    /// Saves the current location to UserDefaults for persistence across app launches
    /// Uses StorageManager for consistent UserDefaults management
    private func saveDeviceLocation(_ location: CLLocation) {
        StorageManager.saveToUserDefaults(location.coordinate.latitude, forKey: lastDeviceLatKey)
        StorageManager.saveToUserDefaults(location.coordinate.longitude, forKey: lastDeviceLonKey)
        StorageManager.saveToUserDefaults(location.timestamp.timeIntervalSince1970, forKey: lastDeviceCoordTimestamp)
        
        #if DEBUG
        print("💾 Saved Latest Device Location to UserDefaults: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        #endif
    }
    
    /// Saves the lookup location to UserDefaults for persistence across app launches
    /// Uses StorageManager for consistent UserDefaults management
    func saveLookupLocation(_ location: CLLocation) {
        StorageManager.saveToUserDefaults(location.coordinate.latitude, forKey: lastLookupLatKey)
        StorageManager.saveToUserDefaults(location.coordinate.longitude, forKey: lastLookupLonKey)
        StorageManager.saveToUserDefaults(location.timestamp.timeIntervalSince1970, forKey: lastLookupCoordTimestamp)
        
        // Update the published property
        lookupLocation = location
        
        #if DEBUG
        print("💾 Saved Latest Lookup Location to UserDefaults: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        #endif
    }
    
    /// Loads the last saved location from UserDefaults
    /// This allows the app to start with the user's last known location
    /// Uses StorageManager for consistent UserDefaults management
    private func loadLastSavedDeviceLocation() {
        guard StorageManager.existsInUserDefaults(forKey: lastDeviceLatKey),
              StorageManager.existsInUserDefaults(forKey: lastDeviceLonKey) else {
            #if DEBUG
            print("ℹ️ No saved location found in UserDefaults")
            #endif
            return
        }
        
        guard let latitudeValue = StorageManager.loadFromUserDefaults(forKey: lastDeviceLatKey, as: Double.self),
              let longitudeValue = StorageManager.loadFromUserDefaults(forKey: lastDeviceLonKey, as: Double.self),
              let timestampValue = StorageManager.loadFromUserDefaults(forKey: lastDeviceCoordTimestamp, as: TimeInterval.self) else {
            #if DEBUG
            print("ℹ️ Failed to load saved location from UserDefaults")
            #endif
            return
        }
        
        let latitude: CLLocationDegrees = latitudeValue
        let longitude: CLLocationDegrees = longitudeValue
        let timestamp = timestampValue
        
        // Validate coordinates are not zero (which would indicate no saved location)
        guard latitude != 0.0 || longitude != 0.0 else {
            #if DEBUG
            print("ℹ️ Saved location coordinates are zero, ignoring")
            #endif
            return
        }
        
        // Create CLLocation from saved coordinates
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let savedTimestamp = Date(timeIntervalSince1970: timestamp)
        
        // Create a CLLocation with saved coordinates
        // Use a default accuracy since we don't save that
        let savedLocation = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: kCLLocationAccuracyHundredMeters,
            verticalAccuracy: -1,
            timestamp: savedTimestamp
        )
        
        // Set as current location immediately
        deviceLocation = savedLocation
        
        // Load location details from LastDeviceLocation key
        if let locationDetailsString = StorageManager.loadFromUserDefaults(forKey: lastDeviceLocationKey, as: String.self),
           let locationDetailsDict = JSONValue.decodeFromString(locationDetailsString) {
            locationDetails = locationDetailsDict
            #if DEBUG
            print("📂 Loaded LastDeviceLocation details from UserDefaults")
            #endif
        }
        
        #if DEBUG
        print("📂 Loaded UserDefaults Last Device Coordinates: \(latitude), \(longitude)")
        #endif
        
        // Note: Geofence will be restored after checking cache/loading data
        // This prevents premature geofence setup that blocks initial data load
    }
    
    /// Loads the last saved lookup location from UserDefaults
    /// This allows the app to start with the user's last known lookup location
    /// Uses StorageManager for consistent UserDefaults management
    private func loadLastSavedLookupLocation() {
        guard StorageManager.existsInUserDefaults(forKey: lastLookupLatKey),
              StorageManager.existsInUserDefaults(forKey: lastLookupLonKey) else {
            #if DEBUG
            print("ℹ️ No saved lookup location found in UserDefaults")
            #endif
            return
        }
        
        guard let latitudeValue = StorageManager.loadFromUserDefaults(forKey: lastLookupLatKey, as: Double.self),
              let longitudeValue = StorageManager.loadFromUserDefaults(forKey: lastLookupLonKey, as: Double.self),
              let timestampValue = StorageManager.loadFromUserDefaults(forKey: lastLookupCoordTimestamp, as: TimeInterval.self) else {
            #if DEBUG
            print("ℹ️ Failed to load saved lookup location from UserDefaults")
            #endif
            return
        }
        
        let latitude: CLLocationDegrees = latitudeValue
        let longitude: CLLocationDegrees = longitudeValue
        let timestamp = timestampValue
        
        // Validate coordinates are not zero (which would indicate no saved location)
        guard latitude != 0.0 || longitude != 0.0 else {
            #if DEBUG
            print("ℹ️ Saved lookup location coordinates are zero, ignoring")
            #endif
            return
        }
        
        // Create CLLocation from saved coordinates
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let savedTimestamp = Date(timeIntervalSince1970: timestamp)
        
        // Create a CLLocation with saved coordinates
        // Use a default accuracy since we don't save that
        let savedLocation = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: kCLLocationAccuracyHundredMeters,
            verticalAccuracy: -1,
            timestamp: savedTimestamp
        )
        
        // Set as current lookup location immediately
        lookupLocation = savedLocation
        
        // Load location details from LastLookupLocation key
        if let lookupLocationDetailsString = StorageManager.loadFromUserDefaults(forKey: lastLookupLocationKey, as: String.self),
           let lookupLocationDetailsDict = JSONValue.decodeFromString(lookupLocationDetailsString) {
            lookupLocationDetails = lookupLocationDetailsDict
            #if DEBUG
            print("📂 Loaded LastLookupLocation details from UserDefaults")
            #endif
        }
        
        #if DEBUG
        print("📂 Loaded UserDefaults Last Lookup Coordinates: \(latitude), \(longitude)")
        #endif
    }
    
    // MARK: - Location Data Access
    
    /// Returns the current latitude if available
    var latitude: CLLocationDegrees? {
        return deviceLocation?.coordinate.latitude
    }
    
    /// Returns the current longitude if available
    var longitude: CLLocationDegrees? {
        return deviceLocation?.coordinate.longitude
    }
    
    // MARK: - Geofencing Management
    
    /// Sets up a single geofence region for monitoring
    /// - Parameters:
    ///   - identifier: Unique identifier for this geofence
    ///   - centerLat: Latitude of the geofence center
    ///   - centerLon: Longitude of the geofence center
    ///   - radius: Radius in meters (default: 100m minimum per iOS requirements)
    ///   - notifyOnEntry: Whether to notify on entry (default: false)
    ///   - notifyOnExit: Whether to notify on exit (default: true)
    func setupGeofence(
        identifier: String,
        centerLat: CLLocationDegrees,
        centerLon: CLLocationDegrees,
        radius: CLLocationDistance = 100.0,
        notifyOnEntry: Bool = false,
        notifyOnExit: Bool = true
    ) {
        // Check if region monitoring is available
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            #if DEBUG
            print("⚠️ Region monitoring not available for circular regions")
            #endif
            return
        }
        
        // Check authorization status - require "Always" for background monitoring
        guard authorizationStatus == .authorizedAlways else {
            #if DEBUG
            print("⚠️ Geofencing requires 'Always' authorization for background monitoring")
            #endif
            return
        }
        
        // Remove existing region with same identifier if present
        if let existingRegion = monitoredGeofences[identifier] {
            locationManager.stopMonitoring(for: existingRegion)
            monitoredGeofences.removeValue(forKey: identifier)
            #if DEBUG
            print("📍 Removed existing geofence with identifier: \(identifier)")
            #endif
        }
        
        // Create circular region
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let region = CLCircularRegion(
            center: center,
            radius: max(radius, 100.0),  // iOS minimum is 100m
            identifier: identifier
        )
        
        // Configure notification preferences
        region.notifyOnEntry = notifyOnEntry
        region.notifyOnExit = notifyOnExit
        
        // Start monitoring
        locationManager.startMonitoring(for: region)
        monitoredGeofences[identifier] = region
        
        #if DEBUG
        print("📍 Set up geofence: identifier=\(identifier), center=[\(centerLat), \(centerLon)], radius=\(max(radius, 100.0))m, entry=\(notifyOnEntry), exit=\(notifyOnExit)")
        #endif
    }
    
    /// Stops monitoring a specific geofence by identifier
    /// - Parameter identifier: The identifier of the geofence to stop monitoring
    func stopGeofence(identifier: String) {
        if let region = monitoredGeofences[identifier] {
            locationManager.stopMonitoring(for: region)
            monitoredGeofences.removeValue(forKey: identifier)
            #if DEBUG
            print("📍 Stopped geofence monitoring: \(identifier)")
            #endif
        }
    }
    
    /// Stops monitoring all geofences
    func stopAllGeofences() {
        for (identifier, region) in monitoredGeofences {
            locationManager.stopMonitoring(for: region)
            #if DEBUG
            print("📍 Stopped geofence: \(identifier)")
            #endif
        }
        monitoredGeofences.removeAll()
    }
    
    // MARK: - Device POIs Geofencing
    
    /// Sets up a geofence around the cached device POIs location
    /// Only refreshes data when user exits this region
    /// - Parameters:
    ///   - centerLat: Latitude of geofence center
    ///   - centerLon: Longitude of geofence center
    ///   - radius: Radius in meters (defaults to devicePOIsRefreshRadius if not provided)
    func setupDevicePOIsRefreshGeofence(centerLat: CLLocationDegrees, centerLon: CLLocationDegrees, radius: CLLocationDistance? = nil) {
        let geofenceRadius = radius ?? devicePOIsRefreshRadius
        
        setupGeofence(
            identifier: "DevicePOIsRefreshRegion",
            centerLat: centerLat,
            centerLon: centerLon,
            radius: geofenceRadius,
            notifyOnEntry: false,
            notifyOnExit: true
        )
        
        // Track device POIs region separately for easy access
        devicePOIsRefreshRegion = monitoredGeofences["DevicePOIsRefreshRegion"]
        
        // Persist geofence info for app relaunch
        saveDevicePOIsGeofence(centerLat: centerLat, centerLon: centerLon, radius: geofenceRadius)
        
        #if DEBUG
        print("📍 Set up device POIs refresh geofence: center=[\(centerLat), \(centerLon)], radius=\(geofenceRadius)m")
        #endif
    }
    
    /// Saves device POIs geofence info to UserDefaults for persistence across app launches
    private func saveDevicePOIsGeofence(centerLat: CLLocationDegrees, centerLon: CLLocationDegrees, radius: CLLocationDistance) {
        StorageManager.saveToUserDefaults(centerLat, forKey: devicePOIsGeofenceLatKey)
        StorageManager.saveToUserDefaults(centerLon, forKey: devicePOIsGeofenceLonKey)
        StorageManager.saveToUserDefaults(radius, forKey: devicePOIsGeofenceRadiusKey)
    }
    
    /// Restores device POIs geofence from UserDefaults if valid and authorization allows
    /// Returns true if geofence was restored, false otherwise
    func restoreDevicePOIsGeofenceIfValid() -> Bool {
        guard authorizationStatus == .authorizedAlways else {
            #if DEBUG
            print("⚠️ Cannot restore geofence: authorization is not 'Always'")
            #endif
            return false
        }
        
        guard StorageManager.existsInUserDefaults(forKey: devicePOIsGeofenceLatKey),
              StorageManager.existsInUserDefaults(forKey: devicePOIsGeofenceLonKey),
              StorageManager.existsInUserDefaults(forKey: devicePOIsGeofenceRadiusKey) else {
            #if DEBUG
            print("ℹ️ No saved geofence found in UserDefaults")
            #endif
            return false
        }
        
        guard let savedLat = StorageManager.loadFromUserDefaults(forKey: devicePOIsGeofenceLatKey, as: Double.self),
              let savedLon = StorageManager.loadFromUserDefaults(forKey: devicePOIsGeofenceLonKey, as: Double.self),
              let savedRadius = StorageManager.loadFromUserDefaults(forKey: devicePOIsGeofenceRadiusKey, as: Double.self) else {
            #if DEBUG
            print("ℹ️ Failed to load saved geofence from UserDefaults")
            #endif
            return false
        }
        
        // Validate coordinates are not zero
        guard savedLat != 0.0 || savedLon != 0.0 else {
            #if DEBUG
            print("ℹ️ Saved geofence coordinates are zero, ignoring")
            #endif
            return false
        }
        
        // Restore geofence
        setupDevicePOIsRefreshGeofence(centerLat: savedLat, centerLon: savedLon, radius: savedRadius)
        
        #if DEBUG
        print("✅ Restored device POIs geofence from UserDefaults: center=[\(savedLat), \(savedLon)], radius=\(savedRadius)m")
        #endif
        
        return true
    }
    
    /// Gets the saved geofence center coordinates from UserDefaults
    /// Returns a tuple (latitude, longitude) if found, nil otherwise
    func getSavedGeofenceCenter() -> (latitude: Double, longitude: Double)? {
        guard let savedLat = StorageManager.loadFromUserDefaults(forKey: devicePOIsGeofenceLatKey, as: Double.self),
              let savedLon = StorageManager.loadFromUserDefaults(forKey: devicePOIsGeofenceLonKey, as: Double.self) else {
            return nil
        }
        
        // Validate coordinates are not zero
        guard savedLat != 0.0 || savedLon != 0.0 else {
            return nil
        }
        
        return (latitude: savedLat, longitude: savedLon)
    }
    
    /// Stops monitoring the device POIs geofence
    func stopDevicePOIsRefreshGeofence() {
        stopGeofence(identifier: "DevicePOIsRefreshRegion")
        devicePOIsRefreshRegion = nil
        
        // Clear persisted geofence info
        StorageManager.removeFromUserDefaults(forKey: devicePOIsGeofenceLatKey)
        StorageManager.removeFromUserDefaults(forKey: devicePOIsGeofenceLonKey)
        StorageManager.removeFromUserDefaults(forKey: devicePOIsGeofenceRadiusKey)
    }
    
    /// Checks if device POIs geofencing is available and active
    var isDevicePOIsGeofencingActive: Bool {
        return devicePOIsRefreshRegion != nil
    }
    
    #if DEBUG
    /// Returns device POIs geofence info for debug visualization
    /// Returns nil if geofence is not set up
    var devicePOIsGeofenceDebugInfo: (center: CLLocationCoordinate2D, radius: CLLocationDistance, isMonitoring: Bool)? {
        guard let region = devicePOIsRefreshRegion else {
            return nil
        }
        // Check if region is actively being monitored
        let isMonitoring = monitoredGeofences["DevicePOIsRefreshRegion"] != nil && authorizationStatus == .authorizedAlways
        return (center: region.center, radius: region.radius, isMonitoring: isMonitoring)
    }
    #endif
    
    /// Returns both latitude and longitude as a tuple if available
    var coordinates: (latitude: CLLocationDegrees, longitude: CLLocationDegrees)? {
        guard let location = deviceLocation else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
    
    // MARK: - Geocoding Methods
    
    /// Geocodes an address string to coordinates using CLGeocoder
    /// - Parameters:
    ///   - addressString: The address or location name to geocode (e.g., "New York, NY" or "1600 Amphitheatre Parkway, Mountain View, CA")
    ///   - completion: Completion handler with optional placemark and error
    /// - Returns: The first placemark if geocoding succeeds, nil otherwise
    func geocodeAddress(_ addressString: String, completion: @escaping @Sendable (CLPlacemark?, Error?) -> Void) {
        guard !addressString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let error = NSError(domain: "LocationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Address string cannot be empty"])
            completion(nil, error)
            return
        }
        
        // Cancel any ongoing geocoding request
        geocoder.cancelGeocode()
        
        isGeocoding = true
        geocodingError = nil
        
        #if DEBUG
        print("🔍 Geocoding address: \(addressString)")
        #endif
        
        geocoder.geocodeAddressString(addressString) { [weak self] placemarks, error in
            guard let self else { return }
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                self.isGeocoding = false
                
                if let error = error {
                    self.geocodingError = error
                    #if DEBUG
                    print("❌ Geocoding failed: \(error.localizedDescription)")
                    #endif
                    completion(nil, error)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    let noResultsError = NSError(domain: "LocationManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No results found for address"])
                    self.geocodingError = noResultsError
                    #if DEBUG
                    print("⚠️ No geocoding results found for: \(addressString)")
                    #endif
                    completion(nil, noResultsError)
                    return
                }
                
                #if DEBUG
                if let location = placemark.location {
                    print("✅ Geocoded '\(addressString)' to: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                }
                #endif
                
                completion(placemark, nil)
            }
        }
    }
    
    /// Async version of geocodeAddress using async/await
    /// - Parameter addressString: The address or location name to geocode
    /// - Returns: The first placemark if geocoding succeeds
    /// - Throws: Error if geocoding fails
    func geocodeAddress(_ addressString: String) async throws -> CLPlacemark {
        return try await withCheckedThrowingContinuation { continuation in
            geocodeAddress(addressString) { placemark, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let placemark = placemark {
                    continuation.resume(returning: placemark)
                } else {
                    let unknownError = NSError(domain: "LocationManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown geocoding error"])
                    continuation.resume(throwing: unknownError)
                }
            }
        }
    }
    
    /// Constructs a JSON dictionary from location and placemark data
    /// - Parameters:
    ///   - location: The CLLocation with coordinates
    ///   - placemark: Optional CLPlacemark with address information
    /// - Returns: Dictionary with location and geocoding data
    /// Note: All fields required by backend Location model must be present
    private func constructDeviceLocation(location: CLLocation, placemark: CLPlacemark?) -> [String: JSONValue] {
        var dict: [String: Any] = [:]
        
        // Core location data (always present) - REQUIRED by backend
        dict["latitude"] = location.coordinate.latitude
        dict["longitude"] = location.coordinate.longitude
        dict["location_type"] = "device"
        
        // Include device timezone (user's current device timezone when function executes)
        
        // Capture function execution time (when this function runs, not location timestamp)
        let now = Date()
        let utcFormatter = ISO8601DateFormatter()
        utcFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dict["action_utc"] = utcFormatter.string(from: now)
        dict["action_timezone"] = TimeZone.current.identifier
        
        // Required fields for backend Location model - ensure they're always present
        // Initialize with empty strings, then populate if placemark is available
        var placeName: String = ""
        var countryCode: String = ""
        var locationString: String = ""
        
        // If placemark found, include address elements
        if let placemark = placemark {
            // Place information (required by backend)
            if let name = placemark.name {
                placeName = name
                dict["place"] = name
            }
            
            // Street address components
            var streetParts: [String] = []
            if let subThoroughfare = placemark.subThoroughfare {
                streetParts.append(subThoroughfare)
            }
            if let thoroughfare = placemark.thoroughfare {
                streetParts.append(thoroughfare)
            }
            if !streetParts.isEmpty {
                dict["street"] = streetParts.joined(separator: " ")
            }
            
            // Combine sublocality, locality, subadministrative area, administrativeArea (required by backend)
            var locationParts: [String] = []
            if let subLocality = placemark.subLocality {
                locationParts.append(subLocality)
            }
            if let locality = placemark.locality {
                locationParts.append(locality)
            }
            if let subAdministrativeArea = placemark.subAdministrativeArea {
                locationParts.append(subAdministrativeArea)
            }
            if let administrativeArea = placemark.administrativeArea {
                locationParts.append(administrativeArea)
            }
            locationString = locationParts.joined(separator: ", ")
            dict["location"] = locationString
            
            // Country information (required by backend)
            if let isoCode = placemark.isoCountryCode {
                countryCode = isoCode
                dict["country_code"] = isoCode
            }
            if let country = placemark.country {
                dict["country"] = country
            }
            
            // Additional information
            if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
                dict["areas_of_interest"] = areasOfInterest
            }
            if let inlandWater = placemark.inlandWater {
                dict["inwater"] = true
                dict["water_name"] = inlandWater
            } else if let ocean = placemark.ocean {
                dict["inwater"] = true
                dict["water_name"] = ocean
            }
            
            // Region information
            if let region = placemark.region as? CLCircularRegion {
                dict["region_lat"] = region.center.latitude
                dict["region_lon"] = region.center.longitude
                dict["region_radius"] = region.radius
            }
        }
        
        // Ensure all required fields for backend Location model are present
        // If placemark was nil or missing fields, use empty strings
        if dict["place"] == nil {
            dict["place"] = placeName.isEmpty ? "" : placeName
        }
        if dict["country_code"] == nil {
            dict["country_code"] = countryCode.isEmpty ? "" : countryCode
        }
        if dict["location"] == nil {
            dict["location"] = locationString.isEmpty ? "" : locationString
        }
        
        // Optional fields
        dict["accuracy"] = location.horizontalAccuracy
        
        // Construct full address string (at the end)
        var addressParts: [String] = []
        if let street = dict["street"] as? String {
            addressParts.append(street)
        }
        if let location = dict["location"] as? String {
            addressParts.append(location)
        }
        if let country = dict["country"] as? String {
            addressParts.append(country)
        }
        if !addressParts.isEmpty {
            dict["full_address"] = addressParts.joined(separator: ", ")
        }
        
        // Convert dict to JSONValue
        guard let jsonValue = JSONValue.dictionary(from: dict) else {
            #if DEBUG
            print("⚠️ Failed to convert location dict to JSONValue")
            #endif
            return [:]
        }
        
        // Save the final dict as JSON string to UserDefaults
        if let jsonString = JSONValue.encodeToString(jsonValue) {
            StorageManager.saveToUserDefaults(jsonString, forKey: lastDeviceLocationKey)
            #if DEBUG
            print("💾 Saved LastDeviceLocation to UserDefaults")
            #endif
        }
        
        return jsonValue
    }
    
    /// Constructs a JSON dictionary from placemark data for lookup/search results
    /// - Parameters:
    ///   - location: The CLLocation with coordinates
    ///   - placemark: CLPlacemark with address information from MKLocalSearch
    ///   - mapItemName: Optional name from MKMapItem
    /// - Returns: Dictionary with location and address data
    func constructLookupLocation(location: CLLocation, placemark: CLPlacemark, mapItemName: String?) -> [String: JSONValue] {
        var dict: [String: Any] = [:]
        
        // Core location data (always present)
        dict["latitude"] = location.coordinate.latitude
        dict["longitude"] = location.coordinate.longitude
        dict["accuracy"] = location.horizontalAccuracy
        dict["location_type"] = "lookup"
        
        
        // Capture function execution time (when this function runs, not location timestamp)
        let now = Date()
        let utcFormatter = ISO8601DateFormatter()
        utcFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dict["action_utc"] = utcFormatter.string(from: now)
        dict["action_timezone"] = TimeZone.current.identifier
        
        // Place information
        if let name = mapItemName {
            dict["place"] = name
        } else if let name = placemark.name {
            dict["place"] = name
        }
        
        // Street address components
        var streetParts: [String] = []
        if let subThoroughfare = placemark.subThoroughfare {
            streetParts.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            streetParts.append(thoroughfare)
        }
        if !streetParts.isEmpty {
            dict["street"] = streetParts.joined(separator: " ")
        }
        
        // Combine sublocality, locality, subadministrative area, administrativeArea
        var locationParts: [String] = []
        if let subLocality = placemark.subLocality {
            locationParts.append(subLocality)
        }
        if let locality = placemark.locality {
            locationParts.append(locality)
        }
        if let subAdministrativeArea = placemark.subAdministrativeArea {
            locationParts.append(subAdministrativeArea)
        }
        if let administrativeArea = placemark.administrativeArea {
            locationParts.append(administrativeArea)
        }
        if !locationParts.isEmpty {
            dict["location"] = locationParts.joined(separator: ", ")
        }
        
        // Country information
        if let countryCode = placemark.isoCountryCode {
            dict["country_code"] = countryCode
        }
        if let country = placemark.country {
            dict["country"] = country
        }
        
        // Additional information
        if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
            dict["areas_of_interest"] = areasOfInterest
        }
        if let inlandWater = placemark.inlandWater {
            dict["inwater"] = true
            dict["water_name"] = inlandWater
        } else if let ocean = placemark.ocean {
            dict["inwater"] = true
            dict["water_name"] = ocean
        }
        
        // Region information
        if let region = placemark.region as? CLCircularRegion {
            dict["region_lat"] = region.center.latitude
            dict["region_lon"] = region.center.longitude
            dict["region_radius"] = region.radius
        }
        
        // Construct full address string (at the end)
        var addressParts: [String] = []
        if let street = dict["street"] as? String {
            addressParts.append(street)
        }
        if let location = dict["location"] as? String {
            addressParts.append(location)
        }
        if let country = dict["country"] as? String {
            addressParts.append(country)
        }
        if !addressParts.isEmpty {
            dict["full_address"] = addressParts.joined(separator: ", ")
        }
        
        // Convert dict to JSONValue
        guard let jsonValue = JSONValue.dictionary(from: dict) else {
            #if DEBUG
            print("⚠️ Failed to convert lookup location dict to JSONValue")
            #endif
            return [:]
        }
        
        // Save the final dict as JSON string to UserDefaults
        if let jsonString = JSONValue.encodeToString(jsonValue) {
            StorageManager.saveToUserDefaults(jsonString, forKey: lastLookupLocationKey)
            #if DEBUG
            print("💾 Saved LastLookupLocation to UserDefaults")
            #endif
        }
        
        return jsonValue
    }
    
    /// Geocodes a location and constructs a NewLocation-like structure matching the Python schema
    /// - Parameter location: The CLLocation to geocode
    /// - Returns: A dictionary matching the NewLocation schema with coordinate and location details
    /// - Throws: Error if geocoding fails
    func constructNewLocation(from location: CLLocation) async throws -> [String: JSONValue] {
        // Reverse geocode the location
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        let placemark = placemarks.first
        
        // Print complete geocoded results for evaluation
        #if DEBUG
        print("🔍 Complete Geocoded Results:")
        print("   Number of placemarks: \(placemarks.count)")
        if let placemark = placemark {
            print("   📍 Placemark Details:")
            print("      - name: \(placemark.name ?? "nil")")
            print("      - thoroughfare: \(placemark.thoroughfare ?? "nil")")
            print("      - subThoroughfare: \(placemark.subThoroughfare ?? "nil")")
            print("      - locality: \(placemark.locality ?? "nil")")
            print("      - subLocality: \(placemark.subLocality ?? "nil")")
            print("      - administrativeArea: \(placemark.administrativeArea ?? "nil")")
            print("      - subAdministrativeArea: \(placemark.subAdministrativeArea ?? "nil")")
            print("      - postalCode: \(placemark.postalCode ?? "nil")")
            print("      - country: \(placemark.country ?? "nil")")
            print("      - isoCountryCode: \(placemark.isoCountryCode ?? "nil")")
            print("      - inlandWater: \(placemark.inlandWater ?? "nil")")
            print("      - ocean: \(placemark.ocean ?? "nil")")
            print("      - areasOfInterest: \(placemark.areasOfInterest?.joined(separator: ", ") ?? "nil")")
            print("      - timeZone: \(placemark.timeZone?.identifier ?? "nil")")
            print("      - region: \(placemark.region?.identifier ?? "nil")")
        } else {
            print("   ⚠️ No placemark available")
        }
        print("   📍 Location Details:")
        print("      - latitude: \(location.coordinate.latitude)")
        print("      - longitude: \(location.coordinate.longitude)")
        print("      - altitude: \(location.altitude)")
        print("      - horizontalAccuracy: \(location.horizontalAccuracy)")
        print("      - verticalAccuracy: \(location.verticalAccuracy)")
        print("      - timestamp: \(location.timestamp)")
        #endif
        
        // Build coordinate object
        var coordinateDict: [String: JSONValue] = [
            "lat": .double(location.coordinate.latitude),
            "lng": .double(location.coordinate.longitude)
        ]
        if location.verticalAccuracy > 0 {
            coordinateDict["alt"] = .double(location.altitude)
        }
        
        // Build NewLocation structure (matching Python schema)
        var newLocationDict: [String: JSONValue] = [
            "coordinate": .dictionary(coordinateDict)
        ]
        
        // Add optional fields from placemark
        if let placemark = placemark {
            if let countryCode = placemark.isoCountryCode {
                newLocationDict["country_code"] = .string(countryCode)
            }
            
            // Build subdivisions string using same pattern as constructDeviceLocation
            // Order: subLocality, locality, subAdministrativeArea, administrativeArea
            var subdivisionsParts: [String] = []
            if let subLocality = placemark.subLocality {
                subdivisionsParts.append(subLocality)
            }
            if let locality = placemark.locality {
                subdivisionsParts.append(locality)
            }
            if let subAdministrativeArea = placemark.subAdministrativeArea {
                subdivisionsParts.append(subAdministrativeArea)
            }
            if let administrativeArea = placemark.administrativeArea {
                subdivisionsParts.append(administrativeArea)
            }
            if !subdivisionsParts.isEmpty {
                newLocationDict["subdivisions"] = .string(subdivisionsParts.joined(separator: ", "))
            }
            
            if let name = placemark.name {
                newLocationDict["place_name"] = .string(name)
            }
            
            if let country = placemark.country {
                newLocationDict["country_name"] = .string(country)
            }
            
            // Get timezone from placemark
            if let timeZone = placemark.timeZone {
                newLocationDict["timezone"] = .string(timeZone.identifier)
            }
        }
        
        // If timezone not available from placemark, use device timezone as fallback
        if newLocationDict["timezone"] == nil {
            newLocationDict["timezone"] = .string(TimeZone.current.identifier)
        }
        
        // Print constructed NewLocation structure for comparison
        #if DEBUG
        print("✅ Constructed NewLocation Structure:")
        print("   - coordinate: \(newLocationDict["coordinate"] != nil ? "present" : "missing")")
        if case .dictionary(let coordDict) = newLocationDict["coordinate"] {
            print("      * lat: \(coordDict["lat"] != nil ? "present" : "missing")")
            print("      * lng: \(coordDict["lng"] != nil ? "present" : "missing")")
            print("      * alt: \(coordDict["alt"] != nil ? "present" : "missing")")
        }
        print("   - timezone: \(newLocationDict["timezone"] != nil ? "present" : "missing")")
        print("   - country_code: \(newLocationDict["country_code"] != nil ? "present" : "missing")")
        print("   - country_name: \(newLocationDict["country_name"] != nil ? "present" : "missing")")
        print("   - place_name: \(newLocationDict["place_name"] != nil ? "present" : "missing")")
        print("   - subdivisions: \(newLocationDict["subdivisions"] != nil ? "present" : "missing")")
        #endif
        
        return newLocationDict
    }
    
    /// Reverse geocodes the current user location and returns a JSON dictionary
    /// - Parameter completion: Completion handler with optional dictionary and error
    func reverseGeocodeUserLocation(completion: @escaping @Sendable ([String: JSONValue]?, Error?) -> Void) {
        #if DEBUG
        print("🔍 reverseGeocodeUserLocation() called")
        print("   deviceLocation: \(deviceLocation != nil ? "available" : "nil")")
        if let location = deviceLocation {
            print("   Coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
        #endif
        
        guard let location = deviceLocation else {
            #if DEBUG
            print("❌ No user location available for reverse geocoding")
            #endif
            let error = NSError(domain: "LocationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user location available"])
            completion(nil, error)
            return
        }
        
        // Cancel any ongoing geocoding request
        geocoder.cancelGeocode()
        
        isGeocoding = true
        geocodingError = nil
        
        #if DEBUG
        print("🌐 Starting reverse geocoding request...")
        #endif
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                self.isGeocoding = false
                
                #if DEBUG
                let latitude = location.coordinate.latitude
                let longitude = location.coordinate.longitude
                
                print("\n" + String(repeating: "=", count: 80))
                print("📍 REVERSE GEOCODING USER LOCATION")
                print(String(repeating: "=", count: 80))
                print("Coordinates: \(latitude), \(longitude)")
                print("Accuracy: ±\(Int(location.horizontalAccuracy))m")
                print("Timestamp: \(location.timestamp)")
                print(String(repeating: "-", count: 80))
                #endif
                
                if let error = error {
                    self.geocodingError = error
                    #if DEBUG
                    print("❌ Reverse Geocoding Error:")
                    print("   Description: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("   Domain: \(nsError.domain)")
                        print("   Code: \(nsError.code)")
                        print("   UserInfo: \(nsError.userInfo)")
                        
                        // Map CoreLocation error codes to human-readable descriptions
                        if nsError.domain == "kCLErrorDomain" {
                            switch nsError.code {
                            case 0:
                                print("   Error Type: kCLErrorLocationUnknown - Location could not be determined")
                            case 1:
                                print("   Error Type: kCLErrorDenied - Location services denied")
                            case 2:
                                print("   Error Type: kCLErrorNetwork - Network error or service unavailable")
                            case 3:
                                print("   Error Type: kCLErrorHeadingFailure - Heading could not be determined")
                            case 4:
                                print("   Error Type: kCLErrorRegionMonitoringDenied - Region monitoring denied")
                            case 5:
                                print("   Error Type: kCLErrorRegionMonitoringFailure - Region monitoring failed")
                            case 6:
                                print("   Error Type: kCLErrorRegionMonitoringSetupDelayed - Region monitoring setup delayed")
                            case 7:
                                print("   Error Type: kCLErrorRegionMonitoringResponseDelayed - Region monitoring response delayed")
                            case 8:
                                print("   Error Type: kCLErrorGeocodeFoundNoResult - Geocode found no result")
                            case 9:
                                print("   Error Type: kCLErrorGeocodeFoundPartialResult - Geocode found partial result")
                            case 10:
                                print("   Error Type: kCLErrorGeocodeCanceled - Geocode request canceled")
                            default:
                                print("   Error Type: Unknown CoreLocation error code")
                            }
                        }
                    }
                    print(String(repeating: "=", count: 80) + "\n")
                    #endif
                    // Still return dict with location data even if geocoding fails
                    let dict = self.constructDeviceLocation(location: location, placemark: nil)
                    // Update locationDetails even on error (with location data only)
                    self.locationDetails = dict
                    #if DEBUG
                    print("✅ Updated locationDetails in LocationManager (location only, no placemark)")
                    #endif
                    completion(dict, error)
                    return
                }
                
                // Use first placemark if available
                let placemark = placemarks?.first
                
                #if DEBUG
                if let placemarks = placemarks, !placemarks.isEmpty {
                    print("✅ Found \(placemarks.count) placemark(s):\n")
                    
                    for (index, placemark) in placemarks.enumerated() {
                        print(String(repeating: "-", count: 80))
                        print("📍 PLACEMARK #\(index + 1)")
                        print(String(repeating: "-", count: 80))
                        
                        // Location coordinates
                        if let placemarkLocation = placemark.location {
                            print("Coordinates: \(placemarkLocation.coordinate.latitude), \(placemarkLocation.coordinate.longitude)")
                            print("Accuracy: ±\(Int(placemarkLocation.horizontalAccuracy))m")
                        }
                        
                        // Address components
                        print("\n📋 Address Components:")
                        if let name = placemark.name {
                            print("  • Name: \(name)")
                        }
                        if let thoroughfare = placemark.thoroughfare {
                            print("  • Street: \(thoroughfare)")
                        }
                        if let subThoroughfare = placemark.subThoroughfare {
                            print("  • Street Number: \(subThoroughfare)")
                        }
                        if let subLocality = placemark.subLocality {
                            print("  • Sub-locality: \(subLocality)")
                        }
                        if let locality = placemark.locality {
                            print("  • City/Locality: \(locality)")
                        }
                        if let subAdministrativeArea = placemark.subAdministrativeArea {
                            print("  • Sub-administrative Area: \(subAdministrativeArea)")
                        }
                        if let administrativeArea = placemark.administrativeArea {
                            print("  • State/Province: \(administrativeArea)")
                        }
                        if let postalCode = placemark.postalCode {
                            print("  • Postal Code: \(postalCode)")
                        }
                        if let country = placemark.country {
                            print("  • Country: \(country)")
                        }
                        if let countryCode = placemark.isoCountryCode {
                            print("  • Country Code: \(countryCode)")
                        }
                        if let inlandWater = placemark.inlandWater {
                            print("  • Inland Water: \(inlandWater)")
                        }
                        if let ocean = placemark.ocean {
                            print("  • Ocean: \(ocean)")
                        }
                        if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
                            print("  • Areas of Interest: \(areasOfInterest.joined(separator: ", "))")
                        }
                        
                        // Region
                        if let region = placemark.region {
                            print("\n🌍 Region:")
                            print("  • Identifier: \(region.identifier)")
                            if let circularRegion = region as? CLCircularRegion {
                                print("  • Center: \(circularRegion.center.latitude), \(circularRegion.center.longitude)")
                                print("  • Radius: \(Int(circularRegion.radius))m")
                            }
                        }
                        
                        // Timezone
                        if let timeZone = placemark.timeZone {
                            print("\n🕐 Timezone: \(timeZone.identifier)")
                        }
                        
                        print()
                    }
                    
                    print(String(repeating: "=", count: 80))
                    print("✅ Reverse geocoding complete")
                    print(String(repeating: "=", count: 80) + "\n")
                } else {
                    print("⚠️ No placemarks found")
                    print(String(repeating: "=", count: 80) + "\n")
                }
                #endif
                
                // Construct and return the dictionary
                let dict = self.constructDeviceLocation(location: location, placemark: placemark)
                
                // Update locationDetails
                self.locationDetails = dict
                
                #if DEBUG
                print("📦 Constructed location dict: \(dict)")
                print("✅ Updated locationDetails in LocationManager")
                if let locationString = dict["location"]?.stringValue {
                  print("   Location string: \(locationString)")
                }
                if let countryName = dict["country_name"]?.stringValue {
                  print("   Country name: \(countryName)")
                }
                #endif
                
                completion(dict, nil)
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            let updateType = self.isUsingSignificantChanges ? "significant change" : "continuous"
            let accuracy = location.horizontalAccuracy
            print("📍 Location updated (\(updateType)): \(location.coordinate.latitude), \(location.coordinate.longitude) (accuracy: ±\(Int(accuracy))m)")
            
            self.deviceLocation = location
            self.saveDeviceLocation(location)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("❌ Location manager failed with error: \(error.localizedDescription)")
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        let accuracyStatus: CLAccuracyAuthorization? = {
            if #available(iOS 14.0, *) {
                return manager.accuracyAuthorization
            }
            return nil
        }()
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            let oldStatus = self.authorizationStatus
            
            guard newStatus != oldStatus else {
                return
            }
            
            self.authorizationStatus = newStatus
            self.isLocationPermissionGranted = newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways
            
            print("🔄 Location authorization changed to: \(newStatus.rawValue)")
            
            if #available(iOS 14.0, *), let accuracyStatus {
                if accuracyStatus == .reducedAccuracy {
                    print("⚠️ Location accuracy is reduced - requesting precise location")
                    self.requestPreciseLocationIfNeeded()
                } else {
                    print("✅ Precise location authorized")
                }
            }
            
            switch newStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                print("✅ Location permission granted")
                if #available(iOS 14.0, *) {
                    // Already handled above
                } else {
                    self.requestPreciseLocationIfNeeded()
                }
                self.startLocationUpdates()
            case .denied:
                print("❌ Location permission denied by user")
            case .restricted:
                print("❌ Location permission restricted by system")
            case .notDetermined:
                print("⏳ Location permission not determined yet")
            @unknown default:
                print("❓ Unknown location permission status: \(newStatus.rawValue)")
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region.identifier == "DevicePOIsRefreshRegion" {
            #if DEBUG
            print("🚪 User exited device POIs refresh region - triggering refresh")
            #endif
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.shouldRefreshDevicePOIs = true
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.shouldRefreshDevicePOIs = false
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        #if DEBUG
        print("🚪 User entered geofence region: \(region.identifier)")
        #endif
    }
    
    // MARK: - Debug Helpers
    
    #if DEBUG
    /// Debug function to print all UserDefaults data stored by this app
    /// Call from Xcode debug console: po LocationManager().debugPrintAllUserDefaults()
    func debugPrintAllUserDefaults() {
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        
        print("📦 UserDefaults Contents for Unheard Path:")
        print("Total keys in UserDefaults: \(dict.count)")
        print("---")
        
        // Filter to only our app's keys (StorageManager adds "UHP." prefix)
        let appKeys = dict.keys.filter { key in
            key.hasPrefix("UHP.")
        }
        
        print("App-specific keys: \(appKeys.count)")
        print("---")
        
        for key in appKeys.sorted() {
            if let value = dict[key] {
                // Calculate approximate size
                let valueString = "\(value)"
                let size = valueString.data(using: .utf8)?.count ?? 0
                
                print("🔑 \(key)")
                print("   Size: \(size) bytes (~\(size / 1024) KB)")
                
                // Print small values, summarize large ones
                if size < 500 {
                    print("   Value: \(valueString.prefix(200))")
                } else {
                    if let dictValue = value as? [String: Any] {
                        print("   Value: [Dictionary with \(dictValue.count) keys]")
                        if let features = dictValue["features"] as? [[String: Any]] {
                            print("   Features count: \(features.count)")
                        }
                    } else {
                        print("   Value: [Large object, \(size) bytes]")
                    }
                }
                print("")
            }
        }
        
        // Calculate total size
        let totalSize = appKeys.compactMap { key -> Int? in
            guard let value = dict[key] else { return nil }
            let valueString = "\(value)"
            return valueString.data(using: .utf8)?.count
        }.reduce(0, +)
        
        print("---")
        print("📊 Summary:")
        print("   Total app keys: \(appKeys.count)")
        print("   Total size: \(totalSize) bytes (~\(totalSize / 1024) KB)")
        print("   Estimated limit: ~1-2 MB (you're using \(String(format: "%.1f", Double(totalSize) / 1024 / 1024 * 100))% of 1 MB)")
    }
    
    /// Debug function to clear all cached location data
    func debugClearAllCache() {
        let defaults = UserDefaults.standard
        // StorageManager adds "UHP." prefix, so we need to look for keys with that prefix
        let keys = defaults.dictionaryRepresentation().keys.filter { key in
            key.hasPrefix("UHP.") && (
                key.contains("PlacesCache_") || key.contains("wiki_")
            )
        }
        // Remove the "UHP." prefix when calling StorageManager.removeFromUserDefaults
        keys.forEach { fullKey in
            let keyWithoutPrefix = fullKey.hasPrefix("UHP.") ? String(fullKey.dropFirst(4)) : fullKey
            StorageManager.removeFromUserDefaults(forKey: keyWithoutPrefix)
        }
        print("🗑️ Cleared \(keys.count) cache entries")
    }
    #endif
}

