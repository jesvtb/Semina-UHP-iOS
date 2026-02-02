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

    /// Reverse geocodes a location using CLGeocoder (MapKit/Core Location).
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: Array of CLPlacemark from the reverse geocode (may be empty).
    /// - Throws: Error if reverse geocoding fails.
    public func geocodeReverseMK(location: CLLocation) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: placemarks ?? [])
            }
        }
    }

    /// Reverse geocodes a location using Geoapify reverse geocode API.
    /// Parses the API response (query + results) into a LocationDict. Geoapify returns { "query": { lat, lon }, "results": [ { address fields } ] }, not GeoJSON.
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: LocationDict with coordinate, place_name, subdivisions, country_name, timezone, timestamp.
    /// - Throws: Error if the API call or parsing fails.
    public func geocodeReverseGeoapify(location: CLLocation) async throws -> LocationDict {
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
        return buildLocationDictFromGeoapifyReverseResponse(location: location, data: data)
    }

    /// Builds a LocationDict from Geoapify reverse API response: { "query": { lat, lon }, "results": [ { state, country_code, city, suburb, ... } ] }.
    private func buildLocationDictFromGeoapifyReverseResponse(location: CLLocation, data: Data) -> LocationDict {
        var coordinateDict: [String: JSONValue] = [
            "lat": .double(location.coordinate.latitude),
            "lng": .double(location.coordinate.longitude),
        ]
        if location.verticalAccuracy > 0 {
            coordinateDict["alt"] = .double(location.altitude)
        }
        var dict: LocationDict = [
            "coordinate": .dictionary(coordinateDict),
            "timestamp": .double(location.timestamp.timeIntervalSince1970),
            "timezone": .string(TimeZone.current.identifier),
        ]

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first else {
            return dict
        }

        if let code = first["country_code"] as? String {
            dict["country_code"] = .string(code)
        }
        let suburb = (first["suburb"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = (first["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = (first["state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subdivisionParts = [suburb, city, state].compactMap { $0 }.filter { !$0.isEmpty }
        if !subdivisionParts.isEmpty {
            dict["subdivisions"] = .string(subdivisionParts.joined(separator: ", "))
        }
        let placeName = (first["address_line1"] as? String) ?? (first["name"] as? String) ?? (first["city"] as? String)
        if let name = placeName, !name.isEmpty {
            dict["place_name"] = .string(name)
        }
        if let country = first["country"] as? String {
            dict["country_name"] = .string(country)
        }
        if let tzObj = first["timezone"] as? [String: Any], let tzName = tzObj["name"] as? String {
            dict["timezone"] = .string(tzName)
        }
        return dict
    }

    /// Reverse geocodes a location using Geoapify and returns a LocationDict (NewLocation schema) for events and content.
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: LocationDict with coordinate, place_name, subdivisions, country_name, timezone, timestamp.
    /// - Throws: Error if the API call or parsing fails.
    public func geocodeReverse(location: CLLocation) async throws -> LocationDict {
        try await geocodeReverseGeoapify(location: location)
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
