import Testing
import Foundation
@testable import unheardpath

struct GeoapifyGatewayTests {
    
    @Test @MainActor func testSearchCities() async throws {
        // Initialize GeoapifyGateway (requires GEOAPIFY_API_KEY in Info.plist)
        let gateway = GeoapifyGateway()
        
        // Search for a well-known city
        let query = "Istan"
        let limit = 5
        
        // Call searchCities method
        let responseData = try await gateway.searchCities(
            query: query,
            limit: limit
        )
        
        // Print response data for inspection
        print("\n📄 Geoapify Test Response Data:")
        print("Response size: \(responseData.count) bytes")
        
        // Pretty print the JSON response
        if let jsonObject = try? JSONSerialization.jsonObject(with: responseData),
           let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📄 Pretty JSON Response:\n\(jsonString)\n")
        } else {
            print("⚠️ Could not pretty print response")
            if let rawString = String(data: responseData, encoding: .utf8) {
                print("Raw response: \(rawString)")
            }
        }
        
        // Verify response is not empty
        #expect(!responseData.isEmpty, "Response data should not be empty")
        
        // Verify response is valid JSON
        guard let jsonObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw TestError.invalidJSON
        }
        
        // Verify response has expected structure (Geoapify typically returns features array)
        // The response should be a valid JSON object
        #expect(jsonObject.count > 0, "Response should contain JSON data")
        
        // Optional: Verify response contains "features" key (typical Geoapify response structure)
        if let features = jsonObject["features"] as? [[String: Any]] {
            print("✅ Found \(features.count) features in response")
            #expect(features.count <= limit, "Response should not exceed limit")
            #expect(features.count > 0, "Response should contain at least one result")
        } else {
            print("⚠️ Response does not contain 'features' array - check actual API response structure")
        }
    }
    
    enum TestError: Error {
        case invalidJSON
    }
}

// MARK: - Autocomplete Considerations
/*
 NOTE: Autocomplete vs Static API Calls
 
 The GeoapifyGateway itself is just a simple API client - it makes HTTP requests.
 For autocomplete functionality, you typically need additional handling at a higher level:
 
 1. **Debouncing/Throttling**: 
    - Don't call the API on every keystroke
    - Wait for user to stop typing (e.g., 300-500ms delay)
    - Cancel previous requests if new one comes in
 
 2. **Request Cancellation**:
    - Cancel in-flight requests when user types new characters
    - Use Task cancellation tokens
 
 3. **Minimum Query Length**:
    - Don't search until user has typed at least 2-3 characters
    - Reduces unnecessary API calls
 
 4. **Caching**:
    - Cache recent results to avoid duplicate API calls
    - Useful for common queries
 
 Example implementation pattern (similar to AddressSearchManager):
 
 ```swift
 @MainActor
 class CitySearchManager: ObservableObject {
     @Published var results: [CityResult] = []
     private var searchTask: Task<Void, Never>?
     
     func search(query: String) {
         // Cancel previous search
         searchTask?.cancel()
         
         // Minimum query length
         guard query.count >= 2 else {
             results = []
             return
         }
         
         // Debounce: wait 300ms before searching
         searchTask = Task {
             try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
             
             // Check if task was cancelled
             guard !Task.isCancelled else { return }
             
             // Make API call
             let data = try? await geoapifyGateway.searchCities(query: query)
             // Parse and update results...
         }
     }
 }
 ```
 
 The gateway itself doesn't need special handling - it's just an API client.
 The autocomplete-specific logic should be in a manager/view layer.
 */

