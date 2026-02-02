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
    /// Note: Location tracking is handled by TrackingManager, this only updates authorization status
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

