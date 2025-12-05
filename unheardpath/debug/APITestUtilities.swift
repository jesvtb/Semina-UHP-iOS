//
//  APITestUtilities.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation


// MARK: - API Test Configuration
struct APITestConfig: Sendable {
    let name: String
    let url: String
    let method: String
    let headers: [String: String]?
    let params: [String: String]
    let jsonDict: [String: JSONValue]
    let expectedSuccess: Bool
    let description: String
    
    init(
        name: String,
        url: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        jsonDict: [String: JSONValue] = [:],
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
        APITestConfig(
            name: "Semina API",
            url: "https://api.unheardpath.com/v1/test/connection",
            expectedSuccess: true,
            description: "Test Semina API"
        ),
        APITestConfig(
            name: "Semina API Local",
            url: "http://192.168.50.171:1031/v1/test/connection",
            expectedSuccess: true,
            description: "Test Semina API Local"
        ),
        
    ]
    
    
}
