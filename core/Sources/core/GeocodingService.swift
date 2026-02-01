//
//  GeocodingService.swift
//  core
//
//  Geocoding operations using CLGeocoder. Owns a single CLGeocoder instance.
//

import Foundation
import CoreLocation

/// Service that performs forward and reverse geocoding using CLGeocoder.
/// Callers should use the shared instance unless dependency injection is required.
/// MainActor-isolated so LocationManager (also @MainActor) can call it without cross-actor send.
@MainActor
public final class GeocodingService {

    /// nonisolated(unsafe) so static `shared` initializer can set it; all method use is on MainActor.
    nonisolated(unsafe) private let geocoder: CLGeocoder

    public static nonisolated(unsafe) let shared: GeocodingService = GeocodingService()

    /// Nonisolated so static `shared` can be initialized; method calls remain MainActor-isolated.
    nonisolated public init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    /// Geocodes an address string to a single placemark.
    /// - Parameter addressString: The address or location name to geocode.
    /// - Returns: The first placemark if geocoding succeeds.
    /// - Throws: Error if the string is empty, geocoding fails, or no results are found.
    public func geocodeAddress(_ addressString: String) async throws -> CLPlacemark {
        let trimmed = addressString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "GeocodingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Address string cannot be empty"])
        }

        geocoder.cancelGeocode()

        return try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(trimmed) { placemarks, error in
                let result: Result<CLPlacemark, Error>
                if let error = error {
                    result = .failure(error)
                } else if let placemark = placemarks?.first {
                    result = .success(placemark)
                } else {
                    result = .failure(NSError(domain: "GeocodingService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No results found for address"]))
                }
                switch result {
                case .success(let placemark):
                    continuation.resume(returning: placemark)
                case .failure(let err):
                    continuation.resume(throwing: err)
                }
            }
        }
    }

    /// Reverse geocodes a location to placemarks. Cancels any in-flight geocode before starting.
    /// - Parameter location: The location to reverse geocode.
    /// - Returns: Array of placemarks (may be empty).
    /// - Throws: Error if reverse geocoding fails.
    public func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        geocoder.cancelGeocode()
        return try await geocoder.reverseGeocodeLocation(location)
    }

    /// Reverse geocodes a location and builds a NewLocation dictionary.
    /// - Parameter location: The CLLocation to reverse geocode.
    /// - Returns: A dictionary matching the NewLocation schema with coordinate and location details.
    /// - Throws: Error if reverse geocoding fails.
    public func constructNewLocation(from location: CLLocation) async throws -> [String: JSONValue] {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        return Geocode.buildNewLocationDict(location: location, placemark: placemarks.first)
    }
}
