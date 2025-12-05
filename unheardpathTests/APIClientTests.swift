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

    @Test @MainActor func testRefreshPOIs() async throws {
        let gateway = UHPGateway()
        
        // Call the refresh POIs endpoint
        let response = try await gateway.request(
            endpoint: "/v1/signed-in-home",
            method: "POST",
            jsonDict: [
                "latitude": .double(22.559569009243607),
                "longitude": .double(114.11699793738644),
                "place": .string("ICBC (Shenzhen Baohu Branch)"),
                "country_code": .string("CN"),
                "location_type": .string("device"),
                "location": .string("Luohu, Shenzhen, Guangdong"),
                "region_lon": .double(114.122075),
                "action_timezone": .string("Asia/Shanghai"),
                "accuracy": .double(7.877263686087196),
                "country": .string("China"),
                "region_lat": .double(22.556874999999998),
                "region_radius": .double(196.96176247987088),
                "action_utc": .string("2025-12-04T08:29:43Z"),
                "full_address": .string("Sungang East Road No.1002-1 Bao'an Square, Luohu, Shenzhen, Guangdong, China"),
                "street": .string("Sungang East Road No.1002-1 Bao'an Square"),
                "areas_of_interest": .array([.string("Bao'an Square") as JSONValue]),
            ]
        )
        
        // response.printPretty()
        // print("event: \(response.event)")
        // print("content: \(response.content)")
        response.printContent()
        
        // Verify response structure
        #expect(response.isSuccess == true, "Response should have success status")
        
    }
    
    enum TestError: Error {
        case missingResult
    }

}

