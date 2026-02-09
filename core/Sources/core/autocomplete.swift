//
//  autocomplete.swift
//  core
//
//  MapSearchResult and helper utilities for autocomplete (MKLocalSearch and GeoJSON).
//  LocationDict is in Geocoder.swift.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - CompletionSource

/// Wraps the original source object from an autocomplete result so it can be used later
/// to build LocationDetailData without a redundant reverse geocode.
public enum CompletionSource: @unchecked Sendable {
    case mapItem(MKMapItem)
    case completion(MKLocalSearchCompletion)
    case geoJSON(MKGeoJSONFeature, properties: [String: Any])
}

// MARK: - MapSearchResult

/// Unified search result from MKLocalSearch, MKLocalSearchCompleter, or GeoJSON (Geoapify).
/// Stores only the required display fields (source, name, address) plus the original source object.
/// Marked @unchecked Sendable because CompletionSource holds non-Sendable MapKit types that are read-only after creation.
public struct MapSearchResult: @unchecked Sendable {
    /// Source identifier: `"mapkit"`, `"mapkit_completer"`, or `"geojson"`.
    public let source: String
    /// Display name of the place.
    public let name: String
    /// Full or formatted address string.
    public let address: String
    /// Original source object for resolving full details later.
    public let completionSource: CompletionSource

    // MARK: - Initializers

    public init(_ mapItem: MKMapItem) {
        source = "mapkit"
        name = mapItem.name ?? mapItem.placemark.name ?? ""
        let rawAddress = MapSearchResult.address(from: mapItem.placemark)
        address = MapSearchResult.normalizeAddress(rawAddress, name: name, postalCode: mapItem.placemark.postalCode)
        completionSource = .mapItem(mapItem)
    }

    public init(_ completion: MKLocalSearchCompletion) {
        source = "mapkit_completer"
        name = completion.title
        address = completion.subtitle
        completionSource = .completion(completion)
    }

    public init(_ feature: MKGeoJSONFeature) {
        source = "geoapify"
        let props = MapSearchResult.decodeProperties(from: feature.properties)
        let nameFromLine1 = (props["address_line1"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var nameValue = nameFromLine1 ?? (props["name"] as? String) ?? (props["title"] as? String) ?? ""
        if nameValue.isEmpty, (props["result_type"] as? String) == "city", let city = props["city"] as? String, !city.isEmpty {
            nameValue = city
        }
        name = nameValue
        let addressFromLine2 = (props["address_line2"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAddress = addressFromLine2 ?? (props["formatted"] as? String) ?? (props["address"] as? String) ?? ""
        let postalCode = (props["postcode"] as? String) ?? (props["postal_code"] as? String)
        address = MapSearchResult.normalizeAddress(rawAddress, name: name, postalCode: postalCode)
        completionSource = .geoJSON(feature, properties: props)
    }

    // MARK: - Build LocationDetailData

    /// Builds LocationDetailData from the stored source object.
    /// Returns nil for `.completion` (needs resolution via MKLocalSearch first).
    public func buildLocationDetailData() -> LocationDetailData? {
        switch completionSource {
        case .mapItem(let mapItem):
            let loc = CLLocation(latitude: mapItem.placemark.coordinate.latitude,
                                 longitude: mapItem.placemark.coordinate.longitude)
            return LocationDetailData(placemark: mapItem.placemark, location: loc)
        case .geoJSON(let feature, let properties):
            guard let coord = feature.geometry.first?.coordinate else { return nil }
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return LocationDetailData(geoapifyProperties: properties, location: loc)
        case .completion:
            return nil
        }
    }

    // MARK: - Helpers

    /// Whether this result represents a "city" type (from Geoapify result_type).
    public var isCityType: Bool {
        if case .geoJSON(_, let props) = completionSource {
            return (props["result_type"] as? String) == "city"
        }
        return false
    }

    // MARK: - Private Static Helpers

    /// Builds a single address string from placemark components (excludes postal code).
    private static func address(from placemark: CLPlacemark) -> String {
        let street = streetFromPlacemark(placemark)
        let location = locationStringFromPlacemark(placemark)
        let country = placemark.country ?? ""
        return [street, location, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Builds street string from placemark (subThoroughfare + thoroughfare).
    private static func streetFromPlacemark(_ placemark: CLPlacemark) -> String {
        var streetParts: [String] = []
        if let subThoroughfare = placemark.subThoroughfare {
            streetParts.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            streetParts.append(thoroughfare)
        }
        return streetParts.joined(separator: " ")
    }

    /// Builds location detail string from placemark (subLocality, locality, subAdmin, adminArea).
    private static func locationStringFromPlacemark(_ placemark: CLPlacemark) -> String {
        var locationParts: [String] = []
        if let subLocality = placemark.subLocality {
            locationParts.append(subLocality)
        }
        if let locality = placemark.locality {
            locationParts.append(locality)
        }
        if let subAdministrativeArea = placemark.subAdministrativeArea {
            locationParts.append(subAdministrativeArea)
        }
        if let administrativeArea = placemark.administrativeArea {
            locationParts.append(administrativeArea)
        }
        return locationParts.joined(separator: ", ")
    }

    /// Removes exact name from the start of address and removes postal/zip code.
    private static func normalizeAddress(_ address: String, name: String, postalCode: String?) -> String {
        var result = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, result.hasPrefix(name) {
            result = String(result.dropFirst(name.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.hasPrefix(",") {
                result = String(result.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let code = postalCode, !code.isEmpty {
            result = result.replacingOccurrences(of: code, with: "")
            result = result.replacingOccurrences(of: ", ,", with: ",")
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        return result
    }

    /// Decodes GeoJSON feature properties Data into [String: Any].
    private static func decodeProperties(from data: Data?) -> [String: Any] {
        guard let data = data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
