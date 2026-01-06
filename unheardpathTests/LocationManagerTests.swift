import Testing
import Foundation
import CoreLocation
@testable import unheardpath

struct LocationManagerTests {
    
    /// Test constructing NewLocation structure from a CLLocation
    /// Uses a known coordinate (San Francisco, CA) for testing
    @Test @MainActor func testConstructNewLocation() async throws {
        // Create a test location (San Francisco, CA)
        let testCoordinate = CLLocationCoordinate2D(
            latitude: 37.7749,
            longitude: -122.4194
        )
        
        let testLocation = CLLocation(
            coordinate: testCoordinate,
            altitude: 50.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        // Create LocationManager instance
        let locationManager = LocationManager()
        
        // Construct NewLocation structure
        let newLocationDict = try await locationManager.constructNewLocation(from: testLocation)
        
        // Verify coordinate structure exists
        guard let coordinateValue = newLocationDict["coordinate"],
              case .dictionary(let coordinateDict) = coordinateValue else {
            Issue.record("Coordinate dictionary not found or invalid")
            return
        }
        
        // Verify coordinate values
        guard case .double(let lat) = coordinateDict["lat"],
              case .double(let lng) = coordinateDict["lng"] else {
            Issue.record("Latitude or longitude not found in coordinate dictionary")
            return
        }
        
        #expect(lat == 37.7749, "Latitude should match test coordinate")
        #expect(lng == -122.4194, "Longitude should match test coordinate")
        
        // Verify altitude is included when verticalAccuracy > 0
        if case .double(let alt) = coordinateDict["alt"] {
            #expect(alt == 50.0, "Altitude should match test location")
        }
        
        // Verify timezone is present (either from placemark or device fallback)
        guard case .string(let timezone) = newLocationDict["timezone"] else {
            Issue.record("Timezone not found in NewLocation dictionary")
            return
        }
        
        #expect(!timezone.isEmpty, "Timezone should not be empty")
        
        // Verify optional fields may be present (depending on geocoding results)
        // These are optional, so we just check they're valid types if present
        if let countryCode = newLocationDict["country_code"] {
            if case .string(let code) = countryCode {
                #expect(!code.isEmpty, "Country code should not be empty if present")
            }
        }
        
        if let countryName = newLocationDict["country_name"] {
            if case .string(let name) = countryName {
                #expect(!name.isEmpty, "Country name should not be empty if present")
            }
        }
        
        if let placeName = newLocationDict["place_name"] {
            if case .string(let name) = placeName {
                #expect(!name.isEmpty, "Place name should not be empty if present")
            }
        }
        
        if let subdivisions = newLocationDict["subdivisions"] {
            if case .string(let subs) = subdivisions {
                #expect(!subs.isEmpty, "Subdivisions should not be empty if present")
            }
        }
        
        // Print the result for debugging
        print("✅ Constructed NewLocation structure:")
        print("   Coordinate: (\(lat), \(lng))")
        print("   Timezone: \(timezone)")
        if case .string(let countryCode) = newLocationDict["country_code"] {
            print("   Country Code: \(countryCode)")
        }
        if case .string(let countryName) = newLocationDict["country_name"] {
            print("   Country Name: \(countryName)")
        }
    }
    
    /// Test constructing NewLocation with a location that has no altitude
    @Test @MainActor func testConstructNewLocationWithoutAltitude() async throws {
        // Create a test location without valid altitude
        let testCoordinate = CLLocationCoordinate2D(
            latitude: 40.7128,
            longitude: -74.0060
        )
        
        let testLocation = CLLocation(
            coordinate: testCoordinate,
            altitude: -1.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: -1.0,  // Invalid vertical accuracy
            timestamp: Date()
        )
        
        let locationManager = LocationManager()
        let newLocationDict = try await locationManager.constructNewLocation(from: testLocation)
        
        // Verify coordinate structure
        guard let coordinateValue = newLocationDict["coordinate"],
              case .dictionary(let coordinateDict) = coordinateValue else {
            Issue.record("Coordinate dictionary not found")
            return
        }
        
        // Verify altitude is NOT included when verticalAccuracy <= 0
        #expect(coordinateDict["alt"] == nil, "Altitude should not be included when verticalAccuracy is invalid")
        
        // Verify lat/lng are present
        guard case .double(let lat) = coordinateDict["lat"],
              case .double(let lng) = coordinateDict["lng"] else {
            Issue.record("Latitude or longitude not found")
            return
        }
        
        #expect(lat == 40.7128, "Latitude should match")
        #expect(lng == -74.0060, "Longitude should match")
    }
    
    /// Test that timezone fallback works when placemark doesn't provide timezone
    @Test @MainActor func testConstructNewLocationTimezoneFallback() async throws {
        let testCoordinate = CLLocationCoordinate2D(
            latitude: 0.0,
            longitude: 0.0
        )
        
        let testLocation = CLLocation(
            coordinate: testCoordinate,
            altitude: 0.0,
            horizontalAccuracy: 100.0,
            verticalAccuracy: -1.0,
            timestamp: Date()
        )
        
        let locationManager = LocationManager()
        let newLocationDict = try await locationManager.constructNewLocation(from: testLocation)
        
        // Verify timezone is always present (either from placemark or device fallback)
        guard case .string(let timezone) = newLocationDict["timezone"] else {
            Issue.record("Timezone should always be present")
            return
        }
        
        #expect(!timezone.isEmpty, "Timezone should not be empty")
        
        // Verify it's a valid timezone identifier format (contains "/" for IANA timezones)
        // or is "UTC" or similar
        let isValidFormat = timezone.contains("/") || timezone == "UTC" || timezone == "GMT"
        #expect(isValidFormat, "Timezone should be in valid format")
    }
}
