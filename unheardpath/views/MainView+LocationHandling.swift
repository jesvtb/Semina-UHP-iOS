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
        logger.debug("updateLocationToUHP called for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        do {
            let locationDict = try await geocoder.geocodeReverse(location: location)
            
            contentManager.setContent(
                type: .locationDetail,
                data: .locationDetail(dict: locationDict)
            )
            
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
            let processor = SSEEventProcessor(handler: router)
            try await processor.processStream(stream)
            
            logger.debug("Successfully added location_detected event to EventManager")
        } catch {
            logger.error("Failed to update location to UHP", handlerType: "updateLocationToUHP", error: error)
        }
    }

    /// Sends the selected lookup (fly-to) location to the backend as a location_searched event.
    /// Called when mapFeaturesManager.flyToLocation is set (autocomplete selection or map long-press).
    @MainActor
    func updateLookupLocationToUHP(flyTo: FlyToLocation, router: SSEEventRouter) async {
        logger.debug("updateLookupLocationToUHP called for location: \(flyTo.location.coordinate.latitude), \(flyTo.location.coordinate.longitude)")

        do {
            let locationDict = try await geocoder.geocodeReverse(location: flyTo.location)

            if !eventManager.shouldSendLocation(locationDict, type: .search) {
                logger.debug("Skipping location_searched send (same coordinate as latest search)")
                return
            }

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
            let processor = SSEEventProcessor(handler: router)
            try await processor.processStream(stream)

            logger.debug("Successfully added location_searched event to EventManager")
        } catch {
            logger.error("Failed to update lookup location to UHP", handlerType: "updateLookupLocationToUHP", error: error)
        }
    }
}

