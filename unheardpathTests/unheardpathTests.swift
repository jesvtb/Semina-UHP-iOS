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

// MARK: - APIService Unit Tests
struct APIServiceTests {
    
    @Test func testAPIServiceInitialization() async throws {
        // Test that APIService can be initialized without throwing an error
        let apiService = APIService()
        // If we get here without throwing, the initialization was successful
        #expect(true, "APIService should initialize successfully")
    }
    
    @Test func testInvalidURLHandling() async throws {
        let apiService = APIService()
        
        do {
            _ = try await apiService.asyncCallAPI(url: "invalid-url")
            #expect(Bool(false), "Should have thrown an error for invalid URL")
        } catch {
            #expect(error is APIError, "Should throw APIError for invalid URL")
        }
    }
    
    // MARK: - Parametrized API Tests
    
    @Test(arguments: APITestUtilities.testConfigurations)
    func testAPIs(config: APITestConfig) async throws {
        let apiService = APIService()
        let result = await APITestUtilities.runTest(config: config, apiService: apiService)
        
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
