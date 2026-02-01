//
//  GeocodingServiceTests.swift
//  coreTests
//
//  Tests for GeocodingService (forward/reverse geocoding).
//

import Testing
import Foundation
import CoreLocation
@testable import core

@Suite("GeocodingService")
struct GeocodingServiceTests {

    /// Uses the real CLGeocoder to geocode an address and verifies the returned placemark shape and that parsing gives the expected format.
    @Test("geocodeAddress with real geocoder returns placemark in expected format")
    @MainActor
    func geocodeAddressRealGeocoderReturnsExpectedFormat() async throws {
        let service = GeocodingService()
        let address = "Apple Park, Cupertino, CA"

        let placemark = try await service.geocodeAddress(address)

        expect(
            placemark.location != nil,
            success: "Placemark has location",
            failure: "Placemark.location is nil"
        )
        guard let loc = placemark.location else { return }
        expect(
            loc.coordinate.latitude != 0 || loc.coordinate.longitude != 0,
            success: "Placemark has non-zero coordinates",
            failure: "Coordinates are zero"
        )
        expect(
            placemark.country != nil && !(placemark.country?.isEmpty ?? true),
            success: "Placemark has country",
            failure: "Placemark.country is nil or empty"
        )
        expect(
            placemark.isoCountryCode != nil && (placemark.isoCountryCode?.count == 2),
            success: "Placemark has 2-letter country code",
            failure: "country code missing or not 2 chars: \(placemark.isoCountryCode ?? "nil")"
        )
    }

    /// Uses the real CLGeocoder to reverse-geocode a location and verifies constructNewLocation output format.
    @Test("constructNewLocation with real geocoder returns NewLocation in expected format")
    @MainActor
    func constructNewLocationRealGeocoderReturnsExpectedFormat() async throws {
        let service = GeocodingService()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.334_900, longitude: -122.009_020),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: -1,
            timestamp: Date()
        )

        let result = try await service.constructNewLocation(from: location)

        guard let coordinateValue = result["coordinate"],
              case .dictionary(let coordinateDict) = coordinateValue,
              case .double(let lat) = coordinateDict["lat"],
              case .double(let lng) = coordinateDict["lng"] else {
            Issue.record("NewLocation missing coordinate.lat/lng")
            return
        }
        expect(
            lat == 37.334_900 && lng == -122.009_020,
            success: "Coordinate matches input location",
            failure: "Coordinate wrong: lat=\(lat), lng=\(lng)"
        )

        guard case .string(let timezone) = result["timezone"] else {
            Issue.record("NewLocation timezone missing or not string")
            return
        }
        expect(
            !timezone.isEmpty,
            success: "Timezone is non-empty",
            failure: "Timezone is empty"
        )

        guard case .double(let timestamp) = result["timestamp"] else {
            Issue.record("NewLocation timestamp missing or not number")
            return
        }
        expect(
            timestamp > 0,
            success: "Timestamp is positive",
            failure: "Timestamp is not positive: \(timestamp)"
        )

        if case .string(let countryCode) = result["country_code"] {
            expect(
                countryCode.count == 2,
                success: "country_code is 2-letter ISO code",
                failure: "country_code not 2 chars: \(countryCode)"
            )
        }
        if case .string(let placeName) = result["place_name"] {
            expect(
                !placeName.isEmpty,
                success: "place_name is non-empty when present",
                failure: "place_name is empty"
            )
        }
    }

    /// Real geocoder: geocode address then verify we can build a NewLocation-style structure from the placemark.
    @Test("geocodeAddress then build NewLocation format with real geocoder")
    @MainActor
    func geocodeAddressThenNewLocationFormatRealGeocoder() async throws {
        let service = GeocodingService()
        let address = "Hagia Sophia"

        let placemark = try await service.geocodeAddress(address)
        print("Placemark: \(placemark)")
        guard let loc = placemark.location else {
            Issue.record("Placemark has no location")
            return
        }

        let result = try await service.constructNewLocation(from: loc)

        expect(
            result["coordinate"] != nil,
            success: "Result has coordinate",
            failure: "coordinate missing"
        )
        expect(
            result["timezone"] != nil,
            success: "Result has timezone",
            failure: "timezone missing"
        )
        expect(
            result["timestamp"] != nil,
            success: "Result has timestamp",
            failure: "timestamp missing"
        )
    }
}
