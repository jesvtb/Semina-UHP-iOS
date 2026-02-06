//
//  Geocoder.swift
//  core
//
//  Stateless service that performs Geoapify autocomplete and MKLocalSearch.Request,
//  returns [MapSearchResult]. API key is injected at init; no key in package.
//

import Foundation
import CoreLocation
import MapKit

/// NewLocation-style dictionary (coordinate, place_name, subdivisions, country_name, etc.) used for events and content. Built by geocodeReverse.
public typealias LocationDict = [String: JSONValue]

// MARK: - Location Data Source
/// Source of location data - device GPS or external lookup.
public enum LocationDataSource: String, Sendable, Codable {
    /// Location obtained from device GPS/CoreLocation.
    case device
    /// Location obtained from geocoding lookup or search.
    case lookup
}

// MARK: - Location Detail Data
/// Structured geocoding result with location metadata for display and events.
/// Built by Geocoder.geocodeReverse from Apple MapKit or Geoapify responses.
public struct LocationDetailData: Sendable {
    public let location: CLLocation
    public let isOcean: Bool?
    public let placeName: String?
    public let subLocality: String?
    public let locality: String?
    public let adminArea: String?
    public let subAdminArea: String?
    public let subdivisions: String?
    public let subdivisionCode: String?
    public let countryName: String?
    public let countryCode: String?
    public let timezone: String
    
    /// Data source of the location (device GPS or lookup). Can be set at init or assigned later.
    public var dataSource: LocationDataSource?
    
    /// Creates LocationDetailData with all geocoding fields.
    public init(
        location: CLLocation,
        placeName: String? = nil,
        subdivisions: String? = nil,
        countryName: String? = nil,
        countryCode: String? = nil,
        timezone: String = TimeZone.current.identifier,
        adminArea: String? = nil,
        subAdminArea: String? = nil,
        locality: String? = nil,
        subLocality: String? = nil,
        subdivisionCode: String? = nil,
        isOcean: Bool? = nil,
        dataSource: LocationDataSource? = nil
    ) {
        self.location = location
        self.placeName = placeName
        self.subdivisions = subdivisions
        self.countryName = countryName
        self.countryCode = countryCode
        self.timezone = timezone
        self.adminArea = adminArea
        self.subAdminArea = subAdminArea
        self.locality = locality
        self.subLocality = subLocality
        self.subdivisionCode = subdivisionCode
        self.isOcean = isOcean
        self.dataSource = dataSource
    }
    
    /// Converts to LocationDict format for events and backend communication.
    public func toLocationDict() -> LocationDict {
        var coordinateDict: [String: JSONValue] = [
            "lat": .double(location.coordinate.latitude),
            "lng": .double(location.coordinate.longitude),
        ]
        if location.verticalAccuracy > 0 {
            coordinateDict["alt"] = .double(location.altitude)
        }
        
        var dict: LocationDict = [
            "coordinate": .dictionary(coordinateDict),
            "timezone": .string(timezone),
        ]
        
        if let countryCode = countryCode, !countryCode.isEmpty {
            dict["country_code"] = .string(countryCode)
        }
        if let subdivisions = subdivisions, !subdivisions.isEmpty {
            dict["subdivisions"] = .string(subdivisions)
        }
        if let placeName = placeName, !placeName.isEmpty {
            dict["place_name"] = .string(placeName)
        }
        if let countryName = countryName, !countryName.isEmpty {
            dict["country_name"] = .string(countryName)
        }
        if let subdivisionCode = subdivisionCode, !subdivisionCode.isEmpty {
            dict["subdivision_code"] = .string(subdivisionCode)
        }
        if let isOcean = isOcean, isOcean {
            dict["is_ocean"] = .bool(true)
        }
        if let adminArea = adminArea, !adminArea.isEmpty {
            dict["adminArea"] = .string(adminArea)
        }
        if let subAdminArea = subAdminArea, !subAdminArea.isEmpty {
            dict["subAdminArea"] = .string(subAdminArea)
        }
        if let locality = locality, !locality.isEmpty {
            dict["locality"] = .string(locality)
        }
        if let subLocality = subLocality, !subLocality.isEmpty {
            dict["subLocality"] = .string(subLocality)
        }
        if let dataSource = dataSource {
            dict["data_source"] = .string(dataSource.rawValue)
        }
        
        return dict
    }
}

/// Stateless geocoder that runs Geoapify autocomplete and MKLocalSearch in parallel,
/// merges and caps results. Used by app-level AutocompleteManager.
public final class Geocoder: Sendable {
    private let geoapifyApiKey: String
    private let apiClient: APIClient
    private let logger: Logger

    private static let geoapifyBaseURL = "https://api.geoapify.com/v1/geocode/autocomplete"
    private static let geoapifyReverseBaseURL = "https://api.geoapify.com/v1/geocode/reverse"
    private static let geoapifyLimit = 8
    private static let mapKitLimit = 8
    private static let maxTotalResults = 15

    public init(
        geoapifyApiKey: String,
        apiClient: APIClient? = nil,
        logger: Logger? = nil
    ) {
        self.geoapifyApiKey = geoapifyApiKey
        self.apiClient = apiClient ?? APIClient(logger: logger ?? NoOpLogger())
        self.logger = logger ?? NoOpLogger()
    }

    /// Runs Geoapify autocomplete and MKLocalSearch in parallel, interleaves and caps at maxTotalResults.
    /// - Parameter query: Search query string (trimmed; empty returns []).
    /// - Returns: Up to maxTotalResults MapSearchResult, interleaved from both sources.
    public func search(query: String) async throws -> [MapSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }

        async let geoapifyResults = autocompleteGeoapify(query: trimmed)
        async let mapKitResults = autocompleteMapKit(query: trimmed)

        let (geoapify, mapKit) = try await (geoapifyResults, mapKitResults)
        return interleave(maxTotal: Self.maxTotalResults, first: geoapify, second: mapKit)
    }

    /// Reverse geocodes a location using MapKit.
    /// On macOS 26+/iOS 26+, uses MKReverseGeocodingRequest for better results.
    /// On older versions, falls back to CLGeocoder.
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: Array of CLPlacemark from the reverse geocode (may be empty).
    /// - Throws: Error if reverse geocoding fails.
    public func geocodeReverseMK(location: CLLocation) async throws -> [CLPlacemark] {
        if #available(macOS 26.0, iOS 26.0, *) {
            return try await geocodeReverseMKNew(location: location)
        } else {
            return try await geocodeReverseMKLegacy(location: location)
        }
    }
    
    @available(macOS 26.0, iOS 26.0, *)
    private func geocodeReverseMKNew(location: CLLocation) async throws -> [CLPlacemark] {
        logger.info("Geocoding reverse using New Apple Geocoder: \(location)")
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return []
        }
        let mapItems = try await request.mapItems
        printItem(item: mapItems)
        return mapItems.map { $0.placemark }
    }
    
    private func geocodeReverseMKLegacy(location: CLLocation) async throws -> [CLPlacemark] {
        logger.info("Geocoding reverse using Legacy Apple Geocoder: \(location)")
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        printItem(item: placemarks)
        return placemarks
    }

    /// Reverse geocodes a location using Geoapify reverse geocode API.
    /// Parses the API response (query + results) into LocationDetailData. Geoapify returns { "query": { lat, lon }, "results": [ { address fields } ] }, not GeoJSON.
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: LocationDetailData with location, place_name, subdivisions, country_name, timezone, and display fields.
    /// - Throws: Error if the API call fails.
    public func geocodeReverseGeoapify(location: CLLocation) async throws -> LocationDetailData {
        let params: [String: String] = [
            "lat": String(location.coordinate.latitude),
            "lon": String(location.coordinate.longitude),
            "format": "json",
            "apiKey": geoapifyApiKey,
        ]
        let data = try await apiClient.asyncCallAPI(
            url: Self.geoapifyReverseBaseURL,
            method: "GET",
            headers: nil,
            params: params,
            dataDict: [:],
            jsonDict: [:],
            timeout: false,
            filesDict: [:]
        )
        printItem(item: data)
        return buildLocationDetailDataFromGeoapifyResponse(location: location, data: data)
    }

    /// Builds LocationDetailData from Geoapify reverse API response: { "query": { lat, lon }, "results": [ { state, country_code, city, suburb, ... } ] }.
    private func buildLocationDetailDataFromGeoapifyResponse(location: CLLocation, data: Data) -> LocationDetailData {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first else {
            // Return minimal data if parsing fails
            return LocationDetailData(location: location)
        }

        // Extract all possible subdivision levels from Geoapify response
        let neighbourhood = (first["neighbourhood"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suburb = (first["suburb"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let district = (first["district"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let town = (first["town"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = (first["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let county = (first["county"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = (first["state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Hierarchy order (smallest to largest): neighbourhood → suburb → district → town → city → county → state
        // Remove duplicates while preserving order (e.g., city="Istanbul" and county="Istanbul")
        var seen = Set<String>()
        let subdivisionParts = [neighbourhood, suburb, district, town, city, county, state]
            .compactMap { $0 }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let subdivisions = subdivisionParts.isEmpty ? nil : subdivisionParts.joined(separator: ", ")
        
        // Timezone
        let timezone: String
        if let tzObj = first["timezone"] as? [String: Any], let tzName = tzObj["name"] as? String {
            timezone = tzName
        } else {
            timezone = TimeZone.current.identifier
        }
        
        // Ocean/marine area - detect ocean name and use as place_name
        let oceanName: String?
        if let ocean = first["ocean"] as? String, !ocean.isEmpty {
            oceanName = ocean
        } else if let marineArea = first["marinearea"] as? String, !marineArea.isEmpty {
            oceanName = marineArea
        } else {
            oceanName = nil
        }
        
        // Place name: use ocean name if in ocean, otherwise address_line1/name/city
        let placeName: String?
        if let ocean = oceanName {
            placeName = ocean
        } else {
            placeName = (first["address_line1"] as? String) ?? (first["name"] as? String) ?? city
        }
        
        // subLocality: lowest hierarchy of (neighborhood, suburb, district, town)
        let subLocality = [neighbourhood, suburb, district, town]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        
        return LocationDetailData(
            location: location,
            placeName: placeName?.isEmpty == true ? nil : placeName,
            subdivisions: subdivisions,
            countryName: first["country"] as? String,
            countryCode: (first["country_code"] as? String)?.uppercased(),
            timezone: timezone,
            adminArea: state?.isEmpty == true ? nil : state,
            subAdminArea: county?.isEmpty == true ? nil : county,
            locality: city?.isEmpty == true ? nil : city,
            subLocality: subLocality?.isEmpty == true ? nil : subLocality,
            subdivisionCode: (first["iso3166_2"] as? String)?.uppercased(),
            isOcean: oceanName != nil ? true : nil
        )
    }

    /// Composite reverse geocode: tries native MapKit first, falls back to Geoapify.
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: LocationDetailData with location, place_name, subdivisions, country_name, timezone, and display fields.
    /// - Throws: Error if both MapKit and Geoapify fail.
    public func geocodeReverse(location: CLLocation) async throws -> LocationDetailData {
        // Try native MapKit geocoder first
        do {
            let placemarks = try await geocodeReverseMK(location: location)
            if let placemark = placemarks.first {
                return buildLocationDetailDataFromPlacemark(location: location, placemark: placemark)
            }
        } catch {
            // CLGeocoder failed, fall through to Geoapify
        }
        // Fallback to Geoapify
        return try await geocodeReverseGeoapify(location: location)
    }
    
    /// Builds LocationDetailData from a CLPlacemark (from MapKit/CLGeocoder).
    private func buildLocationDetailDataFromPlacemark(location: CLLocation, placemark: CLPlacemark) -> LocationDetailData {
        // Debug logging
        printItem(item: placemark.subLocality, heading: "subLocality")
        printItem(item: placemark.locality, heading: "locality")
        printItem(item: placemark.subAdministrativeArea, heading: "subAdministrativeArea")
        printItem(item: placemark.administrativeArea, heading: "administrativeArea")
        printItem(item: placemark.country, heading: "country")
        printItem(item: placemark.isoCountryCode, heading: "isoCountryCode")
        printItem(item: placemark.timeZone, heading: "timeZone")
        printItem(item: placemark.areasOfInterest, heading: "areasOfInterest")
        
        // Build subdivisions: subLocality, locality, subAdministrativeArea, administrativeArea
        let subdivisionParts = [
            placemark.subLocality,
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
         .filter { !$0.isEmpty }
        let subdivisions = subdivisionParts.isEmpty ? nil : subdivisionParts.joined(separator: ", ")
        
        // Timezone
        let timezone = placemark.timeZone?.identifier ?? TimeZone.current.identifier
        
        // Extract display fields
        let adminArea = placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subAdminArea = placemark.subAdministrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locality = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subLocality = placemark.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ocean detection from CLPlacemark
        let oceanName = placemark.ocean?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Place name: use ocean name if in ocean, otherwise prefer name/thoroughfare/locality
        let placeName: String?
        if let ocean = oceanName, !ocean.isEmpty {
            placeName = ocean
        } else {
            placeName = (placemark.name ?? placemark.thoroughfare ?? placemark.locality)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return LocationDetailData(
            location: location,
            placeName: placeName?.isEmpty == true ? nil : placeName,
            subdivisions: subdivisions,
            countryName: placemark.country,
            countryCode: placemark.isoCountryCode?.uppercased(),
            timezone: timezone,
            adminArea: adminArea?.isEmpty == true ? nil : adminArea,
            subAdminArea: subAdminArea?.isEmpty == true ? nil : subAdminArea,
            locality: locality?.isEmpty == true ? nil : locality,
            subLocality: subLocality?.isEmpty == true ? nil : subLocality,
            isOcean: oceanName?.isEmpty == false ? true : nil
        )
    }

    func autocompleteGeoapify(query: String) async throws -> [MapSearchResult] {
        let params: [String: String] = [
            "text": query,
            "apiKey": geoapifyApiKey,
            "limit": String(Self.geoapifyLimit),
        ]
        let data = try await apiClient.asyncCallAPI(
            url: Self.geoapifyBaseURL,
            method: "GET",
            headers: nil,
            params: params,
            dataDict: [:],
            jsonDict: [:],
            timeout: false,
            filesDict: [:]
        )
        let features = try data.extractFeatures()
        // printItem(item: features[0])
        print(features[0])
        return features.map { MapSearchResult($0) }
    }

    func autocompleteMapKit(query: String) async -> [MapSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)

        let results: [MapSearchResult] = await withCheckedContinuation { continuation in
            search.start { response, error in
                if error != nil {
                    continuation.resume(returning: [])
                    return
                }
                guard let response = response else {
                    continuation.resume(returning: [])
                    return
                }
                let mapItems = Array(response.mapItems.prefix(Self.mapKitLimit))
                let searchResults = mapItems.map { MapSearchResult($0) }
                continuation.resume(returning: searchResults)
            }
        }
        return results
    }

    /// Interleaves two arrays, preferring results with type "city"; caps total at maxTotal.
    private func interleave(maxTotal: Int, first: [MapSearchResult], second: [MapSearchResult]) -> [MapSearchResult] {
        var result: [MapSearchResult] = []
        var i = 0
        var j = 0
        while result.count < maxTotal, i < first.count || j < second.count {
            let fromFirst = i < first.count ? first[i] : nil
            let fromSecond = j < second.count ? second[j] : nil
            let firstIsCity = fromFirst?.type == "city"
            let secondIsCity = fromSecond?.type == "city"
            if let a = fromFirst, let b = fromSecond {
                if firstIsCity, !secondIsCity {
                    result.append(a)
                    i += 1
                } else if !firstIsCity, secondIsCity {
                    result.append(b)
                    j += 1
                } else {
                    result.append(a)
                    i += 1
                    if result.count < maxTotal {
                        result.append(b)
                        j += 1
                    }
                }
            } else if let a = fromFirst {
                result.append(a)
                i += 1
            } else if let b = fromSecond {
                result.append(b)
                j += 1
            }
        }
        return result
    }
}
