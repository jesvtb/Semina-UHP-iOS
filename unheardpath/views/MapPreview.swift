import SwiftUI
import MapboxMaps
import CoreLocation
import Foundation
import core

#Preview {
    MapboxMapView()
        .environmentObject(TrackingManager())
        .environmentObject(LocationManager())
        .environmentObject(MapFeaturesManager())
}

// MARK: - GeoJSON Preview
/// Preview view that demonstrates loading and rendering GeoJSON using the declarative MapContent API
struct MapViewGeoJSONPreview: View {
    @State private var geoJSON = GeoJSON()
    
    var body: some View {
        MapboxMaps.Map(initialViewport: .camera(
            center: CLLocationCoordinate2D(latitude: 41.0053851, longitude: 28.9768247), // Blue Mosque coordinates
            zoom: 12,
            bearing: 0,
            pitch: 60
        )) {
            // Add GeoJSON content if available
            GeoJSONMapContent(geoJSON: geoJSON)
        }
        .mapStyle(MapboxMaps.MapStyle(uri: MapboxMaps.StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
        .ignoresSafeArea()
        .onAppear {
            loadGeoJSONFromBundle()
        }
    }
    
    /// Loads GeoJSON data from around_me_example.json bundle file
    private func loadGeoJSONFromBundle() {
        // Try to find the file in the bundle
        // First try with subdirectory
        var url = Bundle.main.url(forResource: "around_me_example", withExtension: "json", subdirectory: "mock")
        
        // If not found, try without subdirectory
        if url == nil {
            url = Bundle.main.url(forResource: "around_me_example", withExtension: "json")
        }
        
        guard let fileURL = url else {
            #if DEBUG
            print("❌ Could not find around_me_example.json in bundle")
            #endif
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data)
            
            // Use GeoJSON.extractFeatures to parse the JSON structure
            // This handles different response structures (direct features, nested in data, nested in result.data)
            let features = try GeoJSON.extractFeatures(from: json)
            geoJSON.setFeatures(features)
            
            #if DEBUG
            print("✅ Loaded GeoJSON preview with \(features.count) features")
            // Demonstrate PointFeature usage - print first few features
            let pointFeatures = features.compactMap { PointFeature(from: $0) }
            print("📍 Converted to \(pointFeatures.count) PointFeature objects")
            if let firstFeature = pointFeatures.first {
                print("   First feature:")
                firstFeature.prettyPrintApp()
            }
            #endif
        } catch {
            #if DEBUG
            if let geoJSONError = error as? GeoJSON.GeoJSONError {
                print("❌ Invalid GeoJSON structure: \(geoJSONError)")
            } else {
                print("❌ Failed to load GeoJSON: \(error.localizedDescription)")
            }
            #endif
        }
    }
}

#Preview("GeoJSON Preview") {
    MapViewGeoJSONPreview()
}

