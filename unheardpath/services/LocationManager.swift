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

// struct LocationDetails

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var deviceLocation: CLLocation?
    @Published var isLocationPermissionGranted: Bool = false
    
    // Geocoding state
    @Published var isGeocoding: Bool = false
    @Published var geocodingError: Error?
    @Published var locationDetails: [String: Any]?
    
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
    
    // Cache configuration for places/geojson data
    private let placesCacheExpirationHours: TimeInterval = 24 * 60 * 60 // 24 hours in seconds
    
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
        deviceLocation = savedLocation
        
        #if DEBUG
        print("📂 Loaded saved location from UserDefaults: \(latitude), \(longitude)")
        print("   Saved at: \(savedTimestamp)")
        #endif
    }
    
    // MARK: - Location Data Access
    
    /// Returns the current latitude if available
    var latitude: Double? {
        return deviceLocation?.coordinate.latitude
    }
    
    /// Returns the current longitude if available
    var longitude: Double? {
        return deviceLocation?.coordinate.longitude
    }
    
    // MARK: - Places Cache Management
    
    /// Generate cache key from rounded coordinates (~100m precision)
    private func placesCacheKey(userLat: Double, userLon: Double) -> String {
        let roundedLat = round(userLat * 100) / 100
        let roundedLon = round(userLon * 100) / 100
        return "PlacesCache_\(roundedLat)_\(roundedLon)"
    }
    
    /// Retrieve cached location data (list of {idx, pageid} dictionaries)
    /// Returns nil if cache doesn't exist or is expired (24 hours)
    func getCachedLocationData(userLat: Double, userLon: Double) -> [[String: Any]]? {
        let defaults = UserDefaults.standard
        let key = placesCacheKey(userLat: userLat, userLon: userLon)
        
        guard let cacheDict = defaults.dictionary(forKey: key),
              let features = cacheDict["features"] as? [[String: Any]],
              let timestamp = cacheDict["timestamp"] as? TimeInterval else {
            #if DEBUG
            print("💾 Cache miss for location: \(userLat), \(userLon)")
            #endif
            return nil
        }
        
        // Check expiration (24 hours)
        let cacheAge = Date().timeIntervalSince1970 - timestamp
        if cacheAge > placesCacheExpirationHours {
            #if DEBUG
            print("⏰ Cache expired for location: \(userLat), \(userLon) (age: \(Int(cacheAge / 3600)) hours)")
            #endif
            // Clean up expired cache
            defaults.removeObject(forKey: key)
            return nil
        }
        
        #if DEBUG
        print("✅ Cache hit for location: \(userLat), \(userLon)")
        #endif
        return features
    }
    
    /// Save cached location data (list of {idx, pageid} dictionaries)
    func saveCachedLocationData(userLat: Double, userLon: Double, features: [[String: Any]]) {
        let defaults = UserDefaults.standard
        let key = placesCacheKey(userLat: userLat, userLon: userLon)
        
        let cacheDict: [String: Any] = [
            "features": features,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        defaults.set(cacheDict, forKey: key)
        defaults.synchronize()
        
        #if DEBUG
        print("💾 Cached location data for: \(userLat), \(userLon) with \(features.count) features")
        #endif
    }
    
    /// Save individual feature by pageid
    func saveCachedFeature(pageid: Int, feature: [String: Any]) {
        let defaults = UserDefaults.standard
        let key = "wiki_\(pageid)"
        
        defaults.set(feature, forKey: key)
        defaults.synchronize()
        
        #if DEBUG
        print("💾 Cached feature for pageid: \(pageid)")
        #endif
    }
    
    /// Retrieve individual feature by pageid
    func getCachedFeature(pageid: Int) -> [String: Any]? {
        let defaults = UserDefaults.standard
        let key = "wiki_\(pageid)"
        
        return defaults.dictionary(forKey: key)
    }
    
    /// Reconstruct GeoJSON FeatureCollection from cache
    /// Returns nil if cache is missing or any required features are missing
    func reconstructGeoJSONFromCache(userLat: Double, userLon: Double) -> [String: Any]? {
        guard let featuresList = getCachedLocationData(userLat: userLat, userLon: userLon) else {
            return nil
        }
        
        var reconstructedFeatures: [[String: Any]] = []
        
        // Fetch each feature by pageid and sort by idx
        for featureRef in featuresList {
            guard let pageid = featureRef["pageid"] as? Int,
                  let idx = featureRef["idx"] as? Int,
                  let feature = getCachedFeature(pageid: pageid) else {
                #if DEBUG
                print("⚠️ Missing feature in cache for pageid: \(featureRef["pageid"] ?? "unknown")")
                #endif
                continue
            }
            
            // Store idx for sorting
            var featureWithIdx = feature
            featureWithIdx["_sortIdx"] = idx
            reconstructedFeatures.append(featureWithIdx)
        }
        
        // Sort by original idx
        reconstructedFeatures.sort { (feature1, feature2) -> Bool in
            let idx1 = feature1["_sortIdx"] as? Int ?? 0
            let idx2 = feature2["_sortIdx"] as? Int ?? 0
            return idx1 < idx2
        }
        
        // Remove temporary sort index
        for i in 0..<reconstructedFeatures.count {
            reconstructedFeatures[i].removeValue(forKey: "_sortIdx")
        }
        
        // Wrap in FeatureCollection format
        let geoJSON: [String: Any] = [
            "event": "map",
            "data": [
                "type": "FeatureCollection",
                "features": reconstructedFeatures
            ]
        ]
        
        #if DEBUG
        print("✅ Reconstructed GeoJSON from cache with \(reconstructedFeatures.count) features")
        #endif
        
        return geoJSON
    }
    
    /// Returns both latitude and longitude as a tuple if available
    var coordinates: (latitude: Double, longitude: Double)? {
        guard let location = deviceLocation else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
    
    // MARK: - Geocoding Methods
    
    /// Geocodes an address string to coordinates using CLGeocoder
    /// - Parameters:
    ///   - addressString: The address or location name to geocode (e.g., "New York, NY" or "1600 Amphitheatre Parkway, Mountain View, CA")
    ///   - completion: Completion handler with optional placemark and error
    /// - Returns: The first placemark if geocoding succeeds, nil otherwise
    func geocodeAddress(_ addressString: String, completion: @escaping (CLPlacemark?, Error?) -> Void) {
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
            guard let self = self else { return }
            
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
    private func constructLocationDict(location: CLLocation, placemark: CLPlacemark?) -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // Required fields
        dict["user_lat"] = location.coordinate.latitude
        dict["user_lon"] = location.coordinate.longitude
        dict["accuracy"] = location.horizontalAccuracy
        
        // Local time (timestamp localized, not UTC)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        formatter.timeZone = TimeZone.current
        dict["local_time"] = formatter.string(from: location.timestamp)
        
        // If placemark found, include address elements
        if let placemark = placemark {
            // Name
            if let name = placemark.name {
                dict["place"] = name
            }
            
            // Street
            if let street = placemark.thoroughfare {
                dict["street"] = street
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
            
            // Country code
            if let countryCode = placemark.isoCountryCode {
                dict["country_code"] = countryCode
            }
            
            // Country name
            if let country = placemark.country {
                dict["country"] = country
            }
            
            // Inland water and ocean
            if let inlandWater = placemark.inlandWater {
                dict["inwater"] = true
                dict["water_name"] = inlandWater
            } else if let ocean = placemark.ocean {
                dict["inwater"] = true
                dict["water_name"] = ocean
            }
            
            // Areas of interest
            if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
                dict["areas_of_interest"] = areasOfInterest
            }
            
            // Region
            if let region = placemark.region as? CLCircularRegion {
                dict["region_lon"] = region.center.longitude
                dict["region_lat"] = region.center.latitude
                dict["region_radius"] = region.radius
            }
        }
        
        return dict
    }
    
    /// Reverse geocodes the current user location and returns a JSON dictionary
    /// - Parameter completion: Completion handler with optional dictionary and error
    func reverseGeocodeUserLocation(completion: @escaping ([String: Any]?, Error?) -> Void) {
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
            guard let self = self else { return }
            
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
                print("❌ Error: \(error.localizedDescription)")
                print(String(repeating: "=", count: 80) + "\n")
                #endif
                // Still return dict with location data even if geocoding fails
                let dict = self.constructLocationDict(location: location, placemark: nil)
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
            let dict = self.constructLocationDict(location: location, placemark: placemark)
            
            // Update locationDetails
            self.locationDetails = dict
            
            #if DEBUG
            print("📦 Constructed location dict: \(dict)")
            print("✅ Updated locationDetails in LocationManager")
            if let locationString = dict["location"] as? String {
              print("   Location string: \(locationString)")
            }
            if let countryName = dict["country_name"] as? String {
              print("   Country name: \(countryName)")
            }
            #endif
            
            completion(dict, nil)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update current location
        deviceLocation = location
        
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
        let newStatus = manager.authorizationStatus
        let oldStatus = authorizationStatus
        
        // Only process if status actually changed (prevents duplicate processing)
        guard newStatus != oldStatus else {
            return
        }
        
        // Update status
        authorizationStatus = newStatus
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
        
        // Filter to only our app's keys
        let appKeys = dict.keys.filter { key in
            key.hasPrefix("LocationManager.") || 
            key.hasPrefix("PlacesCache_") || 
            key.hasPrefix("wiki_")
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
        let keys = defaults.dictionaryRepresentation().keys.filter { key in
            key.hasPrefix("PlacesCache_") || key.hasPrefix("wiki_")
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        print("🗑️ Cleared \(keys.count) cache entries")
    }
    #endif
}

