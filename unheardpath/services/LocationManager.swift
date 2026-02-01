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
import core

// struct LocationDetails

@MainActor  // Ensure all state mutations stay on the main actor to avoid data races with Swift 6 strict concurrency
// AppLifecycleHandler conformance is in a nonisolated extension with proper MainActor bridging
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocodingService = GeocodingService.shared
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // Geocoding state
    @Published var isGeocoding: Bool = false
    @Published var geocodingError: Error?
    
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
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Location Persistence (Removed - now handled by EventManager)
    
    // All location persistence methods have been removed:
    // - saveDeviceLocation() - moved to EventManager
    // - saveLookupLocation() - moved to EventManager
    // - loadLastSavedDeviceLocation() - moved to EventManager
    // - loadLastSavedLookupLocation() - moved to EventManager
    // - @Published properties (deviceLocation, lookupLocation, locationDetails, lookupLocationDetails) - removed
    // - Location Data Access (latitude, longitude) - removed (deviceLocation moved to TrackingManager)
    
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
        Storage.saveToUserDefaults(centerLat, forKey: devicePOIsGeofenceLatKey)
        Storage.saveToUserDefaults(centerLon, forKey: devicePOIsGeofenceLonKey)
        Storage.saveToUserDefaults(radius, forKey: devicePOIsGeofenceRadiusKey)
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
        
        guard Storage.existsInUserDefaults(forKey: devicePOIsGeofenceLatKey),
              Storage.existsInUserDefaults(forKey: devicePOIsGeofenceLonKey),
              Storage.existsInUserDefaults(forKey: devicePOIsGeofenceRadiusKey) else {
            #if DEBUG
            print("ℹ️ No saved geofence found in UserDefaults")
            #endif
            return false
        }
        
        guard let savedLat = Storage.loadFromUserDefaults(forKey: devicePOIsGeofenceLatKey, as: Double.self),
              let savedLon = Storage.loadFromUserDefaults(forKey: devicePOIsGeofenceLonKey, as: Double.self),
              let savedRadius = Storage.loadFromUserDefaults(forKey: devicePOIsGeofenceRadiusKey, as: Double.self) else {
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
        guard let savedLat = Storage.loadFromUserDefaults(forKey: devicePOIsGeofenceLatKey, as: Double.self),
              let savedLon = Storage.loadFromUserDefaults(forKey: devicePOIsGeofenceLonKey, as: Double.self) else {
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
        Storage.removeFromUserDefaults(forKey: devicePOIsGeofenceLatKey)
        Storage.removeFromUserDefaults(forKey: devicePOIsGeofenceLonKey)
        Storage.removeFromUserDefaults(forKey: devicePOIsGeofenceRadiusKey)
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

        isGeocoding = true
        geocodingError = nil

        #if DEBUG
        print("🔍 Geocoding address: \(addressString)")
        #endif

        Task {
            do {
                let placemark = try await geocodingService.geocodeAddress(addressString)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isGeocoding = false
                    #if DEBUG
                    if let location = placemark.location {
                        print("✅ Geocoded '\(addressString)' to: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    }
                    #endif
                    completion(placemark, nil)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isGeocoding = false
                    self.geocodingError = error
                    #if DEBUG
                    print("❌ Geocoding failed: \(error.localizedDescription)")
                    #endif
                    completion(nil, error)
                }
            }
        }
    }
    
    func geocodeAddress(_ addressString: String) async throws -> CLPlacemark {
        isGeocoding = true
        geocodingError = nil
        defer { isGeocoding = false }
        do {
            let placemark = try await geocodingService.geocodeAddress(addressString)
            return placemark
        } catch {
            geocodingError = error
            throw error
        }
    }

    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        isGeocoding = true
        geocodingError = nil
        defer { isGeocoding = false }
        do {
            let placemarks = try await geocodingService.reverseGeocodeLocation(location)
            return placemarks
        } catch {
            geocodingError = error
            throw error
        }
    }
    
    private func constructDeviceLocation(location: CLLocation, placemark: CLPlacemark?) -> [String: JSONValue] {
        return Geocode.constructDeviceLocation(location: location, placemark: placemark)
    }
    
    // constructLookupLocation removed - views call core.constructLookupLocation directly
    
    /// Convenience wrapper: Geocodes a location and constructs a NewLocation structure
    /// - Parameter location: The CLLocation to geocode
    /// - Returns: A dictionary matching the NewLocation schema with coordinate and location details
    /// - Throws: Error if geocoding fails
    func constructNewLocation(from location: CLLocation) async throws -> [String: JSONValue] {
        isGeocoding = true
        geocodingError = nil
        defer { isGeocoding = false }
        do {
            return try await geocodingService.constructNewLocation(from: location)
        } catch {
            geocodingError = error
            throw error
        }
    }
    
    /// Reverse geocodes a given location and returns a JSON dictionary
    /// - Parameters:
    ///   - location: The CLLocation to reverse geocode
    ///   - completion: Completion handler with optional dictionary and error
    func reverseGeocodeUserLocation(location: CLLocation, completion: @escaping @Sendable ([String: JSONValue]?, Error?) -> Void) {
        #if DEBUG
        print("🔍 reverseGeocodeUserLocation() called")
        print("   Coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        #endif

        isGeocoding = true
        geocodingError = nil

        #if DEBUG
        print("🌐 Starting reverse geocoding request...")
        #endif

        Task {
            do {
                let placemarks = try await geocodingService.reverseGeocodeLocation(location)
                await MainActor.run { [weak self] in
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
                    if !placemarks.isEmpty {
                        print("✅ Found \(placemarks.count) placemark(s):\n")
                        for (index, placemark) in placemarks.enumerated() {
                            print(String(repeating: "-", count: 80))
                            print("📍 PLACEMARK #\(index + 1)")
                            print(String(repeating: "-", count: 80))
                            if let placemarkLocation = placemark.location {
                                print("Coordinates: \(placemarkLocation.coordinate.latitude), \(placemarkLocation.coordinate.longitude)")
                                print("Accuracy: ±\(Int(placemarkLocation.horizontalAccuracy))m")
                            }
                            print("\n📋 Address Components:")
                            if let name = placemark.name { print("  • Name: \(name)") }
                            if let thoroughfare = placemark.thoroughfare { print("  • Street: \(thoroughfare)") }
                            if let subThoroughfare = placemark.subThoroughfare { print("  • Street Number: \(subThoroughfare)") }
                            if let subLocality = placemark.subLocality { print("  • Sub-locality: \(subLocality)") }
                            if let locality = placemark.locality { print("  • City/Locality: \(locality)") }
                            if let subAdministrativeArea = placemark.subAdministrativeArea { print("  • Sub-administrative Area: \(subAdministrativeArea)") }
                            if let administrativeArea = placemark.administrativeArea { print("  • State/Province: \(administrativeArea)") }
                            if let postalCode = placemark.postalCode { print("  • Postal Code: \(postalCode)") }
                            if let country = placemark.country { print("  • Country: \(country)") }
                            if let countryCode = placemark.isoCountryCode { print("  • Country Code: \(countryCode)") }
                            if let inlandWater = placemark.inlandWater { print("  • Inland Water: \(inlandWater)") }
                            if let ocean = placemark.ocean { print("  • Ocean: \(ocean)") }
                            if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty { print("  • Areas of Interest: \(areasOfInterest.joined(separator: ", "))") }
                            if let region = placemark.region {
                                print("\n🌍 Region: \(region.identifier)")
                                if let circularRegion = region as? CLCircularRegion {
                                    print("  • Center: \(circularRegion.center.latitude), \(circularRegion.center.longitude), Radius: \(Int(circularRegion.radius))m")
                                }
                            }
                            if let timeZone = placemark.timeZone { print("\n🕐 Timezone: \(timeZone.identifier)") }
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
                    let dict = self.constructDeviceLocation(location: location, placemark: placemarks.first)
                    #if DEBUG
                    if let locationString = dict["location"]?.stringValue { print("📦 Location string: \(locationString)") }
                    if let countryName = dict["country"]?.stringValue { print("   Country: \(countryName)") }
                    #endif
                    completion(dict, nil)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isGeocoding = false
                    self.geocodingError = error
                    #if DEBUG
                    print("❌ Reverse Geocoding Error:")
                    print("   Description: \(error.localizedDescription)")
                    if let nsError = error as NSError?, nsError.domain == "kCLErrorDomain" {
                        switch nsError.code {
                        case 0: print("   Error Type: kCLErrorLocationUnknown")
                        case 1: print("   Error Type: kCLErrorDenied")
                        case 2: print("   Error Type: kCLErrorNetwork")
                        case 8: print("   Error Type: kCLErrorGeocodeFoundNoResult")
                        case 9: print("   Error Type: kCLErrorGeocodeFoundPartialResult")
                        case 10: print("   Error Type: kCLErrorGeocodeCanceled")
                        default: print("   Error Type: CoreLocation error code \(nsError.code)")
                        }
                    }
                    print(String(repeating: "=", count: 80) + "\n")
                    #endif
                    let dict = self.constructDeviceLocation(location: location, placemark: nil)
                    completion(dict, error)
                }
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    /// Updates authorization status when location permissions change
    /// Note: Location tracking is handled by TrackingManager, this only updates status for geofencing checks
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            let oldStatus = self.authorizationStatus
            
            guard newStatus != oldStatus else {
                return
            }
            
            self.authorizationStatus = newStatus
            print("🔄 Location authorization changed to: \(newStatus.rawValue)")
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
        
        // Filter to only our app's keys (Storage uses configured prefix, e.g. "UHP.")
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
    
    /// Debug function to clear all cached location data (Storage-backed UserDefaults keys).
    func debugClearAllCache() {
        let count = Storage.allUserDefaultsKeysWithPrefix().count
        Storage.clearUserDefaultsKeysWithPrefix()
        print("🗑️ Cleared \(count) cache entries")
    }
    #endif
}

