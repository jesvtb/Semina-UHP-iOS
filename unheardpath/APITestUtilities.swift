//
//  APITestUtilities.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation

// MARK: - API Test Configuration
struct APITestConfig {
    let name: String
    let url: String
    let method: String
    let headers: [String: String]?
    let params: [String: String]
    let jsonDict: [String: Any]
    let expectedSuccess: Bool
    let description: String
    
    init(
        name: String,
        url: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        jsonDict: [String: Any] = [:],
        expectedSuccess: Bool = true,
        description: String = ""
    ) {
        self.name = name
        self.url = url
        self.method = method
        self.headers = headers
        self.params = params
        self.jsonDict = jsonDict
        self.expectedSuccess = expectedSuccess
        self.description = description
    }
}

// MARK: - API Test Utilities
class APITestUtilities {
    
    // MARK: - Test Configurations
    static let testConfigurations: [APITestConfig] = [
        // External APIs (may fail if services unavailable)
        APITestConfig(
            name: "Ollama",
            url: "http://192.168.50.171:11434/v1/models",
            expectedSuccess: false,
            description: "Local Ollama instance - may fail if not running"
        ),
        APITestConfig(
            name: "Request Building",
            url: "https://httpbin.org/get",
            headers: ["Test-Header": "Test-Value"],
            params: ["param1": "value1", "param2": "value2"],
            expectedSuccess: true,
            description: "Tests request building with headers and params"
        ),
    ]
    
    // MARK: - Generic Test Runner
    static func runTest(config: APITestConfig, apiService: APIService) async -> (success: Bool, response: String, error: String?) {
        do {
            let response = try await apiService.asyncCallAPI(
                url: config.url,
                method: config.method,
                headers: config.headers,
                params: config.params,
                jsonDict: config.jsonDict
            )
            
            // Convert Any response to String
            let responseString: String
            if let stringResponse = response as? String {
                responseString = stringResponse
            } else {
                // Convert to JSON string if it's a dictionary or array
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
                    responseString = String(data: jsonData, encoding: .utf8) ?? "\(response)"
                } catch {
                    responseString = "\(response)"
                }
            }
            
            return (true, responseString, nil)
        } catch let apiError as APIError {
            return (false, "", "\(apiError.message) (Code: \(apiError.code ?? 0))")
        } catch {
            return (false, "", error.localizedDescription)
        }
    }
    
}
