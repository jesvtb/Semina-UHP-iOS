import SwiftUI
import MapboxMaps
import CoreLocation
import Foundation
import core

// MARK: - GeoJSON MapContent Component
/// A custom MapContent component that renders GeoJSON data on the map
/// Follows Mapbox best practices for declarative map styling
struct GeoJSONMapContent: MapboxMaps.MapContent {
    /// The GeoJSON struct to render
    let geoJSON: GeoJSON
    
    /// Use GeoJSON's toMapboxString() method directly
    private var jsonString: String {
        return geoJSON.toMapboxString()
    }
    
    /// Convert features array to PointFeature objects
    private var pointFeatures: [PointFeature] {
        return geoJSON.features.compactMap { PointFeature(from: $0) }
    }
    
    /// The body is called only when component's properties are changed
    var body: some MapboxMaps.MapContent {
        let sourceId = "geojson-preview-source"
        
        // Create GeoJSON source with data using method chaining (like Mapbox example)
        MapboxMaps.GeoJSONSource(id: sourceId)
            .data(.string(jsonString))
        
        // Add MapViewAnnotation for each Point feature using ForEvery
        // Following Mapbox documentation pattern: https://docs.mapbox.com/ios/maps/api/11.2.0/documentation/mapboxmaps/forevery
        // Only display features that have an "idx" key in their properties
        MapboxMaps.ForEvery(Array(pointFeatures.enumerated()), id: \.offset) { index, pointFeature in
            if let coordinate = pointFeature.clCoordinate {
                MapboxMaps.MapViewAnnotation(coordinate: coordinate) {
    MainActor.assumeIsolated {
        PlaceView(feature: pointFeature)  // ✅ @State works fine
    }
}
                .allowOverlap(true)
                // .priority(0)
            }
        }
    }
    
}

