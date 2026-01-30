import Testing
import Foundation
@testable import core

/// One test case per name; use JSONTestCases.testCaseNames(inSubdirectory:) for all files, or a list for specific ones.
// private let geojsonTestCaseNamesForExtractFeatures: [String] = JSONTestCases.testCaseNames(inSubdirectory: "extractFeaturesDirect")

@Suite("GeoJSON tests")
struct GeoJSONTests {

    // Approved
    @Test(
        "extractFeatures from test case", 
        arguments: JSONTestCases.testCaseNames(inSubdirectory: "extractFeaturesDirect")
    )
    func extractFeaturesDirect(testCaseName: String) throws {
        let json = try JSONTestCases.loadJSONDictionary(
            testCaseName: testCaseName, 
            subdirectory: "extractFeaturesDirect"
            )
        let features = try GeoJSON.extractFeatures(from: json)
        let fileLabel = "\(testCaseName).json"
        try require(!features.isEmpty, success: "[\(fileLabel)] Features extracted", failure: "[\(fileLabel)] Expected at least 1 feature, got \(features.count)")
        let coord = pointCoordinate(from: features[0])
        try require(coord != nil, success: "[\(fileLabel)] First feature has Point coordinate", failure: "[\(fileLabel)] No coordinate on first feature")
    }

    @Test("extractFeatures from nested data.features")
    func extractFeaturesNestedData() throws {
        let json: [String: Any] = [
            "data": [
                "features": [
                    [
                        "type": "Feature",
                        "geometry": ["type": "Point", "coordinates": [0.0, 0.0]],
                        "properties": [:] as [String: Any]
                    ]
                ]
            ]
        ]
        let features = try GeoJSON.extractFeatures(from: json)
        try require(features.count == 1, success: "One feature from data.features", failure: "Expected 1, got \(features.count)")
    }

    @Test("extractFeatures throws invalidJSON for invalid structure")
    func extractFeaturesInvalid() throws {
        let invalid = ["not": "features"]
        do {
            _ = try GeoJSON.extractFeatures(from: invalid)
            try require(false, success: "", failure: "Expected invalidJSON to be thrown")
        } catch GeoJSON.GeoJSONError.invalidJSON {
            try require(true, success: "invalidJSON thrown", failure: "")
        } catch {
            try require(false, success: "", failure: "Wrong error: \(error)")
        }
    }

    @Test("setFeatures rounds coordinates to 4 decimal places")
    func setFeaturesRoundsCoordinates() throws {
        let raw: [String: Any] = [
            "type": "Feature",
            "geometry": ["type": "Point", "coordinates": [12.49640001, 41.90279999]],
            "properties": [:] as [String: Any]
        ]
        guard let featureDict = JSONValue.dictionary(from: raw) else {
            try require(false, success: "", failure: "Failed to build feature dict")
            return
        }
        var geoJSON = GeoJSON()
        geoJSON.setFeatures([featureDict])
        let coords = geoJSON.extractCoordinates()
        try require(coords.count == 1, success: "One coordinate", failure: "Got \(coords.count)")
        expect(coords[0].latitude == 41.9028, success: "Lat rounded to 41.9028", failure: "Lat is \(coords[0].latitude)")
        expect(coords[0].longitude == 12.4964, success: "Lon rounded to 12.4964", failure: "Lon is \(coords[0].longitude)")
    }

    @Test("extractCoordinates returns Coordinate2D array")
    func extractCoordinatesReturnsCoordinate2D() throws {
        let raw: [String: Any] = [
            "type": "Feature",
            "geometry": ["type": "Point", "coordinates": [2.35, 48.85]],
            "properties": [:] as [String: Any]
        ]
        guard let featureDict = JSONValue.dictionary(from: raw) else {
            try require(false, success: "", failure: "Failed to build feature dict")
            return
        }
        var geoJSON = GeoJSON()
        geoJSON.setFeatures([featureDict])
        let coords = geoJSON.extractCoordinates()
        try require(coords.count == 1, success: "One Coordinate2D", failure: "Got \(coords.count)")
        expect(coords[0].latitude == 48.85, success: "Coordinate2D latitude", failure: "\(coords[0].latitude)")
        expect(coords[0].longitude == 2.35, success: "Coordinate2D longitude", failure: "\(coords[0].longitude)")
    }

    @Test("PointFeature init validates Point geometry")
    func pointFeatureInitValid() throws {
        let featureDict: [String: JSONValue] = [
            "type": .string("Feature"),
            "geometry": .dictionary([
                "type": .string("Point"),
                "coordinates": .array([.double(12.5), .double(41.9)])
            ]),
            "properties": .dictionary(["name": .string("Colosseum")])
        ]
        let pointFeature = PointFeature(from: featureDict)
        try require(pointFeature != nil, success: "PointFeature created", failure: "PointFeature init returned nil")
        expect(pointFeature?.coordinate?.latitude == 41.9, success: "latitude", failure: "\(pointFeature?.coordinate?.latitude ?? 0)")
        expect(pointFeature?.coordinate?.longitude == 12.5, success: "longitude", failure: "\(pointFeature?.coordinate?.longitude ?? 0)")
        expect(pointFeature?.rawTitle == "Colosseum", success: "rawTitle from name", failure: "\(pointFeature?.rawTitle ?? "nil")")
        expect((pointFeature?.id.hasPrefix("poi_")) == true, success: "id prefix poi_", failure: "id is \(pointFeature?.id ?? "")")
    }

    @Test("PointFeature init returns nil for non-Point geometry")
    func pointFeatureInitInvalid() {
        let notPoint: [String: JSONValue] = [
            "type": .string("Feature"),
            "geometry": .dictionary([
                "type": .string("LineString"),
                "coordinates": .array([.double(0), .double(0)])
            ]),
            "properties": .dictionary([:])
        ]
        let pointFeature = PointFeature(from: notPoint)
        expect(pointFeature == nil, success: "nil for LineString", failure: "Expected nil for non-Point")
    }

    @Test("PointFeature properties and id")
    func pointFeaturePropertiesAndId() throws {
        let featureDict: [String: JSONValue] = [
            "type": .string("Feature"),
            "geometry": .dictionary([
                "type": .string("Point"),
                "coordinates": .array([.double(1.0), .double(2.0)])
            ]),
            "properties": .dictionary(["title": .string("A Place")])
        ]
        guard let pf = PointFeature(from: featureDict) else {
            try require(false, success: "", failure: "PointFeature nil")
            return
        }
        expect(pf.properties?["title"]?.stringValue == "A Place", success: "properties accessible", failure: "\(pf.properties ?? [:])")
        expect(pf.id == "poi_2.0_1.0", success: "id from coordinates", failure: "id is \(pf.id)")
        expect(pf.toDictionary()["geometry"] != nil, success: "toDictionary has geometry", failure: "toDictionary missing geometry")
    }
}

private func pointCoordinate(from feature: [String: JSONValue]) -> Coordinate2D? {
    guard let geometry = feature["geometry"],
          case .dictionary(let geometryDict) = geometry,
          let coordinates = geometryDict["coordinates"],
          case .array(let arr) = coordinates,
          arr.count >= 2 else { return nil }
    let lon: Double?
    let lat: Double?
    switch arr[0] {
    case .double(let v): lon = v
    case .int(let v): lon = Double(v)
    default: lon = nil
    }
    switch arr[1] {
    case .double(let v): lat = v
    case .int(let v): lat = Double(v)
    default: lat = nil
    }
    guard let longitude = lon, let latitude = lat else { return nil }
    return Coordinate2D(latitude: latitude, longitude: longitude)
}
