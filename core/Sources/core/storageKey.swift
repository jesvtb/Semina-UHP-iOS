//
//  storageKey.swift
//  core
//
//  Geographic key derivation for catalogue persistence.
//  Mirrors the backend's GeoCatalogue._cache_key() hierarchy from locale.py.
//

import Foundation
import CoreLocation

// MARK: - GeoLevel

/// Geographic hierarchy levels from most general to most specific.
/// Mirrors the backend's GeoCatalogue.HIERARCHY in locale.py.
public enum GeoLevel: Int, Comparable, CaseIterable, Sendable, Codable {
    case country = 0
    case adminArea = 1
    case locality = 2
    case subLocality = 3
    case geohash = 4

    public static func < (lhs: GeoLevel, rhs: GeoLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// String identifier matching backend naming convention.
    public var identifier: String {
        switch self {
        case .country: return "country"
        case .adminArea: return "admin_area"
        case .locality: return "locality"
        case .subLocality: return "sub_locality"
        case .geohash: return "geohash"
        }
    }

    /// Initialize from a backend identifier string (e.g. `"country"`, `"locality"`).
    /// Returns `nil` for unrecognized identifiers.
    public init?(identifier: String) {
        switch identifier {
        case "country": self = .country
        case "admin_area": self = .adminArea
        case "locality": self = .locality
        case "sub_locality": self = .subLocality
        case "geohash": self = .geohash
        default: return nil
        }
    }
}

// MARK: - StorageKey

/// Derives hierarchical geographic cache keys from location data.
///
/// Key format uses dots (`.`) as level delimiters and underscores (`_`) for spaces within a level:
/// ```
/// country:      "us"
/// admin_area:   "us.california"
/// locality:     "us.california.san_francisco"
/// sub_locality: "us.california.san_francisco.mission"
/// geohash:      "9q8yyk"
/// ```
public enum StorageKey {

    /// Derive the geo key for a specific level from location data.
    ///
    /// Returns `nil` if required fields are missing for that level.
    /// - Parameters:
    ///   - location: Structured location data from geocoding.
    ///   - level: The geographic level to derive the key for.
    /// - Returns: A normalized, dot-delimited geographic key, or `nil`.
    public static func geoKey(from location: LocationDetailData, level: GeoLevel) -> String? {
        switch level {
        case .country:
            guard let country = location.countryCode else { return nil }
            return normalize(country)

        case .adminArea:
            guard let country = location.countryCode,
                  let admin = location.adminArea else { return nil }
            return [normalize(country), normalize(admin)].joined(separator: ".")

        case .locality:
            guard let country = location.countryCode,
                  let admin = location.adminArea,
                  let locality = location.locality else { return nil }
            return [normalize(country), normalize(admin), normalize(locality)].joined(separator: ".")

        case .subLocality:
            guard let country = location.countryCode,
                  let admin = location.adminArea,
                  let locality = location.locality,
                  let subLoc = location.subLocality else { return nil }
            return [normalize(country), normalize(admin), normalize(locality), normalize(subLoc)].joined(separator: ".")

        case .geohash:
            let coord = location.location.coordinate
            return Geohash.encode(latitude: coord.latitude, longitude: coord.longitude, precision: 5)
        }
    }

    /// Derive a geo key from a backend-provided ``_metadata.location.context`` dict.
    ///
    /// Backend context keys use the Python model's snake_case naming:
    /// `country_code`, `admin_area`, `locality`, `sub_locality`.
    /// Returns `nil` if required fields for the given level are missing, or for `.geohash`
    /// (backend context doesn't carry geohash coordinates).
    public static func geoKey(fromBackendContext context: [String: String], level: GeoLevel) -> String? {
        switch level {
        case .country:
            guard let country = context["country_code"] else { return nil }
            return normalize(country)

        case .adminArea:
            guard let country = context["country_code"],
                  let admin = context["admin_area"] else { return nil }
            return [normalize(country), normalize(admin)].joined(separator: ".")

        case .locality:
            guard let country = context["country_code"],
                  let admin = context["admin_area"],
                  let locality = context["locality"] else { return nil }
            return [normalize(country), normalize(admin), normalize(locality)].joined(separator: ".")

        case .subLocality:
            guard let country = context["country_code"],
                  let admin = context["admin_area"],
                  let locality = context["locality"],
                  let sub = context["sub_locality"] else { return nil }
            return [normalize(country), normalize(admin), normalize(locality), normalize(sub)].joined(separator: ".")

        case .geohash:
            return nil
        }
    }

    /// Returns all applicable (level, geoKey) pairs for a location, from most general to most specific.
    /// Only levels whose required fields are present in the location are included.
    public static func applicableLevels(from location: LocationDetailData) -> [(level: GeoLevel, key: String)] {
        var result: [(GeoLevel, String)] = []
        for level in GeoLevel.allCases {
            if let key = geoKey(from: location, level: level) {
                result.append((level, key))
            }
        }
        return result
    }

    // MARK: - Normalization

    /// Normalize a geographic name for use in cache keys.
    ///
    /// Mirrors the backend's `GeoCatalogue._normalize_id()`:
    /// - Lowercase
    /// - Strip diacritics (São Paulo → sao_paulo, Zürich → zurich)
    /// - Strip punctuation that varies across geocoder sources
    ///   (commas, periods, apostrophes, parentheses)
    /// - Replace whitespace and hyphens with underscores
    /// - Trim leading/trailing underscores
    public static func normalize(_ name: String) -> String {
        // Decompose unicode and strip combining marks (diacritics)
        let decomposed = name.decomposedStringWithCanonicalMapping
        let stripped = decomposed.unicodeScalars
            .filter { !CharacterSet.nonBaseCharacters.contains($0) }
            .map { String($0) }
            .joined()

        // Word-separator punctuation → spaces (collapsed to _ below)
        let separatorPunctuation = CharacterSet(charactersIn: "-'\"()[]")
        var cleaned = stripped.unicodeScalars
            .map { separatorPunctuation.contains($0) ? " " : String($0) }
            .joined()

        // Decoration punctuation → removed
        cleaned = cleaned
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")

        return cleaned
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

// MARK: - Geohash Encoder

/// Minimal geohash encoder. Converts (latitude, longitude) into a geohash string of configurable precision.
///
/// Reference: https://en.wikipedia.org/wiki/Geohash
public enum Geohash {

    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Encode a coordinate into a geohash string.
    /// - Parameters:
    ///   - latitude: Latitude in degrees (-90...90).
    ///   - longitude: Longitude in degrees (-180...180).
    ///   - precision: Number of characters in the result (default 5, ~5km x 5km cell).
    /// - Returns: A geohash string of the specified precision.
    public static func encode(latitude: CLLocationDegrees, longitude: CLLocationDegrees, precision: Int = 5) -> String {
        var latRange: (min: Double, max: Double) = (-90.0, 90.0)
        var lonRange: (min: Double, max: Double) = (-180.0, 180.0)
        var isEvenBit = true
        var bitIndex = 0
        var currentCharValue: Int = 0
        var result = ""

        while result.count < precision {
            if isEvenBit {
                let mid = (lonRange.min + lonRange.max) / 2.0
                if longitude >= mid {
                    currentCharValue = currentCharValue | (1 << (4 - bitIndex))
                    lonRange.min = mid
                } else {
                    lonRange.max = mid
                }
            } else {
                let mid = (latRange.min + latRange.max) / 2.0
                if latitude >= mid {
                    currentCharValue = currentCharValue | (1 << (4 - bitIndex))
                    latRange.min = mid
                } else {
                    latRange.max = mid
                }
            }
            isEvenBit.toggle()
            bitIndex += 1

            if bitIndex == 5 {
                result.append(base32[currentCharValue])
                currentCharValue = 0
                bitIndex = 0
            }
        }

        return result
    }
}
