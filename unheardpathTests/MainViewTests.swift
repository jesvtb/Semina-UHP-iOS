import Testing
import Foundation
import CoreLocation
import SwiftUI
@testable import unheardpath

struct MainViewTests {
    
    // MARK: - Test refreshPOIList
    
    @Test @MainActor func testRefreshPOIListWithHagiaSophia() async throws {
        // Set up dependencies
        let gateway = UHPGateway()
        let userManager = UserManager()
        let locationManager = LocationManager()
        
        // Use a helper class to test the refreshPOIList functionality
        // This avoids SwiftUI view constraints when calling instance methods
        let helper = TestMainViewTestHelper(
            gateway: gateway,
            userManager: userManager,
            locationManager: locationManager
        )
        
        // Hagia Sophia coordinates: 41.0086° N, 28.9802° E
        let hagiaSophiaLocation = CLLocationCoordinate2D(
            latitude: 41.0086,
            longitude: 28.9802
        )
        
        // Call refreshPOIList through the helper
        try await helper.refreshPOIList(from: hagiaSophiaLocation)
        
        // Verify the function completed successfully
        #expect(Bool(true), "refreshPOIList completed successfully for Hagia Sophia location")
    }
}

// MARK: - Test Helper Class
/// Helper class to test TestMainView methods without SwiftUI view constraints
@MainActor
private class TestMainViewTestHelper {
    let gateway: UHPGateway
    let userManager: UserManager
    let locationManager: LocationManager
    
    init(gateway: UHPGateway, userManager: UserManager, locationManager: LocationManager) {
        self.gateway = gateway
        self.userManager = userManager
        self.locationManager = locationManager
    }
    
    func refreshPOIList(from location: CLLocationCoordinate2D?) async throws {
        // Replicate the logic from TestMainView.refreshPOIList
        // This allows us to test the API call without SwiftUI view constraints
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
        
        // Verify response structure
        #expect(response.isSuccess == true, "API call should succeed")
        #expect(response.event == "map", "Response event should be 'map'")
        #expect(response.content != nil, "Response should have content")
    }
}

// MARK: - JSONValue Extension for Testing
extension JSONValue {
    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }
}

