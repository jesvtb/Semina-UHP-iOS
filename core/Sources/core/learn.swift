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