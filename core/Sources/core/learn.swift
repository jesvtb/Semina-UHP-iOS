import Foundation
import MapKit

/// Normalizes GeoJSON data so `MKGeoJSONDecoder` can decode it. If the root is an array of Feature objects, wraps it in a FeatureCollection.
public func shapeIntoFeatureCollection(from data: Data) throws -> Data {
    let decoder = JSONDecoder()
    let value = try decoder.decode(JSONValue.self, from: data)
    if case .array(let features) = value, !features.isEmpty {
        let wrapped: JSONValue = .dictionary([
            "type": .string("FeatureCollection"),
            "features": .array(features)
        ])
        let encoder = JSONEncoder()
        return try encoder.encode(wrapped)
    }
    return data
}

extension Data {

    func shapeIntoJsonValue() throws -> JSONValue {
        let jsonValue = try JSONDecoder().decode(JSONValue.self, from: self)
        if let dict = jsonValue.dictionaryValue {
            let prettyDict = JSONValue.prettyDict(dict)
            print("prettyDict:\n\(prettyDict)")
            return .dictionary(dict)
        } else {
            throw JSONValue.JSONError.invalidJSON(message: "JSONValue is not a dictionary")
        }
    }

    func extractFeatures() throws -> [MKGeoJSONFeature] {
        let jsonDecoder = JSONDecoder()
        let geojsonDecoder = MKGeoJSONDecoder()
        let value = try jsonDecoder.decode(JSONValue.self, from: self)
        if case .array(let features) = value, !features.isEmpty {
            let wrapped: JSONValue = .dictionary([
                "type": .string("FeatureCollection"),
                "features": .array(features)
            ])
            let wrappedData = try JSONEncoder().encode(wrapped)
            let geoJSONObjects: [MKGeoJSONObject] = try geojsonDecoder.decode(wrappedData)
            return geoJSONObjects.compactMap { $0 as? MKGeoJSONFeature }
        }
        let geoJSONObjects: [MKGeoJSONObject] = try geojsonDecoder.decode(self)
        return geoJSONObjects.compactMap { $0 as? MKGeoJSONFeature }
    }
}

/// Builds a walkable route polyline across stop coordinates using MapKit directions.
/// Falls back to direct segment endpoints if directions are unavailable.
public func buildWalkingRouteCoordinatesWithMapKit(from stops: [Coordinate2D]) async -> [Coordinate2D] {
    guard stops.count >= 2 else { return stops }

    var fullRouteCoordinates: [Coordinate2D] = []
    for segmentStartIndex in 0..<(stops.count - 1) {
        let start = stops[segmentStartIndex]
        let end = stops[segmentStartIndex + 1]
        let segmentCoordinates = await fetchWalkingSegmentCoordinates(start: start, end: end)
        let resolvedSegment = segmentCoordinates.isEmpty ? [start, end] : segmentCoordinates
        if fullRouteCoordinates.isEmpty {
            fullRouteCoordinates.append(contentsOf: resolvedSegment)
        } else {
            fullRouteCoordinates.append(contentsOf: resolvedSegment.dropFirst())
        }
    }
    return fullRouteCoordinates
}

private func fetchWalkingSegmentCoordinates(start: Coordinate2D, end: Coordinate2D) async -> [Coordinate2D] {
    let request = MKDirections.Request()
    request.transportType = .walking
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
        latitude: start.latitude,
        longitude: start.longitude
    )))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
        latitude: end.latitude,
        longitude: end.longitude
    )))

    do {
        let response = try await MKDirections(request: request).calculate()
        guard let polyline = response.routes.first?.polyline else {
            return []
        }
        return polyline.coordinates.map { coordinate in
            Coordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    } catch {
        return []
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        var buffer = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: pointCount
        )
        getCoordinates(&buffer, range: NSRange(location: 0, length: pointCount))
        return buffer
    }
}