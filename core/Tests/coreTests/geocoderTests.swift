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
        "Geocoder.search returns results when API key is set",
        arguments: ["Hagia Sophi", "ista"]
    )
    func testGeocoderSearch(query: String) async throws {
        let apiKey = ProcessInfo.processInfo.environment["GEOAPIFY_API_KEY"] ?? ""
        guard !apiKey.isEmpty else { return }
        let geocoder = Geocoder(geoapifyApiKey: apiKey)
        let results = try await geocoder.search(query: query)
        try require(
            !results.isEmpty,
            success: "Geocoder returned results",
            failure: "Results empty for query '\(query)'"
        )
        let first = results[0]
        expect(
            first.coordinate != nil,
            success: "First result has coordinate",
            failure: "First result coordinate is nil"
        )
        expect(
            !first.name.isEmpty || !first.address.isEmpty,
            success: "First result has name or address",
            failure: "First result has empty name and address"
        )
    }

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
            first.coordinate != nil,
            success: "First result has coordinate",
            failure: "First result coordinate is nil"
        )
        expect(
            !first.name.isEmpty || !first.address.isEmpty,
            success: "First result has name or address",
            failure: "First result has empty name and address"
        )
    }

    @Test(
        "autocompleteMapKit returns results for natural language query",
        arguments: ["Apple Park", "Cupertino"]
    )
    func testAutocompleteMapKit(query: String) async throws {
        let geocoder = Geocoder(geoapifyApiKey: "")
        let results = await geocoder.autocompleteMapKit(query: query)
        try require(
            !results.isEmpty,
            success: "MapKit returned results",
            failure: "MapKit results empty for query '\(query)'"
        )
        let first = results[0]
        expect(
            first.source == "mapkit",
            success: "First result source is mapkit",
            failure: "First result source is '\(first.source)', expected mapkit"
        )
        expect(
            first.coordinate != nil,
            success: "First result has coordinate",
            failure: "First result coordinate is nil"
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
        "geocodeReverse returns LocationDetailData with expected fields when API key is set",
        arguments: [
            // CLLocation(latitude: 22.559623109782347, longitude: 114.11698910372738), // Shenzhen, China
            CLLocation(latitude: 41.008918, longitude: 28.979900), 
            // CLLocation(latitude: 5.416011, longitude: 100.338764), // Penang, Malaysia
            // CLLocation(latitude: 35.0, longitude: 18.0), // Mediterranean Sea
            // CLLocation(latitude: 30.333000, longitude: 89.051053), // Himlayas
            
            // CLLocation(latitude: 42.569393, longitude: 88.465132), // Lake Garda
            // CLLocation(latitude:30.0, longitude: -40.0),  
        ]
    )
    func geocodeReverse(location: CLLocation) async throws {
        let apiKey = ProcessInfo.processInfo.environment["GEOAPIFY_API_KEY"] ?? "e810e0454fda45acbf6b3fbaa7bebe15"
        guard !apiKey.isEmpty else { return }
        let geocoder = Geocoder(geoapifyApiKey: apiKey)
        let locationDetailData = try await geocoder.geocodeReverse(location: location)
        printItem(item: locationDetailData)

        // Verify location is set with correct coordinates
        try require(
            abs(locationDetailData.location.coordinate.latitude - location.coordinate.latitude) < 0.001 &&
            abs(locationDetailData.location.coordinate.longitude - location.coordinate.longitude) < 0.001,
            success: "LocationDetailData has correct coordinates",
            failure: "LocationDetailData coordinates don't match input"
        )
        
        expect(
            !locationDetailData.timezone.isEmpty,
            success: "LocationDetailData has timezone: \(locationDetailData.timezone)",
            failure: "LocationDetailData missing timezone"
        )
        
        // Verify toLocationDict() produces valid dict
        let locationDict = locationDetailData.toLocationDict()
        expect(
            locationDict["coordinate"] != nil,
            success: "toLocationDict() includes coordinate",
            failure: "toLocationDict() missing coordinate"
        )
        expect(
            locationDict["timezone"] != nil,
            success: "toLocationDict() includes timezone",
            failure: "toLocationDict() missing timezone"
        )
        
        // Log display fields for debugging
        if let adminArea = locationDetailData.adminArea {
            print("  adminArea: \(adminArea)")
        }
        if let subAdminArea = locationDetailData.subAdminArea {
            print("  subAdminArea: \(subAdminArea)")
        }
        if let locality = locationDetailData.locality {
            print("  locality: \(locality)")
        }
        if let subLocality = locationDetailData.subLocality {
            print("  subLocality: \(subLocality)")
        }
    }
}
