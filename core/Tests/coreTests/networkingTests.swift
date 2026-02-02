import Testing
import Foundation
@preconcurrency import MapKit
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

// MARK: - MapKit Completer Integration Test Helper

/// Sendable snapshot of a completion (title/subtitle only) for crossing isolation in tests.
private struct MapKitCompletionSnapshot: Sendable {
    let title: String
    let subtitle: String
}

/// Captures MKLocalSearchCompleter results and resumes a continuation once (used for async test wait).
/// Resumes with Sendable snapshots (title/subtitle) to avoid sending non-Sendable MKLocalSearchCompletion.
private final class MapKitCompleterTestDelegate: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<[MapKitCompletionSnapshot], Never>
    private let lock = NSLock()
    private var fulfilled = false

    init(continuation: CheckedContinuation<[MapKitCompletionSnapshot], Never>) {
        self.continuation = continuation
    }

    /// Call from delegate or timeout; resumes the continuation exactly once.
    func deliver(_ results: [MapKitCompletionSnapshot]) {
        lock.lock()
        defer { lock.unlock() }
        guard !fulfilled else { return }
        fulfilled = true
        continuation.resume(returning: results)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let snapshots = completer.results.map { MapKitCompletionSnapshot(title: $0.title, subtitle: $0.subtitle) }
        deliver(snapshots)
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        deliver([])
    }
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

    @Test
    func testCallUHPAPI() async throws {
        let client = APIClient()
        let data = try await client.asyncCallAPI(
            url: "http://192.168.50.171:1031/v1/test/connection",
            method: "GET",
            headers: ["Content-Type": "application/json"],
            // params: ["simulate_data": "geojson"],
            params: ["simulate_data": "sse_map"],
        )
       try require(
           data is Data,
           success: "data is Data type",
           failure: "data is not Data type"
       )
       let jsonValue = try data.shapeIntoJsonValue()
       try require(
           jsonValue["status"]?.stringValue == "success",
           success: "status is success",
           failure: "status is not success"
       )
   
    }

    @Test(
        "Test streaming API",
        arguments: ["sse_map"]
    )
    func testStreamAPI(testCase: String) async throws {
        let client = APIClient()
        let stream = try await client.streamAPI(
            url: "http://192.168.50.171:1031/v1/test/stream",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            params: ["simulate_data": testCase],
        )
        var chunkIndex = 0
        for try await chunk in stream {
            chunkIndex += 1
            // print("--- testCase: \(testCase), chunk #\(chunkIndex), event: \(chunk.event ?? "nil") ---")
            printItem(item: chunk)
            if chunk.event == "map" {
                let jsonValue = chunk.dataValue
                printItem(item: jsonValue)
            }
            // if chunk.event == "content" {
            //     let jsonValue = try chunk.parseJSONData()
            //     print("jsonValue: \(jsonValue)")
            //     // try require(
            //     //     jsonValue["type"]?.stringValue == "regionalCuisine",
            //     //     success: "type is regionalCuisine",
            //     //     failure: "type is not regionalCuisine"
            //     // )
            // }
        }
    }

    @Test(
        "Test streaming API",
        // arguments: ["ista", "shen", "apple par"]
        arguments: ["Shenzhe"]
    )
    func testGeocodeAPI(testCase: String) async throws {
        let client = APIClient()
        let baseURL = "https://api.geoapify.com/v1/geocode/autocomplete"
        let params = [
            "text": testCase,
            "apiKey": "e810e0454fda45acbf6b3fbaa7bebe15",
            "limit": "5",
            // "type": "city",
            // "filter": "countrycode:US"
        ]
        let data = try await client.asyncCallAPI(
            url: baseURL,
            method: "GET",
            headers: nil,
            params: params,
            jsonDict: [:],
            timeout: false,
            filesDict: [:]
        )
        // print("data: \(data)")
        let jsonValue = try data.shapeIntoJsonValue()
        let features = try data.extractFeatures()
        // printItem(item: jsonValue)
        // let geojson = Data
        // printItem(item: features[0])
        // printItem(item: features[0].properties)
        let mapSearchResult = MapSearchResult(features[0])
        printItem(item: mapSearchResult)
    }

    @Test(
        "MapKit local search completer returns results for query",
        // arguments: ["Hagia", "Istan", "London"]
        arguments: ["Hagia Sophi", "Istan"]
    )
    @MainActor
    func testMapKitCompleterAPI(query: String) async throws {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest, .query]
        let globalCenter = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        completer.region = MKCoordinateRegion(
            center: globalCenter,
            latitudinalMeters: 200_000_000,
            longitudinalMeters: 200_000_000
        )

        let results: [MapKitCompletionSnapshot] = await withCheckedContinuation { continuation in
            let delegate = MapKitCompleterTestDelegate(continuation: continuation)
            completer.delegate = delegate
            completer.queryFragment = query
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                delegate.deliver([])
            }
        }

        printItem(item: results[0])
    }

    @Test(
        "MKLocalSearch.Request returns map items with coordinates",
        arguments: ["Hagia Sophi"]
    )
    @MainActor
    func testMKLocalSearchRequest(query: String) async throws {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)

        let results: [MKMapItem] = await withCheckedContinuation { continuation in
            search.start { response, error in
                if let error = error {
                    print("MKLocalSearch error for '\(query)': \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                guard let response = response else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: Array(response.mapItems.prefix(5)))
            }
        }

        printItem(item: results[0])
        // printItem(item: results[1].placemark.coordinate)
        let mapSearchResult = MapSearchResult(results[0])
        printItem(item: mapSearchResult)
    }
}