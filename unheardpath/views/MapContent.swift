import SwiftUI
import MapboxMaps
import CoreLocation
import Foundation
import core

#if DEBUG
// MARK: - Geofence Debug Circle MapContent
/// MapContent component for displaying geofence debug circle on map
struct GeofenceDebugCircleContent: MapboxMaps.MapContent {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let isMonitoring: Bool
    
    private let sourceId = "geofence-debug-source"
    private let fillLayerId = "geofence-debug-fill-layer"
    private let lineLayerId = "geofence-debug-line-layer"
    
    /// Creates points for a circle polygon approximation
    private func createCirclePoints(numPoints: Int) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        let earthRadius: Double = 6371000.0 // Earth radius in meters
        
        for i in 0..<numPoints {
            let angle = Double(i) * 2.0 * .pi / Double(numPoints)
            
            // Convert radius from meters to degrees (approximate)
            let radiusLat = radius / earthRadius * (180.0 / .pi)
            let radiusLon = radius / (earthRadius * cos(center.latitude * .pi / 180.0)) * (180.0 / .pi)
            
            let lat = center.latitude + radiusLat * cos(angle)
            let lon = center.longitude + radiusLon * sin(angle)
            
            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        
        return points
    }
    
    /// Creates GeoJSON string for the circle polygon
    private var geofenceGeoJSON: String {
        let circlePoints = createCirclePoints(numPoints: 64)
        let coordinates = circlePoints.map { [$0.longitude, $0.latitude] } + [[circlePoints[0].longitude, circlePoints[0].latitude]]
        
        let polygonCoordinates: [[[Double]]] = [coordinates]
        
        let geofenceFeature: [String: Any] = [
            "type": "Feature",
            "geometry": [
                "type": "Polygon",
                "coordinates": polygonCoordinates
            ],
            "properties": [
                "isMonitoring": isMonitoring
            ]
        ]
        
        let featureCollection: [String: Any] = [
            "type": "FeatureCollection",
            "features": [geofenceFeature]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: featureCollection, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"type\":\"FeatureCollection\",\"features\":[]}"
        }
        
        return jsonString
    }
    
    var body: some MapboxMaps.MapContent {
        // Create GeoJSON source
        MapboxMaps.GeoJSONSource(id: sourceId)
            .data(.string(geofenceGeoJSON))
        
        // Add fill layer
        let fillColorValue: StyleColor = isMonitoring ? StyleColor(.black) : StyleColor(.yellow)
        MapboxMaps.FillLayer(id: fillLayerId, source: sourceId)
            .fillColor(fillColorValue)
            .fillOpacity(0.1)
            .fillOutlineColor(fillColorValue)
        
        // Add line layer for outline
        MapboxMaps.LineLayer(id: lineLayerId, source: sourceId)
            .lineColor(fillColorValue)
            .lineWidth(2)
            .lineOpacity(0.8)
    }
}
#endif

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

