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
        
        // Read API key from Info.plist
        guard let apiKey = Bundle.main.infoDictionary?["GEOAPIFY_API_KEY"] as? String,
              !apiKey.isEmpty else {
            fatalError("❌ GEOAPIFY_API_KEY not found in Info.plist!")
        }
        
        self.apiKey = apiKey
        self.baseURL = "https://api.geoapify.com/v1/geocode/autocomplete"
        self.apiClient = APIClient()
    }
    
    /// Searches for cities, localities, states, and countries using Geoapify autocomplete API
    /// Makes parallel requests for each type and merges the results
    /// - Parameters:
    ///   - query: The search query string
    ///   - limit: Maximum number of results per type (default: 5)
    ///   - countryCode: Optional ISO country code filter (e.g., "US", "GB")
    /// - Returns: Raw Data response from the API with merged results
    /// - Throws: GeoapifyError if all requests fail
    nonisolated func searchCities(
        query: String,
        limit: Int = 5,
        countryCode: String? = nil
    ) async throws -> Data {
        // Capture actor-isolated properties before async work
        let capturedApiKey = await MainActor.run { apiKey }
        let capturedBaseURL = await MainActor.run { baseURL }
        let capturedApiClient = await MainActor.run { apiClient }
        
        // Types to search for: city, locality, state, and country
        let types = ["city", "locality", "state", "country"]
        
        // Make parallel requests for each type
        async let results = withThrowingTaskGroup(of: (type: String, data: Data?).self) { group in
            for type in types {
                group.addTask {
                    do {
                        var params: [String: String] = [
                            "text": query,
                            "type": type,
                            "apiKey": capturedApiKey,
                            "limit": String(limit)
                        ]
                        
                        // Add country code filter if provided
                        if let countryCode = countryCode, !countryCode.isEmpty {
                            params["filter"] = "countrycode:\(countryCode)"
                        }
                        
                        // Build full URL
                        guard var urlComponents = URLComponents(string: capturedBaseURL) else {
                            return (type, nil)
                        }
                        
                        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
                        
                        guard let fullURL = urlComponents.url?.absoluteString else {
                            return (type, nil)
                        }
                        
                        // Make API call
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
                        
                        return (type, data)
                    } catch {
                        #if DEBUG
                        print("⚠️ Geoapify search failed for type '\(type)': \(error.localizedDescription)")
                        #endif
                        return (type, nil)
                    }
                }
            }
            
            // Collect all successful results
            var allResults: [(type: String, data: Data?)] = []
            for try await result in group {
                allResults.append(result)
            }
            return allResults
        }
        
        let typeResults = try await results
        
        // Merge all features from all types into a single response
        var allFeatures: [[String: Any]] = []
        for (_, data) in typeResults {
            guard let data = data,
                  let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = jsonObject["features"] as? [[String: Any]] else {
                continue
            }
            allFeatures.append(contentsOf: features)
        }
        
        // Create merged response
        let mergedResponse: [String: Any] = [
            "type": "FeatureCollection",
            "features": allFeatures
        ]
        
        // Convert to Data
        guard let mergedData = try? JSONSerialization.data(withJSONObject: mergedResponse) else {
            throw GeoapifyError.requestFailed("Failed to merge Geoapify responses")
        }
        
        #if DEBUG
        printGeoapifyResponse(data: mergedData)
        #endif
        
        return mergedData
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

