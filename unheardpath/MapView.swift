import SwiftUI
import MapKit
import MapboxMaps
import CoreLocation
import MapLibre



struct AppleMapView: View {
    @State private var locationManager = CLLocationManager()
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.015944, longitude: 28.955556),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        Map(coordinateRegion: $region, showsUserLocation: true)
            .ignoresSafeArea()
            .onAppear {
                // Request location permission
                locationManager.requestWhenInUseAuthorization()
            }
    }
}

struct MapboxMapView: View {
    @State private var locationManager = CLLocationManager()
    
    var body: some View {
        MapReader { proxy in
            Map(initialViewport: .camera(center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.0), zoom: 2, bearing: 0, pitch: 0)) {
                // Add user location puck - this is Mapbox's recommended way
                MapboxMaps.Puck2D(bearing: MapboxMaps.PuckBearing.heading)
            }
            .mapStyle(MapStyle(uri: StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
            .ignoresSafeArea()
            .onAppear {
                setupMapboxLocation(proxy: proxy)
            }
        }
    }
    
    private func setupMapboxLocation(proxy: MapboxMaps.MapProxy) {
        print("🔧 Setting up Mapbox location manager...")
        
        // Request location permission first
        locationManager.requestWhenInUseAuthorization()
        
        // Configure Mapbox's built-in location provider
        let locationProvider = AppleLocationProvider()
        locationProvider.options.activityType = .otherNavigation
        locationProvider.options.desiredAccuracy = kCLLocationAccuracyBest
        
        // Override the map's location provider with our configured one
        proxy.location?.override(provider: locationProvider)
        
        // Configure location puck options
        proxy.location?.options.puckType = .puck2D()
        proxy.location?.options.puckBearingEnabled = true
        
        print("✅ Mapbox location provider configured")
    }
}

// MARK: - Location Manager Delegate
class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    private let onLocationUpdate: (CLLocation) -> Void
    
    init(onLocationUpdate: @escaping (CLLocation) -> Void) {
        self.onLocationUpdate = onLocationUpdate
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocationUpdate(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("🔄 Location authorization changed to: \(status.rawValue)")
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Location permission granted - starting location updates")
            manager.startUpdatingLocation()
        case .denied:
            print("❌ Location permission denied by user")
        case .restricted:
            print("❌ Location permission restricted by system")
        case .notDetermined:
            print("⏳ Location permission not determined yet")
        @unknown default:
            print("❓ Unknown location permission status: \(status.rawValue)")
        }
    }
}

struct MapLibreMapView: UIViewRepresentable {
    // Optional: Allow passing a custom style URL
    let styleURL: String?
    
    // Default initializer with no custom style
    init(styleURL: String? = nil) {
        self.styleURL = styleURL
    }
    
    func makeUIView(context _: Context) -> MLNMapView {
        let mapView = MLNMapView()
        
        // Set custom style if provided, otherwise use local basemap_style.json
        if let styleURL = styleURL {
            mapView.styleURL = URL(string: styleURL)
        } else {
            // Load local basemap_style.json from app bundle
            if let localStyleURL = Bundle.main.url(forResource: "basemap_style", withExtension: "json") {
                mapView.styleURL = localStyleURL
                print("✅ Loaded local basemap_style.json from bundle")
            } else {
                print("❌ Could not find basemap_style.json in app bundle")
            }
        }
        
        mapView.setCenter(CLLocationCoordinate2D(latitude: 41.0136, longitude: 28.955), zoomLevel: 2, animated: false)
        return mapView
    }

    func updateUIView(_: MLNMapView, context _: Context) {}
}

// SwiftUI wrapper to apply modifiers like .ignoresSafeArea()
struct MapLibreMapViewWrapper: View {
    let styleURL: String?
    
    init(styleURL: String? = nil) {
        self.styleURL = styleURL
    }
    
    var body: some View {
        MapLibreMapView(styleURL: styleURL)
            .ignoresSafeArea()
    }
}

// MARK: - Mapbox Directions API Integration
struct MapboxDirectionsView: View {
    @StateObject private var apiService = APIService()
    @State private var directionsData: Any?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Mapbox API configuration
    private let mapboxToken = "pk.eyJ1IjoiamVzc2ljYW1pbmd5dSIsImEiOiJjbWZjY3cxd3AwODFvMmxxbzJiNWc4NGY4In0.6hWdeAXgQKoDQNqbPiebzw"
    private let startCoordinate = "-122.42,37.78"  // San Francisco
    private let endCoordinate = "-77.03,38.91"     // Washington DC
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Mapbox Directions API")
                .font(.title2)
                .fontWeight(.bold)
            
            Button("Get Cycling Directions") {
                Task {
                    await fetchDirections()
                }
            }
            .disabled(isLoading)
            .buttonStyle(.borderedProminent)
            
            if isLoading {
                ProgressView("Loading directions...")
            }
            
            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            if let data = directionsData {
                ScrollView {
                    Text("Directions Response:")
                        .font(.headline)
                    Text(formatResponse(data))
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
    }
    
    private func fetchDirections() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Convert curl command to Swift using APIService
            // curl "https://api.mapbox.com/directions/v5/mapbox/cycling/-122.42,37.78;-77.03,38.91?access_token=..."
            let response = try await apiService.asyncCallAPI(
                url: "https://api.mapbox.com/directions/v5/mapbox/walking/\(startCoordinate);\(endCoordinate)",
                method: "GET",
                params: ["access_token": mapboxToken]
            )
            
            directionsData = response
            
        } catch let apiError as APIError {
            errorMessage = "API Error: \(apiError.message)"
            if let code = apiError.code {
                errorMessage! += " (Status: \(code))"
            }
        } catch {
            errorMessage = "Network Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func formatResponse(_ data: Any) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? "Unable to format response"
        } catch {
            return "\(data)"
        }
    }
}

#Preview {
//    MapboxDirectionsView()
    MapboxMapView()
    // MapLibreMapViewWrapper()
}
