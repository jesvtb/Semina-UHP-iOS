//
//  LocationManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import CoreLocation
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isLocationPermissionGranted: Bool = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
        isLocationPermissionGranted = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
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
    
    private func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        locationManager.startUpdatingLocation()
        print("📍 Started location updates")
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
        currentLocation = location
        print("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
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

