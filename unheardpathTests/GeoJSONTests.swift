import Testing
import Foundation
import CoreLocation
@testable import unheardpath

struct GeoJSONTests {
    
    // MARK: - Helper Methods
    
    /// Loads the mock JSON file from the bundle
    /// Uses the same approach as the app code (Bundle.main)
    private func loadMockJSON() throws -> [String: Any] {
        // Try to find the file in the bundle (same approach as MapView.swift)
        // First try with subdirectory
        var url = Bundle.main.url(forResource: "around_me_example", withExtension: "json", subdirectory: "mock")
        
        // If not found, try without subdirectory
        if url == nil {
            url = Bundle.main.url(forResource: "around_me_example", withExtension: "json")
        }
        
        guard let fileURL = url else {
            throw TestError.missingFile
        }
        
        let data = try Data(contentsOf: fileURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError.invalidJSON
        }
        
        return json
    }
    
    
    /// Extracts coordinates from a feature
    private func extractCoordinates(from feature: [String: JSONValue]) -> (lon: CLLocationDegrees, lat: CLLocationDegrees)? {
        guard let geometryValue = feature["geometry"],
              case .dictionary(let geometry) = geometryValue,
              let coordinatesValue = geometry["coordinates"],
              case .array(let coordinates) = coordinatesValue,
              coordinates.count >= 2 else {
            return nil
        }
        
        let lon: CLLocationDegrees?
        let lat: CLLocationDegrees?
        
        if case .double(let value) = coordinates[0] {
            lon = CLLocationDegrees(value)
        } else if case .int(let value) = coordinates[0] {
            lon = CLLocationDegrees(value)
        } else {
            lon = nil
        }
        
        if case .double(let value) = coordinates[1] {
            lat = CLLocationDegrees(value)
        } else if case .int(let value) = coordinates[1] {
            lat = CLLocationDegrees(value)
        } else {
            lat = nil
        }
        
        guard let longitude = lon, let latitude = lat else {
            return nil
        }
        
        return (lon: longitude, lat: latitude)
    }
    
    /// Rounds a number to 4 decimal places (for comparison)
    private func roundTo4Decimals(_ value: CLLocationDegrees) -> CLLocationDegrees {
        return round(value * 10000) / 10000
    }
    
    /// Counts decimal places in a number
    private func decimalPlaces(_ value: CLLocationDegrees) -> Int {
        let string = String(value)
        guard let dotIndex = string.firstIndex(of: ".") else {
            return 0
        }
        let decimalPart = string[string.index(after: dotIndex)...]
        return decimalPart.count
    }
    
    // MARK: - Test setFeatures
    
    @Test func testSetFeaturesRoundsCoordinates() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        // Create GeoJSON and set features
        var geoJSON = GeoJSON()
        geoJSON.setFeatures(features)
        
        // Verify all features have rounded coordinates
        for i in 0..<geoJSON.featureCount {
            guard let feature = geoJSON.getFeature(at: i),
                  let coords = extractCoordinates(from: feature) else {
                continue
            }
            
            // Check that coordinates are rounded to 4 decimal places
            let roundedLon = roundTo4Decimals(coords.lon)
            let roundedLat = roundTo4Decimals(coords.lat)
            
            #expect(coords.lon == roundedLon, "Longitude should be rounded to 4 decimal places")
            #expect(coords.lat == roundedLat, "Latitude should be rounded to 4 decimal places")
            
            // Verify decimal places (should be <= 4)
            let lonDecimals = decimalPlaces(abs(coords.lon))
            let latDecimals = decimalPlaces(abs(coords.lat))
            
            #expect(lonDecimals <= 4, "Longitude should have at most 4 decimal places, got \(lonDecimals)")
            #expect(latDecimals <= 4, "Latitude should have at most 4 decimal places, got \(latDecimals)")
        }
    }
    
    @Test func testSetFeaturesWithHighPrecisionCoordinates() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        // Find a feature with high precision coordinates (like Hagia Sophia)
        // From the file: coordinates: [28.98000557733333, 41.00841894019655]
        let hagiaSophiaFeature = features.first { feature in
            guard let coords = extractCoordinates(from: feature) else { return false }
            // Check if this is the Hagia Sophia feature (approximately)
            return abs(coords.lon - 28.98000557733333) < 0.0001 &&
                   abs(coords.lat - 41.00841894019655) < 0.0001
        }
        
        guard let feature = hagiaSophiaFeature else {
            // If not found, use first feature with high precision
            let highPrecisionFeature = features.first { feature in
                guard let coords = extractCoordinates(from: feature) else { return false }
                return decimalPlaces(abs(coords.lon)) > 4 || decimalPlaces(abs(coords.lat)) > 4
            }
            guard let testFeature = highPrecisionFeature else {
                throw TestError.missingTestData
            }
            
            // Test with this feature
            var geoJSON = GeoJSON()
            geoJSON.setFeatures([testFeature])
            
            guard let resultFeature = geoJSON.getFeature(at: 0),
                  let coords = extractCoordinates(from: resultFeature) else {
                throw TestError.missingResult
            }
            
            // Verify rounding
            let originalCoords = extractCoordinates(from: testFeature)!
            let expectedLon = roundTo4Decimals(originalCoords.lon)
            let expectedLat = roundTo4Decimals(originalCoords.lat)
            
            #expect(coords.lon == expectedLon, "Longitude should be rounded from \(originalCoords.lon) to \(expectedLon)")
            #expect(coords.lat == expectedLat, "Latitude should be rounded from \(originalCoords.lat) to \(expectedLat)")
            return
        }
        
        // Test with Hagia Sophia feature
        var geoJSON = GeoJSON()
        geoJSON.setFeatures([feature])
        
        guard let resultFeature = geoJSON.getFeature(at: 0),
              let coords = extractCoordinates(from: resultFeature) else {
            throw TestError.missingResult
        }
        
        // Original coordinates: [28.98000557733333, 41.00841894019655]
        // Expected rounded: [28.9800, 41.0084]
        let expectedLon = roundTo4Decimals(28.98000557733333) // Should be 28.9800
        let expectedLat = roundTo4Decimals(41.00841894019655) // Should be 41.0084
        
        #expect(coords.lon == expectedLon, "Longitude should be rounded to \(expectedLon), got \(coords.lon)")
        #expect(coords.lat == expectedLat, "Latitude should be rounded to \(expectedLat), got \(coords.lat)")
    }
    
    @Test func testSetFeaturesPreservesFeatureCount() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        // Create GeoJSON and set features
        var geoJSON = GeoJSON()
        geoJSON.setFeatures(features)
        
        // Verify feature count matches
        #expect(geoJSON.featureCount == features.count, "Feature count should match input")
    }
    
    // MARK: - Test setFeature
    
    @Test func testSetFeatureRoundsCoordinates() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        // Use first feature
        guard let firstFeature = features.first else {
            throw TestError.missingTestData
        }
        
        // Get original coordinates
        guard let originalCoords = extractCoordinates(from: firstFeature) else {
            throw TestError.missingTestData
        }
        
        // Create GeoJSON and set single feature
        var geoJSON = GeoJSON()
        let index = geoJSON.setFeature(firstFeature)
        
        #expect(index != nil, "setFeature should return a valid index")
        #expect(index == 0, "First feature should be at index 0")
        
        // Get the feature back and check coordinates
        guard let resultFeature = geoJSON.getFeature(at: 0),
              let resultCoords = extractCoordinates(from: resultFeature) else {
            throw TestError.missingResult
        }
        
        // Verify rounding
        let expectedLon = roundTo4Decimals(originalCoords.lon)
        let expectedLat = roundTo4Decimals(originalCoords.lat)
        
        #expect(resultCoords.lon == expectedLon, "Longitude should be rounded to 4 decimal places")
        #expect(resultCoords.lat == expectedLat, "Latitude should be rounded to 4 decimal places")
    }
    
    @Test func testSetFeatureWithHighPrecisionCoordinates() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        // Find a feature with high precision coordinates
        // Example: Basilica Cistern with coordinates [28.977850189999998, 41.00822923019654]
        let highPrecisionFeature = features.first { feature in
            guard let coords = extractCoordinates(from: feature) else { return false }
            return decimalPlaces(abs(coords.lon)) > 4 || decimalPlaces(abs(coords.lat)) > 4
        }
        
        guard let feature = highPrecisionFeature else {
            throw TestError.missingTestData
        }
        
        // Get original coordinates
        guard let originalCoords = extractCoordinates(from: feature) else {
            throw TestError.missingTestData
        }
        
        // Create GeoJSON and set single feature
        var geoJSON = GeoJSON()
        _ = geoJSON.setFeature(feature)
        
        // Get the feature back and check coordinates
        guard let resultFeature = geoJSON.getFeature(at: 0),
              let resultCoords = extractCoordinates(from: resultFeature) else {
            throw TestError.missingResult
        }
        
        // Verify rounding
        let expectedLon = roundTo4Decimals(originalCoords.lon)
        let expectedLat = roundTo4Decimals(originalCoords.lat)
        
        #expect(resultCoords.lon == expectedLon, 
                "Longitude should be rounded from \(originalCoords.lon) to \(expectedLon), got \(resultCoords.lon)")
        #expect(resultCoords.lat == expectedLat,
                "Latitude should be rounded from \(originalCoords.lat) to \(expectedLat), got \(resultCoords.lat)")
        
        // Verify decimal places
        let lonDecimals = decimalPlaces(abs(resultCoords.lon))
        let latDecimals = decimalPlaces(abs(resultCoords.lat))
        
        #expect(lonDecimals <= 4, "Longitude should have at most 4 decimal places")
        #expect(latDecimals <= 4, "Latitude should have at most 4 decimal places")
    }
    
    @Test func testSetFeatureAppendsToEnd() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        guard features.count >= 2 else {
            throw TestError.missingTestData
        }
        
        // Create GeoJSON and add multiple features
        var geoJSON = GeoJSON()
        
        // Add first feature
        let index1 = geoJSON.setFeature(features[0])
        #expect(index1 == 0, "First feature should be at index 0")
        #expect(geoJSON.featureCount == 1, "Should have 1 feature")
        
        // Add second feature (should append)
        let index2 = geoJSON.setFeature(features[1])
        #expect(index2 == 1, "Second feature should be at index 1")
        #expect(geoJSON.featureCount == 2, "Should have 2 features")
    }
    
    @Test func testSetFeatureAtSpecificIndex() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        guard features.count >= 2 else {
            throw TestError.missingTestData
        }
        
        // Create GeoJSON and add features
        var geoJSON = GeoJSON()
        _ = geoJSON.setFeature(features[0])
        _ = geoJSON.setFeature(features[1])
        
        // Set a new feature at index 0 (should replace)
        let index = geoJSON.setFeature(features[0], at: 0)
        #expect(index == 0, "Feature should be set at index 0")
        #expect(geoJSON.featureCount == 2, "Feature count should remain 2")
        
        // Verify coordinates are still rounded
        guard let resultFeature = geoJSON.getFeature(at: 0),
              let coords = extractCoordinates(from: resultFeature) else {
            throw TestError.missingResult
        }
        
        let lonDecimals = decimalPlaces(abs(coords.lon))
        let latDecimals = decimalPlaces(abs(coords.lat))
        
        #expect(lonDecimals <= 4, "Longitude should have at most 4 decimal places")
        #expect(latDecimals <= 4, "Latitude should have at most 4 decimal places")
    }
    
    @Test func testSetFeatureWithAlreadyRoundedCoordinates() throws {
        // Load mock JSON
        let json = try loadMockJSON()
        let features = try GeoJSON.extractFeatures(from: json)
        
        // Find a feature with already 4-decimal coordinates (like Armenian Patriarchate: 28.9612, 41.0045)
        let roundedFeature = features.first { feature in
            guard let coords = extractCoordinates(from: feature) else { return false }
            return decimalPlaces(abs(coords.lon)) <= 4 && decimalPlaces(abs(coords.lat)) <= 4
        }
        
        guard let feature = roundedFeature else {
            throw TestError.missingTestData
        }
        
        // Get original coordinates
        guard let originalCoords = extractCoordinates(from: feature) else {
            throw TestError.missingTestData
        }
        
        // Create GeoJSON and set feature
        var geoJSON = GeoJSON()
        _ = geoJSON.setFeature(feature)
        
        // Get the feature back
        guard let resultFeature = geoJSON.getFeature(at: 0),
              let resultCoords = extractCoordinates(from: resultFeature) else {
            throw TestError.missingResult
        }
        
        // Coordinates should remain the same (already rounded)
        #expect(resultCoords.lon == originalCoords.lon, "Already-rounded longitude should remain unchanged")
        #expect(resultCoords.lat == originalCoords.lat, "Already-rounded latitude should remain unchanged")
    }
    
    // MARK: - Test Errors
    
    enum TestError: Error {
        case missingFile
        case invalidJSON
        case missingTestData
        case missingResult
    }
}

