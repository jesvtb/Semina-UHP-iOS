//
//  GeocodingService.swift
//  core
//
//  Geocoding operations using CLGeocoder. Owns a single CLGeocoder instance.
//

import Foundation
import CoreLocation

/// Service that performs reverse geocoding using CLGeocoder.
/// Callers should use the shared instance unless dependency injection is required.
/// MainActor-isolated so LocationManager (also @MainActor) can call it without cross-actor send.
@MainActor
public final class GeocodingService {

    /// nonisolated(unsafe) so static `shared` initializer can set it; all method use is on MainActor.
    nonisolated(unsafe) private let geocoder: CLGeocoder

    public static let shared: GeocodingService = GeocodingService()

    /// Nonisolated so static `shared` can be initialized; method calls remain MainActor-isolated.
    nonisolated public init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    /// Reverse geocodes a location to placemarks. Cancels any in-flight geocode before starting.
    /// - Parameter location: The location to reverse geocode.
    /// - Returns: Array of placemarks (may be empty).
    /// - Throws: Error if reverse geocoding fails.
    public func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        geocoder.cancelGeocode()
        return try await geocoder.reverseGeocodeLocation(location)
    }
}
