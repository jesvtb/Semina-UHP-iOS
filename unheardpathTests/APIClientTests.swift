import Testing
import Foundation
@testable import unheardpath

struct APIClientTests {
    
    @Test @MainActor func testBuildRequestBasic() throws {
        let client = APIClient()
        let url = "http://192.168.50.171:1031/v1/test/connection"
        let method = "POST"
        let headers = ["Content-Type": "application/json"]
        let jsonDict: [String: JSONValue] = [
            "key": .string("value"),
            "count": .int(42),
            "price": .double(19.99),
            "isActive": .bool(true)
        ]
        
        let request = try client.buildRequest(
            url: url,
            method: method,
            headers: headers,
            jsonDict: jsonDict
        )
        print("request: \(request)")
        #expect(request.url?.absoluteString == url)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody != nil)
    }

    @Test @MainActor func testBuildRequestWithQueryParams() async throws {
        let client = APIClient()
        let url = "http://192.168.50.171:1031/v1/test/connection"
        let method = "GET"
        
        let response = try await client.asyncCallAPI(url: url, method: method)
        
        // Extract and pretty-print response data
        guard let resultDict = response as? [String: Any],
              let data = resultDict["data"],
              let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        print("📄 Pretty JSON:\n\(jsonString)")

    }

}

