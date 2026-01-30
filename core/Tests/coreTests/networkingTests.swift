import Testing
import Foundation
@testable import core

// MARK: - Test Cases (mirrors param_call_api API_CONNECTION_CASES and error-code tests)

struct AsyncCallAPICase: CustomStringConvertible, Sendable {
    let id: String
    let url: String
    let method: String
    let headers: [String: String]?
    let jsonDict: [String: JSONValue]
    let expectSuccess: Bool
    let expectedStatusCode: Int?

    var description: String { id }

    static let connectionCases: [AsyncCallAPICase] = [
        AsyncCallAPICase(
            id: "openrouter",
            url: "https://openrouter.ai/api/v1/models",
            method: "GET",
            headers: nil,
            jsonDict: [:],
            expectSuccess: true,
            expectedStatusCode: nil
        ),
        AsyncCallAPICase(
            id: "httpbin_get",
            url: "https://httpbin.org/get",
            method: "GET",
            headers: nil,
            jsonDict: [:],
            expectSuccess: true,
            expectedStatusCode: nil
        ),
        AsyncCallAPICase(
            id: "httpbin_post",
            url: "https://httpbin.org/post",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            jsonDict: ["key": .string("value")],
            expectSuccess: true,
            expectedStatusCode: nil
        ),
    ]

    static let errorCodeCases: [AsyncCallAPICase] = [404, 500, 403, 429, 502].map { code in
        AsyncCallAPICase(
            id: "httpbin_status_\(String(code))",
            url: "https://httpbin.org/status/\(String(code))",
            method: "GET",
            headers: nil,
            jsonDict: [:],
            expectSuccess: false,
            expectedStatusCode: code
        )
    }

    static let allCases: [AsyncCallAPICase] = connectionCases + errorCodeCases
}

// MARK: - Suite

@Suite("APIClient Tests")
struct NetworkingTests {

    @Test(
        "Async call API returns response or expected error",
        arguments: AsyncCallAPICase.allCases
    )
    func testAsyncCallAPI(testCase: AsyncCallAPICase) async throws {
        let client = APIClient()

        if testCase.expectSuccess {
            // asyncCallAPI returns Data (raw response bytes); decode to JSONValue for consistent typing and printing
            let data = try await client.asyncCallAPI(
                url: testCase.url,
                method: testCase.method,
                headers: testCase.headers,
                jsonDict: testCase.jsonDict
            )
            try require(
                !data.isEmpty,
                success: "Returned response from \(testCase.url)",
                failure: "Failed to return response from \(testCase.url)"
            )
            let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data)
            if let jsonValue = jsonValue {
                let encoded = jsonValue.encodeToString() ?? ""
                let preview = encoded.count > 500 ? String(encoded.prefix(500)) + "…" : encoded
                print("response as JSONValue (\(jsonValue)); preview: \(preview)")
            } else {
                print("response: \(data.count) bytes (JSON decode failed or non-JSON)")
            }
            try require(
                jsonValue != nil,
                success: "Response from \(testCase.url) is valid JSON",
                failure: "Response from \(testCase.url) is not valid JSON"
            )
        } else {
            let expectedCode = testCase.expectedStatusCode ?? -1
            do {
                _ = try await client.asyncCallAPI(
                    url: testCase.url,
                    method: testCase.method,
                    headers: testCase.headers,
                    jsonDict: testCase.jsonDict
                )
                try require(
                    false,
                    success: "",
                    failure: "Expected APIError with status \(expectedCode) from \(testCase.url)"
                )
            } catch let error as APIError {
                try require(
                    error.code == expectedCode,
                    success: "Received expected status \(expectedCode) from \(testCase.url)",
                    failure: "Expected status \(expectedCode) but got \(error.code ?? -1) from \(testCase.url)"
                )
            } catch {
                try require(
                    false,
                    success: "",
                    failure: "Expected APIError from \(testCase.url), got \(error)"
                )
            }
        }
    }
}
