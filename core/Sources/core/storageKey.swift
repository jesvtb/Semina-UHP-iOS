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
    case adminarea = 1
    case locality = 2
    case sublocality = 3
    case geohash = 4

    public static func < (lhs: GeoLevel, rhs: GeoLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// String identifier matching backend naming convention.
    public var identifier: String {
        switch self {
        case .country: return "country"
        case .adminarea: return "adminarea"
        case .locality: return "locality"
        case .sublocality: return "sublocality"
        case .geohash: return "geohash"
        }
    }

    /// Initialize from a backend identifier string (e.g. `"country"`, `"locality"`).
    /// Returns `nil` for unrecognized identifiers.
    public init?(identifier: String) {
        switch identifier {
        case "country": self = .country
        case "adminarea": self = .adminarea
        case "locality": self = .locality
        case "sublocality": self = .sublocality
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
/// country:     "us"
/// adminarea:   "us.california"
/// locality:    "us.california.san_francisco"
/// sublocality: "us.california.san_francisco.mission"
/// geohash:     "9q8yyk"
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

        case .adminarea:
            guard let country = location.countryCode,
                  let admin = location.adminArea else { return nil }
            return [normalize(country), normalize(admin)].joined(separator: ".")

        case .locality:
            guard let country = location.countryCode,
                  let admin = location.adminArea,
                  let locality = location.locality else { return nil }
            return [normalize(country), normalize(admin), normalize(locality)].joined(separator: ".")

        case .sublocality:
            guard let country = location.countryCode,
                  let admin = location.adminArea,
                  let locality = location.locality,
                  let sublocality = location.subLocality else { return nil }
            return [normalize(country), normalize(admin), normalize(locality), normalize(sublocality)].joined(separator: ".")

        case .geohash:
            let coord = location.location.coordinate
            return Geohash.encode(latitude: coord.latitude, longitude: coord.longitude, precision: 5)
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
    /// Mirrors the backend's `GeoCatalogue._normalize_geo_id()`:
    /// - Lowercase
    /// - Strip diacritics (São Paulo → sao_paulo, Zürich → zurich)
    /// - Replace whitespace with underscores
    /// - Remove commas
    /// - Trim leading/trailing underscores
    static func normalize(_ name: String) -> String {
        // Decompose unicode and strip combining marks (diacritics)
        let decomposed = name.decomposedStringWithCanonicalMapping
        let stripped = decomposed.unicodeScalars
            .filter { !CharacterSet.nonBaseCharacters.contains($0) }
            .map { String($0) }
            .joined()

        return stripped
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
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
