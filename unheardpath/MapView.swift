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
            logger.error("\(errorMessage)")
            
            // Print all available Info.plist keys to help diagnose
            if let infoDict = Bundle.main.infoDictionary {
                print("🔍 Available Info.plist keys: \(infoDict.keys.sorted().joined(separator: ", "))")
            }
            
            let helpMessage = "   Make sure Config.xcconfig has MAPBOX_ACCESS_TOKEN set and INFOPLIST_KEY_MBXAccessToken = $(MAPBOX_ACCESS_TOKEN)"
            print(helpMessage)
            logger.error("\(helpMessage)")
            print("   For device builds: Clean build folder (Cmd+Shift+K) and rebuild")
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
            .mapStyle(MapStyle(uri: StyleURI.standard)) // Use standard Mapbox style
            // Or use custom style: .mapStyle(MapStyle(uri: StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
            .ignoresSafeArea()
            .onAppear {
                verifyMapboxToken()
                setupMapboxLocation(proxy: proxy)
            }
        }
        .overlay(alignment: .topLeading) {
            BackButton(showBackground: true)
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



#Preview {
//    MapboxDirectionsView()
    MapboxMapView()
    // MapView()
    // MapLibreMapViewWrapper()
}
