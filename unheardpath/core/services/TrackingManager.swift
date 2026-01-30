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
import core

/// Manages location tracking functionality including permissions, foreground/background tracking modes,
/// and high accuracy mode. Handles only location tracking - excludes geofencing and lookup location management.
@MainActor
class TrackingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let coreLocationManager = CLLocationManager()
    
    // Published state
    @Published var deviceLocation: CLLocation?
    
    /// Current authorization status (read from coreLocationManager)
    var authorizationStatus: CLAuthorizationStatus {
        coreLocationManager.authorizationStatus
    }
    
    /// Computed property indicating if location permission is granted
    var isLocationPermissionGranted: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
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
    
    // EventManager reference (set after initialization)
    weak var eventManager: EventManager?
    
    // LocationManager reference (set after initialization, for constructing NewLocation dicts)
    weak var locationManager: LocationManager?
    
    // Use AppLifecycleManager's state as single source of truth
    // Removes duplicate state tracking
    private var isAppInBackground: Bool {
        appLifecycleManager?.isAppInBackground ?? false
    }
    
    // Configuration constants (Google Maps strategy)
    private let foregroundDistanceFilter: CLLocationDistance = 50.0  // Update every 50 meters when in foreground
    private let foregroundAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters  // Moderate accuracy when in foreground
    
    private let trackingModeKey = "TrackingMode.current"
    
    // Logger for error and debug logging
    private let logger: Logger
    
    init(logger: Logger = AppLifecycleManager.sharedLogger) {
        self.logger = logger
        super.init()
        coreLocationManager.delegate = self
    }
    
    // MARK: - Permission Management
    
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            // Request "when in use" authorization first
            coreLocationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission already granted, start location updates
            startLocationUpdates()
        case .denied, .restricted:
            logger.error("Location permission denied or restricted", handlerType: "TrackingManager", error: nil)
        @unknown default:
            logger.warning("Unknown location authorization status", handlerType: "TrackingManager")
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
            switchToForegroundTracking()
        }
    }
    
    /// Switches to foreground tracking mode (app in foreground)
    /// Uses continuous GPS with moderate accuracy and distance filter
    private func switchToForegroundTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        // Stop significant location changes if active
        if isUsingSignificantChanges {
            coreLocationManager.stopMonitoringSignificantLocationChanges()
            isUsingSignificantChanges = false
            logger.debug("Stopped significant location changes")
        }
        
        coreLocationManager.desiredAccuracy = foregroundAccuracy
        coreLocationManager.distanceFilter = foregroundDistanceFilter
        
        // Start continuous updates
        if !isTrackingActive {
            coreLocationManager.startUpdatingLocation()
            isTrackingActive = true
            logger.debug("Started foreground location tracking (accuracy: \(foregroundAccuracy)m, filter: \(foregroundDistanceFilter)m)")
        } else {
            logger.debug("Updated foreground tracking configuration")
        }
        
        // Save tracking mode to UserDefaults for widget
        Storage.saveToUserDefaults("foreground", forKey: trackingModeKey)
        
        // Reload widget timeline to reflect tracking mode change
        WidgetCenter.shared.reloadTimelines(ofKind: "widget")
    }
    
    /// Switches to background tracking mode (app in background)
    /// Uses significant location changes for battery efficiency
    private func switchToBackgroundTracking() {
        // Stop continuous updates if active (always do this when switching to background)
        if isTrackingActive {
            coreLocationManager.stopUpdatingLocation()
            isTrackingActive = false
            logger.debug("Stopped continuous location updates")
        }
        
        // Check authorization - iOS will prevent significant changes without "Always" permission
        // but we need to update widget state accordingly
        guard authorizationStatus == .authorizedAlways else {
            Storage.saveToUserDefaults("stopped", forKey: trackingModeKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "widget")
            logger.warning("Background tracking requires 'Always' permission", handlerType: "TrackingManager")
            return
        }
        
        // Start significant location changes if available
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            logger.warning("Significant location change monitoring not available", handlerType: "TrackingManager")
            Storage.saveToUserDefaults("stopped", forKey: trackingModeKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "widget")
            return
        }
        
        if !isUsingSignificantChanges {
            coreLocationManager.startMonitoringSignificantLocationChanges()
            isUsingSignificantChanges = true
            logger.debug("Switching to significant location change monitoring")
        }
        
        Storage.saveToUserDefaults("background", forKey: trackingModeKey)
        
        // Reload widget timeline to reflect tracking mode change
        WidgetCenter.shared.reloadTimelines(ofKind: "widget")
    }
    
    /// Stops all location tracking
    func stopLocationUpdates() {
        if isTrackingActive {
            coreLocationManager.stopUpdatingLocation()
            isTrackingActive = false
            logger.debug("📡 Stopped continuous location updates")
        }
        
        if isUsingSignificantChanges {
            coreLocationManager.stopMonitoringSignificantLocationChanges()
            isUsingSignificantChanges = false
            logger.debug("📡 Stopped significant location changes")
        }
    }
    
    // MARK: - App Lifecycle Methods

    func appDidEnterBackground() {
        switchToBackgroundTracking()
    }
    
    func appWillEnterForeground() {
        switchToForegroundTracking()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            let updateType = self.isUsingSignificantChanges ? "significant change" : "continuous"
            let accuracy = location.horizontalAccuracy
            self.logger.debug("Location updated (\(updateType)): \(location.coordinate.latitude), \(location.coordinate.longitude) (accuracy: ±\(Int(accuracy))m)")
            
            // Update deviceLocation property immediately (for UI)
            self.deviceLocation = location
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            // Notify SwiftUI that authorization status changed (so computed properties are re-evaluated)
            self.objectWillChange.send()
            
            self.logger.debug("Location authorization changed to: \(newStatus.rawValue)")
            
            switch newStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.logger.debug("Location permission granted")
                self.startLocationUpdates()
            case .denied:
                self.logger.error("Location permission denied by user", handlerType: "TrackingManager", error: nil)
            case .restricted:
                self.logger.error("Location permission restricted by system", handlerType: "TrackingManager", error: nil)
            case .notDetermined:
                self.logger.debug("Location permission not determined yet")
            @unknown default:
                self.logger.warning("Unknown location permission status: \(newStatus.rawValue)", handlerType: "TrackingManager")
            }
        }
    }
}

// MARK: - AppLifecycleHandler Conformance

extension TrackingManager: @MainActor AppLifecycleHandler {
    // Methods appDidEnterBackground() and appWillEnterForeground() already exist above
    // Protocol conformance is automatic - no additional implementation needed
}
