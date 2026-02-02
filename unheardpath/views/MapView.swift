import SwiftUI
import MapboxMaps
import CoreLocation
import core

// MARK: - Custom Location Provider for Mapbox
/// Custom location provider that bridges the shared LocationManager to Mapbox
/// This ensures Mapbox uses the same location data as the rest of the app
/// Note: Mapbox's location system will still track location internally for the puck,
/// but we configure it to match LocationManager's settings and avoid duplicate permission requests

struct MapboxMapView: View {
    @EnvironmentObject var trackingManager: TrackingManager
    @EnvironmentObject var mapFeaturesManager: MapFeaturesManager
    @State private var mapProxy: MapboxMaps.MapProxy?
    @State private var defaultPitch: Double = 60
    @State private var longPressLocation: CGPoint?

    // Logger for error and debug logging
    private let logger: Logger

    init(logger: Logger = AppLifecycleManager.sharedLogger) {
        self.logger = logger
    }
    
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
    
    /// Computes the initial viewport using the saved location from TrackingManager
    /// TrackingManager loads the last saved location on init, so it should be available immediately
    private var initialViewport: Viewport {
        if let location = trackingManager.deviceLocation {
            // Use saved location with offset south for camera center
            let offsetCenter = offsetCameraSouth(of: location)
            logger.debug("Initialized map with device location offset: \(offsetCenter.latitude), \(offsetCenter.longitude)")
            
            return .camera(center: offsetCenter, zoom: 14, bearing: 0, pitch: defaultPitch)
        } else {
            logger.debug("Initialized map with fallback viewport")
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
                    
                    // Add lookup marker when flyToLocation is set (autocomplete selection or long press)
                    if let flyToLocation = mapFeaturesManager.flyToLocation {
                        MapboxMaps.MapViewAnnotation(coordinate: flyToLocation.location.coordinate) {
                            LookupLocation(flyToLocation: flyToLocation)
                        }
                        .allowOverlap(true)
                    }
                }
                // .mapStyle(MapboxMaps.MapStyle(uri: StyleURI.standard)) // Use standard Mapbox style
                .mapStyle(MapboxMaps.MapStyle(uri: MapboxMaps.StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
                .id(mapFeaturesManager.geoJSONUpdateTrigger) // Force re-render when GeoJSON data updates
                .ignoresSafeArea()
                .onAppear {
                    mapProxy = proxy
                    setupMapboxLocation(proxy: proxy)
                    // If we have a saved location, update camera immediately
                    // (TrackingManager loads saved location on init, so it should be available)
                    if let location = trackingManager.deviceLocation {
                        updateMapCamera(proxy: proxy, location: location, isDeviceLocation: true)
                    }
                    // GeoJSON data will be added as a source when available
                }
                .onChange(of: trackingManager.deviceLocation) { newLocation in
                    // When location updates from shared TrackingManager, update camera
                    // This happens when GPS gets a fresh location update
                    if let location = newLocation {
                        updateMapCamera(proxy: proxy, location: location, isDeviceLocation: true)
                    }
                }
                .onChange(of: mapFeaturesManager.geoJSONUpdateTrigger) { _ in
                    // When GeoJSON data updates, fit camera to show all features
                    fitCameraToGeoJSON(proxy: proxy, geoJSON: mapFeaturesManager.poisGeoJSON)
                }
                .onChange(of: mapFeaturesManager.flyToLocation) { newFlyToLocation in
                    // When flyToLocation is set (autocomplete selection or long press), fly to it and show marker
                    if let flyTo = newFlyToLocation {
                        updateMapCamera(proxy: proxy, location: flyTo.location, isDeviceLocation: false)
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
        logger.debug("Setting up Mapbox location with shared TrackingManager...")
        // Note: Location permission is already handled by the shared TrackingManager
        // in unheardpathApp.swift, so we don't need to request it again here.
        // This avoids duplicate permission requests.
        
        // Configure Mapbox's location provider to match TrackingManager's settings
        // This ensures consistent behavior and reduces battery usage
        var options = AppleLocationProvider.Options()
        options.activityType = .otherNavigation
        // Match TrackingManager's accuracy setting (kCLLocationAccuracyHundredMeters)
        options.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        // Set the map's location data model (replaces deprecated override(provider:))
        proxy.location?.dataModel = LocationDataModel.createDefault(options)
        
        // Configure location puck options
        proxy.location?.options.puckType = .puck2D()
        proxy.location?.options.puckBearingEnabled = true
        
        // If we already have a location from shared TrackingManager, center the map on it
        if let deviceLocation = trackingManager.deviceLocation {
            updateMapCamera(proxy: proxy, location: deviceLocation, isDeviceLocation: true)
        }
        
        logger.debug("Mapbox location provider configured - Using shared TrackingManager for permission handling")
        logger.debug("Mapbox location provider configured to match TrackingManager accuracy settings")
        if let deviceLocation = trackingManager.deviceLocation {
            logger.debug("Current location: \(deviceLocation.coordinate.latitude), \(deviceLocation.coordinate.longitude)")
        } else {
            logger.debug("Waiting for location update from shared TrackingManager...")
        }
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
                logger.warning("Camera proxy not available yet, will retry", handlerType: "MapboxMapView")
                return
            }
            
            // Try to update camera - the exact method may vary by SDK version
            // Using flyTo with a short duration for smooth transition
            camera.fly(to: cameraOptions, duration: 0.5)
            if isDeviceLocation {
                logger.debug("Camera updated to offset center (south of user): \(cameraCenter.latitude), \(cameraCenter.longitude)")
                logger.debug("User location puck at: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            } else {
                logger.debug("Camera flew to target location: \(cameraCenter.latitude), \(cameraCenter.longitude)")
            }
        }
    }
    
    /// Fits the camera to show all GeoJSON features' coordinates
    /// Uses Mapbox SDK's camera(for:...) method following the recommended workflow
    /// Applies the same geographic offset south as the initial camera to keep content toward the top of the viewport
    private func fitCameraToGeoJSON(proxy: MapboxMaps.MapProxy, geoJSON: GeoJSON) {
        let coordinates = geoJSON.extractCLCoordinates()
        
        guard !coordinates.isEmpty else {
            logger.warning("No coordinates found in GeoJSON features to fit camera", handlerType: "MapboxMapView")
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
                logger.warning("Failed to calculate camera for GeoJSON coordinates using SDK method", handlerType: "MapboxMapView")
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
                logger.warning("Camera proxy not available for fitting", handlerType: "MapboxMapView")
                return
            }
            
            // Use flyTo with a short duration for smooth transition
            camera.fly(to: cameraOptions, duration: 0.5)
            
            logger.debug("Camera fitted to \(coordinates.count) GeoJSON feature coordinates with south offset applied")
        }
    }
    
    /// Handles long press selection on the map
    /// Converts screen coordinates to geographic coordinates and creates a CLLocation
    private func handleLongPressSelection(at point: CGPoint, proxy: MapboxMaps.MapProxy) {
        guard let mapboxMap = proxy.map else {
            logger.warning("MapboxMap not available for coordinate conversion", handlerType: "MapboxMapView")
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
        
        logger.debug("Manual location selected: \(coordinate.latitude), \(coordinate.longitude)")

        Task { @MainActor in
            mapFeaturesManager.flyToLocation = FlyToLocation(location: location, name: nil)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds delay
            updateMapCamera(proxy: proxy, location: location, isDeviceLocation: false)
        }
    }
}

// MARK: - Location Manager Delegate
class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    private let onLocationUpdate: (CLLocation) -> Void
    private let logger: Logger
    
    init(
        onLocationUpdate: @escaping (CLLocation) -> Void,
        logger: Logger = AppLifecycleManager.sharedLogger
    ) {
        self.onLocationUpdate = onLocationUpdate
        self.logger = logger
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocationUpdate(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location manager failed", handlerType: "LocationManagerDelegate", error: error)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        logger.debug("Location authorization changed to: \(status.rawValue)")
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            logger.debug("Location permission granted - starting location updates")
            manager.startUpdatingLocation()
        case .denied:
            logger.error("Location permission denied by user", handlerType: "LocationManagerDelegate", error: nil)
        case .restricted:
            logger.error("Location permission restricted by system", handlerType: "LocationManagerDelegate", error: nil)
        case .notDetermined:
            logger.debug("Location permission not determined yet")
        @unknown default:
            logger.warning("Unknown location permission status: \(status.rawValue)", handlerType: "LocationManagerDelegate")
        }
    }
}
