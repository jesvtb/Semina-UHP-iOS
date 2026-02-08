import SwiftUI
@preconcurrency import MapKit
import core

// MARK: - Location Management
extension MainView {
    /// Logger for error and debug logging
    private var logger: Logger {
        AppLifecycleManager.sharedLogger
    }

    @MainActor
    func updateLocationToUHP(location: CLLocation, router: SSEEventRouter) async {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        logger.debug("updateLocationToUHP called for location: \(lat), \(lon)")

        let locationDictForCheck: [String: JSONValue] = [
            "coordinate": .dictionary(["lat": .double(lat), "lng": .double(lon)])
        ]
        let decision = eventManager.locationSendDecision(locationDictForCheck, type: .device)

        switch decision {
        case .skip:
            logger.debug("Skipping device location update (within distance and time threshold)")
            return
        case .sendSameLocationNewTime:
            guard let lastLocationDict = eventManager.latestDeviceLocation else { return }
            do {
                let event = UserEventBuilder.build(
                    evtType: "location_detected",
                    evtData: lastLocationDict,
                    sessionId: eventManager.sessionId
                )
                let returnedStream = try await eventManager.addEvent(event)
                guard let stream = returnedStream else {
                    #if DEBUG
                    print("⚠️ Failed to add location_detected event to EventManager (same location, new time)")
                    #endif
                    return
                }
                let processor = SSEEventProcessor(router: router)
                try await processor.processStream(stream)
                logger.debug("Added location_detected (same location, new time) to EventManager")
            } catch {
                logger.error("Failed to add location_detected (same location, new time)", handlerType: "updateLocationToUHP", error: error)
            }
            return
        case .sendNewLocation:
            break
        }

        do {
            var locationDetailData = try await geocoder.geocodeReverse(location: location)
            locationDetailData.dataSource = .device
            let locationDict = locationDetailData.toLocationDict()

            // Prune stale catalogue items before updating location context.
            // Must be called before setLocationData so the old location is still available for comparison.
            catalogueManager.pruneStaleItems(forNewLocation: locationDetailData)
            catalogueManager.setLocationData(locationDetailData)

            let event = UserEventBuilder.build(
                evtType: "location_detected",
                evtData: locationDict,
                sessionId: eventManager.sessionId
            )

            let returnedStream = try await eventManager.addEvent(event)
            guard let stream = returnedStream else {
                #if DEBUG
                print("⚠️ Failed to add location_detected event to EventManager")
                #endif
                return
            }
            let processor = SSEEventProcessor(router: router)
            try await processor.processStream(stream)
            
            // Persist catalogue state after SSE stream delivers new content
            catalogueManager.persistCurrentState(for: locationDetailData)

            logger.debug("Successfully added location_detected event to EventManager")
        } catch {
            logger.error("Failed to update location to UHP", handlerType: "updateLocationToUHP", error: error)
        }
    }

    /// Sends the selected lookup (fly-to) location to the backend as a location_searched event.
    /// Called when mapFeaturesManager.flyToLocation is set (autocomplete selection or map long-press).
    /// For autocomplete selections, uses pre-built LocationDetailData directly.
    /// For long-press (minimal LocationDetailData), falls back to reverse geocode.
    @MainActor
    func updateLookupLocationToUHP(flyTo: FlyToLocation, router: SSEEventRouter) async {
        let locationDetail = flyTo.locationDetail
        let lat = locationDetail.location.coordinate.latitude
        let lon = locationDetail.location.coordinate.longitude
        logger.debug("updateLookupLocationToUHP called for location: \(lat), \(lon)")

        let locationDictForCheck: [String: JSONValue] = [
            "coordinate": .dictionary(["lat": .double(lat), "lng": .double(lon)])
        ]
        let decision = eventManager.locationSendDecision(locationDictForCheck, type: .lookup)

        if case .skip = decision {
            logger.debug("Skipping location_searched send (within distance threshold)")
            return
        }

        do {
            // Use pre-built data for autocomplete; reverse geocode for long-press (minimal data)
            var finalDetail: LocationDetailData
            if locationDetail.placeName == nil && locationDetail.countryCode == nil {
                finalDetail = try await geocoder.geocodeReverse(location: locationDetail.location)
            } else {
                finalDetail = locationDetail
            }
            finalDetail.dataSource = .lookup

            let locationDict = finalDetail.toLocationDict()

            // Prune stale catalogue items before updating location context.
            // Must be called before setLocationData so the old location is still available for comparison.
            catalogueManager.pruneStaleItems(forNewLocation: finalDetail)
            catalogueManager.setLocationData(finalDetail)

            let event = UserEventBuilder.build(
                evtType: "location_searched",
                evtData: locationDict,
                sessionId: eventManager.sessionId
            )

            let returnedStream = try await eventManager.addEvent(event)
            guard let stream = returnedStream else {
                #if DEBUG
                print("⚠️ Failed to add location_searched event to EventManager")
                #endif
                return
            }
            let processor = SSEEventProcessor(router: router)
            try await processor.processStream(stream)
            
            // Persist catalogue state after SSE stream delivers new content
            catalogueManager.persistCurrentState(for: finalDetail)

            logger.debug("Successfully added location_searched event to EventManager")
        } catch {
            logger.error("Failed to update lookup location to UHP", handlerType: "updateLookupLocationToUHP", error: error)
        }
    }
}

