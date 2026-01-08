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
                "evt_type": .string("location_updated"),
                "evt_data": .dictionary(newLocationDict)
            ]
            
            // Send to /v1/orchestor endpoint
            #if DEBUG
            print("📤 Sending location update event to /v1/orchestor")
            #endif
            
            let _ = try await uhpGateway.request(
                endpoint: "/v1/orchestor",
                method: "POST",
                jsonDict: eventDict
            )
            
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

