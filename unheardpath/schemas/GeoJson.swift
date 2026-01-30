import Foundation
import CoreLocation
import core

// MARK: - GeoJSON Extensions (app-specific)

extension GeoJSON {
    /// Convert to JSON string compatible with MapboxMapView's GeoJSONSource.
    /// Uses GeoJSON's Codable conformance (core) instead of duplicating structure with asAny + JSONSerialization.
    func toMapboxString() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("❌ Failed to convert GeoJSON to string for MapboxMapView")
            #endif
            return "{\"type\":\"FeatureCollection\",\"features\":[]}"
        }
        return jsonString
    }

    /// Extracts coordinates as CLLocationCoordinate2D for Mapbox/MapKit use
    func extractCLCoordinates() -> [CLLocationCoordinate2D] {
        extractCoordinates().map { coord in
            CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
    }
}

// MARK: - PointFeature Extensions (app-specific)

extension PointFeature {
    /// CLLocationCoordinate2D for use with Mapbox/MapKit (converted from core Coordinate2D)
    var clCoordinate: CLLocationCoordinate2D? {
        guard let coord = coordinate else { return nil }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    /// Title with priority: names.device_lang > names.local_lang > names.global_lang > title > name
    var title: String? {
        guard let properties = properties else { return nil }
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

    /// Pretty print for debugging (uses app title)
    func prettyPrintApp() {
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
