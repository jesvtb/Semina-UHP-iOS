import SwiftUI
@preconcurrency import MapKit

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
            // Extract features from the JSONValue array
            guard case .array(let featuresArray) = geojsonDict else {
                #if DEBUG
                print("⚠️ Response content is not a features array")
                #endif
                return
            }
            
            let features = featuresArray.compactMap { featureValue -> [String: JSONValue]? in
                guard case .dictionary(let featureDict) = featureValue else {
                    return nil
                }
                return featureDict
            }
            
            guard !features.isEmpty else {
                #if DEBUG
                print("⚠️ No valid features extracted from response")
                #endif
                return
            }
            
            poisGeoJSON.setFeatures(features)
            geoJSONUpdateTrigger = UUID()  // Trigger map update
            
            #if DEBUG
            print("✅ refreshPOIList completed - updated poisGeoJSON with \(features.count) features")
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

    /// Routes SSE events from orchestrator stream to appropriate handlers
    func handleOrchestratorStreamEvent(event: SSEEvent, data: inout String) async {
        let eventType = (event.event ?? "").lowercased()

        switch eventType {
        case "map":
            await handleMapEvent(event: event)
        default:
            #if DEBUG
            print("⚠️ Unknown or unsupported event type: \(event.event ?? "nil")")
            #endif
        }
    }

    @MainActor
    func updateLocationToUHP(location: CLLocation) async {
        #if DEBUG
        print("📍 updateLocationToUHP called for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        #endif
        
        do {
            // Use LocationManager helper to construct NewLocation structure
            let newLocationDict = try await locationManager.constructNewLocation(from: location)
            
            // Create event structure
            let now = Date()
            let utcFormatter = ISO8601DateFormatter()
            utcFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            let eventDict: [String: JSONValue] = [
                "evt_utc": .string(utcFormatter.string(from: now)),
                "evt_timezone": .string(TimeZone.current.identifier),
                "evt_type": .string("location_detected"),
                "evt_data": .dictionary(newLocationDict)
            ]
            
            // Send to /v1/orchestor endpoint
            #if DEBUG
            print("📤 Sending location update event to /v1/orchestor")
            #endif
            
            // let _ = try await uhpGateway.request(
            //     endpoint: "/v1/orchestor",
            //     method: "POST",
            //     jsonDict: eventDict
            // )
            let stream = try await uhpGateway.stream(
                endpoint: "/v1/orchestor",
                jsonDict: eventDict
            )

            var data = ""

            for try await event in stream {
                await handleOrchestratorStreamEvent(event: event, data: &data)
            }
            
            #if DEBUG
            print("✅ Successfully sent location update to /v1/orchestor")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to update location to UHP: \(error.localizedDescription)")
            print("   Full error: \(error)")
            #endif
        }
    }

    /// Handles `map` SSE events by processing GeoJSON features array
    /// Similar to refreshPOIListOnOneTimeLocation, extracts features and updates poisGeoJSON
    @MainActor
    private func handleMapEvent(event: SSEEvent) async {
        #if DEBUG
        print("🗺️ Processing map event from SSE stream")
        print("   Data length: \(event.data.count)")
        print("   Data preview (first 200 chars): \(String(event.data.prefix(200)))")
        #endif
        
        // Trim whitespace and newlines from the data string
        let trimmedData = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse the event data as JSON
        guard !trimmedData.isEmpty,
              let jsonData = trimmedData.data(using: .utf8) else {
            #if DEBUG
            print("⚠️ Failed to convert data string to Data")
            #endif
            return
        }
        
        // Try to parse as JSON
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
        } catch {
            #if DEBUG
            print("⚠️ Failed to parse map event data as JSON: \(error.localizedDescription)")
            print("   Data preview: \(String(trimmedData.prefix(500)))")
            #endif
            return
        }
        
        // Convert to JSONValue
        guard let geojsonValue = JSONValue(from: jsonObject) else {
            #if DEBUG
            print("⚠️ Failed to convert JSON object to JSONValue")
            #endif
            return
        }
        
        // Extract features array from the JSONValue
        // The data should be a features array directly (same as refreshPOIListOnOneTimeLocation)
        guard case .array(let featuresArray) = geojsonValue else {
            #if DEBUG
            print("⚠️ Map event data is not a features array")
            #endif
            return
        }
        
        // Extract features from the JSONValue array
        let features = featuresArray.compactMap { featureValue -> [String: JSONValue]? in
            guard case .dictionary(let featureDict) = featureValue else {
                return nil
            }
            return featureDict
        }
        
        guard !features.isEmpty else {
            #if DEBUG
            print("⚠️ No valid features extracted from map event")
            #endif
            return
        }
        
        // Update poisGeoJSON with the new features
        poisGeoJSON.setFeatures(features)
        geoJSONUpdateTrigger = UUID()  // Trigger map and content updates
        
        #if DEBUG
        print("✅ Map event processed - updated poisGeoJSON with \(features.count) features")
        #endif
    }


    /// Loads location data when geofence exit is detected
    /// This is the single source of truth for when to fetch data from backend
    // @MainActor
    // private func loadLocationFromGeofenceExit() async {
    //     // Prevent concurrent API calls
    //     guard !isLoadingLocation else {
    //         #if DEBUG
    //         print("⏸️ API call already in progress, skipping duplicate request")
    //         #endif
    //         return
    //     }
        
    //     // Only proceed if location is actually available
    //     guard locationManager.latitude != nil,
    //           locationManager.longitude != nil else {
    //         #if DEBUG
    //         print("⚠️ Location not available yet, skipping API call")
    //         #endif
    //         return
    //     }
        
    //     // Reverse geocode user location and get JSON dict
    //     #if DEBUG
    //     print("📍 Geofence exit detected - reverse geocoding location for data refresh")
    //     #endif
        
    //     // reverseGeocodeUserLocation now returns [String: JSONValue] directly
    //     let jsonDict = await withCheckedContinuation { (continuation: CheckedContinuation<[String: JSONValue]?, Never>) in
    //         locationManager.reverseGeocodeUserLocation { dict, error in
    //             if let error = error {
    //                 #if DEBUG
    //                 print("⚠️ Reverse geocoding error: \(error.localizedDescription), using location only")
    //                 #endif
    //                 // Even if geocoding fails, dict should still have location data
    //                 continuation.resume(returning: dict)
    //             } else {
    //                 continuation.resume(returning: dict)
    //             }
    //         }
    //     }
        
    //     guard let jsonDict = jsonDict else {
    //         #if DEBUG
    //         print("❌ Failed to get location dict from reverse geocoding")
    //         #endif
    //         return
    //     }
        
    //     // Load location data (will check cache, then API if needed)
    //     await loadLocation(jsonDict: jsonDict)
    // }
    
    /// Updates location to UHP backend by geocoding the coordinate and sending event to /v1/orchestor
    /// - Parameter location: The CLLocation to geocode and send
    

}

