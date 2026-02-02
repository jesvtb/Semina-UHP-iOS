import SwiftUI
@preconcurrency import MapKit
import core
// MARK: - Standalone refreshPOIList Function
@MainActor
func refreshPOIList(
    from location: CLLocationCoordinate2D?,
    gateway: UHPGateway,
    userManager: UserManager
) async throws -> UHPResponse {
    var jsonDict: [String: JSONValue] = [:]
    if let user = userManager.currentUser {
        jsonDict["device_lang"] = .string(user.device_lang)
    } else {
        jsonDict["device_lang"] = .string("en")
    }
    if let location = location {
        jsonDict["lat"] = .double(location.latitude)
        jsonDict["lon"] = .double(location.longitude)
    }
    jsonDict["range_type"] = .string("city")
    
    let response = try await gateway.request(
        endpoint: "/v1/pois",
        method: "POST",
        jsonDict: jsonDict
    )
    // response.printContent()
    return response
}

// MARK: - Location Management
extension TestMainView {
    /// Logger for error and debug logging
    private var logger: Logger {
        AppLifecycleManager.sharedLogger
    }
    
    /// Refreshes POI list when one-time location request completes
    /// Only called once when requestOneTimeLocation() returns a location with 100m or better accuracy
    @MainActor
    func refreshPOIListOnOneTimeLocation(location: CLLocation) async {
        #if DEBUG
        print("📍 One-time location request completed with 100m accuracy - calling refreshPOIList")
        print("   Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("   Accuracy: ±\(Int(location.horizontalAccuracy))m")
        #endif
        
        do {
            let response = try await refreshPOIList(
                from: location.coordinate,
                gateway: uhpGateway,
                userManager: userManager
            )
            
            guard response.event == "map", let geojsonDict = response.content else {
                #if DEBUG
                print("⚠️ Response event is not 'map' or content is nil")
                print("   Event: \(response.event ?? "nil")")
                print("   Content: \(response.content != nil ? "exists" : "nil")")
                #endif
                return
            }
            
            // response.content is the features array directly
            // Extract features from the JSONValue array using shared helper
            guard case .array(let featuresArray) = geojsonDict else {
                #if DEBUG
                print("⚠️ Response content is not a features array")
                #endif
                return
            }
            
            // Use shared helper to extract features (same logic as SSEEventProcessor)
            let features = extractFeaturesFromArray(featuresArray)
            
            guard !features.isEmpty else {
                #if DEBUG
                print("⚠️ No valid features extracted from response")
                #endif
                return
            }
            
            mapFeaturesManager.apply(features: features)
            
            #if DEBUG
            print("✅ refreshPOIList completed - updated mapFeaturesManager with \(features.count) features")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to refresh POI list on GPS update: \(error.localizedDescription)")
            if let geoJSONError = error as? GeoJSON.GeoJSONError {
                print("   Error type: GeoJSONError")
                print("   Error details: \(geoJSONError)")
            }
            print("   Full error: \(error)")
            #endif
        }
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
            
            // Add event to EventManager (handles backend sending)
            // Note: EventManager sends to backend but doesn't process SSE stream
            // If SSE processing is needed, it should be handled separately
            // try await eventManager.addEvent(event)
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
    /// Updates location to UHP backend by geocoding the coordinate and sending event to /v1/orchestor
    /// - Parameter location: The CLLocation to geocode and send
}

// MARK: - Helper Functions

/// Extracts GeoJSON features from a JSONValue array
/// Shared helper to avoid duplicate parsing logic
/// - Parameter featuresArray: Array of JSONValue items (should be dictionaries)
/// - Returns: Array of feature dictionaries, or empty array if parsing fails
private func extractFeaturesFromArray(_ featuresArray: [JSONValue]) -> [[String: JSONValue]] {
    return featuresArray.compactMap { featureValue -> [String: JSONValue]? in
        guard case .dictionary(let featureDict) = featureValue else {
            return nil
        }
        return featureDict
    }
}


