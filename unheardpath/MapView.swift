import SwiftUI
import MapKit
import MapboxMaps
import CoreLocation
import MapLibre
import OSLog
import OSLog



struct AppleMapView: View {
    @State private var locationManager = CLLocationManager()
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.015944, longitude: 28.955556),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true)
                .ignoresSafeArea()
                .onAppear {
                    // Request location permission
                    locationManager.requestWhenInUseAuthorization()
                }
        }
        .overlay(alignment: .topLeading) {
            BackButton(showBackground: true)
        }
        .navigationBarHidden(true)
    }
}

struct MapView: View {
    var body: some View {
        let center = CLLocationCoordinate2D(latitude: 39.5, longitude: -98.0)
        // Mapbox SDK automatically reads MBXAccessToken from Info.plist (injected via Config.xcconfig)
        // If token is missing from Info.plist on device, it will show black screen with Mapbox logo
        Map(initialViewport: .camera(center: center, zoom: 2, bearing: 0, pitch: 0)) {
            // Mapbox needs a style to render tiles
        }
        .mapStyle(MapStyle(uri: StyleURI.standard)) // Use standard Mapbox style
        .ignoresSafeArea()
        .onAppear {
            verifyMapboxToken()
            // Additional check: verify token is actually accessible
            checkMapboxTokenAccessibility()
        }
    }
    
    /// Additional check to verify token is accessible (helps diagnose device vs simulator differences)
    private func checkMapboxTokenAccessibility() {
        guard let token = Bundle.main.infoDictionary?["MBXAccessToken"] as? String,
              !token.isEmpty else {
            print("❌ CRITICAL: MBXAccessToken not found in Info.plist on device!")
            print("   This will cause black screen with Mapbox logo")
            print("   The map loads but can't fetch tiles without a valid token")
            print("   Solution: Ensure Config.xcconfig is properly configured and rebuild")
            return
        }
        
        print("✅ MBXAccessToken is accessible: \(String(token.prefix(20)))...")
        print("   If map is still black, check:")
        print("   1. Token is valid and has proper permissions")
        print("   2. Device has internet connection")
        print("   3. No firewall/proxy blocking Mapbox API")
    }
    
    /// Verifies that Mapbox access token is available from Config.xcconfig via Info.plist
    private func verifyMapboxToken() {
        let logger = Logger(subsystem: "com.unheardpath.app", category: "Mapbox")
        let verification = verifyMapboxConfiguration()
        
        // Always log on device (not just DEBUG) to help diagnose device issues
        if verification.isValid {
            let message = "✅ Mapbox access token verified from Config.xcconfig"
            print(message)
            logger.info("\(message)")
            if let tokenPrefix = verification.tokenPrefix {
                let prefixMessage = "   Token prefix: \(tokenPrefix)..."
                print(prefixMessage)
                logger.debug("\(prefixMessage)")
            }
            
            // Check if token is actually accessible to Mapbox SDK
            if let token = Bundle.main.infoDictionary?["MBXAccessToken"] as? String {
                print("✅ MBXAccessToken found in Info.plist: \(String(token.prefix(20)))...")
                // Verify token format
                if !token.hasPrefix("pk.") && !token.hasPrefix("sk.") {
                    print("⚠️ WARNING: Token format looks incorrect. Expected 'pk.eyJ...' or 'sk.eyJ...'")
                }
            }
        } else {
            let error = verification.error ?? "Unknown error"
            let errorMessage = "❌ Mapbox token verification failed: \(error)"
            print(errorMessage)
        }
    }
}

// MARK: - Custom Location Provider for Mapbox
/// Custom location provider that bridges the shared LocationManager to Mapbox
/// This ensures Mapbox uses the same location data as the rest of the app
/// Note: Mapbox's location system will still track location internally for the puck,
/// but we configure it to match LocationManager's settings and avoid duplicate permission requests

struct MapboxMapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @Binding var geoJSONData: [String: Any]?
    @Binding var geoJSONUpdateTrigger: UUID
    @State private var mapProxy: MapboxMaps.MapProxy?
    @State private var selectedFeature: [String: Any]?
    @State private var showPopup: Bool = false
    
    /// Offset distance in degrees to move camera south of user location
    /// This creates space for UI elements (like bottom sheets) above the user's location
    private let cameraOffsetSouth: Double = 0.006 // Approximately 200-250 meters south
    
    /// Calculates camera center offset south of the given location
    /// This allows the puck to show at the actual location while camera is offset
    private func offsetCameraSouth(of location: CLLocation) -> CLLocationCoordinate2D {
        return CLLocationCoordinate2D(
            latitude: location.coordinate.latitude - cameraOffsetSouth,
            longitude: location.coordinate.longitude
        )
    }
    
    /// Computes the initial viewport using the saved location from LocationManager
    /// LocationManager loads the last saved location on init, so it should be available immediately
    private var initialViewport: Viewport {
        if let location = locationManager.currentLocation {
            // Use saved location with offset south for camera center
            let offsetCenter = offsetCameraSouth(of: location)
            return .camera(center: offsetCenter, zoom: 14, bearing: 0, pitch: 0)
        } else {
            // Fallback: Use a wide viewport if no saved location exists (first time app launch)
            return .camera(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), zoom: 2, bearing: 0, pitch: 0)
        }
    }
    
    var body: some View {
        ZStack {
            MapReader { proxy in
                MapboxMaps.Map(initialViewport: initialViewport) {
                    // Add user location puck - this is Mapbox's recommended way
                    MapboxMaps.Puck2D(bearing: MapboxMaps.PuckBearing.heading)
                }
                // .mapStyle(MapboxMaps.MapStyle(uri: StyleURI.standard)) // Use standard Mapbox style
                .mapStyle(MapboxMaps.MapStyle(uri: MapboxMaps.StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
                .ignoresSafeArea()
                .onAppear {
                    mapProxy = proxy
                    verifyMapboxToken()
                    setupMapboxLocation(proxy: proxy)
                    // If we have a saved location, update camera immediately
                    // (LocationManager loads saved location on init, so it should be available)
                    if let location = locationManager.currentLocation {
                        updateMapCamera(proxy: proxy, location: location)
                    }
                    // GeoJSON data will be added as a source when available
                }
                .onChange(of: locationManager.currentLocation) { newLocation in
                    // When location updates from shared LocationManager, update camera
                    // This happens when GPS gets a fresh location update
                    if let location = newLocation {
                        updateMapCamera(proxy: proxy, location: location)
                    }
                }
                .onChange(of: geoJSONUpdateTrigger) { _ in
                    // When geojson data is updated, show nearby points on map
                    #if DEBUG
                    print("🔄 geoJSONUpdateTrigger changed, geoJSONData: \(geoJSONData != nil ? "exists" : "nil")")
                    #endif
                    if let geoJSON = geoJSONData {
                        #if DEBUG
                        print("🗺️ Calling showNearby with geoJSON")
                        #endif
                        showNearby(geoJSON: geoJSON)
                    } else {
                        #if DEBUG
                        print("⚠️ geoJSONData is nil, cannot show nearby points")
                        #endif
                    }
                }
            }
            
            // Popup overlay
            if showPopup, let feature = selectedFeature,
               let properties = feature["properties"] as? [String: Any] {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if let idx = properties["idx"] as? Int {
                                Text("Index: \(idx)")
                                    .font(.headline)
                            }
                            Spacer()
                            Button(action: {
                                showPopup = false
                                selectedFeature = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        if let extract = properties["extract"] as? String {
                            Text(extract)
                                .font(.body)
                                .lineLimit(5)
                        }
                        
                        if let imgURL = properties["img_url"] as? String,
                           let imageURL = URL(string: imgURL) {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                case .failure:
                                    EmptyView()
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(.horizontal)
                    .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .navigationBarHidden(true)
    }
    
    /// Verifies that Mapbox access token is available from Config.xcconfig via Info.plist
    /// The Mapbox iOS SDK automatically reads MBXAccessToken from Info.plist
    private func verifyMapboxToken() {
        // Verify token is available (loaded from Config.xcconfig via Info.plist)
        let verification = verifyMapboxConfiguration()
        
        if verification.isValid {
            #if DEBUG
            print("✅ Mapbox access token verified from Config.xcconfig")
            if let tokenPrefix = verification.tokenPrefix {
                print("   Token prefix: \(tokenPrefix)...")
            }
            #endif
        } else {
            #if DEBUG
            let error = verification.error ?? "Unknown error"
            print("❌ Mapbox token verification failed: \(error)")
            print("   Make sure Config.xcconfig has MAPBOX_ACCESS_TOKEN set")
            print("   and INFOPLIST_KEY_MBXAccessToken = $(MAPBOX_ACCESS_TOKEN)")
            #endif
        }
    }
    
    private func setupMapboxLocation(proxy: MapboxMaps.MapProxy) {
        print("🔧 Setting up Mapbox location with shared LocationManager...")
        
        // Note: Location permission is already handled by the shared LocationManager
        // in unheardpathApp.swift, so we don't need to request it again here.
        // This avoids duplicate permission requests.
        
        // Configure Mapbox's location provider to match LocationManager's settings
        // This ensures consistent behavior and reduces battery usage
        let mapboxProvider = AppleLocationProvider()
        mapboxProvider.options.activityType = .otherNavigation
        // Match LocationManager's accuracy setting (kCLLocationAccuracyHundredMeters)
        mapboxProvider.options.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        // Override the map's location provider
        proxy.location?.override(provider: mapboxProvider)
        
        // Configure location puck options
        proxy.location?.options.puckType = .puck2D()
        proxy.location?.options.puckBearingEnabled = true
        
        // If we already have a location from shared LocationManager, center the map on it
        if let currentLocation = locationManager.currentLocation {
            updateMapCamera(proxy: proxy, location: currentLocation)
        }
        
        #if DEBUG
        print("✅ Mapbox location provider configured")
        print("   Using shared LocationManager for permission handling")
        print("   Mapbox location provider configured to match LocationManager accuracy settings")
        if let currentLocation = locationManager.currentLocation {
            print("   Current location: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
        } else {
            print("   Waiting for location update from shared LocationManager...")
        }
        #endif
    }
    
    /// Updates the map camera to center slightly south of the user's location
    /// The location puck will show at the actual user location, but the camera will be offset south
    /// This creates space for UI elements (like bottom sheets) above the user's location
    private func updateMapCamera(proxy: MapboxMaps.MapProxy, location: CLLocation) {
        // Calculate offset camera center (south of user location)
        let offsetCenter = offsetCameraSouth(of: location)
        
        // Update camera to the offset center programmatically
        // The puck will still show at the actual user location
        Task { @MainActor in
            let cameraOptions = CameraOptions(
                center: offsetCenter,
                zoom: 14,
                bearing: 0,
                pitch: 0
            )
            
            // Use the map's camera API to update the viewport
            guard let camera = proxy.camera else {
                #if DEBUG
                print("⚠️ Camera proxy not available yet, will retry")
                #endif
                return
            }
            
            // Try to update camera - the exact method may vary by SDK version
            // Using flyTo with a short duration for smooth transition
            do {
                try await camera.fly(to: cameraOptions, duration: 0.5)
                #if DEBUG
                print("✅ Camera updated to offset center (south of user): \(offsetCenter.latitude), \(offsetCenter.longitude)")
                print("   User location puck at: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ Camera update failed: \(error.localizedDescription)")
                print("   Camera center state updated to: \(offsetCenter.latitude), \(offsetCenter.longitude)")
                #endif
            }
        }
    }
    
    /// Adds nearby points from GeoJSON data source
    /// - Parameter geoJSON: Dictionary containing GeoJSON FeatureCollection with features
    func showNearby(geoJSON: [String: Any]) {
        guard let data = geoJSON["data"] as? [String: Any] else {
            #if DEBUG
            print("❌ Invalid GeoJSON structure: missing 'data' key")
            print("   Available keys: \(geoJSON.keys.joined(separator: ", "))")
            #endif
            return
        }
        
        guard let features = data["features"] as? [[String: Any]] else {
            #if DEBUG
            print("❌ Invalid GeoJSON structure: missing 'data.features'")
            print("   Data keys: \(data.keys.joined(separator: ", "))")
            #endif
            return
        }
        
        #if DEBUG
        print("✅ Found \(features.count) features in GeoJSON")
        #endif
        
        // Add GeoJSON as a source to the map
        addGeoJSONSource(geoJSONData: data)
    }
    
    /// Add GeoJSON source and layer to the map
    private func addGeoJSONSource(geoJSONData: [String: Any]) {
        guard let mapProxy = mapProxy else {
            #if DEBUG
            print("⚠️ Map proxy not available yet")
            #endif
            return
        }
        
        Task {
            do {
                // Convert GeoJSON dictionary to JSON string
                let jsonData = try JSONSerialization.data(withJSONObject: geoJSONData)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    #if DEBUG
                    print("❌ Failed to convert GeoJSON to string")
                    #endif
                    return
                }
                
                // Create GeoJSON source with data
                let sourceId = "nearby-places-source"
                var source = MapboxMaps.GeoJSONSource(id: sourceId)
                source.data = .string(jsonString)
                
                // Add or update source
                guard let map = mapProxy.map else {
                    #if DEBUG
                    print("⚠️ Map not available")
                    #endif
                    return
                }
                
                try await map.addSource(source)
                
                // Create circle layer for points
                let layerId = "nearby-places-layer"
                var circleLayer = MapboxMaps.CircleLayer(id: layerId, source: sourceId)
                circleLayer.circleColor = .constant(StyleColor(.blue))
                circleLayer.circleRadius = .constant(8)
                circleLayer.circleStrokeWidth = .constant(2)
                circleLayer.circleStrokeColor = .constant(StyleColor(.white))
                
                // Remove existing layer if it exists, then add new one
                try? await map.removeLayer(withId: layerId)
                try await map.addLayer(circleLayer)
                
                #if DEBUG
                print("✅ Added GeoJSON source and layer to map")
                #endif
            } catch {
                #if DEBUG
                print("❌ Failed to add GeoJSON source: \(error)")
                #endif
            }
        }
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



#Preview {
//    MapboxDirectionsView()
    MapboxMapView(geoJSONData: .constant(nil), geoJSONUpdateTrigger: .constant(UUID()))
        .environmentObject(LocationManager())
    // MapView()
    // MapLibreMapViewWrapper()
}
