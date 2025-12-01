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

class UHPGateway: ObservableObject {
    // Private instance of APIClient configured for internal gateway
    private let apiClient: APIClient
    
    // Pre-configured settings
    private let baseURL: String
    private let defaultHeaders: [String: String]
    
    init(
        baseURL: String = "http://192.168.50.171:1031",  // Your FastAPI gateway
    ) {
        self.baseURL = baseURL
        self.apiClient = APIClient()
        
        // Set default headers (e.g., content type)
        // Note: Auth token is added dynamically in request() method since it's async
        self.defaultHeaders = [
            "Content-Type": "application/json"
        ]
    }
    
    /// Builds headers with access token included
    /// Always retrieves auth token from Supabase for internal gateway requests
    private func buildHeaders() async throws -> [String: String] {
        var headers = defaultHeaders
        
        // Always include auth token from Supabase
        let accessToken = try await supabase.auth.session.accessToken
        headers["Authorization"] = "Bearer \(accessToken)"
        
        return headers
    }
    
    // Simplified request method that automatically adds baseURL and headers
    func request(
        endpoint: String,  // Just the endpoint path, not full URL
        method: String = "POST",
        params: [String: String] = [:],
        jsonDict: [String: Any] = [:]
    ) async throws -> Any {
        // Combine baseURL with endpoint
        let fullURL = "\(baseURL)\(endpoint)"
        
        // Build headers with auth token (always included)
        let headers = try await buildHeaders()
        
        // Use the wrapped APIClient
        // Headers already include auth token from buildHeaders()
        return try await apiClient.asyncCallAPI(
            url: fullURL,
            method: method,
            headers: headers,
            params: params,
            jsonDict: jsonDict
        )
    }

    func stream(
        endpoint: String,
        method: String = "POST",
        params: [String: String] = [:],
        jsonDict: [String: Any] = [:]
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let fullURL = "\(baseURL)\(endpoint)"
        let headers = try await buildHeaders()
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
    private func buildRequest(
        url: String,
        method: String,
        headers: [String: String]?,
        params: [String: String],
        dataDict: [String: Any],
        jsonDict: [String: Any],
        timeout: Bool,
        filesDict: [String: Data]
    ) async throws -> URLRequest {
        // Build URL with parameters
        guard var urlComponents = URLComponents(string: url) else {
            throw APIError(message: "Invalid URL: \(url)", code: nil)
        }
        
        if !params.isEmpty {
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
                let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
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
        if timeout {
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
            print("📦 JSON Body: \(jsonDict)")
        }
        if !dataDict.isEmpty {
            print("📦 Data Body: \(dataDict)")
        }
        #endif
        
        return request
    }
    
    // MARK: - Async API Call Function (mirrors Python async_call_api)
    func asyncCallAPI(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        dataDict: [String: Any] = [:],
        jsonDict: [String: Any] = [:],
        timeout: Bool = false,
        filesDict: [String: Data] = [:]
    ) async throws -> Any {
        // Build the request (like preparing a request object in Python httpx)
        let request = try await buildRequest(
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
            
            // Validate response (like screenshot pattern)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = extractErrorMessage(from: data, statusCode: statusCode)
                #if DEBUG
                print("❌ API Error from \(url): \(errorMessage)")
                #endif
                throw APIError(message: errorMessage, code: statusCode)
            }
            
            #if DEBUG
            print("📊 Response Status from \(url): \(httpResponse.statusCode)")
            #endif
            
            // Parse response with JSONDecoder (like screenshot pattern)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            // For now, return as generic JSON object to maintain compatibility
            let responseData = try JSONSerialization.jsonObject(with: data)
            #if DEBUG
            print("📞 API Response from \(url): \(responseData)")
            #endif
            
            return responseData
            
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
    private func extractErrorMessage(from data: Data, statusCode: Int) -> String {
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

    func streamAPI(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        dataDict: [String: Any] = [:],
        jsonDict: [String: Any] = [:],
        timeout: Bool = false,
        filesDict: [String: Data] = [:],
        includeAuthToken: Bool = false
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Build URL with parameters
                    guard var urlComponents = URLComponents(string: url) else {
                        continuation.finish(throwing: APIError(message: "Invalid URL: \(url)", code: nil))
                        return
                    }
                    
                    if !params.isEmpty {
                        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
                    }
                    
                    guard let finalURL = urlComponents.url else {
                        continuation.finish(throwing: APIError(message: "Failed to build URL", code: nil))
                        return
                    }
                    
                    // Create request
                    var request = URLRequest(url: finalURL)
                    request.httpMethod = method.uppercased()
                    
                    // Set headers - add Accept header for SSE
                    var requestHeaders = headers ?? [:]
                    requestHeaders["Accept"] = "text/event-stream"
                    requestHeaders["Cache-Control"] = "no-cache"
                    requestHeaders["Connection"] = "keep-alive"
                    
                    // Automatically add access token if requested
                    if includeAuthToken {
                        let accessToken = try await supabase.auth.session.accessToken
                        requestHeaders["Authorization"] = "Bearer \(accessToken)"
                    }
                    
                    // Apply headers to request
                    for (key, value) in requestHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    
                    // Set request body (same logic as asyncCallAPI)
                    if !filesDict.isEmpty {
                        let boundary = "Boundary-\(UUID().uuidString)"
                        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                        
                        var body = Data()
                        for (key, data) in filesDict {
                            body.append("--\(boundary)\r\n".data(using: .utf8)!)
                            body.append("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(key)\"\r\n".data(using: .utf8)!)
                            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                            body.append(data)
                            body.append("\r\n".data(using: .utf8)!)
                        }
                        for (key, value) in dataDict {
                            body.append("--\(boundary)\r\n".data(using: .utf8)!)
                            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                            body.append("\(value)\r\n".data(using: .utf8)!)
                        }
                        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                        request.httpBody = body
                    } else if method.uppercased() == "POST" || method.uppercased() == "PUT" || method.uppercased() == "PATCH" {
                        if request.value(forHTTPHeaderField: "Content-Type") == nil {
                            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        }
                        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
                        request.httpBody = jsonData
                    } else if !dataDict.isEmpty {
                        let jsonData = try JSONSerialization.data(withJSONObject: dataDict)
                        request.httpBody = jsonData
                    }
                    
                    // Configure timeout
                    if timeout {
                        request.timeoutInterval = 10.0
                    } else {
                        // For streaming, use longer timeout
                        // Note: iOS may still suspend connections in background after ~30 seconds
                        request.timeoutInterval = 300.0 // 5 minutes for long-running streams
                    }
                    
                    // Important: iOS will suspend network tasks when app goes to background
                    // The connection will resume when app returns to foreground, but may need reconnection
                    // Consider implementing reconnection logic if streaming is critical in background
                    
                    #if DEBUG
                    print("🌊 Starting SSE Stream: \(method.uppercased()) \(url)")
                    #endif
                    
                    // Use URLSession.bytes to get streaming response
                    let (asyncBytes, response) = try await session.bytes(for: request)
                    
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
                        let errorMessage = extractErrorMessage(from: errorData, statusCode: httpResponse.statusCode)
                        continuation.finish(throwing: APIError(message: errorMessage, code: httpResponse.statusCode))
                        return
                    }
                    
                    #if DEBUG
                    print("📡 SSE Stream Connected: Status \(httpResponse.statusCode)")
                    #endif
                    
                    // Parse SSE stream
                    // Note: This handles both continuous streaming (like LLM) and sparse progress notifications
                    // The connection stays alive during gaps between progress updates
                    
                    var currentEvent: String?
                    var currentData = ""
                    var currentId: String?
                    
                    // asyncBytes.lines will wait for lines to arrive, handling long gaps between progress updates
                    for try await line in asyncBytes.lines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        print("SSE Line: \(trimmedLine)")
                        // Empty line indicates end of event
                        if trimmedLine.isEmpty {
                            if !currentData.isEmpty {
                                let event = SSEEvent(
                                    event: currentEvent,
                                    data: currentData,
                                    id: currentId
                                )
                                continuation.yield(event)
                                
                                #if DEBUG
                                if let eventName = currentEvent {
                                    print("📨 SSE Event: \(eventName)")
                                }
                                #endif
                                
                                // Reset for next event
                                currentEvent = nil
                                currentData = ""
                                currentId = nil
                            }
                            continue
                        }
                        
                        // Parse SSE line format: "field: value"
                        if let colonIndex = trimmedLine.firstIndex(of: ":") {
                            let field = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                            let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                            
                            switch field.lowercased() {
                            case "event":
                                // If we see a new event type, yield the previous event first (if it has data)
                                if !currentData.isEmpty {
                                    let event = SSEEvent(
                                        event: currentEvent,
                                        data: currentData,
                                        id: currentId
                                    )
                                    continuation.yield(event)
                                    
                                    #if DEBUG
                                    if let eventName = currentEvent {
                                        print("📨 SSE Event: \(eventName)")
                                    }
                                    #endif
                                    
                                    // Reset for new event
                                    currentData = ""
                                    currentId = nil
                                }
                                currentEvent = value
                            case "data":
                                if currentData.isEmpty {
                                    currentData = value
                                } else {
                                    // Multiple data lines should be concatenated with newline
                                    currentData += "\n" + value
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
                    
                    // Handle any remaining data when stream ends
                    if !currentData.isEmpty {
                        let event = SSEEvent(
                            event: currentEvent,
                            data: currentData,
                            id: currentId
                        )
                        continuation.yield(event)
                    }
                    
                    #if DEBUG
                    print("✅ SSE Stream Completed")
                    #endif
                    
                    continuation.finish()
                    
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
