//
//  TrackingManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

/// Manages location tracking functionality including permissions, active/background tracking modes,
/// and high accuracy mode. Handles only location tracking - excludes geofencing and lookup location management.
@MainActor
class TrackingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    // Published state
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var deviceLocation: CLLocation?
    @Published var isLocationPermissionGranted: Bool = false
    
    // Tracking mode state
    private var isTrackingActive = false
    private var isUsingSignificantChanges = false
    
    // App lifecycle manager (optional, set after initialization)
    // Auto-registers with AppLifecycleManager when set
    weak var appLifecycleManager: AppLifecycleManager? {
        didSet {
            guard let appLifecycleManager = appLifecycleManager else { return }
            // Auto-register when appLifecycleManager is set
            appLifecycleManager.registerLifecycleHandler(self)
        }
    }
    
    // Use AppLifecycleManager's state as single source of truth
    // Removes duplicate state tracking
    private var isAppInBackground: Bool {
        appLifecycleManager?.isAppInBackground ?? false
    }
    
    // Configuration constants (Google Maps strategy)
    private let activeDistanceFilter: CLLocationDistance = 50.0  // Update every 50 meters when active
    private let backgroundDistanceFilter: CLLocationDistance = 100.0  // Update every 100 meters in background
    private let activeAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters  // Moderate accuracy when active
    private let backgroundAccuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer  // Lower accuracy in background
    private let highAccuracyMode: CLLocationAccuracy = kCLLocationAccuracyBest  // High accuracy for navigation
    
    // UserDefaults keys for widget state
    // Note: StorageManager will automatically add "UHP." prefix
    private let appStateIsInBackgroundKey = "AppState.isInBackground"
    private let trackingModeKey = "TrackingMode.current"
    
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
    }
    
    // MARK: - Permission Management
    
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
    }
    
    // MARK: - App Lifecycle Methods
    
    /// Called when the app enters the background
    /// Switches to battery-efficient tracking mode
    /// This method is called from @MainActor context (AppLifecycleManager is @MainActor)
    /// 
    /// Note: AppLifecycleManager already sets isAppInBackground = true, so we use its state
    func appDidEnterBackground() {
        // Save app state to UserDefaults for widget
        // Note: AppLifecycleManager.isAppInBackground is already true at this point
        StorageManager.saveToUserDefaults(true, forKey: appStateIsInBackgroundKey)
        #if DEBUG
        // Verify the value was saved correctly
        let savedValue = StorageManager.loadFromUserDefaults(forKey: appStateIsInBackgroundKey, as: Bool.self)
        print("💾 Set UserDefaults: isInBackground = \(savedValue ?? false)")
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
    /// 
    /// Note: AppLifecycleManager already sets isAppInBackground = false, so we use its state
    func appWillEnterForeground() {
        // Save app state to UserDefaults for widget
        // Note: AppLifecycleManager.isAppInBackground is already false at this point
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
    
    // MARK: - High Accuracy Mode
    
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
    
    // MARK: - Location Data Access
    
    /// Returns the current latitude if available
    var latitude: CLLocationDegrees? {
        return deviceLocation?.coordinate.latitude
    }
    
    /// Returns the current longitude if available
    var longitude: CLLocationDegrees? {
        return deviceLocation?.coordinate.longitude
    }
    
    /// Returns both latitude and longitude as a tuple if available
    var coordinates: (latitude: CLLocationDegrees, longitude: CLLocationDegrees)? {
        guard let location = deviceLocation else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            let updateType = self.isUsingSignificantChanges ? "significant change" : "continuous"
            let accuracy = location.horizontalAccuracy
            print("📍 Location updated (\(updateType)): \(location.coordinate.latitude), \(location.coordinate.longitude) (accuracy: ±\(Int(accuracy))m)")
            
            // Update deviceLocation property
            self.deviceLocation = location
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
}

// MARK: - AppLifecycleHandler Conformance

extension TrackingManager: @MainActor AppLifecycleHandler {
    // Methods appDidEnterBackground() and appWillEnterForeground() already exist above
    // Protocol conformance is automatic - no additional implementation needed
}
