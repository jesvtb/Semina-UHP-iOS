import SwiftUI
import MapKit
import MapboxMaps
import CoreLocation
import OSLog
import SafariServices



// MARK: - Target Location Model
/// Represents a target location with its coordinates and place name
/// Used for autocomplete selections to update map camera and show marker
struct TargetLocation: Equatable {
    let location: CLLocation
    let name: String?
    
    static func == (lhs: TargetLocation, rhs: TargetLocation) -> Bool {
        return lhs.location.coordinate.latitude == rhs.location.coordinate.latitude &&
               lhs.location.coordinate.longitude == rhs.location.coordinate.longitude &&
               lhs.name == rhs.name
    }
}

// MARK: - Custom Location Provider for Mapbox
/// Custom location provider that bridges the shared LocationManager to Mapbox
/// This ensures Mapbox uses the same location data as the rest of the app
/// Note: Mapbox's location system will still track location internally for the puck,
/// but we configure it to match LocationManager's settings and avoid duplicate permission requests

struct MapboxMapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @Binding var poisGeoJSON: GeoJSON
    @Binding var geoJSONUpdateTrigger: UUID
    @Binding var targetLocation: TargetLocation?
    @State private var mapProxy: MapboxMaps.MapProxy?
    @State private var defaultPitch: Double = 60
    
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
        if let location = locationManager.deviceLocation {
            // Use saved location with offset south for camera center
            let offsetCenter = offsetCameraSouth(of: location)
            #if DEBUG 
            print("🌍 Initalizd map with device location offset: \(offsetCenter.latitude), \(offsetCenter.longitude)")
            #endif

            
            return .camera(center: offsetCenter, zoom: 14, bearing: 0, pitch: defaultPitch)
        } else {
            #if DEBUG
            print("🌍 Initalizd map with fallback viewport")
            #endif
            // Fallback: Use a wide viewport if no saved location exists (first time app launch)
            return .camera(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), zoom: 3, bearing: 0, pitch: defaultPitch)
        }
    }
    
    
    var body: some View {
        ZStack {
            MapReader { proxy in
                MapboxMaps.Map(initialViewport: initialViewport) {
                    // Add user location puck - this is Mapbox's recommended way
                    MapboxMaps.Puck2D(bearing: MapboxMaps.PuckBearing.heading)
                    
                    // Add GeoJSON content using declarative MapContent API
                    // Use poisGeoJSON directly
                    showGeoJSON(geoJSON: poisGeoJSON)
                    
                    // Add lookup location marker when autocomplete selection is made
                    if let targetLocation = targetLocation {
                        MapboxMaps.MapViewAnnotation(coordinate: targetLocation.location.coordinate) {
                            LookupLocation(targetLocation: targetLocation)
                        }
                        .allowOverlap(true)
                    }
                    
                    #if DEBUG
                    // Add geofence visualization for debugging
                    if let geofenceInfo = locationManager.devicePOIsGeofenceDebugInfo {
                        showGeofenceDebugCircle(
                            center: geofenceInfo.center,
                            radius: geofenceInfo.radius,
                            isMonitoring: geofenceInfo.isMonitoring
                        )
                    }
                    #endif
                }
                // .mapStyle(MapboxMaps.MapStyle(uri: StyleURI.standard)) // Use standard Mapbox style
                .mapStyle(MapboxMaps.MapStyle(uri: MapboxMaps.StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
                .id(geoJSONUpdateTrigger) // Force re-render when GeoJSON data updates
                .ignoresSafeArea()
                .onAppear {
                    mapProxy = proxy
                    setupMapboxLocation(proxy: proxy)
                    // If we have a saved location, update camera immediately
                    // (LocationManager loads saved location on init, so it should be available)
                    if let location = locationManager.deviceLocation {
                        updateMapCamera(proxy: proxy, location: location, isDeviceLocation: true)
                    }
                    // GeoJSON data will be added as a source when available
                }
                .onChange(of: locationManager.deviceLocation) { newLocation in
                    // When location updates from shared LocationManager, update camera
                    // This happens when GPS gets a fresh location update
                    if let location = newLocation {
                        updateMapCamera(proxy: proxy, location: location, isDeviceLocation: true)
                    }
                }
                .onChange(of: geoJSONUpdateTrigger) { _ in
                    // When GeoJSON data updates, fit camera to show all features
                    fitCameraToGeoJSON(proxy: proxy, geoJSON: poisGeoJSON)
                }
                .onChange(of: targetLocation) { newTargetLocation in
                    // When target location is set (from autocomplete selection), fly to it and show marker
                    if let target = newTargetLocation {
                        updateMapCamera(proxy: proxy, location: target.location, isDeviceLocation: false)
                        // Note: We don't reset targetLocation to nil here because it's needed to display the marker
                        // The marker will persist until a new targetLocation is set (replacing the old one)
                    }
                }
                // Note: geoJSONUpdateTrigger is still used to trigger re-rendering when data changes
                // The declarative MapContent API will automatically update when poisGeoJSON changes
            }
            
        }
        .navigationBarHidden(true)
    }
    
    
    private func setupMapboxLocation(proxy: MapboxMaps.MapProxy) {
        #if DEBUG
        print("🌍 Setting up Mapbox location with shared LocationManager...")
        #endif
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
        if let deviceLocation = locationManager.deviceLocation {
            updateMapCamera(proxy: proxy, location: deviceLocation, isDeviceLocation: true)
        }
        
        #if DEBUG
        print("✅ Mapbox location provider configured")
        print("   Using shared LocationManager for permission handling")
        print("   Mapbox location provider configured to match LocationManager accuracy settings")
        if let deviceLocation = locationManager.deviceLocation {
            print("   Current location: \(deviceLocation.coordinate.latitude), \(deviceLocation.coordinate.longitude)")
        } else {
            print("   Waiting for location update from shared LocationManager...")
        }
        #endif
    }
    
    /// Updates the map camera to center slightly south of the user's location
    /// The location puck will show at the actual user location, but the camera will be offset south
    /// This creates space for UI elements (like bottom sheets) above the user's location
    /// When isDeviceLocation is false, centers directly on the target location without offset
    private func updateMapCamera(proxy: MapboxMaps.MapProxy, location: CLLocation, isDeviceLocation: Bool = true) {
        // For user location, offset camera south; for target locations (autocomplete), center directly
        let cameraCenter = isDeviceLocation ? offsetCameraSouth(of: location) : location.coordinate
        
        // Update camera to the center programmatically
        Task { @MainActor in
            let cameraOptions = CameraOptions(
                center: cameraCenter,
                zoom: 14,
                bearing: 0,
                pitch: defaultPitch
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
            camera.fly(to: cameraOptions, duration: 0.5)
            #if DEBUG
            if isDeviceLocation {
                print("✅ Camera updated to offset center (south of user): \(cameraCenter.latitude), \(cameraCenter.longitude)")
                print("📍 User location puck at: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            } else {
                print("✅ Camera flew to target location: \(cameraCenter.latitude), \(cameraCenter.longitude)")
            }
            #endif
        }
    }
    
    /// Fits the camera to show all GeoJSON features' coordinates
    /// Uses Mapbox SDK's camera(for:...) method following the recommended workflow
    private func fitCameraToGeoJSON(proxy: MapboxMaps.MapProxy, geoJSON: GeoJSON) {
        let coordinates = geoJSON.extractCoordinates()
        
        guard !coordinates.isEmpty else {
            #if DEBUG
            print("⚠️ No coordinates found in GeoJSON features to fit camera")
            #endif
            return
        }
        
        Task { @MainActor in
            // The reference camera options will be applied before calculating a camera fitting the given coordinates
            // If any of the fields in this reference camera options is not provided then the current value from the map will be used
            let referenceCamera = CameraOptions(pitch: defaultPitch)
            
            // Access the underlying MapboxMap instance via proxy.map
            // Fit camera to the given coordinates using Mapbox SDK's recommended method
            guard let mapboxMap = proxy.map,
                  let cameraOptions = try? mapboxMap.camera(
                      for: coordinates,
                      camera: referenceCamera,
                      coordinatesPadding: .zero,
                      maxZoom: nil,
                      offset: nil
                  ) else {
                #if DEBUG
                print("⚠️ Failed to calculate camera for GeoJSON coordinates using SDK method")
                #endif
                return
            }
            
            // Apply the fitted camera
            guard let camera = proxy.camera else {
                #if DEBUG
                print("⚠️ Camera proxy not available for fitting")
                #endif
                return
            }
            
            // Use flyTo with a short duration for smooth transition
            camera.fly(to: cameraOptions, duration: 0.5)
            
            #if DEBUG
            print("✅ Camera fitted to \(coordinates.count) GeoJSON feature coordinates using SDK method")
           
            #endif
        }
    }
    
    fileprivate func showGeoJSON(geoJSON: GeoJSON) -> GeoJSONMapContent {
        return GeoJSONMapContent(geoJSON: geoJSON)
    }
    
    #if DEBUG
    /// Creates a GeoJSON circle feature for geofence debug visualization
    /// Uses approximate method to create a circle polygon from center and radius
    fileprivate func showGeofenceDebugCircle(
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        isMonitoring: Bool
    ) -> GeofenceDebugCircleContent {
        return GeofenceDebugCircleContent(
            center: center,
            radius: radius,
            isMonitoring: isMonitoring
        )
    }
    #endif
}

#if DEBUG
// MARK: - Geofence Debug Circle MapContent
/// MapContent component for displaying geofence debug circle on map
fileprivate struct GeofenceDebugCircleContent: MapboxMaps.MapContent {
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

// MARK: - Custom Annotation View
/// Custom SwiftUI view for GeoJSON feature annotations
/// Used with MapViewAnnotation to display feature information on the map
fileprivate struct PlaceView: View {
    let properties: [String: JSONValue]?
    @State private var showWebPage: Bool = false
    
    /// Frame size for the circular image
    private let imageFrameSize: CGFloat = Spacing.current.spaceL
    
    /// Extracts Wikipedia URL from properties
    private var wikipediaURL: URL? {
        guard let properties = properties,
              let wikipediaValue = properties["wikipedia"],
              let wikipedia = wikipediaValue.dictionaryValue,
              let urlValue = wikipedia["url"],
              let urlString = urlValue.stringValue,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }
    
    /// Handles tap action on the place annotation
    private func handleTap() {
        if wikipediaURL != nil {
            showWebPage = true
        }
    }
    
    /// Extracts title from properties, prioritizing names field with device_lang, local_lang, global_lang
    /// Falls back to "title" or "name" fields if names is not available
    private var title: String? {
        guard let properties = properties else { return nil }
        
        // First, try to get title from names field with priority: device_lang > local_lang > global_lang
        if let namesValue = properties["names"],
           let names = namesValue.dictionaryValue {
            if let deviceLangValue = names["device_lang"],
               let deviceLang = deviceLangValue.stringValue,
               !deviceLang.isEmpty {
                return deviceLang
            }
            if let localLangValue = names["local_lang"],
               let localLang = localLangValue.stringValue,
               !localLang.isEmpty {
                return localLang
            }
            if let globalLangValue = names["global_lang"],
               let globalLang = globalLangValue.stringValue,
               !globalLang.isEmpty {
                return globalLang
            }
        }
        
        // Fall back to title or name fields if names is not available or empty
        if let titleValue = properties["title"],
           let title = titleValue.stringValue {
            return title
        }
        if let nameValue = properties["name"],
           let name = nameValue.stringValue {
            return name
        }
        return nil
    }
    
    /// Extracts image URL from properties
    /// img_url is a direct child of properties
    /// Handles URLs with special characters (e.g., parentheses in Wikipedia URLs)
    private var imageURL: URL? {
        guard let properties = properties,
              let imgURLValue = properties["img_url"],
              let imgURL = imgURLValue.stringValue else {
            return nil
        }
        
        // Trim whitespace
        let trimmedURL = imgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create URL - URL(string:) handles properly formatted URLs including those with parentheses
        // Wikipedia URLs like "https://en.wikipedia.org/wiki/Special:FilePath/Hagia_Sophia_(228968325).jpeg" work as-is
        guard let url = URL(string: trimmedURL) else {
            #if DEBUG
            print("⚠️ Failed to create URL from img_url: \(trimmedURL)")
            #endif
            return nil
        }
        
        // Ensure it's an HTTP/HTTPS URL
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            #if DEBUG
            print("⚠️ img_url is not an HTTP/HTTPS URL: \(trimmedURL)")
            #endif
            return nil
        }
        
        return url
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Image in circular clip (only show if img_url exists)
            if let imageURL = imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: imageFrameSize, height: imageFrameSize)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: imageFrameSize, height: imageFrameSize)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color("AppBkgColor"), lineWidth: 2))
                            .shadow(radius: Spacing.current.space3xs)
                    case .failure:
                        #if DEBUG
                        let _ = print("⚠️ Failed to load image from URL: \(imageURL.absoluteString)")
                        #endif
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            // Title text (only show if title exists)
            if let title = title {
                Text(title)
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor10"))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.vertical,Spacing.current.space3xs)
                    .padding(.horizontal,Spacing.current.space2xs)
                    .background(Color("AppBkgColor").cornerRadius(Spacing.current.spaceXs))
                    .shadow(radius: Spacing.current.space3xs)
            }
            // Pin icon
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: Spacing.current.spaceXs))
                .foregroundColor(Color("AppBkgColor"))
                .shadow(radius: Spacing.current.space3xs)
            
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .sheet(isPresented: $showWebPage) {
            if let url = wikipediaURL {
                SafariView(url: url)
            }
        }
    }
}

// MARK: - Lookup Location Annotation View
/// Custom SwiftUI view for lookup location annotations (from autocomplete selection)
/// Used with MapViewAnnotation to display lookup place information on the map
fileprivate struct LookupLocation: View {
    let targetLocation: TargetLocation
    
    var body: some View {
        VStack(spacing: 4) {
            // Pin icon
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: Spacing.current.spaceM))
                .foregroundColor(Color("AppBkgColor"))
                .shadow(radius: Spacing.current.space3xs)
            
            // Place name text (only show if name exists)
            if let name = targetLocation.name {
                Text(name)
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor10"))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, Spacing.current.space3xs)
                    .padding(.horizontal, Spacing.current.space2xs)
                    .background(Color("AppBkgColor").cornerRadius(Spacing.current.spaceXs))
                    .shadow(radius: Spacing.current.space3xs)
            }
        }
    }
}

// MARK: - GeoJSON Helper Functions
/// Shared helper function to extract coordinate from a Point geometry feature
/// GeoJSON coordinates format: [longitude, latitude]
fileprivate func extractCoordinateFromFeature(_ feature: [String: Any]) -> CLLocationCoordinate2D? {
    guard let geometry = feature["geometry"] as? [String: Any],
          let type = geometry["type"] as? String,
          type == "Point",
          let coordinatesArray = geometry["coordinates"] as? [Any],
          coordinatesArray.count >= 2 else {
        return nil
    }
    
    // Convert coordinates from Any to Double
    let longitude: Double?
    let latitude: Double?
    
    if let lon = coordinatesArray[0] as? Double {
        longitude = lon
    } else if let lonNum = coordinatesArray[0] as? NSNumber {
        longitude = lonNum.doubleValue
    } else {
        longitude = nil
    }
    
    if let lat = coordinatesArray[1] as? Double {
        latitude = lat
    } else if let latNum = coordinatesArray[1] as? NSNumber {
        latitude = latNum.doubleValue
    } else {
        latitude = nil
    }
    
    guard let lon = longitude, let lat = latitude else {
        return nil
    }
    
    // GeoJSON coordinates are [longitude, latitude]
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
}

// MARK: - GeoJSON MapContent Component
/// A custom MapContent component that renders GeoJSON data on the map
/// Follows Mapbox best practices for declarative map styling
fileprivate struct GeoJSONMapContent: MapboxMaps.MapContent {
    /// The GeoJSON struct to render
    let geoJSON: GeoJSON
    
    /// Use GeoJSON's toMapboxString() method directly
    private var jsonString: String {
        return geoJSON.toMapboxString()
    }
    
    /// Use GeoJSON's features property directly (no conversion needed)
    private var features: [[String: JSONValue]] {
        return geoJSON.features
    }
    
    /// Extract coordinate from a Point geometry feature
    private func coordinate(from feature: [String: JSONValue]) -> CLLocationCoordinate2D? {
        // Convert JSONValue feature to [String: Any] for existing helper function
        let featureAsAny = feature.mapValues { $0.asAny }
        return extractCoordinateFromFeature(featureAsAny)
    }
    
    /// Extract properties from a feature
    private func properties(from feature: [String: JSONValue]) -> [String: JSONValue]? {
        guard let propertiesValue = feature["properties"],
              case .dictionary(let propertiesDict) = propertiesValue else {
            return nil
        }
        return propertiesDict
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
        MapboxMaps.ForEvery(Array(features.enumerated()), id: \.offset) { index, feature in
            if let coordinate = coordinate(from: feature),
               let properties = properties(from: feature),
               properties["idx"] != nil {
                MapboxMaps.MapViewAnnotation(coordinate: coordinate) {
    MainActor.assumeIsolated {
        PlaceView(properties: properties)  // ✅ @State works fine
    }
}
                .allowOverlap(true)
                // .priority(0)
                // .priority(Int(distanceFromUser / 100))
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



#Preview {
//    MapboxDirectionsView()
    MapboxMapView(
        poisGeoJSON: .constant(GeoJSON()),
        geoJSONUpdateTrigger: .constant(UUID()),
        targetLocation: .constant(nil)
    )
        .environmentObject(LocationManager())
    // MapView()
    // MapLibreMapViewWrapper()
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
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Extract the "data" field which contains the FeatureCollection
            if let dataField = json?["data"] as? [String: Any],
               let features = dataField["features"] as? [[String: Any]] {
                // Convert features to [[String: JSONValue]]
                let featuresJSONValue = try features.map { featureDict -> [String: JSONValue] in
                    guard let jsonValueDict = JSONValue.dictionary(from: featureDict) else {
                        throw NSError(domain: "GeoJSONPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert feature to JSONValue"])
                    }
                    return jsonValueDict
                }
                geoJSON.setFeatures(featuresJSONValue)
                #if DEBUG
                print("✅ Loaded GeoJSON preview with \(featuresJSONValue.count) features")
                #endif
            } else {
                #if DEBUG
                print("❌ Invalid JSON structure: missing 'data' field or 'features' array")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ Failed to load GeoJSON: \(error.localizedDescription)")
            #endif
        }
    }
}

#Preview("GeoJSON Preview") {
    MapViewGeoJSONPreview()
}
