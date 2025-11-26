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

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isLocationPermissionGranted: Bool = false
    
    // Tracking mode state
    private var isTrackingActive = false
    private var isUsingSignificantChanges = false
    private var isAppInBackground = false
    
    // Configuration constants (Google Maps strategy)
    private let activeDistanceFilter: CLLocationDistance = 50.0  // Update every 50 meters when active
    private let backgroundDistanceFilter: CLLocationDistance = 100.0  // Update every 100 meters in background
    private let activeAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters  // Moderate accuracy when active
    private let backgroundAccuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer  // Lower accuracy in background
    private let highAccuracyMode: CLLocationAccuracy = kCLLocationAccuracyBest  // High accuracy for navigation
    
    // UserDefaults keys for persisting location
    private let lastLocationLatitudeKey = "LocationManager.lastLocation.latitude"
    private let lastLocationLongitudeKey = "LocationManager.lastLocation.longitude"
    private let lastLocationTimestampKey = "LocationManager.lastLocation.timestamp"
    
    override init() {
        super.init()
        locationManager.delegate = self
        // Start with moderate accuracy (Google Maps strategy)
        locationManager.desiredAccuracy = activeAccuracy
        locationManager.distanceFilter = activeDistanceFilter
        authorizationStatus = locationManager.authorizationStatus
        isLocationPermissionGranted = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        
        // Load last saved location immediately
        loadLastSavedLocation()
        
        // Observe app lifecycle to adapt tracking strategy
        setupAppLifecycleObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App Lifecycle Observers
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        isAppInBackground = true
        print("📱 App entered background - switching to battery-efficient tracking")
        switchToBackgroundTracking()
    }
    
    @objc private func appWillEnterForeground() {
        isAppInBackground = false
        print("📱 App entering foreground - switching to active tracking")
        switchToActiveTracking()
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
                    if let error = error {
                        print("❌ Failed to request precise location: \(error.localizedDescription)")
                    } else {
                        print("✅ Precise location permission granted")
                        self?.startLocationUpdates()
                    }
                }
            } else {
                print("✅ Precise location already authorized")
            }
        }
    }
    
    // MARK: - Location Tracking Methods
    
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
        locationManager.desiredAccuracy = activeAccuracy
        locationManager.distanceFilter = activeDistanceFilter
        
        // Start continuous updates
        if !isTrackingActive {
            locationManager.startUpdatingLocation()
            isTrackingActive = true
            print("📍 Started active location tracking (accuracy: \(activeAccuracy)m, filter: \(activeDistanceFilter)m)")
        } else {
            print("📍 Updated active tracking configuration")
        }
    }
    
    /// Switches to background tracking mode (app in background)
    /// Uses significant location changes for battery efficiency
    private func switchToBackgroundTracking() {
        guard authorizationStatus == .authorizedAlways else {
            // If we don't have "Always" permission, stop tracking in background
            if isTrackingActive {
                locationManager.stopUpdatingLocation()
                isTrackingActive = false
                print("⏸️ Stopped location tracking (no 'Always' permission for background)")
            }
            return
        }
        
        // Stop continuous updates
        if isTrackingActive {
            locationManager.stopUpdatingLocation()
            isTrackingActive = false
            print("🔄 Stopped continuous location updates")
        }
        
        // Start significant location changes if available
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            if !isUsingSignificantChanges {
                locationManager.startMonitoringSignificantLocationChanges()
                isUsingSignificantChanges = true
                print("📍 Started significant location change monitoring (battery-efficient)")
            }
        } else {
            print("⚠️ Significant location change monitoring not available")
        }
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
        print("📍 Disabled high accuracy mode, returned to adaptive strategy")
        
        // Restart tracking if it was active
        if !isTrackingActive && !isAppInBackground {
            startLocationUpdates()
        }
    }
    
    // MARK: - Location Persistence
    
    /// Saves the current location to UserDefaults for persistence across app launches
    private func saveLocation(_ location: CLLocation) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: lastLocationLatitudeKey)
        defaults.set(location.coordinate.longitude, forKey: lastLocationLongitudeKey)
        defaults.set(location.timestamp.timeIntervalSince1970, forKey: lastLocationTimestampKey)
        defaults.synchronize()
        
        #if DEBUG
        print("💾 Saved location to UserDefaults: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        #endif
    }
    
    /// Loads the last saved location from UserDefaults
    /// This allows the app to start with the user's last known location
    private func loadLastSavedLocation() {
        let defaults = UserDefaults.standard
        
        guard defaults.object(forKey: lastLocationLatitudeKey) != nil,
              defaults.object(forKey: lastLocationLongitudeKey) != nil else {
            #if DEBUG
            print("ℹ️ No saved location found in UserDefaults")
            #endif
            return
        }
        
        let latitude = defaults.double(forKey: lastLocationLatitudeKey)
        let longitude = defaults.double(forKey: lastLocationLongitudeKey)
        let timestamp = defaults.double(forKey: lastLocationTimestampKey)
        
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
        currentLocation = savedLocation
        
        #if DEBUG
        print("📂 Loaded saved location from UserDefaults: \(latitude), \(longitude)")
        print("   Saved at: \(savedTimestamp)")
        #endif
    }
    
    // MARK: - Location Data Access
    
    /// Returns the current latitude if available
    var latitude: Double? {
        return currentLocation?.coordinate.latitude
    }
    
    /// Returns the current longitude if available
    var longitude: Double? {
        return currentLocation?.coordinate.longitude
    }
    
    /// Returns both latitude and longitude as a tuple if available
    var coordinates: (latitude: Double, longitude: Double)? {
        guard let location = currentLocation else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update current location
        currentLocation = location
        
        // Save location to UserDefaults for persistence
        saveLocation(location)
        
        // Log update with context
        let updateType = isUsingSignificantChanges ? "significant change" : "continuous"
        let accuracy = location.horizontalAccuracy
        print("📍 Location updated (\(updateType)): \(location.coordinate.latitude), \(location.coordinate.longitude) (accuracy: ±\(Int(accuracy))m)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        isLocationPermissionGranted = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        
        print("🔄 Location authorization changed to: \(authorizationStatus.rawValue)")
        
        // Check accuracy authorization for iOS 14+
        if #available(iOS 14.0, *) {
            let accuracyStatus = manager.accuracyAuthorization
            if accuracyStatus == .reducedAccuracy {
                print("⚠️ Location accuracy is reduced - requesting precise location")
                requestPreciseLocationIfNeeded()
            } else {
                print("✅ Precise location authorized")
            }
        }
        
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Location permission granted")
            if #available(iOS 14.0, *) {
                // Already handled above
            } else {
                requestPreciseLocationIfNeeded()
            }
            // Start with adaptive strategy based on current app state
            startLocationUpdates()
        case .denied:
            print("❌ Location permission denied by user")
        case .restricted:
            print("❌ Location permission restricted by system")
        case .notDetermined:
            print("⏳ Location permission not determined yet")
        @unknown default:
            print("❓ Unknown location permission status: \(authorizationStatus.rawValue)")
        }
    }
}

