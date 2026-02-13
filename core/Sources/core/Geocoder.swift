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

/// NewLocation-style dictionary (coordinate, place_name, country_name, admin_area, locality, etc.) used for events and content. Built by geocodeReverse.
public typealias LocationDict = [String: JSONValue]

// MARK: - Location Data Source
/// Source of location data - device GPS or external lookup.
public enum LocationSource: String, Sendable, Codable {
    /// Location obtained from device GPS/CoreLocation.
    case device
    /// Location obtained from geocoding lookup.
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
    public let subdivisionCode: String?
    public let countryName: String?
    public let countryCode: String?
    public let timezone: String?
    
    /// Data source of the location (device GPS or lookup). Can be set at init or assigned later.
    public var dataSource: LocationSource?
    
    /// Creates LocationDetailData with all geocoding fields.
    public init(
        location: CLLocation,
        placeName: String? = nil,
        countryName: String? = nil,
        countryCode: String? = nil,
        timezone: String? = nil,
        adminArea: String? = nil,
        subAdminArea: String? = nil,
        locality: String? = nil,
        subLocality: String? = nil,
        subdivisionCode: String? = nil,
        isOcean: Bool? = nil,
        dataSource: LocationSource? = nil
    ) {
        self.location = location
        self.placeName = placeName
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

    /// Creates LocationDetailData from a CLPlacemark (MapKit/CLGeocoder result).
    public init(placemark: CLPlacemark, location: CLLocation) {
        self.init(placemark: placemark, location: location, mapItemTimeZone: nil)
    }

    /// Creates LocationDetailData from an MKMapItem (MKReverseGeocodingRequest result).
    /// Uses mapItem.timeZone (always populated on MKMapItem) instead of placemark.timeZone
    /// which may be nil for results from MKReverseGeocodingRequest.
    public init(mapItem: MKMapItem, location: CLLocation) {
        self.init(placemark: mapItem.placemark, location: location, mapItemTimeZone: mapItem.timeZone)
    }

    /// Shared initializer for CLPlacemark-based construction.
    ///   - mapItemTimeZone: Optional timezone from MKMapItem (preferred over placemark.timeZone).
    private init(placemark: CLPlacemark, location: CLLocation, mapItemTimeZone: TimeZone?) {
        var adminArea = placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subAdminArea = placemark.subAdministrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locality = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subLocality = placemark.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines)

        // For direct-administered municipalities (e.g., Shanghai, Beijing) the geocoder may
        // return a locality but no administrativeArea. Default adminArea to locality so the
        // geographic hierarchy is complete for caching and backend processing.
        if (adminArea == nil || adminArea?.isEmpty == true), let loc = locality, !loc.isEmpty {
            adminArea = loc
        }

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

        self.location = location
        self.placeName = placeName?.isEmpty == true ? nil : placeName
        self.countryName = placemark.country
        self.countryCode = placemark.isoCountryCode?.uppercased()
        // Prefer MKMapItem.timeZone (always populated) over placemark.timeZone (may be nil
        // for MKReverseGeocodingRequest results).
        self.timezone = placemark.timeZone?.identifier ?? mapItemTimeZone?.identifier
        self.adminArea = adminArea?.isEmpty == true ? nil : adminArea
        self.subAdminArea = subAdminArea?.isEmpty == true ? nil : subAdminArea
        self.locality = locality?.isEmpty == true ? nil : locality
        self.subLocality = subLocality?.isEmpty == true ? nil : subLocality
        self.subdivisionCode = nil
        self.isOcean = oceanName?.isEmpty == false ? true : nil
        self.dataSource = nil
    }

    /// Creates LocationDetailData from a Geoapify properties dictionary.
    /// Expects the inner result dict (e.g. `results[0]`), not the full API response wrapper.
    public init(geoapifyProperties props: [String: Any], location: CLLocation) {
        // Extract all possible subdivision levels
        let neighbourhood = (props["neighbourhood"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suburb = (props["suburb"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let district = (props["district"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let town = (props["town"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = (props["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let county = (props["county"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = (props["state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Timezone
        let timezone: String?
        if let tzObj = props["timezone"] as? [String: Any], let tzName = tzObj["name"] as? String {
            timezone = tzName
        } else {
            timezone = nil
        }

        // Ocean/marine area
        let oceanName: String?
        if let ocean = props["ocean"] as? String, !ocean.isEmpty {
            oceanName = ocean
        } else if let marineArea = props["marinearea"] as? String, !marineArea.isEmpty {
            oceanName = marineArea
        } else {
            oceanName = nil
        }

        // Place name: use ocean name if in ocean, otherwise address_line1/name/city
        let placeName: String?
        if let ocean = oceanName {
            placeName = ocean
        } else {
            placeName = (props["address_line1"] as? String) ?? (props["name"] as? String) ?? city
        }

        // subLocality: lowest hierarchy of (neighborhood, suburb, district, town)
        let subLocality = [neighbourhood, suburb, district, town]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        // For direct-administered municipalities (e.g., Shanghai, Beijing) Geoapify may
        // return a city but no state. Default adminArea to city so the geographic hierarchy
        // is complete for caching and backend processing.
        let resolvedAdminArea: String?
        if let s = state, !s.isEmpty {
            resolvedAdminArea = s
        } else if let c = city, !c.isEmpty {
            resolvedAdminArea = c
        } else {
            resolvedAdminArea = nil
        }

        self.location = location
        self.placeName = placeName?.isEmpty == true ? nil : placeName
        self.countryName = props["country"] as? String
        self.countryCode = (props["country_code"] as? String)?.uppercased()
        self.timezone = timezone
        self.adminArea = resolvedAdminArea
        self.subAdminArea = county?.isEmpty == true ? nil : county
        self.locality = city?.isEmpty == true ? nil : city
        self.subLocality = subLocality?.isEmpty == true ? nil : subLocality
        self.subdivisionCode = (props["iso3166_2"] as? String)?.uppercased()
        self.isOcean = oceanName != nil ? true : nil
        self.dataSource = nil
    }
    
    /// Creates LocationDetailData from an event dictionary.
    /// Returns nil if the required coordinate cannot be extracted.
    public init?(eventDict dict: [String: JSONValue]) {
        guard case .dictionary(let coordDict) = dict["coordinate"],
              case .double(let lat) = coordDict["lat"],
              case .double(let lng) = coordDict["lng"] else {
            return nil
        }

        let altitude: Double
        let verticalAccuracy: Double
        if case .double(let alt) = coordDict["alt"] {
            altitude = alt
            verticalAccuracy = 0
        } else {
            altitude = 0
            verticalAccuracy = -1
        }

        self.location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            altitude: altitude,
            horizontalAccuracy: 0,
            verticalAccuracy: verticalAccuracy,
            timestamp: Date()
        )

        self.timezone = dict["timezone"]?.stringValue
        self.placeName = dict["place_name"]?.stringValue
        self.countryName = dict["country_name"]?.stringValue
        self.countryCode = dict["country_code"]?.stringValue
        self.subdivisionCode = dict["subdivision_code"]?.stringValue
        self.adminArea = dict["admin_area"]?.stringValue
        self.subAdminArea = dict["sub_admin_area"]?.stringValue
        self.locality = dict["locality"]?.stringValue
        self.subLocality = dict["sub_locality"]?.stringValue
        self.isOcean = dict["is_ocean"]?.boolValue
        self.dataSource = dict["data_source"]?.stringValue.flatMap { LocationSource(rawValue: $0) }
    }

    /// Converts to LocationDict format for events and backend communication.
    public func toJSONDict() -> LocationDict {
        var coordinateDict: [String: JSONValue] = [
            "lat": .double(location.coordinate.latitude),
            "lng": .double(location.coordinate.longitude),
        ]
        if location.verticalAccuracy > 0 {
            coordinateDict["alt"] = .double(location.altitude)
        }
        
        var dict: LocationDict = [
            "coordinate": .dictionary(coordinateDict),
        ]
        if let timezone = timezone, !timezone.isEmpty {
            dict["timezone"] = .string(timezone)
        }
        
        if let countryCode = countryCode, !countryCode.isEmpty {
            dict["country_code"] = .string(countryCode)
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
            dict["admin_area"] = .string(adminArea)
        }
        if let subAdminArea = subAdminArea, !subAdminArea.isEmpty {
            dict["sub_admin_area"] = .string(subAdminArea)
        }
        if let locality = locality, !locality.isEmpty {
            dict["locality"] = .string(locality)
        }
        if let subLocality = subLocality, !subLocality.isEmpty {
            dict["sub_locality"] = .string(subLocality)
        }
        if let dataSource = dataSource {
            dict["data_source"] = .string(dataSource.rawValue)
        }
        
        return dict
    }
}

// MARK: - Geocoder Error

/// Errors thrown by Geocoder when reverse geocoding fails.
public enum GeocoderError: Error, CustomStringConvertible {
    /// Both MapKit and Geoapify failed to produce valid geocoding results for the given location.
    case noResults(location: CLLocation)

    public var description: String {
        switch self {
        case .noResults(let location):
            return "Geocoder: no results for (\(location.coordinate.latitude), \(location.coordinate.longitude))"
        }
    }
}

// MARK: - Geocoder

/// Stateless geocoder: Geoapify autocomplete, MKLocalSearch, reverse geocode, and completion resolution.
/// The MKLocalSearchCompleter (incremental autocomplete) lives in AutocompleteManager (app layer)
/// because it requires @MainActor and a persistent delegate — not suited for a Sendable stateless service.
public final class Geocoder: Sendable {
    private let geoapifyApiKey: String
    private let apiClient: APIClient
    private let logger: Logger

    private static let geoapifyBaseURL = "https://api.geoapify.com/v1/geocode/autocomplete"
    private static let geoapifyReverseBaseURL = "https://api.geoapify.com/v1/geocode/reverse"
    private static let geoapifySearchBaseURL = "https://api.geoapify.com/v1/geocode/search"
    private static let geoapifyLimit = 8

    public init(
        geoapifyApiKey: String,
        apiClient: APIClient? = nil,
        logger: Logger? = nil
    ) {
        self.geoapifyApiKey = geoapifyApiKey
        self.apiClient = apiClient ?? APIClient(logger: logger ?? NoOpLogger())
        self.logger = logger ?? NoOpLogger()
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
    /// - Returns: LocationDetailData if the response contains valid results, nil if the response is malformed or empty.
    /// - Throws: Error if the API call fails.
    public func geocodeReverseGeoapify(location: CLLocation) async throws -> LocationDetailData? {
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
        return buildLocationDetailDataFromGeoapifyResponse(location: location, data: data)
    }

    /// Builds LocationDetailData from Geoapify reverse API response: { "query": { lat, lon }, "results": [ { state, country_code, city, suburb, ... } ] }.
    /// Returns nil if the response is malformed or contains no results.
    private func buildLocationDetailDataFromGeoapifyResponse(location: CLLocation, data: Data) -> LocationDetailData? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first else {
            return nil
        }
        return LocationDetailData(geoapifyProperties: first, location: location)
    }

    /// Composite reverse geocode: tries native MapKit first, falls back to Geoapify.
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: LocationDetailData with location, place_name, country_name, timezone, admin_area, locality, and display fields.
    /// - Throws: Error if both MapKit and Geoapify fail to produce valid results.
    public func geocodeReverse(location: CLLocation) async throws -> LocationDetailData {
        // Try native MapKit geocoder first
        do {
            if #available(macOS 26.0, iOS 26.0, *) {
                // Use MKReverseGeocodingRequest directly to preserve MKMapItem.timeZone
                // (placemark.timeZone may be nil for MKReverseGeocodingRequest results).
                if let result = try await geocodeReverseFromMapItems(location: location) {
                    return result
                }
            } else {
                let placemarks = try await geocodeReverseMKLegacy(location: location)
                if let placemark = placemarks.first {
                    return buildLocationDetailDataFromPlacemark(location: location, placemark: placemark)
                }
            }
        } catch {
            // MapKit failed, fall through to Geoapify
        }
        // Fallback to Geoapify
        if let result = try await geocodeReverseGeoapify(location: location) {
            return result
        }
        throw GeocoderError.noResults(location: location)
    }

    /// Reverse geocodes using MKReverseGeocodingRequest and builds LocationDetailData
    /// directly from MKMapItem to preserve mapItem.timeZone.
    @available(macOS 26.0, iOS 26.0, *)
    private func geocodeReverseFromMapItems(location: CLLocation) async throws -> LocationDetailData? {
        logger.info("Geocoding reverse using New Apple Geocoder (MKMapItem): \(location)")
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let mapItems = try await request.mapItems
        printItem(item: mapItems)
        guard let first = mapItems.first else { return nil }
        return buildLocationDetailDataFromMapItem(location: location, mapItem: first)
    }
    
    /// Builds LocationDetailData from an MKMapItem (from MKReverseGeocodingRequest).
    /// Uses mapItem.timeZone which is always populated, unlike placemark.timeZone.
    private func buildLocationDetailDataFromMapItem(location: CLLocation, mapItem: MKMapItem) -> LocationDetailData {
        return LocationDetailData(mapItem: mapItem, location: location)
    }

    /// Builds LocationDetailData from a CLPlacemark (from CLGeocoder legacy path).
    private func buildLocationDetailDataFromPlacemark(location: CLLocation, placemark: CLPlacemark) -> LocationDetailData {
        return LocationDetailData(placemark: placemark, location: location)
    }

    /// Forward geocodes a text query using Geoapify search API.
    /// Optionally filters by ISO 3166-1 alpha-2 country code (e.g., "SG", "US").
    /// - Parameters:
    ///   - text: The search text (e.g., a venue name or address).
    ///   - countryCode: Optional country code to narrow results.
    /// - Returns: The coordinate of the best match, or nil if no result is found.
    public func geocodeForward(text: String, countryCode: String? = nil) async throws -> CLLocationCoordinate2D? {
        var params: [String: String] = [
            "text": text,
            "format": "json",
            "apiKey": geoapifyApiKey,
            "limit": "1",
        ]
        if let code = countryCode, !code.isEmpty {
            params["filter"] = "countrycode:\(code.lowercased())"
        }
        let data = try await apiClient.asyncCallAPI(
            url: Self.geoapifySearchBaseURL,
            method: "GET",
            headers: nil,
            params: params,
            dataDict: [:],
            jsonDict: [:],
            timeout: false,
            filesDict: [:]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first,
              let lat = first["lat"] as? Double,
              let lon = first["lon"] as? Double else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    public func autocompleteGeoapify(query: String) async throws -> [MapSearchResult] {
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

    /// Resolves an MKLocalSearchCompletion into a full MKMapItem with coordinates.
    /// Used when the user selects a completer result from the autocomplete list (phase 2).
    /// - Parameter completion: The MKLocalSearchCompletion to resolve.
    /// - Returns: An MKMapItem with coordinates, or nil if resolution fails.
    public func resolveMapKitCompletion(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        // Wrap MKMapItem in @unchecked Sendable to cross the continuation boundary safely.
        // MKMapItem is read-only after creation so this is safe.
        struct SendableMapItem: @unchecked Sendable { let mapItem: MKMapItem }

        let wrapped: SendableMapItem? = await withCheckedContinuation { continuation in
            search.start { response, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                guard let response = response, let firstItem = response.mapItems.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: SendableMapItem(mapItem: firstItem))
            }
        }
        return wrapped?.mapItem
    }

    /// Interleaves two arrays, preferring results with type "city"; caps total at maxTotal.
    /// Public static so AutocompleteManager can use it for progressive merging.
    public static func interleave(maxTotal: Int, first: [MapSearchResult], second: [MapSearchResult]) -> [MapSearchResult] {
        var result: [MapSearchResult] = []
        var i = 0
        var j = 0
        while result.count < maxTotal, i < first.count || j < second.count {
            let fromFirst = i < first.count ? first[i] : nil
            let fromSecond = j < second.count ? second[j] : nil
            let firstIsCity = fromFirst?.isCityType ?? false
            let secondIsCity = fromSecond?.isCityType ?? false
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
