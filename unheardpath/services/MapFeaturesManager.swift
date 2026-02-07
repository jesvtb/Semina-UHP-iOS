import Foundation
import SwiftUI
import CoreLocation
import core

// MARK: - FlyToLocation

/// Observable vessel for map fly-to and marker. Wraps LocationDetailData so the map
/// annotation and downstream handlers get rich location data without a reverse geocode.
struct FlyToLocation: Equatable {
    let locationDetail: LocationDetailData

    static func == (lhs: FlyToLocation, rhs: FlyToLocation) -> Bool {
        lhs.locationDetail.location.coordinate.latitude == rhs.locationDetail.location.coordinate.latitude &&
        lhs.locationDetail.location.coordinate.longitude == rhs.locationDetail.location.coordinate.longitude
    }
}

// MARK: - MapFeaturesManager

/// Shared manager for managing GeoJSON map features and the selected fly-to location.
/// Ensures both chat and orchestrator endpoints update the same map state.
@MainActor
class MapFeaturesManager: ObservableObject {
    @Published var poisGeoJSON: GeoJSON
    @Published var geoJSONUpdateTrigger: UUID
    /// Selected search item for map fly-to and marker (autocomplete selection or long-press).
    @Published var flyToLocation: FlyToLocation?

    init() {
        self.poisGeoJSON = GeoJSON()
        self.geoJSONUpdateTrigger = UUID()
        self.flyToLocation = nil
    }

    /// Apply new features to the manager, updating both GeoJSON and trigger
    /// - Parameter features: Array of GeoJSON feature dictionaries
    func apply(features: [[String: JSONValue]]) {
        poisGeoJSON.setFeatures(features)
        geoJSONUpdateTrigger = UUID()  // Trigger map and content updates

        #if DEBUG
        print("✅ MapFeaturesManager: Updated with \(features.count) features")
        #endif
    }
}
