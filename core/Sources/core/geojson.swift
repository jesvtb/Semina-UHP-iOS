//
//  geojson.swift
//  core
//
//  GeoJSON and PointFeature types; framework-agnostic (no CoreLocation).
//

import Foundation

// MARK: - Coordinate2D

/// A generic coordinate (latitude, longitude) without CoreLocation dependency.
public struct Coordinate2D: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Point Coordinate Parsing (shared)

/// Parses a Point geometry coordinate from a GeoJSON feature.
/// GeoJSON format: [longitude, latitude]. Returns nil if not a valid Point feature.
fileprivate func parsePointCoordinate(from feature: [String: JSONValue]) -> Coordinate2D? {
    guard let geometry = feature["geometry"],
          case .dictionary(let geometryDict) = geometry,
          let typeValue = geometryDict["type"],
          case .string(let geometryType) = typeValue,
          geometryType == "Point",
          let coordinatesValue = geometryDict["coordinates"],
          case .array(let coordinatesArray) = coordinatesValue,
          coordinatesArray.count >= 2,
          let longitude = coordinatesArray[0].doubleValue,
          let latitude = coordinatesArray[1].doubleValue else {
        return nil
    }
    return Coordinate2D(latitude: latitude, longitude: longitude)
}

// MARK: - GeoJSON

/// A type-safe representation of a GeoJSON FeatureCollection.
/// Supports setting, updating, and removing features individually or in bulk.
public struct GeoJSON: Sendable, Codable {
    /// The type of GeoJSON object (always "FeatureCollection" for this struct)
    public var type: String {
        return "FeatureCollection"
    }

    /// Array of GeoJSON features
    public private(set) var features: [[String: JSONValue]]

    /// Initialize an empty FeatureCollection
    public init() {
        self.features = []
    }

    /// Initialize with existing features
    /// Coordinates are automatically rounded to 4 decimal places
    /// - Parameter features: Array of feature dictionaries
    public init(features: [[String: JSONValue]]) {
        self.features = features.map { Self.roundCoordinatesInFeature($0) }
    }

    // MARK: - Coordinate Rounding

    /// Rounds coordinates in a GeoJSON feature to 4 decimal places
    /// GeoJSON coordinates format: [longitude, latitude]
    private static func roundCoordinatesInFeature(_ feature: [String: JSONValue]) -> [String: JSONValue] {
        guard let coord = parsePointCoordinate(from: feature) else {
            return feature
        }
        let roundedLon = round(coord.longitude * 10000) / 10000
        let roundedLat = round(coord.latitude * 10000) / 10000
        var roundedFeature = feature
        guard let geometryValue = feature["geometry"],
              case .dictionary(var geometry) = geometryValue,
              let typeValue = geometry["type"],
              case .string(let geometryType) = typeValue,
              geometryType == "Point",
              let coordinatesValue = geometry["coordinates"],
              case .array(var coordinates) = coordinatesValue,
              coordinates.count >= 2 else {
            return feature
        }
        coordinates[0] = .double(roundedLon)
        coordinates[1] = .double(roundedLat)
        geometry["coordinates"] = .array(coordinates)
        roundedFeature["geometry"] = .dictionary(geometry)
        return roundedFeature
    }

    // MARK: - Feature Management

    /// Set all features, replacing any existing features
    public mutating func setFeatures(_ features: [[String: JSONValue]]) {
        self.features = features.map { Self.roundCoordinatesInFeature($0) }
    }

    /// Add or update a single feature at the specified index
    @discardableResult
    public mutating func setFeature(_ feature: [String: JSONValue], at index: Int? = nil) -> Int? {
        let roundedFeature = Self.roundCoordinatesInFeature(feature)
        if let index = index {
            guard index >= 0 && index <= features.count else { return nil }
            if index < features.count {
                features[index] = roundedFeature
            } else {
                features.append(roundedFeature)
            }
            return index
        } else {
            features.append(roundedFeature)
            return features.count - 1
        }
    }

    /// Update a feature at the specified index
    @discardableResult
    public mutating func updateFeature(_ feature: [String: JSONValue], at index: Int) -> Bool {
        guard index >= 0 && index < features.count else { return false }
        features[index] = Self.roundCoordinatesInFeature(feature)
        return true
    }

    /// Remove a feature at the specified index
    @discardableResult
    public mutating func removeFeature(at index: Int) -> [String: JSONValue]? {
        guard index >= 0 && index < features.count else { return nil }
        return features.remove(at: index)
    }

    /// Remove all features
    public mutating func removeAllFeatures() {
        features.removeAll()
    }

    /// Get a feature at the specified index
    public func getFeature(at index: Int) -> [String: JSONValue]? {
        guard index >= 0 && index < features.count else { return nil }
        return features[index]
    }

    /// Get the number of features
    public var featureCount: Int {
        features.count
    }

    // MARK: - Coordinate Extraction

    /// Extracts all coordinates from GeoJSON features (Point geometry only).
    public func extractCoordinates() -> [Coordinate2D] {
        features.compactMap { parsePointCoordinate(from: $0) }
    }

    // MARK: - Feature Extraction

    /// Extracts features from a GeoJSON response dictionary.
    /// Handles direct features, nested in data, or result.data.
    public static func extractFeatures(from jsonDict: Any) throws -> [[String: JSONValue]] {
        guard let dict = jsonDict as? [String: Any] else {
            throw GeoJSONError.invalidJSON
        }
        var features: [[String: Any]]
        if let directFeatures = dict["features"] as? [[String: Any]] {
            features = directFeatures
        } else if let data = dict["data"] as? [String: Any],
                  let dataFeatures = data["features"] as? [[String: Any]] {
            features = dataFeatures
        } else if let result = dict["result"] as? [String: Any],
                  let resultData = result["data"] as? [String: Any],
                  let resultFeatures = resultData["features"] as? [[String: Any]] {
            features = resultFeatures
        } else {
            throw GeoJSONError.invalidJSON
        }
        return try features.map { featureDict in
            guard let jsonValueDict = JSONValue.dictionary(from: featureDict) else {
                throw GeoJSONError.invalidJSON
            }
            return jsonValueDict
        }
    }

    public enum GeoJSONError: Error, Sendable {
        case invalidJSON
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
        case features
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("FeatureCollection", forKey: .type)
        try container.encode(features, forKey: .features)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(String.self, forKey: .type)
        features = try container.decode([[String: JSONValue]].self, forKey: .features)
    }
}

// MARK: - PointFeature

/// A type-safe representation of a GeoJSON Point feature.
public struct PointFeature: Sendable, Identifiable {
    private let feature: [String: JSONValue]

    /// Stable identifier based on coordinates, or raw title / UUID fallback
    public var id: String {
        if let coord = coordinate {
            return "poi_\(coord.latitude)_\(coord.longitude)"
        }
        return "poi_\(rawTitle ?? UUID().uuidString)"
    }

    /// Simple title fallback from properties (title or name only); app layer adds device_lang priority.
    public var rawTitle: String? {
        guard let properties = properties else { return nil }
        if let titleValue = properties["title"], let title = titleValue.stringValue { return title }
        if let nameValue = properties["name"], let name = nameValue.stringValue { return name }
        return nil
    }

    /// Failable initializer that validates Point geometry
    public init?(from feature: [String: JSONValue]) {
        guard parsePointCoordinate(from: feature) != nil else {
            return nil
        }
        self.feature = feature
    }

    /// Coordinate from Point geometry (generic type, no CoreLocation)
    public var coordinate: Coordinate2D? {
        parsePointCoordinate(from: feature)
    }

    /// Properties dictionary from the feature
    public var properties: [String: JSONValue]? {
        guard let propertiesValue = feature["properties"],
              case .dictionary(let propertiesDict) = propertiesValue else {
            return nil
        }
        return propertiesDict
    }

    /// Image URL from properties (img_url)
    public var imageURL: URL? {
        guard let properties = properties,
              let imgURLValue = properties["img_url"],
              let imgURL = imgURLValue.stringValue else {
            return nil
        }
        let trimmedURL = imgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// Wikipedia URL from properties (wikipedia.url)
    public var wikipediaURL: URL? {
        guard let properties = properties,
              let wikipediaValue = properties["wikipedia"],
              let wikipedia = wikipediaValue.dictionaryValue,
              let urlValue = wikipedia["url"],
              let urlString = urlValue.stringValue,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    /// Subtitle string from properties (city, state/region, country)
    /// e.g. "City, State, Country"
    public var subtitle: String {
        guard let properties = properties else {
            return ""
        }
        var components: [String] = []
        if let cityValue = properties["city"],
           let city = cityValue.stringValue,
           !city.isEmpty {
            components.append(city)
        }
        if let stateValue = properties["state"] ?? properties["region"],
           let state = stateValue.stringValue,
           !state.isEmpty {
            components.append(state)
        }
        if let countryValue = properties["country"],
           let country = countryValue.stringValue,
           !country.isEmpty {
            components.append(country)
        }
        return components.joined(separator: ", ")
    }

    /// Convert back to dictionary format
    public func toDictionary() -> [String: JSONValue] {
        feature
    }

    /// Pretty print for debugging
    public func prettyPrint() {
        let coordString: String
        if let coord = coordinate {
            coordString = "(\(coord.latitude), \(coord.longitude))"
        } else {
            coordString = "(no coordinate)"
        }
        let titleString = rawTitle ?? "(no title)"
        print("📍 PointFeature: \(titleString) @ \(coordString)")
    }
}
