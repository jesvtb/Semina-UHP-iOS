import Foundation
import SwiftUI
import CoreLocation
import core

// MARK: - FlyToLocation

/// Selected search item for map fly-to and marker. Replaces TargetLocation.
struct FlyToLocation: Equatable {
    let location: CLLocation
    let name: String?

    static func == (lhs: FlyToLocation, rhs: FlyToLocation) -> Bool {
        lhs.location.coordinate.latitude == rhs.location.coordinate.latitude &&
        lhs.location.coordinate.longitude == rhs.location.coordinate.longitude &&
        lhs.name == rhs.name
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
