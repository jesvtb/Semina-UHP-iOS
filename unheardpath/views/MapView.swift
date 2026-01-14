import SwiftUI
import MapboxMaps
import CoreLocation



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
    @EnvironmentObject var mapFeaturesManager: MapFeaturesManager
    @Binding var targetLocation: TargetLocation?
    @Binding var selectedLocation: CLLocation?
    @State private var mapProxy: MapboxMaps.MapProxy?
    @State private var defaultPitch: Double = 60
    @State private var longPressLocation: CGPoint?
    
    /// Offset distance in degrees to move camera south of user location
    /// This creates space for UI elements (like bottom sheets) above the user's location
    private let cameraOffsetSouth: Double = 0.01 // Approximately 200-250 meters south
    
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
                    // Use mapFeaturesManager.poisGeoJSON directly
                    GeoJSONMapContent(geoJSON: mapFeaturesManager.poisGeoJSON)
                    
                    // Add lookup location marker when autocomplete selection is made
                    if let targetLocation = targetLocation {
                        MapboxMaps.MapViewAnnotation(coordinate: targetLocation.location.coordinate) {
                            LookupLocation(targetLocation: targetLocation)
                        }
                        .allowOverlap(true)
                    }
                    
                    // Add marker for manually selected location (long press)
                    if let selectedLocation = selectedLocation {
                        let manualTargetLocation = TargetLocation(location: selectedLocation, name: nil)
                        MapboxMaps.MapViewAnnotation(coordinate: selectedLocation.coordinate) {
                            LookupLocation(targetLocation: manualTargetLocation)
                        }
                        .allowOverlap(true)
                    }
                    
                    #if DEBUG
                    // Add geofence visualization for debugging
                    if let geofenceInfo = locationManager.devicePOIsGeofenceDebugInfo {
                        GeofenceDebugCircleContent(
                            center: geofenceInfo.center,
                            radius: geofenceInfo.radius,
                            isMonitoring: geofenceInfo.isMonitoring
                        )
                    }
                    #endif
                }
                // .mapStyle(MapboxMaps.MapStyle(uri: StyleURI.standard)) // Use standard Mapbox style
                .mapStyle(MapboxMaps.MapStyle(uri: MapboxMaps.StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
                .id(mapFeaturesManager.geoJSONUpdateTrigger) // Force re-render when GeoJSON data updates
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
                .onChange(of: mapFeaturesManager.geoJSONUpdateTrigger) { _ in
                    // When GeoJSON data updates, fit camera to show all features
                    fitCameraToGeoJSON(proxy: proxy, geoJSON: mapFeaturesManager.poisGeoJSON)
                }
                .onChange(of: targetLocation) { newTargetLocation in
                    // When target location is set (from autocomplete selection), fly to it and show marker
                    if let target = newTargetLocation {
                        updateMapCamera(proxy: proxy, location: target.location, isDeviceLocation: false)
                        // Note: We don't reset targetLocation to nil here because it's needed to display the marker
                        // The marker will persist until a new targetLocation is set (replacing the old one)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Track the initial touch location for long press
                            if longPressLocation == nil {
                                longPressLocation = value.startLocation
                            }
                        }
                        .onEnded { _ in
                            // Reset on end (unless long press is active)
                            // Delay reset to allow long press to complete
                            Task {
                                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
                                await MainActor.run {
                                    longPressLocation = nil
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            // When long press completes, use the tracked location
                            if let location = longPressLocation, let proxy = mapProxy {
                                handleLongPressSelection(at: location, proxy: proxy)
                                longPressLocation = nil
                            }
                        }
                )
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
    /// Applies the same geographic offset south as the initial camera to keep content toward the top of the viewport
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
                  var cameraOptions = try? mapboxMap.camera(
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
            
            // Apply the same geographic offset south as the initial camera
            // This moves the center south, making content appear toward the top of the viewport
            if let currentCenter = cameraOptions.center {
                let location = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                let offsetCenter = offsetCameraSouth(of: location)
                cameraOptions.center = offsetCenter
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
            print("✅ Camera fitted to \(coordinates.count) GeoJSON feature coordinates with south offset applied")
           
            #endif
        }
    }
    
    /// Handles long press selection on the map
    /// Converts screen coordinates to geographic coordinates and creates a CLLocation
    private func handleLongPressSelection(at point: CGPoint, proxy: MapboxMaps.MapProxy) {
        guard let mapboxMap = proxy.map else {
            #if DEBUG
            print("⚠️ MapboxMap not available for coordinate conversion")
            #endif
            return
        }
        
        // Convert screen point to geographic coordinate
        // Note: coordinate(for:) returns a non-optional CLLocationCoordinate2D
        let coordinate = mapboxMap.coordinate(for: point)
        
        // Create CLLocation from coordinate
        // Use default values for altitude and accuracy since manual selection doesn't have this data
        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0.0,
            horizontalAccuracy: kCLLocationAccuracyHundredMeters,
            verticalAccuracy: kCLLocationAccuracyHundredMeters,
            timestamp: Date()
        )
        
        #if DEBUG
        print("📍 Manual location selected: \(coordinate.latitude), \(coordinate.longitude)")
        #endif
        
        // First, set the marker to show immediate visual feedback
        Task { @MainActor in
            selectedLocation = location
            
            // Then, after a brief delay, move the camera to the selected location
            // This creates a more user-friendly flow: marker appears first, then camera moves
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds delay
            // Move camera to selected location with south offset (same as initial viewport)
            updateMapCamera(proxy: proxy, location: location, isDeviceLocation: true)
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
