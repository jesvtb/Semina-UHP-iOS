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
    private let geocoder = CLGeocoder()
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
    
    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        return try await geocoder.reverseGeocodeLocation(location)
    }
    
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
        
        // NOTE: Persistence of lookup location has been moved to EventManager.
        // This function now only constructs and returns the lookup location dictionary.
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
        
        // Add timestamp from location
        newLocationDict["timestamp"] = .double(location.timestamp.timeIntervalSince1970)
        
        
        return newLocationDict
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
                
                #if DEBUG
                print("📦 Constructed location dict: \(dict)")
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

