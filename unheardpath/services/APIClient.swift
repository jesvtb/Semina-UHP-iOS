//
//  APIClient.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation

// MARK: - API Response Models
struct APIResponse: Codable {
    let data: AnyCodable?
    let error: APIError?
}

struct APIError: Codable, Error {
    let message: String
    let code: Int?
}

// MARK: - SSE (Server-Sent Events) Models
struct SSEEvent {
    let event: String?
    let data: String
    let id: String?
    
    /// Parses the data field as JSON and returns it as a dictionary
    func parseJSONData() throws -> [String: Any]? {
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    }
    
    /// Parses the data field as JSON and returns it as a generic Any type
    func parseData() throws -> Any? {
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: jsonData)
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

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
    private let apiClient: APIClient
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
        
        self.apiClient = APIClient()
        
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
}

// MARK: - API Service
@MainActor
class APIClient: ObservableObject {
    private let session: URLSession
    
    init() {
        // See https://developer.apple.com/documentation/foundation/urlsessionconfiguration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        // Allow streaming connections to continue in background (with limitations)
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true // Wait for network to become available
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Request Building
    /// Builds a URLRequest from the provided parameters
    /// Similar to building a request object in Python's httpx or JavaScript's axios
    nonisolated func buildRequest(
        url: String,
        method: String,
        headers: [String: String]? = nil,
        params: [String: String]? = nil,
        dataDict: [String: Any]? = nil,
        jsonDict: [String: JSONValue]? = nil,
        timeout: Bool? = nil,
        filesDict: [String: Data]? = nil
    ) throws -> URLRequest {
        // Build URL with parameters
        guard var urlComponents = URLComponents(string: url) else {
            throw APIError(message: "Invalid URL: \(url)", code: nil)
        }
        
        if let params = params, !params.isEmpty {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let finalURL = urlComponents.url else {
            throw APIError(message: "Failed to build URL", code: nil)
        }
        
        // Create request
        var request = URLRequest(url: finalURL)
        request.httpMethod = method.uppercased()
        
        // Set headers (auth token should be included in headers if needed)
        let requestHeaders = headers ?? [:]
        
        // Apply headers to request
        for (key, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Set request body
        // Priority: filesDict > jsonDict > dataDict
        // For POST/PUT/PATCH: always send jsonDict if provided (even if empty) to ensure body is present
        let filesDict = filesDict ?? [:]
        let dataDict = dataDict ?? [:]
        let jsonDict = jsonDict ?? [:]
        
        // Convert JSONValue to [String: Any] for JSONSerialization
        let jsonDictAsAny = jsonDict.mapValues { $0.asAny }
        
        if !filesDict.isEmpty {
            // Handle file uploads (multipart form data) - takes priority
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            
            // Add files
            for (key, data) in filesDict {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(key)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
            
            // Add other form fields
            for (key, value) in dataDict {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
            
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body
        } else if method.uppercased() == "POST" || method.uppercased() == "PUT" || method.uppercased() == "PATCH" {
            // For POST/PUT/PATCH: always send jsonDict (even if empty) when provided
            // This ensures endpoints that require a body always get one
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                // Always send jsonDict (even if empty {}) to ensure body is present
                // This is required for endpoints like /signed_in_home that expect a body
                let jsonData = try JSONSerialization.data(withJSONObject: jsonDictAsAny)
                request.httpBody = jsonData
            } catch {
                throw APIError(message: "Failed to serialize JSON: \(error.localizedDescription)", code: nil)
            }
        } else if !dataDict.isEmpty {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: dataDict)
                request.httpBody = jsonData
            } catch {
                throw APIError(message: "Failed to serialize data: \(error.localizedDescription)", code: nil)
            }
        }
        
        // Configure timeout
        if let timeout = timeout, timeout {
            request.timeoutInterval = 10.0
        }
        
        // Debug logging (only in debug builds)
        #if DEBUG
        print("🚀 API Request: \(method.uppercased()) \(url)")
        if let headers = headers {
            // Print a truncated view of the headers (showing up to 2 entries)
            let maxToShow = 2
            let shownHeaders = headers.prefix(maxToShow).map { "\($0.key): \($0.value)" }
            var headersString = shownHeaders.joined(separator: ", ")
            if headers.count > maxToShow {
                headersString += ", ... (\(headers.count - maxToShow) more)"
            }
            // print("📋 Headers: [\(headersString)]")
        }
        if !jsonDict.isEmpty {
            print("📦 JSON Body: \(jsonDictAsAny)")
        }
        if !dataDict.isEmpty {
            print("📦 Data Body: \(dataDict)")
        }
        #endif
        
        return request
    }
    
    // MARK: - SSE Stream Processing
    /// Processes an SSE (Server-Sent Events) stream and yields events to the continuation
    /// Note: This handles both continuous streaming (like LLM) and sparse progress notifications
    /// The connection stays alive during gaps between progress updates
    /// Events are processed immediately when both event type and data are available (Solution 1)
    nonisolated private static func processSSEStream(
        asyncBytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async throws {
        var currentEvent: String?
        var currentData = ""
        var currentId: String?
        var hasEventType = false
        var hasData = false
        var hasYielded = false  // Track if we've already yielded this event
        
        // Helper function to yield event if we have both event type and data
        // Only yields once per event to avoid duplicates from multiple data lines
        func yieldEventIfComplete(force: Bool = false) {
            if hasEventType && hasData && !currentData.isEmpty {
                // Only yield if we haven't already yielded, or if forced (e.g., on empty line or new event)
                if !hasYielded || force {
                    let event = SSEEvent(
                        event: currentEvent,
                        data: currentData,
                        id: currentId
                    )
                    continuation.yield(event)
                    
                    #if DEBUG
                    if let eventName = currentEvent {
                        if hasYielded {
                            print("📨 SSE Event (update): \(eventName)")
                        } else {
                            print("📨 SSE Event (immediate): \(eventName)")
                        }
                    }
                    #endif
                    
                    hasYielded = true
                    
                    // Only reset if forced (empty line or new event type)
                    if force {
                        currentEvent = nil
                        currentData = ""
                        currentId = nil
                        hasEventType = false
                        hasData = false
                        hasYielded = false
                    }
                }
            }
        }
        
        // asyncBytes.lines will wait for lines to arrive, handling long gaps between progress updates
        for try await line in asyncBytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            print("SSE Line: \(trimmedLine)")
            
            // Empty line indicates end of event (force yield and reset)
            if trimmedLine.isEmpty {
                yieldEventIfComplete(force: true)
                continue
            }
            
            // Parse SSE line format: "field: value"
            if let colonIndex = trimmedLine.firstIndex(of: ":") {
                let field = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                
                switch field.lowercased() {
                case "event":
                    // If we see a new event type, yield the previous event first (if it has data)
                    yieldEventIfComplete(force: true)
                    
                    // Set new event type
                    currentEvent = value
                    hasEventType = true
                    hasYielded = false  // Reset yield flag for new event
                    
                case "data":
                    if currentData.isEmpty {
                        currentData = value
                    } else {
                        // Multiple data lines should be concatenated with newline
                        currentData += "\n" + value
                    }
                    hasData = true
                    
                    // If we have both event type and data, yield immediately on first data line
                    // Subsequent data lines will be accumulated but not re-yielded (to avoid duplicates)
                    if hasEventType && !hasYielded {
                        yieldEventIfComplete()
                    }
                    
                case "id":
                    currentId = value
                default:
                    // Ignore unknown fields
                    break
                }
            } else if trimmedLine.hasPrefix(":") {
                // Comment line (often used as keep-alive heartbeat)
                // FastAPI may send ":\n\n" as keep-alive during long operations
                // We ignore these but they help keep the connection alive
                #if DEBUG
                print("💓 SSE Keep-alive heartbeat received")
                #endif
                continue
            }
        }
        
        // Handle any remaining data when stream ends (force yield)
        yieldEventIfComplete(force: true)
        
        #if DEBUG
        print("✅ SSE Stream Completed")
        #endif
        
        continuation.finish()
    }
    
    // MARK: - Async API Call Function (mirrors Python async_call_api)
    nonisolated func asyncCallAPI(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        dataDict: [String: Any] = [:],
        jsonDict: [String: JSONValue] = [:],
        timeout: Bool = false,
        filesDict: [String: Data] = [:]
    ) async throws -> Data {
        // Build the request (like preparing a request object in Python httpx)
        let request = try buildRequest(
            url: url,
            method: method,
            headers: headers,
            params: params,
            dataDict: dataDict,
            jsonDict: jsonDict,
            timeout: timeout,
            filesDict: filesDict
        )
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response - only accept status code 200
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = Self.extractErrorMessage(from: data, statusCode: statusCode)
                #if DEBUG
                print("❌ API Error from \(url): \(errorMessage)")
                #endif
                throw APIError(message: errorMessage, code: statusCode)
            }
            
            #if DEBUG
            print("📊 Response Status from \(url): \(httpResponse.statusCode)")
            #endif
            
            // Return raw data directly
            return data
            
        } catch let apiError as APIError {
            #if DEBUG
            print("❌ API Error from \(url): \(apiError.message)")
            #endif
            throw apiError
        } catch {
            let errorMessage = "Failed to call API at \(url): \(error.localizedDescription)"
            #if DEBUG
            print("❌ Network Error from \(url): \(errorMessage)")
            #endif
            throw APIError(message: errorMessage, code: nil)
        }
    }
    
    // MARK: - Error Message Extraction (mirrors Python _extract_error_message)
    nonisolated private static func extractErrorMessage(from data: Data, statusCode: Int) -> String {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] as? [String: Any] {
                    return error["message"] as? String ?? String(describing: error)
                } else if let message = json["message"] as? String {
                    return message
                } else if let detail = json["detail"] as? String {
                    return detail
                } else {
                    return String(describing: json)
                }
            }
        } catch {
            // If JSON parsing fails, return raw text
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        
        return "HTTP \(statusCode) Error"
    }

    nonisolated func streamAPI(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        params: [String: String]? = nil,
        dataDict: [String: Any]? = nil,
        jsonDict: [String: JSONValue]? = nil,
        timeout: Bool? = nil,
        filesDict: [String: Data]? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        // Build request outside return - all synchronous work
        let request: URLRequest
        do {
            // Merge SSE-specific headers with provided headers
            var mergedHeaders = headers ?? [:]
            mergedHeaders["Accept"] = "text/event-stream"
            mergedHeaders["Cache-Control"] = "no-cache"
            mergedHeaders["Connection"] = "keep-alive"
            
            // Build base request using buildRequest
            var baseRequest = try buildRequest(
                url: url,
                method: method,
                headers: mergedHeaders,
                params: params,
                dataDict: dataDict,
                jsonDict: jsonDict,
                timeout: nil,  // Override below for streaming
                filesDict: filesDict
            )
            
            // Override timeout for streaming (longer timeout for long-running streams)
            // Note: iOS may still suspend connections in background after ~30 seconds
            baseRequest.timeoutInterval = timeout == true ? 10.0 : 300.0
            
            request = baseRequest
        } catch {
            // Return a stream that immediately fails if request building fails
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
        
        // Return stream - only async work inside
        return AsyncThrowingStream { continuation in
            // Capture variables inside closure for Task
            let capturedRequest = request
            let capturedMethod = method
            let capturedUrl = url
            let capturedSession = session
            
            Task.detached {
                do {
                    #if DEBUG
                    print("🌊 Starting SSE Stream: \(capturedMethod.uppercased()) \(capturedUrl)")
                    #endif
                    
                    // Important: iOS will suspend network tasks when app goes to background
                    // The connection will resume when app returns to foreground, but may need reconnection
                    // Consider implementing reconnection logic if streaming is critical in background
                    
                    // Use URLSession.bytes to get streaming response
                    let (asyncBytes, response) = try await capturedSession.bytes(for: capturedRequest)
                    
                    // Validate response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: APIError(message: "Invalid response type", code: nil))
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        var errorData = Data()
                        for try await byte in asyncBytes {
                            errorData.append(byte)
                        }
                        let errorMessage = Self.extractErrorMessage(from: errorData, statusCode: httpResponse.statusCode)
                        continuation.finish(throwing: APIError(message: errorMessage, code: httpResponse.statusCode))
                        return
                    }
                    
                    #if DEBUG
                    print("📡 SSE Stream Connected: Status \(httpResponse.statusCode)")
                    #endif
                    
                    // Process SSE stream
                    try await Self.processSSEStream(
                        asyncBytes: asyncBytes,
                        continuation: continuation
                    )
                    
                } catch let apiError as APIError {
                    #if DEBUG
                    print("❌ SSE Stream Error: \(apiError.message)")
                    #endif
                    continuation.finish(throwing: apiError)
                } catch {
                    let errorMessage = "Failed to stream API at \(url): \(error.localizedDescription)"
                    #if DEBUG
                    print("❌ SSE Network Error: \(errorMessage)")
                    #endif
                    continuation.finish(throwing: APIError(message: errorMessage, code: nil))
                }
            }
        }
    }
}

// MARK: - JSON Response Utilities
extension APIClient {
    
    /// Converts generic JSON response to a specific Codable struct
    /// Usage: let user: User = try apiClient.decodeResponse(response, to: User.self)
    func decodeResponse<T: Codable>(_ response: Any, to type: T.Type) throws -> T {
        // Convert Any to Data first
        let jsonData = try JSONSerialization.data(withJSONObject: response)
        
        // Decode with camelCase conversion
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(type, from: jsonData)
    }
    
    /// Converts generic JSON response to a specific Codable struct (static method)
    /// Usage: let user: User = try APIClient.decodeJSON(response, to: User.self)
    static func decodeJSON<T: Codable>(_ response: Any, to type: T.Type) throws -> T {
        // Convert Any to Data first
        let jsonData = try JSONSerialization.data(withJSONObject: response)
        
        // Decode with camelCase conversion
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(type, from: jsonData)
    }
}

