//
//  APIClient.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import core

// Use core types so UHPGateway and rest of app resolve correctly
typealias APIError = core.APIError
typealias SSEEvent = core.SSEEvent
typealias APIClient = core.APIClient

// MARK: - UHP Gateway Error Types
enum UHPError: Error, Sendable {
    case invalidResponseFormat
    case missingField(String)
    case decodingError(Error)
    case backendError(String)
}

// MARK: - UHP Gateway Response
struct UHPResponse: Sendable {
    let data: Data
    
    private let envelope: [String: JSONValue]
    
    init(data: Data) throws {
        self.data = data
        
        // Parse Data to JSONValue
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let jsonValue = JSONValue(from: jsonObject),
              case .dictionary(let dict) = jsonValue else {
            throw UHPError.invalidResponseFormat
        }
        
        self.envelope = dict
    }
    
    /// Checks if the response status is "success"
    var isSuccess: Bool {
        guard case .string(let status) = envelope["status"] else {
            return false
        }
        return status == "success"
    }
    
    /// Raw result field (can be dictionary, array, or primitive)
    var result: JSONValue? {
        return envelope["result"]
    }
    
    /// Extract event type from result if it's in SSE format (has "event" field)
    /// Returns the event string (e.g., "map", "update", etc.)
    var event: String? {
        guard case .dictionary(let resultDict) = result,
              case .string(let eventString) = resultDict["event"] else {
            return nil
        }
        return eventString
    }
    
    /// Extract data/content from result if it's in SSE format (has "data" field)
    /// Returns the data JSONValue (typically a FeatureCollection or other data structure)
    var content: JSONValue? {
        guard case .dictionary(let resultDict) = result,
              let dataValue = resultDict["data"] else {
            return nil
        }
        return dataValue
    }
    
    /// Pretty print the content field (data from SSE format)
    func printContent() {
        guard let content = content else {
            print("⚠️ No content to print")
            return
        }
        
        let jsonObject: Any
        
        switch content {
        case .dictionary(let dict):
            jsonObject = dict.mapValues { $0.asAny }
        case .array(let array):
            jsonObject = array.map { $0.asAny }
        default:
            jsonObject = content.asAny
        }
        
        // Pretty print using JSONSerialization
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📄 Content JSON:\n\(jsonString)")
        } else {
            print("⚠️ Failed to pretty print content")
        }
    }
    
    /// Maps result to [String: Any] and pretty prints it
    /// Uses response.result and mapValues to convert JSONValue to Any for JSONSerialization
    func printPretty() {
        guard let result = result else {
            print("⚠️ No result to print")
            return
        }
        
        let jsonObject: Any
        
        switch result {
        case .dictionary(let dict):
            // Convert [String: JSONValue] to [String: Any] using mapValues
            // mapValues transforms each value while keeping the same keys
            jsonObject = dict.mapValues { $0.asAny }
        case .array(let array):
            // Convert [JSONValue] to [Any] using map
            jsonObject = array.map { $0.asAny }
        default:
            // For primitives, use the raw value
            jsonObject = result.asAny
        }
        
        // Pretty print using JSONSerialization
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📄 Pretty JSON:\n\(jsonString)")
        } else {
            print("⚠️ Failed to pretty print result")
        }
    }
}

@MainActor
class UHPGateway: ObservableObject {
    private let apiClient: core.APIClient
    private let baseURL: String
    private let defaultHeaders: [String: String]
    
    init() {
        // Read both gateway hosts (both are available in all builds via Config.xcconfig)
        guard let debugHost = Bundle.main.infoDictionary?["UHP_GATEWAY_HOST_DEBUG"] as? String,
              !debugHost.isEmpty,
              let releaseHost = Bundle.main.infoDictionary?["UHP_GATEWAY_HOST_RELEASE"] as? String,
              !releaseHost.isEmpty else {
            fatalError("❌ Gateway hosts not found in Info.plist!")
        }
        
        // Choose host and protocol based on build configuration using compiler flags
        #if DEBUG
            self.baseURL = "http://\(debugHost)"
        #else
            self.baseURL = "https://\(releaseHost)"
        #endif
        
        self.apiClient = core.APIClient(logger: AppLifecycleManager.sharedLogger)
        
        self.defaultHeaders = [
            "Content-Type": "application/json"
        ]
    }
    
    nonisolated private func addAuthHeader() async throws -> [String: String] {
        
        // #if DEBUG
        // let accessToken = "1234567890"
        // #else
        let accessToken = try await supabase.auth.session.accessToken
        // #endif

        #if DEBUG
        print("🔑 Supabase Access Token: \(accessToken)")
        #endif

        var headers = defaultHeaders
        headers["Authorization"] = "Bearer \(accessToken)"
        
        return headers
    }
    
    // Add auth token to headers and combine endpoint with baseURL, baseURL + "v1/..."
    
    nonisolated func request(
        endpoint: String,
        method: String = "POST",
        params: [String: String] = [:],
        jsonDict: [String: JSONValue] = [:],
        customHeaders: [String: String] = [:]
    ) async throws -> UHPResponse {

        let fullURL = "\(baseURL)\(endpoint)"
        var headers = try await self.addAuthHeader()
        
        // Merge custom headers (custom headers override default headers)
        for (key, value) in customHeaders {
            headers[key] = value
        }
        
        let data = try await apiClient.asyncCallAPI(
            url: fullURL,
            method: method,
            headers: headers,
            params: params,
            jsonDict: jsonDict
        )
        
        // Parse Data to UHPResponse
        let uhpResponse = try UHPResponse(data: data)
        
        // Validate envelope format - check if status is success
        guard uhpResponse.isSuccess else {
            // Extract error message from envelope if available
            // Access the raw JSON to check for error field
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = jsonObject["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                throw UHPError.backendError(message)
            } else {
                throw UHPError.backendError("Backend returned error status")
            }
        }
        
        return uhpResponse
    }

    nonisolated func stream(
        endpoint: String,
        method: String = "POST",
        params: [String: String] = [:],
        jsonDict: [String: JSONValue] = [:]
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        
        let fullURL = "\(baseURL)\(endpoint)"
        let headers = try await addAuthHeader()
        
        return apiClient.streamAPI(
            url: fullURL,
            method: method,
            headers: headers,
            params: params,
            jsonDict: jsonDict,
            timeout: false,
            filesDict: [:]
        )
    }
    
    /// Convenience method to stream user events with auto-generated UTC and timezone
    /// - Parameters:
    ///   - endpoint: API endpoint (e.g., "/v1/chat", "/v1/orchestor")
    ///   - evtType: Event type (e.g., "chat_sent", "location_detected")
    ///   - evtData: Event data dictionary
    /// - Returns: AsyncThrowingStream of SSEEvent
    nonisolated func streamUserEvent(
        endpoint: String,
        evtType: String,
        evtData: [String: JSONValue]
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let userEvent = UserEventBuilder.build(evtType: evtType, evtData: evtData)
        return try await stream(
            endpoint: endpoint,
            jsonDict: userEvent.toJSONDict()
        )
    }
}
