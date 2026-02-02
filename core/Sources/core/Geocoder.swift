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

/// Stateless geocoder that runs Geoapify autocomplete and MKLocalSearch in parallel,
/// merges and caps results. Used by app-level AutocompleteManager.
public final class Geocoder: Sendable {
    private let geoapifyApiKey: String
    private let apiClient: APIClient
    private let logger: Logger

    private static let geoapifyBaseURL = "https://api.geoapify.com/v1/geocode/autocomplete"
    private static let geoapifyLimit = 3
    private static let mapKitLimit = 3
    private static let maxTotalResults = 6

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

        async let geoapifyResults = fetchGeoapifyResults(query: trimmed)
        async let mapKitResults = fetchMapKitResults(query: trimmed)

        let (geoapify, mapKit) = try await (geoapifyResults, mapKitResults)
        return interleave(maxTotal: Self.maxTotalResults, first: geoapify, second: mapKit)
    }

    private func fetchGeoapifyResults(query: String) async throws -> [MapSearchResult] {
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
        return features.map { MapSearchResult($0) }
    }

    private func fetchMapKitResults(query: String) async -> [MapSearchResult] {
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

    /// Interleaves two arrays, alternating; caps total at maxTotal.
    private func interleave(maxTotal: Int, first: [MapSearchResult], second: [MapSearchResult]) -> [MapSearchResult] {
        var result: [MapSearchResult] = []
        let maxIndex = max(first.count, second.count)
        for i in 0..<maxIndex {
            if result.count >= maxTotal { break }
            if i < first.count { result.append(first[i]) }
            if result.count >= maxTotal { break }
            if i < second.count { result.append(second[i]) }
        }
        return result
    }
}
