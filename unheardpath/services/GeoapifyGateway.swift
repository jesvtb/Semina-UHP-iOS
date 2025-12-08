//
//  GeoapifyGateway.swift
//  unheardpath
//
//  Created for Geoapify city autocomplete API integration
//

import Foundation

// MARK: - Geoapify Error Types
enum GeoapifyError: Error, Sendable {
    case missingAPIKey
    case invalidURL
    case requestFailed(String)
}

// MARK: - Geoapify Gateway
@MainActor
class GeoapifyGateway: ObservableObject {
    private let apiClient: APIClient
    private let baseURL: String
    private let apiKey: String
    
    init() {
        // Debug: Print all Info.plist keys to help diagnose issues
        #if DEBUG
        if let infoDict = Bundle.main.infoDictionary {
            print("🔍 Available Info.plist keys: \(infoDict.keys.sorted().joined(separator: ", "))")
            // Specifically check for GEOAPIFY_API_KEY
            if let geoapifyKey = infoDict["GEOAPIFY_API_KEY"] as? String {
                print("✅ Found GEOAPIFY_API_KEY in Info.plist: \(String(geoapifyKey.prefix(20)))...")
            } else {
                print("❌ GEOAPIFY_API_KEY NOT found in Info.plist")
                print("   This means Config.xcconfig values are not being injected")
                print("   Check that project.pbxproj has INFOPLIST_KEY_GEOAPIFY_API_KEY = \"$(GEOAPIFY_API_KEY)\"")
            }
        }
        #endif
        
        // Read API key from Info.plist
        guard let apiKey = Bundle.main.infoDictionary?["GEOAPIFY_API_KEY"] as? String,
              !apiKey.isEmpty else {
            fatalError("❌ GEOAPIFY_API_KEY not found in Info.plist!")
        }
        
        self.apiKey = apiKey
        self.baseURL = "https://api.geoapify.com/v1/geocode/autocomplete"
        self.apiClient = APIClient()
    }
    
    /// Searches for cities using Geoapify autocomplete API
    /// - Parameters:
    ///   - query: The search query string
    ///   - limit: Maximum number of results (default: 5)
    ///   - countryCode: Optional ISO country code filter (e.g., "US", "GB")
    /// - Returns: Raw Data response from the API
    /// - Throws: GeoapifyError if request fails
    nonisolated func searchCities(
        query: String,
        limit: Int = 5,
        countryCode: String? = nil
    ) async throws -> Data {
        // Capture actor-isolated properties before async work
        let capturedApiKey = await MainActor.run { apiKey }
        let capturedBaseURL = await MainActor.run { baseURL }
        let capturedApiClient = await MainActor.run { apiClient }
        
        // Build query parameters
        var params: [String: String] = [
            "text": query,
            "type": "city",
            "apiKey": capturedApiKey,
            "limit": String(limit)
        ]
        
        // Add country code filter if provided
        if let countryCode = countryCode, !countryCode.isEmpty {
            params["filter"] = "countrycode:\(countryCode)"
        }
        
        // Build full URL
        guard var urlComponents = URLComponents(string: capturedBaseURL) else {
            throw GeoapifyError.invalidURL
        }
        
        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let fullURL = urlComponents.url?.absoluteString else {
            throw GeoapifyError.invalidURL
        }
        
        do {
            // Make API call using APIClient
            let data = try await capturedApiClient.asyncCallAPI(
                url: fullURL,
                method: "GET",
                headers: nil,
                params: [:], // Params already in URL
                dataDict: [:],
                jsonDict: [:],
                timeout: false,
                filesDict: [:]
            )
            
            // Pretty print JSON response for debugging
            printGeoapifyResponse(data: data)
            
            return data
        } catch let apiError as APIError {
            throw GeoapifyError.requestFailed(apiError.message)
        } catch {
            throw GeoapifyError.requestFailed("Failed to call Geoapify API: \(error.localizedDescription)")
        }
    }
    
    /// Pretty prints the Geoapify API response JSON to console
    /// Uses the same pattern as UHPResponse.printPretty()
    private nonisolated func printGeoapifyResponse(data: Data) {
        do {
            // Parse Data to JSON object
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("⚠️ Geoapify response is not a JSON object")
                return
            }
            
            // Convert to pretty printed string
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📄 Geoapify Response JSON:\n\(jsonString)")
            } else {
                print("⚠️ Failed to pretty print Geoapify response")
            }
        } catch {
            print("⚠️ Failed to parse Geoapify response: \(error.localizedDescription)")
        }
    }
}

