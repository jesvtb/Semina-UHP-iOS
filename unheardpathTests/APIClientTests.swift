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
        
        let responseData = try await client.asyncCallAPI(url: url, method: method)
        
        // Parse Data to JSON and pretty-print
        guard let jsonObject = try? JSONSerialization.jsonObject(with: responseData),
              let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
              let _ = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        // print("📄 Pretty JSON:\n\(jsonString)")
    
    }

    @Test @MainActor func testUHPGatewayRequest() async throws {
        let gateway = UHPGateway()
        
        // Call the test connection endpoint
        let response = try await gateway.request(
            endpoint: "/v1/test/connection",
            method: "GET"
        )
        
        // response.printPretty()
        
        // Verify response structure
        #expect(response.isSuccess == true, "Response should have success status")
        
    }

    
    
    enum TestError: Error {
        case missingResult
    }

}

