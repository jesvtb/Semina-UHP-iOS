import SwiftUI
@preconcurrency import MapKit

// MARK: - Autocomplete Management
extension TestMainView {
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
                #if DEBUG
                print("⚠️ No coordinate found for Geoapify result")
                #endif
                return
            }
            
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
            #if DEBUG
            print("✅ Using Geoapify coordinate directly: \(coordinate.latitude), \(coordinate.longitude)")
            #endif
            
            // Reverse geocode to get placemark for lookupLocationDetails
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                
                if let placemark = placemarks.first {
                    // Construct lookup place dictionary and update lookupLocationDetails
                    let lookupDict = locationManager.constructLookupLocation(
                        location: location,
                        placemark: placemark,
                        mapItemName: result.title
                    )
                    locationManager.lookupLocationDetails = lookupDict
                    
                    #if DEBUG
                    print("📦 Constructed lookup place dict from reverse geocoding: \(lookupDict)")
                    print("✅ Updated lookupLocationDetails in LocationManager")
                    if let fullAddress = lookupDict["full_address"]?.stringValue {
                        print("   Full address: \(fullAddress)")
                    }
                    #endif
                    
                    // Save lookup location to UserDefaults
                    locationManager.saveLookupLocation(location)
                    
                    // Update target location to trigger map camera update and show marker
                    let placeName = lookupDict["place"]?.stringValue ?? result.title
                    targetLocation = TargetLocation(location: location, name: placeName)
                    
                    // Clear autocomplete results and input location after flying to the location
                    addressSearchManager.clearResults()
                    liveUpdateViewModel.inputLocation = ""
                    isTextFieldFocused = false
                } else {
                    // No placemarks returned - use fallback
                    #if DEBUG
                    print("⚠️ Reverse geocoding returned no placemarks")
                    #endif
                    await handleGeoapifyLocationWithoutPlacemark(location: location, title: result.title)
                }
            } catch {
                #if DEBUG
                print("⚠️ Reverse geocoding failed, using coordinate without placemark: \(error.localizedDescription)")
                #endif
                
                // Fallback: Use coordinate without placemark
                await handleGeoapifyLocationWithoutPlacemark(location: location, title: result.title)
            }
            
        case .mapkit:
            // MapKit: Use existing geocoding path with MKLocalSearch.Request
            guard let completion = result.mapkitCompletion else {
                #if DEBUG
                print("⚠️ No MKLocalSearchCompletion found for MapKit result")
                #endif
                return
            }
            
            #if DEBUG
            print("\n" + String(repeating: "=", count: 80))
            print("🔍 MKLocalSearchCompletion - All Available Properties")
            print(String(repeating: "=", count: 80))
            
            // Print title
            print("📝 title: String")
            print("   Value: \(completion.title)")
            
            // Print titleHighlightRanges
            print("\n✨ titleHighlightRanges: [NSValue]")
            print("   Count: \(completion.titleHighlightRanges.count)")
            for (index, rangeValue) in completion.titleHighlightRanges.enumerated() {
                let range = rangeValue.rangeValue
                let startIndex = completion.title.index(completion.title.startIndex, offsetBy: range.location)
                let endIndex = completion.title.index(startIndex, offsetBy: range.length)
                let highlightedText = String(completion.title[startIndex..<endIndex])
                print("   Range #\(index + 1): location=\(range.location), length=\(range.length)")
                print("   Highlighted text: \"\(highlightedText)\"")
            }
            
            // Print subtitle
            print("\n📄 subtitle: String")
            print("   Value: \(completion.subtitle)")
            
            // Print subtitleHighlightRanges
            print("\n✨ subtitleHighlightRanges: [NSValue]")
            print("   Count: \(completion.subtitleHighlightRanges.count)")
            for (index, rangeValue) in completion.subtitleHighlightRanges.enumerated() {
                let range = rangeValue.rangeValue
                let startIndex = completion.subtitle.index(completion.subtitle.startIndex, offsetBy: range.location)
                let endIndex = completion.subtitle.index(startIndex, offsetBy: range.length)
                let highlightedText = String(completion.subtitle[startIndex..<endIndex])
                print("   Range #\(index + 1): location=\(range.location), length=\(range.length)")
                print("   Highlighted text: \"\(highlightedText)\"")
            }
            
            print(String(repeating: "=", count: 80) + "\n")
            #endif
            
            let request = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: request)
            
            do {
                let response = try await search.start() 
                
                #if DEBUG
                print("\n" + String(repeating: "=", count: 80))
                print("🔍 MKLocalSearch.Response - All Available Properties")
                print(String(repeating: "=", count: 80))
                
                // Print mapItems
                print("📋 mapItems: [MKMapItem]")
                print("   Count: \(response.mapItems.count)")
                for (index, mapItem) in response.mapItems.enumerated() {
                    print("   --- MapItem #\(index + 1) ---")
                    print("   • Name: \(mapItem.name ?? "nil")")
                    print("   • Phone Number: \(mapItem.phoneNumber ?? "nil")")
                    print("   • URL: \(mapItem.url?.absoluteString ?? "nil")")
                    let placemark = mapItem.placemark
                    
                    print("\n   📍 Placemark - Full Address Components:")
                    print("   • Location: \(placemark.location?.coordinate.latitude ?? 0), \(placemark.location?.coordinate.longitude ?? 0)")
                    print("   • Name: \(placemark.name ?? "nil")")
                    
                    // Street address components
                    print("\n   🏠 Street Address:")
                    print("   • Sub Thoroughfare (Street Number): \(placemark.subThoroughfare ?? "nil")")
                    print("   • Thoroughfare (Street Name): \(placemark.thoroughfare ?? "nil")")
                    print("   • Sub Locality: \(placemark.subLocality ?? "nil")")
                    
                    // City/Region components
                    print("\n   🏙️ City/Region:")
                    print("   • Locality (City): \(placemark.locality ?? "nil")")
                    print("   • Sub Administrative Area: \(placemark.subAdministrativeArea ?? "nil")")
                    print("   • Administrative Area (State/Province): \(placemark.administrativeArea ?? "nil")")
                    print("   • Postal Code: \(placemark.postalCode ?? "nil")")
                    
                    // Country components
                    print("\n   🌍 Country:")
                    print("   • Country: \(placemark.country ?? "nil")")
                    print("   • ISO Country Code: \(placemark.isoCountryCode ?? "nil")")
                    
                    // Additional placemark properties
                    print("\n   📋 Additional Properties:")
                    print("   • Areas of Interest: \(placemark.areasOfInterest?.joined(separator: ", ") ?? "nil")")
                    print("   • Inland Water: \(placemark.inlandWater ?? "nil")")
                    print("   • Ocean: \(placemark.ocean ?? "nil")")
                    if let region = placemark.region as? CLCircularRegion {
                        print("   • Region Center: \(region.center.latitude), \(region.center.longitude)")
                        print("   • Region Radius: \(Int(region.radius))m")
                        print("   • Region Identifier: \(region.identifier)")
                    }
                    print("   • Timezone: \(placemark.timeZone?.identifier ?? "nil")")
                    
                    print("\n   🎯 MapItem Properties:")
                    print("   • Point of Interest Category: \(mapItem.pointOfInterestCategory?.rawValue ?? "nil")")
                    print("   • Is Current Location: \(mapItem.isCurrentLocation)")
                }
                
                // Print boundingRegion
                print("\n🌍 boundingRegion: MKCoordinateRegion")
                print("   • Center: \(response.boundingRegion.center.latitude), \(response.boundingRegion.center.longitude)")
                print("   • Span: \(response.boundingRegion.span.latitudeDelta) lat, \(response.boundingRegion.span.longitudeDelta) lon")
                print(String(repeating: "=", count: 80) + "\n")
                #endif
                
                guard let mapItem = response.mapItems.first,
                      let location = mapItem.placemark.location else {
                    #if DEBUG
                    print("⚠️ No location found for selected autocomplete result")
                    #endif
                    return
                }
                
                #if DEBUG
                print("✅ Geocoded '\(completion.title)' to: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                #endif
                
                // Construct lookup place dictionary and update lookupLocationDetails
                let placemark = mapItem.placemark
                let lookupDict = locationManager.constructLookupLocation(
                    location: location,
                    placemark: placemark,
                    mapItemName: mapItem.name
                )
                locationManager.lookupLocationDetails = lookupDict
                
                #if DEBUG
                print("📦 Constructed lookup place dict: \(lookupDict)")
                print("✅ Updated lookupLocationDetails in LocationManager")
                if let fullAddress = lookupDict["full_address"]?.stringValue {
                    print("   Full address: \(fullAddress)")
                }
                #endif
                
                // Save lookup location to UserDefaults
                locationManager.saveLookupLocation(location)
                
                // Update target location to trigger map camera update and show marker
                let placeName = lookupDict["place"]?.stringValue
                targetLocation = TargetLocation(location: location, name: placeName)
                
                // Clear autocomplete results and input location after flying to the location
                addressSearchManager.clearResults()
                liveUpdateViewModel.inputLocation = ""
                isTextFieldFocused = false
            } catch {
                #if DEBUG
                print("❌ Failed to geocode autocomplete result: \(error.localizedDescription)")
                #endif
            }
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
        
        // Construct lookup place dictionary and update lookupLocationDetails
        let lookupDict = locationManager.constructLookupLocation(
            location: location,
            placemark: minimalPlacemark,
            mapItemName: title
        )
        locationManager.lookupLocationDetails = lookupDict
        
        #if DEBUG
        print("📦 Constructed lookup place dict with minimal placemark: \(lookupDict)")
        #endif
        
        // Save lookup location to UserDefaults
        locationManager.saveLookupLocation(location)
        
        // Update target location to trigger map camera update and show marker
        let placeName = lookupDict["place"]?.stringValue ?? title
        targetLocation = TargetLocation(location: location, name: placeName)
        
        // Clear autocomplete results and input location after flying to the location
        addressSearchManager.clearResults()
        liveUpdateViewModel.inputLocation = ""
        isTextFieldFocused = false
    }
}

