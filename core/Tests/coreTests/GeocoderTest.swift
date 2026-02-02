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

    @Test("geocodeReverseMK returns placemarks for a known coordinate")
    func testGeocodeReverseMK() async throws {
        let geocoder = Geocoder(geoapifyApiKey: "")
        let location = CLLocation(
            latitude: 22.559614,
            longitude: 114.116995
        )
        let placemarks: [CLPlacemark]
        // printItem(item: location)
        do {
            placemarks = try await geocoder.geocodeReverseMK(location: location)
            printItem(item: placemarks)
        } catch is CLError {
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

    @Test("geocodeReverse returns LocationDict with expected keys when API key is set")
    func testGeocodeReverse() async throws {
        let apiKey = ProcessInfo.processInfo.environment["GEOAPIFY_API_KEY"] ?? "e810e0454fda45acbf6b3fbaa7bebe15"
        guard !apiKey.isEmpty else { return }
        let geocoder = Geocoder(geoapifyApiKey: apiKey)
        let location = CLLocation(latitude: 52.518_948_879_280_74, longitude: 13.409_808_180_753_316)
        let locationDict = try await geocoder.geocodeReverse(location: location)
        try require(
            locationDict["coordinate"] != nil,
            success: "LocationDict has coordinate",
            failure: "LocationDict missing coordinate"
        )
        try require(
            locationDict["timestamp"] != nil,
            success: "LocationDict has timestamp",
            failure: "LocationDict missing timestamp"
        )
        expect(
            locationDict["timezone"] != nil,
            success: "LocationDict has timezone",
            failure: "LocationDict missing timezone"
        )
    }
}
