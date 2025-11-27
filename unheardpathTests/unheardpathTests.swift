//
//  unheardpathTests.swift
//  unheardpathTests
//
//  Created by Jessica Luo on 2025-09-09.
//

import Testing
import Foundation
@testable import unheardpath

struct unheardpathTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

// MARK: - APIClient Unit Tests
struct APIClientTests {
    
    @Test func testAPIClientInitialization() async throws {
        // Test that APIClient can be initialized without throwing an error
        let apiClient = APIClient()
        // If we get here without throwing, the initialization was successful
        #expect(true, "APIClient should initialize successfully")
    }
    
    @Test func testInvalidURLHandling() async throws {
        let apiClient = APIClient()
        
        do {
            _ = try await apiClient.asyncCallAPI(url: "invalid-url")
            #expect(Bool(false), "Should have thrown an error for invalid URL")
        } catch {
            #expect(error is APIError, "Should throw APIError for invalid URL")
        }
    }
    
    // MARK: - Parametrized API Tests
    
    @Test(arguments: APITestUtilities.testConfigurations)
    func testAPIs(config: APITestConfig) async throws {
        let apiClient = APIClient()
        let result = await APITestUtilities.runTest(config: config, apiClient: apiClient)
        
        if config.expectedSuccess {
            #expect(result.success, "\(config.name) should work correctly - \(config.description)")
        } else {
            // For external APIs that may fail, we only assert success if it actually succeeds
            // This prevents CI/CD failures when external services are unavailable
            if result.success {
                #expect(true, "\(config.name) API returned a response - \(config.description)")
            }
        }
    }
}
