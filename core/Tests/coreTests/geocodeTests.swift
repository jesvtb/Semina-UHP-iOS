//
//  geocodeTests.swift
//  coreTests
//
//  Tests for geocode construction functions
//

import Testing
import Foundation
import CoreLocation
@preconcurrency import MapKit
@testable import core

struct GeocodeTests {
    
    /// Test constructing device location with placemark
    @Test func testConstructDeviceLocationWithPlacemark() {
        // Create a test location
        let testLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 50.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        // Create a mock placemark using MKPlacemark (subclass of CLPlacemark)
        // Note: In real tests, you might want to use a test double or mock
        let placemark = MKPlacemark(
            coordinate: testLocation.coordinate,
            addressDictionary: [
                "Name": "Test Place",
                "Street": "123 Main St",
                "City": "San Francisco",
                "State": "CA",
                "Country": "United States",
                "CountryCode": "US"
            ]
        )
        
        // Construct device location
        let result = Geocode.constructDeviceLocation(location: testLocation, placemark: placemark)
        
        // Verify required fields
        guard case .double(let lat) = result["latitude"],
              case .double(let lng) = result["longitude"] else {
            Issue.record("Latitude or longitude not found")
            return
        }
        
        #expect(lat == 37.7749, "Latitude should match")
        #expect(lng == -122.4194, "Longitude should match")
        
        // Verify location_type
        guard case .string(let locationType) = result["location_type"] else {
            Issue.record("location_type not found")
            return
        }
        #expect(locationType == "device", "location_type should be 'device'")
        
        // Verify action_utc and action_timezone are present
        guard case .string(let actionUTC) = result["action_utc"],
              case .string(let actionTimezone) = result["action_timezone"] else {
            Issue.record("action_utc or action_timezone not found")
            return
        }
        #expect(!actionUTC.isEmpty, "action_utc should not be empty")
        #expect(!actionTimezone.isEmpty, "action_timezone should not be empty")
        
        // Verify required backend fields are present (even if empty)
        #expect(result["place"] != nil, "place field should be present")
        #expect(result["country_code"] != nil, "country_code field should be present")
        #expect(result["location"] != nil, "location field should be present")
    }
    
    /// Test constructing device location without placemark
    @Test func testConstructDeviceLocationWithoutPlacemark() {
        let testLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0.0,
            horizontalAccuracy: 20.0,
            verticalAccuracy: -1.0,
            timestamp: Date()
        )
        
        let result = Geocode.constructDeviceLocation(location: testLocation, placemark: nil)
        
        // Verify coordinates
        guard case .double(let lat) = result["latitude"],
              case .double(let lng) = result["longitude"] else {
            Issue.record("Coordinates not found")
            return
        }
        #expect(lat == 40.7128)
        #expect(lng == -74.0060)
        
        // Verify required fields are present (should be empty strings)
        guard case .string(let place) = result["place"],
              case .string(let countryCode) = result["country_code"],
              case .string(let location) = result["location"] else {
            Issue.record("Required fields not found")
            return
        }
        // They should be empty strings when placemark is nil
        #expect(place == "", "place should be empty string when placemark is nil")
        #expect(countryCode == "", "country_code should be empty string when placemark is nil")
        #expect(location == "", "location should be empty string when placemark is nil")
    }
    
    /// Test constructing lookup location
    @Test func testConstructLookupLocation() {
        let testLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0.0,
            horizontalAccuracy: 15.0,
            verticalAccuracy: -1.0,
            timestamp: Date()
        )
        
        let placemark = MKPlacemark(
            coordinate: testLocation.coordinate,
            addressDictionary: [
                "Name": "Golden Gate Park",
                "Street": "Golden Gate Park",
                "City": "San Francisco",
                "State": "CA"
            ]
        )
        
        let result = Geocode.constructLookupLocation(
            location: testLocation,
            placemark: placemark,
            mapItemName: "Golden Gate Park"
        )
        
        // Verify coordinates and location_type
        guard case .double(let lat) = result["latitude"],
              case .double(let lng) = result["longitude"],
              case .string(let locationType) = result["location_type"] else {
            Issue.record("Required fields not found")
            return
        }
        
        #expect(lat == 37.7749)
        #expect(lng == -122.4194)
        #expect(locationType == "lookup", "location_type should be 'lookup'")
        
        // Verify place name from mapItemName
        guard case .string(let place) = result["place"] else {
            Issue.record("place not found")
            return
        }
        #expect(place == "Golden Gate Park", "place should use mapItemName")
        
        // Verify action_utc and action_timezone
        #expect(result["action_utc"] != nil, "action_utc should be present")
        #expect(result["action_timezone"] != nil, "action_timezone should be present")
    }
    
    /// Test building NewLocation dict
    @Test func testBuildNewLocationDict() {
        let testLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 50.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        let placemark = MKPlacemark(
            coordinate: testLocation.coordinate,
            addressDictionary: [
                "Name": "Test Location",
                "City": "San Francisco",
                "State": "CA",
                "Country": "United States",
                "CountryCode": "US"
            ]
        )
        
        let result = Geocode.buildNewLocationDict(location: testLocation, placemark: placemark)
        
        // Verify coordinate structure
        guard let coordinateValue = result["coordinate"],
              case .dictionary(let coordinateDict) = coordinateValue else {
            Issue.record("Coordinate dictionary not found")
            return
        }
        
        guard case .double(let lat) = coordinateDict["lat"],
              case .double(let lng) = coordinateDict["lng"] else {
            Issue.record("Latitude or longitude not found in coordinate")
            return
        }
        
        #expect(lat == 37.7749)
        #expect(lng == -122.4194)
        
        // Verify altitude is included when verticalAccuracy > 0
        guard case .double(let alt) = coordinateDict["alt"] else {
            Issue.record("Altitude should be included when verticalAccuracy > 0")
            return
        }
        #expect(alt == 50.0)
        
        // Verify timezone is present
        guard case .string(let timezone) = result["timezone"] else {
            Issue.record("Timezone not found")
            return
        }
        #expect(!timezone.isEmpty, "Timezone should not be empty")
        
        // Verify timestamp is present
        guard case .double(let timestamp) = result["timestamp"] else {
            Issue.record("Timestamp not found")
            return
        }
        #expect(timestamp > 0, "Timestamp should be positive")
    }
    
    /// Test building NewLocation dict without placemark (timezone fallback)
    @Test func testBuildNewLocationDictWithoutPlacemark() {
        let testLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: -1.0,
            horizontalAccuracy: 20.0,
            verticalAccuracy: -1.0,  // Invalid, so altitude should not be included
            timestamp: Date()
        )
        
        let result = Geocode.buildNewLocationDict(location: testLocation, placemark: nil)
        
        // Verify coordinate structure
        guard let coordinateValue = result["coordinate"],
              case .dictionary(let coordinateDict) = coordinateValue else {
            Issue.record("Coordinate dictionary not found")
            return
        }
        
        // Verify altitude is NOT included when verticalAccuracy <= 0
        #expect(coordinateDict["alt"] == nil, "Altitude should not be included when verticalAccuracy is invalid")
        
        // Verify timezone fallback (should use device timezone)
        guard case .string(let timezone) = result["timezone"] else {
            Issue.record("Timezone should always be present (fallback to device)")
            return
        }
        #expect(!timezone.isEmpty, "Timezone should not be empty")
    }
}
