import Foundation
import CoreLocation

// MARK: - GeoJSON
/// A type-safe representation of a GeoJSON FeatureCollection
/// Supports setting, updating, and removing features individually or in bulk
struct GeoJSON: Sendable, Codable {
    /// The type of GeoJSON object (always "FeatureCollection" for this struct)
    var type: String {
        return "FeatureCollection"
    }
    private var shouldUpdateMap: Bool = false
    
    /// Array of GeoJSON features
    private(set) var features: [[String: JSONValue]]
    
    /// Initialize an empty FeatureCollection
    init() {
        self.features = []
    }
    
    /// Initialize with existing features
    /// Coordinates are automatically rounded to 4 decimal places
    /// - Parameter features: Array of feature dictionaries
    init(features: [[String: JSONValue]]) {
        self.features = features.map { Self.roundCoordinatesInFeature($0) }
    }
    
    // MARK: - Coordinate Rounding
    
    /// Rounds coordinates in a GeoJSON feature to 4 decimal places
    /// GeoJSON coordinates format: [longitude, latitude]
    /// - Parameter feature: Feature dictionary to process
    /// - Returns: Feature with rounded coordinates
    private static func roundCoordinatesInFeature(_ feature: [String: JSONValue]) -> [String: JSONValue] {
        var roundedFeature = feature
        
        // Extract geometry
        guard let geometryValue = feature["geometry"],
              case .dictionary(var geometry) = geometryValue,
              let typeValue = geometry["type"],
              case .string(let geometryType) = typeValue,
              geometryType == "Point",
              let coordinatesValue = geometry["coordinates"],
              case .array(var coordinates) = coordinatesValue,
              coordinates.count >= 2 else {
            // Not a Point geometry or invalid structure, return as-is
            return feature
        }
        
        // Round longitude (index 0) to 4 decimal places
        if case .double(let lonValue) = coordinates[0] {
            let longitude: CLLocationDegrees = lonValue
            let roundedLon: CLLocationDegrees = round(longitude * 10000) / 10000
            coordinates[0] = .double(roundedLon)
        } else if case .int(let lonValue) = coordinates[0] {
            // If it's an int, convert to CLLocationDegrees and round
            let longitude: CLLocationDegrees = CLLocationDegrees(lonValue)
            let roundedLon: CLLocationDegrees = round(longitude * 10000) / 10000
            coordinates[0] = .double(roundedLon)
        }
        
        // Round latitude (index 1) to 4 decimal places
        if case .double(let latValue) = coordinates[1] {
            let latitude: CLLocationDegrees = latValue
            let roundedLat: CLLocationDegrees = round(latitude * 10000) / 10000
            coordinates[1] = .double(roundedLat)
        } else if case .int(let latValue) = coordinates[1] {
            // If it's an int, convert to CLLocationDegrees and round
            let latitude: CLLocationDegrees = CLLocationDegrees(latValue)
            let roundedLat: CLLocationDegrees = round(latitude * 10000) / 10000
            coordinates[1] = .double(roundedLat)
        }
        
        // Update geometry with rounded coordinates
        geometry["coordinates"] = .array(coordinates)
        roundedFeature["geometry"] = .dictionary(geometry)
        
        return roundedFeature
    }
    
    // MARK: - Feature Management
    
    /// Set all features, replacing any existing features
    /// Coordinates are automatically rounded to 4 decimal places
    /// - Parameter features: Array of feature dictionaries to set
    mutating func setFeatures(_ features: [[String: JSONValue]]) {
        self.features = features.map { Self.roundCoordinatesInFeature($0) }
        shouldUpdateMap = true
    }
    
    /// Add or update a single feature at the specified index
    /// Coordinates are automatically rounded to 4 decimal places
    /// - Parameters:
    ///   - feature: Feature dictionary to add or update
    ///   - index: Index where to insert/update. If nil, appends to the end
    /// - Returns: The index where the feature was added/updated, or nil if invalid
    @discardableResult
    mutating func setFeature(_ feature: [String: JSONValue], at index: Int? = nil) -> Int? {
        let roundedFeature = Self.roundCoordinatesInFeature(feature)
        shouldUpdateMap = true
        if let index = index {
            guard index >= 0 && index <= features.count else {
                return nil
            }
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
    /// Coordinates are automatically rounded to 4 decimal places
    /// - Parameters:
    ///   - feature: Feature dictionary to update with
    ///   - index: Index of the feature to update
    /// - Returns: true if update was successful, false if index is invalid
    @discardableResult
    mutating func updateFeature(_ feature: [String: JSONValue], at index: Int) -> Bool {
        guard index >= 0 && index < features.count else {
            return false
        }
        features[index] = Self.roundCoordinatesInFeature(feature)
        shouldUpdateMap = true
        return true
    }
    
    /// Remove a feature at the specified index
    /// - Parameter index: Index of the feature to remove
    /// - Returns: The removed feature, or nil if index is invalid
    @discardableResult
    mutating func removeFeature(at index: Int) -> [String: JSONValue]? {
        guard index >= 0 && index < features.count else {
            return nil
        }
        shouldUpdateMap = true
        return features.remove(at: index)
    }
    
    /// Remove all features
    mutating func removeAllFeatures() {
        features.removeAll()
        shouldUpdateMap = true
    }
    
    /// Get a feature at the specified index
    /// - Parameter index: Index of the feature to retrieve
    /// - Returns: The feature dictionary, or nil if index is invalid
    func getFeature(at index: Int) -> [String: JSONValue]? {
        guard index >= 0 && index < features.count else {
            return nil
        }
        return features[index]
    }
    
    /// Get the number of features
    var featureCount: Int {
        return features.count
    }
    
    // MARK: - Feature Extraction
    
    /// Extracts features from a GeoJSON response dictionary
    /// Handles different response structures (direct features, nested in data, nested in result.data)
    /// - Parameter jsonDict: The JSON dictionary containing features
    /// - Returns: Array of feature dictionaries as JSONValue
    /// - Throws: Error if JSON structure is invalid
    static func extractFeatures(from jsonDict: Any) throws -> [[String: JSONValue]] {
        guard let dict = jsonDict as? [String: Any] else {
            throw GeoJSONError.invalidJSON
        }
        
        // Handle different response structures
        var features: [[String: Any]]
        
        // Check if features are directly in the dict
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
    
    enum GeoJSONError: Error {
        case invalidJSON
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type
        case features
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("FeatureCollection", forKey: .type)
        try container.encode(features, forKey: .features)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Ignore the type from input, always use "FeatureCollection"
        _ = try container.decodeIfPresent(String.self, forKey: .type)
        features = try container.decode([[String: JSONValue]].self, forKey: .features)
    }
    
    // MARK: - Conversion
    
    /// Convert to JSON string compatible with MapboxMapView's GeoJSONSource
    /// - Returns: JSON string representation for use with MapboxMapView, or empty FeatureCollection string if encoding fails
    func toMapboxString() -> String {
        // Convert features to [String: Any] for JSONSerialization
        let featuresArray = features.map { $0.mapValues { $0.asAny } }
        let featureCollection: [String: Any] = [
            "type": "FeatureCollection",
            "features": featuresArray
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: featureCollection, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            #if DEBUG
            print("❌ Failed to convert GeoJSON to string for MapboxMapView")
            #endif
            return "{\"type\":\"FeatureCollection\",\"features\":[]}"
        }
        return jsonString
    }
}


