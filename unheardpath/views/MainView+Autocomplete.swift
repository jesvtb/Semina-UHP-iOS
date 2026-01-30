import SwiftUI
@preconcurrency import MapKit
import core

// MARK: - Autocomplete Management
extension TestMainView {
    /// Logger for error and debug logging
    private var logger: Logger {
        AppLifecycleManager.sharedLogger
    }
    
    /// Updates autocomplete query
    func updateAutocomplete(query: String) {
        addressSearchManager.updateQuery(query)
    }
    
    /// Geocodes a selected autocomplete result and flies to that location on the map
    /// Handles both Geoapify (direct coordinate) and MapKit (requires geocoding) sources
    @MainActor
    func geocodeAndFlyToLocation(result: AddressSearchResult) async {
        switch result.source {
        case .geoapify:
            // Geoapify: Use coordinate directly (no geocoding needed)
            guard let coordinate = result.coordinate else {
                logger.warning("No coordinate found for Geoapify result", handlerType: "geocodeAndFlyToLocation")
                return
            }
            
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
            // Reverse geocode to get placemark for lookupLocationDetails
            // Use LocationManager's geocoder for consistent state management
            do {
                let placemarks = try await locationManager.reverseGeocodeLocation(location)
                
                if let placemark = placemarks.first {
                    // Construct lookup place dictionary
                    let lookupDict = Geocode.constructLookupLocation(
                        location: location,
                        placemark: placemark,
                        mapItemName: result.title
                    )
                    
                    // Create location_searched event and add to EventManager
                    // Use NewLocation structure for backend compatibility
                    do {
                        let placemarksForNewLocation = try await locationManager.reverseGeocodeLocation(location)
                        let newLocationDict = Geocode.buildNewLocationDict(location: location, placemark: placemarksForNewLocation.first)
                        let event = UserEventBuilder.build(
                            evtType: "location_searched",
                            evtData: newLocationDict,
                            sessionId: eventManager.sessionId
                        )
                        let returnedStream = try await eventManager.addEvent(event)
                        if let stream = returnedStream {
                            let processor = SSEEventProcessor(handler: sseEventRouter)
                            try await processor.processStream(stream)
                        }
                    } catch { }
                    
                    // Update target location to trigger map camera update and show marker
                    let placeName = lookupDict["place"]?.stringValue ?? result.title
                    targetLocation = TargetLocation(location: location, name: placeName)
                    
                    // Clear autocomplete results and input location after flying to the location
                    addressSearchManager.clearResults()
                    liveUpdateViewModel.inputLocation = ""
                    isTextFieldFocused = false
                } else {
                    // No placemarks returned - use fallback
                    await handleGeoapifyLocationWithoutPlacemark(location: location, title: result.title)
                }
            } catch {
                // Fallback: Use coordinate without placemark
                await handleGeoapifyLocationWithoutPlacemark(location: location, title: result.title)
            }
            
        case .mapkit:
            // MapKit: Use existing geocoding path with MKLocalSearch.Request
            guard let completion = result.mapkitCompletion else {
                return
            }
            
            let request = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: request)
            
            do {
                let response = try await search.start() 
                
                guard let mapItem = response.mapItems.first,
                      let location = mapItem.placemark.location else {
                    return
                }
                
                // Construct lookup place dictionary
                let placemark = mapItem.placemark
                let lookupDict = Geocode.constructLookupLocation(
                    location: location,
                    placemark: placemark,
                    mapItemName: mapItem.name
                )
                
                // Create location_searched event and add to EventManager
                // Use NewLocation structure for backend compatibility
                do {
                    let placemarksForNewLocation = try await locationManager.reverseGeocodeLocation(location)
                    let newLocationDict = Geocode.buildNewLocationDict(location: location, placemark: placemarksForNewLocation.first)
                    let event = UserEventBuilder.build(
                        evtType: "location_searched",
                        evtData: newLocationDict,
                        sessionId: eventManager.sessionId
                    )
                    let returnedStream = try await eventManager.addEvent(event)
                    if let stream = returnedStream {
                        let processor = SSEEventProcessor(handler: sseEventRouter)
                        try await processor.processStream(stream)
                    }
                } catch { }
                
                // Update target location to trigger map camera update and show marker
                let placeName = lookupDict["place"]?.stringValue
                targetLocation = TargetLocation(location: location, name: placeName)
                
                // Clear autocomplete results and input location after flying to the location
                addressSearchManager.clearResults()
                liveUpdateViewModel.inputLocation = ""
                isTextFieldFocused = false
            } catch { }
        }
    }
    
    /// Handles Geoapify location when reverse geocoding fails or returns no placemarks
    /// Creates a minimal MKPlacemark from the coordinate to satisfy constructLookupLocation requirements
    /// - Parameters:
    ///   - location: The CLLocation with coordinates
    ///   - title: The title/name of the location
    @MainActor
    func handleGeoapifyLocationWithoutPlacemark(location: CLLocation, title: String) async {
        // Create a minimal MKPlacemark from the coordinate
        // MKPlacemark is a subclass of CLPlacemark, so it can be used where CLPlacemark is expected
        let minimalPlacemark = MKPlacemark(coordinate: location.coordinate)
        
        // Construct lookup place dictionary (for display only)
        let lookupDict = Geocode.constructLookupLocation(
            location: location,
            placemark: minimalPlacemark,
            mapItemName: title
        )
        
        // Create location_searched event and add to EventManager
        // Use NewLocation structure for backend compatibility
        do {
            let placemarksForNewLocation = try await locationManager.reverseGeocodeLocation(location)
            let newLocationDict = Geocode.buildNewLocationDict(location: location, placemark: placemarksForNewLocation.first)
            let event = UserEventBuilder.build(
                evtType: "location_searched",
                evtData: newLocationDict,
                sessionId: eventManager.sessionId
            )
            let returnedStream = try await eventManager.addEvent(event)
            if let stream = returnedStream {
                let processor = SSEEventProcessor(handler: sseEventRouter)
                try await processor.processStream(stream)
            }
        } catch { }
        
        // Update target location to trigger map camera update and show marker
        let placeName = lookupDict["place"]?.stringValue ?? title
        targetLocation = TargetLocation(location: location, name: placeName)
        
        // Clear autocomplete results and input location after flying to the location
        addressSearchManager.clearResults()
        liveUpdateViewModel.inputLocation = ""
        isTextFieldFocused = false
    }
}

