import Testing
@testable import unheardpath

struct APIClientTests {
    
    @Test func testBuildRequestBasic() throws {
        let client = APIClient()
        let url = "http://192.168.50.171:1031/v1/test/connection"
        let method = "POST"
        let headers = ["Content-Type": "application/json"]
        let jsonDict: [String: Any] = ["key": "value"]
        
        let request = try client.buildRequest(
            url: url,
            method: method,
            headers: headers,
            jsonDict: jsonDict
        )
        
        #expect(request.url?.absoluteString == url)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody != nil)
    }
    
    @Test func testBuildRequestWithQueryParams() throws {
        let client = APIClient()
        let url = "https://api.example.com/test"
        let params = ["param1": "value1", "param2": "value2"]
        
        let request = try client.buildRequest(
            url: url,
            method: "GET",
            params: params
        )
        
        #expect(request.url?.absoluteString.contains("param1=value1") == true)
        #expect(request.url?.absoluteString.contains("param2=value2") == true)
    }
    
    @Test func testBuildRequestInvalidURL() throws {
        let client = APIClient()
        
        #expect(throws: APIError.self) {
            try client.buildRequest(
                url: "not a valid url",
                method: "GET"
            )
        }
    }
}

