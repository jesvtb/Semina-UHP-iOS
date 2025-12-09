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
    
    // MARK: - Coordinate Extraction
    
    /// Extracts all coordinates from GeoJSON features
    /// Supports Point geometry types
    /// - Returns: Array of coordinates from all Point features
    func extractCoordinates() -> [CLLocationCoordinate2D] {
        return features.compactMap { feature -> CLLocationCoordinate2D? in
            guard let geometry = feature["geometry"],
                  case .dictionary(let geometryDict) = geometry,
                  let type = geometryDict["type"],
                  case .string(let typeString) = type,
                  typeString == "Point",
                  let coordinates = geometryDict["coordinates"],
                  case .array(let coordinatesArray) = coordinates,
                  coordinatesArray.count >= 2 else {
                return nil
            }
            
            // Extract longitude and latitude from coordinates array
            // GeoJSON format: [longitude, latitude]
            let longitude: CLLocationDegrees?
            let latitude: CLLocationDegrees?
            
            switch coordinatesArray[0] {
            case .double(let value):
                longitude = value
            case .int(let value):
                longitude = CLLocationDegrees(value)
            default:
                longitude = nil
            }
            
            switch coordinatesArray[1] {
            case .double(let value):
                latitude = value
            case .int(let value):
                latitude = CLLocationDegrees(value)
            default:
                latitude = nil
            }
            
            guard let lon = longitude, let lat = latitude else {
                return nil
            }
            
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
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

// MARK: - PointFeature
/// A type-safe representation of a GeoJSON Point feature
/// Validates that the feature has Point geometry type and provides convenient access to properties
struct PointFeature: Sendable, Identifiable {
    /// The validated Point feature dictionary
    private let feature: [String: JSONValue]
    
    /// Stable identifier based on coordinates - prevents view recreation on parent state changes
    var id: String {
        if let coord = coordinate {
            return "poi_\(coord.latitude)_\(coord.longitude)"
        }
        // Fallback to title if no coordinate (shouldn't happen for valid Point features)
        return "poi_\(title ?? UUID().uuidString)"
    }
    
    /// Failable initializer that validates the feature is a Point geometry type
    /// - Parameter feature: Feature dictionary to validate and wrap
    /// - Returns: nil if the feature is not a Point geometry type
    init?(from feature: [String: JSONValue]) {
        // Validate that this is a Point geometry feature
        guard let geometry = feature["geometry"],
              case .dictionary(let geometryDict) = geometry,
              let typeValue = geometryDict["type"],
              case .string(let geometryType) = typeValue,
              geometryType == "Point",
              let coordinates = geometryDict["coordinates"],
              case .array(let coordinatesArray) = coordinates,
              coordinatesArray.count >= 2 else {
            return nil
        }
        
        self.feature = feature
    }
    
    /// Extract coordinate from Point geometry
    var coordinate: CLLocationCoordinate2D? {
        guard let geometry = feature["geometry"],
              case .dictionary(let geometryDict) = geometry,
              let coordinates = geometryDict["coordinates"],
              case .array(let coordinatesArray) = coordinates,
              coordinatesArray.count >= 2 else {
            return nil
        }
        
        // Extract longitude and latitude from coordinates array
        // GeoJSON format: [longitude, latitude]
        let longitude: CLLocationDegrees?
        let latitude: CLLocationDegrees?
        
        switch coordinatesArray[0] {
        case .double(let value):
            longitude = value
        case .int(let value):
            longitude = CLLocationDegrees(value)
        default:
            longitude = nil
        }
        
        switch coordinatesArray[1] {
        case .double(let value):
            latitude = value
        case .int(let value):
            latitude = CLLocationDegrees(value)
        default:
            latitude = nil
        }
        
        guard let lon = longitude, let lat = latitude else {
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Extract properties dictionary from the feature
    var properties: [String: JSONValue]? {
        guard let propertiesValue = feature["properties"],
              case .dictionary(let propertiesDict) = propertiesValue else {
            return nil
        }
        return propertiesDict
    }
    
    /// Extract title with priority: names.device_lang > names.local_lang > names.global_lang > title > name
    var title: String? {
        guard let properties = properties else { return nil }
        
        // First, try to get title from names field with priority: device_lang > local_lang > global_lang
        if let namesValue = properties["names"],
           let names = namesValue.dictionaryValue {
            if let deviceLangValue = names["device_lang"],
               let deviceLang = deviceLangValue.stringValue,
               !deviceLang.isEmpty {
                return deviceLang
            }
            if let localLangValue = names["local_lang"],
               let localLang = localLangValue.stringValue,
               !localLang.isEmpty {
                return localLang
            }
            if let globalLangValue = names["global_lang"],
               let globalLang = globalLangValue.stringValue,
               !globalLang.isEmpty {
                return globalLang
            }
        }
        
        // Fall back to title or name fields if names is not available or empty
        if let titleValue = properties["title"],
           let title = titleValue.stringValue {
            return title
        }
        if let nameValue = properties["name"],
           let name = nameValue.stringValue {
            return name
        }
        return nil
    }
    
    /// Extract and validate image URL from properties
    var imageURL: URL? {
        guard let properties = properties,
              let imgURLValue = properties["img_url"],
              let imgURL = imgURLValue.stringValue else {
            return nil
        }
        
        // Trim whitespace
        let trimmedURL = imgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create URL - URL(string:) handles properly formatted URLs including those with parentheses
        guard let url = URL(string: trimmedURL) else {
            #if DEBUG
            print("⚠️ Failed to create URL from img_url: \(trimmedURL)")
            #endif
            return nil
        }
        
        // Ensure it's an HTTP/HTTPS URL
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            #if DEBUG
            print("⚠️ img_url is not an HTTP/HTTPS URL: \(trimmedURL)")
            #endif
            return nil
        }
        
        return url
    }
    
    /// Extract Wikipedia URL from properties
    var wikipediaURL: URL? {
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
    
    /// Convert back to dictionary format
    func toDictionary() -> [String: JSONValue] {
        return feature
    }
    
    /// Pretty print coordinate and title for debugging
    func prettyPrint() {
        let coordString: String
        if let coord = coordinate {
            coordString = "(\(coord.latitude), \(coord.longitude))"
        } else {
            coordString = "(no coordinate)"
        }
        
        let titleString = title ?? "(no title)"
        
        print("📍 PointFeature: \(titleString) @ \(coordString)")
    }
}


