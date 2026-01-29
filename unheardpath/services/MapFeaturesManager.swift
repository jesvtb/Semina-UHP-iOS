import Foundation
import SwiftUI
import core

/// Shared manager for managing GeoJSON map features
/// Ensures both chat and orchestrator endpoints update the same map state
@MainActor
class MapFeaturesManager: ObservableObject {
    @Published var poisGeoJSON: GeoJSON
    @Published var geoJSONUpdateTrigger: UUID
    
    init() {
        self.poisGeoJSON = GeoJSON()
        self.geoJSONUpdateTrigger = UUID()
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
