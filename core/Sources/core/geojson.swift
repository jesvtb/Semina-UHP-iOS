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

    /// Extracts features from a root-level array of GeoJSON feature objects (backend often sends this shape).
    public static func extractFeatures(from jsonArray: [[String: Any]]) throws -> [[String: JSONValue]] {
        try jsonArray.map { featureDict in
            guard let jsonValueDict = JSONValue.dictionary(from: featureDict) else {
                throw GeoJSONError.invalidJSON(reason: "feature could not be converted to JSONValue dictionary")
            }
            return jsonValueDict
        }
    }

    /// Extracts features from a GeoJSON object (FeatureCollection or single Feature).
    /// Handles: features, data.features, result.data.features, single Feature, or data as JSON string.
    public static func extractFeatures(from jsonDict: [String: Any]) throws -> [[String: JSONValue]] {
        // data as JSON string (double-encoded)
        if let dataString = jsonDict["data"] as? String,
           let data = dataString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            if let array = parsed as? [[String: Any]] {
                return try extractFeatures(from: array)
            }
            if let dict = parsed as? [String: Any] {
                return try extractFeatures(from: dict)
            }
            throw GeoJSONError.invalidJSON(reason: "parsed data is not an array of features or a dictionary")
        }

        var features: [[String: Any]]
        if let directFeatures = jsonDict["features"] as? [[String: Any]] {
            features = directFeatures
        } else if let data = jsonDict["data"] as? [String: Any],
                  let dataFeatures = data["features"] as? [[String: Any]] {
            features = dataFeatures
        } else if let result = jsonDict["result"] as? [String: Any],
                  let resultData = result["data"] as? [String: Any],
                  let resultFeatures = resultData["features"] as? [[String: Any]] {
            features = resultFeatures
        } else if let type = jsonDict["type"] as? String, type == "Feature" {
            features = [jsonDict]
        } else {
            let keys = Array(jsonDict.keys).joined(separator: ", ")
            throw GeoJSONError.invalidJSON(reason: "expected FeatureCollection or Feature; got keys: \(keys)")
        }
        return try features.map { featureDict in
            guard let jsonValueDict = JSONValue.dictionary(from: featureDict) else {
                throw GeoJSONError.invalidJSON(reason: "feature could not be converted to JSONValue dictionary")
            }
            return jsonValueDict
        }
    }

    public enum GeoJSONError: Error, Sendable {
        case invalidJSON(reason: String = "invalid structure")
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

    /// Image URL from properties. Checks `img_urls` (array) first, then `img_url` (string).
    public var imageURL: URL? {
        guard let properties = properties else { return nil }
        if let arrayValue = properties["img_urls"], case .array(let urls) = arrayValue {
            for item in urls {
                if let urlString = item.stringValue, let url = Self.validHTTPURL(urlString) {
                    return url
                }
            }
        }
        if let singleValue = properties["img_url"], let urlString = singleValue.stringValue {
            return Self.validHTTPURL(urlString)
        }
        return nil
    }

    /// Image URL downsized to 200 px for map annotation circles (retina-ready).
    /// Rewrites Wikimedia `/thumb/…/{width}px-Name` URLs; passes non-wiki URLs through unchanged.
    public var mapImageURL: URL? {
        guard let url = imageURL else { return nil }
        return Self.wikimediaThumbnail(url, width: 200)
    }

    private static func wikimediaThumbnail(_ url: URL, width: Int) -> URL {
        let str = url.absoluteString
        guard str.contains("upload.wikimedia.org"),
              str.contains("/thumb/"),
              let range = str.range(of: #"/\d+px-[^/]+$"#, options: .regularExpression) else {
            return url
        }
        let filename = str[range].split(separator: "-", maxSplits: 1).dropFirst().joined(separator: "-")
        let replacement = "/\(width)px-\(filename)"
        return URL(string: str.replacingCharacters(in: range, with: replacement)) ?? url
    }

    /// Wikipedia URL derived from `refs.wiki_{lang}`.
    /// Prefers the device language page, falls back to English.
    public var wikipediaURL: URL? {
        guard let properties = properties,
              let refsValue = properties["refs"],
              case .dictionary(let refs) = refsValue else {
            return nil
        }
        let deviceLang: String
        if #available(iOS 16.0, *) {
            deviceLang = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            deviceLang = Locale.current.languageCode ?? "en"
        }
        let baseLang = deviceLang.split(separator: "-").first.map(String.init) ?? deviceLang

        // Device language first, then English fallback
        let keysToTry = baseLang == "en"
            ? ["wiki_\(baseLang)"]
            : ["wiki_\(baseLang)", "wiki_en"]

        for key in keysToTry {
            guard let titleValue = refs[key], let title = titleValue.stringValue, !title.isEmpty else {
                continue
            }
            let lang = String(key.dropFirst(5)) // strip "wiki_"
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            if let url = URL(string: "https://\(lang).wikipedia.org/wiki/\(encoded)") {
                return url
            }
        }
        return nil
    }

    private static func validHTTPURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
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
