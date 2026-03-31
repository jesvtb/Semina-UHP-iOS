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
/// and high accuracy mode. Handles only location tracking - excludes lookup location management.
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
    
    // Use AppLifecycleManager's state as single source of truth
    // Removes duplicate state tracking
    private var isAppInBackground: Bool {
        appLifecycleManager?.isAppInBackground ?? false
    }
    
    // Configuration constants (Google Maps strategy)
    private let foregroundDistanceFilter: CLLocationDistance = 50.0  // Update every 50 meters when in foreground
    private let foregroundAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters  // Moderate accuracy when in foreground
    
    // MARK: - Marina / jitter stabilization (foreground continuous updates)
    /// Reject fixes older than this (Core Location may deliver stale cached points).
    private let maxFixAgeSeconds: TimeInterval = 55
    /// Reject fixes with invalid or extremely poor reported accuracy (multipath / bad GNSS).
    private let maxAcceptableHorizontalAccuracyMeters: CLLocationAccuracy = 220
    /// Ignore new fixes within this distance of the last accepted fix (suppress small jitter).
    private let smallJitterSuppressionMeters: CLLocationDistance = 42
    /// Treat as real movement: publish immediately without waiting for a cluster.
    private let largeMoveImmediateMeters: CLLocationDistance = 260
    /// When horizontal accuracy is worse than this, use looser cluster rules (water / marina).
    private let unstableAccuracyThresholdMeters: CLLocationAccuracy = 125
    /// Samples must lie within this radius of their centroid to count as a stable cluster (stable GNSS).
    private let stabilizationClusterRadiusMeters: CLLocationDistance = 105
    /// Looser cluster radius when accuracy is poor (berthed boat, multipath).
    private let unstableStabilizationClusterRadiusMeters: CLLocationDistance = 150
    /// Minimum samples to confirm a stable position in the ambiguous band.
    private let requiredStableSamples: Int = 3
    private let unstableRequiredStableSamples: Int = 4
    /// After this many ambiguous samples without a stable cluster, publish best-effort centroid (avoid stalling).
    private let ambiguousFallbackSampleCount: Int = 7
    
    /// Last fix promoted to `deviceLocation` (stabilized).
    private var lastAcceptedFix: CLLocation?
    /// Recent fixes in the ambiguous distance band (between jitter suppression and large move).
    private var ambiguityBuffer: [CLLocation] = []
    
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
        
        lastAcceptedFix = nil
        ambiguityBuffer.removeAll()
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
            self.processIncomingLocation(location, updateTypeLabel: updateType)
        }
    }
    
    /// Quality gates, jitter suppression, and cluster stabilization before updating `deviceLocation`.
    private func processIncomingLocation(_ location: CLLocation, updateTypeLabel: String) {
        let rawLat = location.coordinate.latitude
        let rawLon = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy
        let ageSeconds = -location.timestamp.timeIntervalSinceNow
        
        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            logger.debug("location_rejected reason=invalid_coordinate lat=\(rawLat) lon=\(rawLon) type=\(updateTypeLabel)")
            return
        }
        
        guard accuracy >= 0 else {
            logger.debug("location_rejected reason=invalid_accuracy hacc=\(accuracy) lat=\(rawLat) lon=\(rawLon) type=\(updateTypeLabel)")
            return
        }
        
        guard accuracy <= maxAcceptableHorizontalAccuracyMeters else {
            logger.debug("location_rejected reason=poor_accuracy hacc=\(Int(accuracy)) max=\(Int(maxAcceptableHorizontalAccuracyMeters)) lat=\(rawLat) lon=\(rawLon) type=\(updateTypeLabel)")
            return
        }
        
        guard ageSeconds <= maxFixAgeSeconds else {
            logger.debug("location_rejected reason=stale_fix age_s=\(Int(ageSeconds)) max_s=\(Int(maxFixAgeSeconds)) lat=\(rawLat) lon=\(rawLon) type=\(updateTypeLabel)")
            return
        }
        
        if isUsingSignificantChanges {
            publishDeviceLocation(location, reason: "significant_change")
            return
        }
        
        guard let lastAccepted = lastAcceptedFix else {
            publishDeviceLocation(location, reason: "first_fix")
            return
        }
        
        let distanceFromLast = lastAccepted.distance(from: location)
        
        if distanceFromLast <= smallJitterSuppressionMeters {
            logger.debug("location_suppressed reason=small_jitter d_m=\(Int(distanceFromLast)) max=\(Int(smallJitterSuppressionMeters)) hacc=\(Int(accuracy)) lat=\(rawLat) lon=\(rawLon)")
            return
        }
        
        if distanceFromLast >= largeMoveImmediateMeters {
            publishDeviceLocation(location, reason: "large_move")
            return
        }
        
        // Ambiguous band: multipath / marina — require a stable cluster or fallback.
        let unstable = accuracy > unstableAccuracyThresholdMeters
        let clusterRadius = unstable ? unstableStabilizationClusterRadiusMeters : stabilizationClusterRadiusMeters
        let requiredSamples = unstable ? unstableRequiredStableSamples : requiredStableSamples
        
        ambiguityBuffer.append(location)
        if ambiguityBuffer.count > ambiguousFallbackSampleCount {
            ambiguityBuffer.removeFirst()
        }
        
        let trimmed = Array(ambiguityBuffer.suffix(requiredSamples))
        if trimmed.count >= requiredSamples,
           let centroid = centroidIfClustered(samples: trimmed, maxRadiusMeters: clusterRadius) {
            publishDeviceLocation(centroid, reason: unstable ? "cluster_stable_unstable" : "cluster_stable")
            return
        }
        
        if ambiguityBuffer.count >= ambiguousFallbackSampleCount,
           let fallback = centroidOfBestEffort(samples: ambiguityBuffer) {
            logger.debug("location_fallback reason=cluster_timeout samples=\(ambiguityBuffer.count) lat=\(fallback.coordinate.latitude) lon=\(fallback.coordinate.longitude)")
            publishDeviceLocation(fallback, reason: "cluster_fallback")
            return
        }
        
        logger.debug("location_pending reason=ambiguous_band d_m=\(Int(distanceFromLast)) hacc=\(Int(accuracy)) unstable=\(unstable) buf=\(ambiguityBuffer.count) lat=\(rawLat) lon=\(rawLon)")
    }
    
    private func publishDeviceLocation(_ location: CLLocation, reason: String) {
        let accuracy = location.horizontalAccuracy
        logger.debug("location_published reason=\(reason) lat=\(location.coordinate.latitude) lon=\(location.coordinate.longitude) hacc=\(Int(accuracy))")
        lastAcceptedFix = location
        ambiguityBuffer.removeAll()
        deviceLocation = location
    }
    
    /// Returns a centroid if all samples lie within `maxRadiusMeters` of the mean coordinate.
    private func centroidIfClustered(samples: [CLLocation], maxRadiusMeters: CLLocationDistance) -> CLLocation? {
        guard !samples.isEmpty else { return nil }
        let meanLat = samples.map(\.coordinate.latitude).reduce(0, +) / Double(samples.count)
        let meanLon = samples.map(\.coordinate.longitude).reduce(0, +) / Double(samples.count)
        let meanCoord = CLLocationCoordinate2D(latitude: meanLat, longitude: meanLon)
        guard CLLocationCoordinate2DIsValid(meanCoord) else { return nil }
        let meanLocation = CLLocation(latitude: meanLat, longitude: meanLon)
        for sample in samples {
            if meanLocation.distance(from: sample) > maxRadiusMeters {
                return nil
            }
        }
        let avgAccuracy = samples.map(\.horizontalAccuracy).reduce(0, +) / Double(samples.count)
        let ref = samples.last!
        return CLLocation(
            coordinate: meanCoord,
            altitude: ref.altitude,
            horizontalAccuracy: avgAccuracy,
            verticalAccuracy: ref.verticalAccuracy,
            timestamp: Date()
        )
    }
    
    /// Best-effort centroid when stabilization times out (avoid indefinite stall).
    private func centroidOfBestEffort(samples: [CLLocation]) -> CLLocation? {
        guard !samples.isEmpty else { return nil }
        let best = samples.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) ?? samples.last!
        let meanLat = samples.map(\.coordinate.latitude).reduce(0, +) / Double(samples.count)
        let meanLon = samples.map(\.coordinate.longitude).reduce(0, +) / Double(samples.count)
        let meanCoord = CLLocationCoordinate2D(latitude: meanLat, longitude: meanLon)
        guard CLLocationCoordinate2DIsValid(meanCoord) else { return nil }
        let avgAccuracy = samples.map(\.horizontalAccuracy).reduce(0, +) / Double(samples.count)
        return CLLocation(
            coordinate: meanCoord,
            altitude: best.altitude,
            horizontalAccuracy: max(avgAccuracy, best.horizontalAccuracy),
            verticalAccuracy: best.verticalAccuracy,
            timestamp: Date()
        )
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
