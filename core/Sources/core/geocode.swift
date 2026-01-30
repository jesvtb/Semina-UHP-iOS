//
//  geocode.swift
//  core
//
//  Location data construction utilities for device, lookup, and NewLocation schemas.
//

import Foundation
import CoreLocation

// MARK: - Shared Helpers (fileprivate)

/// Adds action_utc and action_timezone to the dictionary
fileprivate func addActionTimestamp(to dict: inout [String: Any]) {
    let now = Date()
    let utcFormatter = ISO8601DateFormatter()
    utcFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
    utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dict["action_utc"] = utcFormatter.string(from: now)
    dict["action_timezone"] = TimeZone.current.identifier
}

/// Builds street string from placemark (subThoroughfare + thoroughfare)
fileprivate func streetFromPlacemark(_ placemark: CLPlacemark) -> String {
    var streetParts: [String] = []
    if let subThoroughfare = placemark.subThoroughfare {
        streetParts.append(subThoroughfare)
    }
    if let thoroughfare = placemark.thoroughfare {
        streetParts.append(thoroughfare)
    }
    return streetParts.joined(separator: " ")
}

/// Builds location/subdivisions string from placemark (subLocality, locality, subAdmin, adminArea)
fileprivate func locationStringFromPlacemark(_ placemark: CLPlacemark) -> String {
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
    return locationParts.joined(separator: ", ")
}

/// Sets full_address from street, location, and country in the dictionary
fileprivate func setFullAddress(from dict: [String: Any], into target: inout [String: Any]) {
    var addressParts: [String] = []
    if let street = dict["street"] as? String, !street.isEmpty {
        addressParts.append(street)
    }
    if let location = dict["location"] as? String, !location.isEmpty {
        addressParts.append(location)
    }
    if let country = dict["country"] as? String, !country.isEmpty {
        addressParts.append(country)
    }
    if !addressParts.isEmpty {
        target["full_address"] = addressParts.joined(separator: ", ")
    }
}

/// Populates common placemark fields into the dictionary
fileprivate func populateFromPlacemark(_ placemark: CLPlacemark, into dict: inout [String: Any], mapItemName: String? = nil) {
    // Place information
    if let name = mapItemName {
        dict["place"] = name
    } else if let name = placemark.name {
        dict["place"] = name
    }
    
    // Street address components
    let street = streetFromPlacemark(placemark)
    if !street.isEmpty {
        dict["street"] = street
    }
    
    // Location string
    let locationString = locationStringFromPlacemark(placemark)
    if !locationString.isEmpty {
        dict["location"] = locationString
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
}

// MARK: - Public API

/// Namespace for geocode construction functions
public enum Geocode {
        /// - Parameters:
    ///   - location: The CLLocation with coordinates
    ///   - placemark: Optional CLPlacemark with address information
    /// - Returns: Dictionary with location and address data
    public static func constructDeviceLocation(location: CLLocation, placemark: CLPlacemark?) -> [String: JSONValue] {
    var dict: [String: Any] = [:]
    
    // Core location data (always present) - REQUIRED by backend
    dict["latitude"] = location.coordinate.latitude
    dict["longitude"] = location.coordinate.longitude
    dict["location_type"] = "device"
    
    // Add action timestamp
    addActionTimestamp(to: &dict)
    
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
        
        // Populate common placemark fields
        populateFromPlacemark(placemark, into: &dict)
        
        // Update local variables for required field defaults
        if let isoCode = placemark.isoCountryCode {
            countryCode = isoCode
        }
        locationString = locationStringFromPlacemark(placemark)
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
    setFullAddress(from: dict, into: &dict)
    
    // Convert dict to JSONValue
    guard let jsonValue = JSONValue.dictionary(from: dict) else {
        #if DEBUG
        print("⚠️ Failed to convert location dict to JSONValue")
        #endif
        return [:]
    }
    
    return jsonValue
}

    /// Constructs a lookup location dictionary from placemark data for search results
    /// - Parameters:
    ///   - location: The CLLocation with coordinates
    ///   - placemark: CLPlacemark with address information from MKLocalSearch
    ///   - mapItemName: Optional name from MKMapItem
    /// - Returns: Dictionary with location and address data
    public static func constructLookupLocation(location: CLLocation, placemark: CLPlacemark, mapItemName: String?) -> [String: JSONValue] {
    var dict: [String: Any] = [:]
    
    // Core location data (always present)
    dict["latitude"] = location.coordinate.latitude
    dict["longitude"] = location.coordinate.longitude
    dict["accuracy"] = location.horizontalAccuracy
    dict["location_type"] = "lookup"
    
    // Add action timestamp
    addActionTimestamp(to: &dict)
    
    // Populate common placemark fields
    populateFromPlacemark(placemark, into: &dict, mapItemName: mapItemName)
    
    // Construct full address string (at the end)
    setFullAddress(from: dict, into: &dict)
    
    // Convert dict to JSONValue
    guard let jsonValue = JSONValue.dictionary(from: dict) else {
        #if DEBUG
        print("⚠️ Failed to convert lookup location dict to JSONValue")
        #endif
        return [:]
    }
    
    return jsonValue
}

    /// Builds a NewLocation dictionary matching the Python schema
    /// - Parameters:
    ///   - location: The CLLocation with coordinates
    ///   - placemark: Optional CLPlacemark with address information
    /// - Returns: Dictionary matching the NewLocation schema with coordinate and location details
    public static func buildNewLocationDict(location: CLLocation, placemark: CLPlacemark?) -> [String: JSONValue] {
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
        
        // Build subdivisions string using same pattern as location string
        let subdivisionsString = locationStringFromPlacemark(placemark)
        if !subdivisionsString.isEmpty {
            newLocationDict["subdivisions"] = .string(subdivisionsString)
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
}
