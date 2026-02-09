//
//  GeocoderTest.swift
//  coreTests
//
//  Tests for Geocoder (Geoapify + MapKit search).
//

import Testing
import Foundation
import CoreLocation
@preconcurrency import MapKit
@testable import core

@Suite("Geocoder")
struct GeocoderTests {

    @Test(
        "autocompleteGeoapify returns results when API key is set",
        arguments: ["Hag", "Shenzhe"]
    )
    func testAutocompleteGeoapify(query: String) async throws {
        let apiKey = ProcessInfo.processInfo.environment["GEOAPIFY_API_KEY"] ?? "e810e0454fda45acbf6b3fbaa7bebe15"
        guard !apiKey.isEmpty else { return }
        let geocoder = Geocoder(geoapifyApiKey: apiKey)
        let results = try await geocoder.autocompleteGeoapify(query: query)
        try require(
            !results.isEmpty,
            success: "Geoapify returned results",
            failure: "Geoapify results empty for query '\(query)'"
        )
        let first = results[0]
        printItem(item: first)
        expect(
            first.source == "geojson",
            success: "First result source is geojson",
            failure: "First result source is '\(first.source)', expected geojson"
        )
        expect(
            first.buildLocationDetailData() != nil,
            success: "First result can build LocationDetailData",
            failure: "First result buildLocationDetailData returned nil"
        )
        expect(
            !first.name.isEmpty || !first.address.isEmpty,
            success: "First result has name or address",
            failure: "First result has empty name and address"
        )
    }

    @Test(
        "geocodeReverseMK returns placemarks for a known coordinate",
        arguments: [
            // CLLocation(latitude: 22.559623109782347, longitude: 114.11698910372738), // Shenzhen, China
            // CLLocation(latitude: 41.008590, longitude: 28.978512), // 41.008918°N 28.979900°E Istanbul, Turkey
            // CLLocation(latitude: 43.235377, longitude: 32.636948), // 43.235377°N 32.636948°E Black Sea, Turkey
            CLLocation(latitude: 5.416011, longitude: 100.338764), // 5.416011°N 100.338764°E Penang, Malaysia
        ]
    )
    func geocodeReverseMK(location: CLLocation) async throws {
        let geocoder = Geocoder(geoapifyApiKey: "")
        let placemarks: [CLPlacemark]
        // printItem(item: location)
        do {
            placemarks = try await geocoder.geocodeReverseMK(location: location)
        } catch let error as CLError {
            print("================")
            print("⚠️ CLError for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("   code: \(error.code.rawValue), description: \(error.localizedDescription)")
            print("================")
            return
        } catch let error as MKError {
            print("================")
            print("⚠️ MKError for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("   code: \(error.code.rawValue), description: \(error.localizedDescription)")
            print("================")
            return
        }
        try require(
            !placemarks.isEmpty,
            success: "Reverse geocode returned placemarks",
            failure: "Reverse geocode returned empty array"
        )
        let first = placemarks[0]
        expect(
            first.location != nil,
            success: "First placemark has location",
            failure: "First placemark location is nil"
        )
        expect(
            !(first.locality?.isEmpty ?? true) || !(first.country?.isEmpty ?? true),
            success: "First placemark has locality or country",
            failure: "First placemark has empty locality and country"
         )
    }

    @Test(
        "geocodeReverse",
        arguments: [
            CLLocation(latitude: 35.01161, longitude: 135.76811), // Kyoto, Japan
            CLLocation(latitude: 22.352725, longitude: 114.139399), // Hong Kong, China
            CLLocation(latitude: 22.559623109782347, longitude: 114.11698910372738), // Shenzhen, China
            CLLocation(latitude: 41.008918, longitude: 28.979900), 
            CLLocation(latitude: 1.283333, longitude: 103.833333), // Singapore, Singapore
            CLLocation(latitude: 5.416011, longitude: 100.338764), // Penang, Malaysia
            CLLocation(latitude: -6.1753, longitude: 106.8269), // Jakarta, Indonesia
            CLLocation(latitude: 35.0, longitude: 18.0), // Mediterranean Sea
            CLLocation(latitude: 41.902222, longitude: 12.453333), // Vatican City, Italy
            CLLocation(latitude: 30.333000, longitude: 89.051053), // Himlayas
            CLLocation(latitude: 40.0, longitude: 20.0), // Albania
            CLLocation(latitude: 42.569393, longitude: 88.465132), // Lake Garda
            CLLocation(latitude:30.0, longitude: -40.0), 
            CLLocation(latitude: 68.1386, longitude: 24.2215), // Rovaniemi, Finland
            CLLocation(latitude: 55.7569, longitude: 37.6151), // Moscow, Russia
        ]
    )
    func geocodeReverse(location: CLLocation) async throws {
        let apiKey = ProcessInfo.processInfo.environment["GEOAPIFY_API_KEY"] ?? "e810e0454fda45acbf6b3fbaa7bebe15"
        guard !apiKey.isEmpty else { return }
        let geocoder = Geocoder(geoapifyApiKey: apiKey)
        let locationDetail = try await geocoder.geocodeReverse(location: location)
        let placeName = locationDetail.placeName ?? "unknown"

        let locationDetailConditions: [(condition: Bool, failure: String)] = [
            (
                abs(locationDetail.location.coordinate.latitude - location.coordinate.latitude) < 0.001 &&
                abs(locationDetail.location.coordinate.longitude - location.coordinate.longitude) < 0.001,
                "\(placeName): coordinates don't match input"
            ),
            (
                locationDetail.timezone != nil && !locationDetail.timezone!.isEmpty,
                "\(placeName): missing timezone"
            ),
            (
                locationDetail.countryCode != nil && !locationDetail.countryCode!.isEmpty,
                "\(placeName): missing country_code"
            ),
            (
                (locationDetail.adminArea != nil && !locationDetail.adminArea!.isEmpty) ||
                (locationDetail.locality != nil && !locationDetail.locality!.isEmpty),
                "\(placeName): missing both admin_area and locality"
            ),
        ]
        expectAll(locationDetailConditions, success: "\(placeName): locationDetail has all expected fields")
        
        // Verify toLocationDict() produces valid dict
        let locationDict = locationDetail.toLocationDict()
        printItem(item: locationDict)
    }
}
