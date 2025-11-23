//
//  APIService.swift
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

// MARK: - API Service
class APIService: ObservableObject {
    static let shared = APIService()
    
    private let session: URLSession
    
    init() {
        // Create a custom URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
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
        filesDict: [String: Data] = [:],
        includeAuthToken: Bool = false
    ) async throws -> Any {
        
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
        
        // Set headers
        var requestHeaders = headers ?? [:]
        
        // Automatically add access token if requested
        if includeAuthToken {
            let accessToken = try await supabase.auth.session.accessToken
            requestHeaders["Authorization"] = "Bearer \(accessToken)"
        }

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
            print("📋 Headers: \(headers)")
        }
        if !jsonDict.isEmpty {
            print("📦 JSON Body: \(jsonDict)")
        }
        if !dataDict.isEmpty {
            print("📦 Data Body: \(dataDict)")
        }
        #endif
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response (like screenshot pattern)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = extractErrorMessage(from: data, statusCode: statusCode)
                #if DEBUG
                print("❌ API Error: \(errorMessage)")
                #endif
                throw APIError(message: errorMessage, code: statusCode)
            }
            
            #if DEBUG
            print("📊 Response Status: \(httpResponse.statusCode)")
            #endif
            
            // Parse response with JSONDecoder (like screenshot pattern)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            // For now, return as generic JSON object to maintain compatibility
            let responseData = try JSONSerialization.jsonObject(with: data)
            #if DEBUG
            print("✅ API Response: \(responseData)")
            #endif
            
            return responseData
            
        } catch let apiError as APIError {
            #if DEBUG
            print("❌ API Error: \(apiError.message)")
            #endif
            throw apiError
        } catch {
            let errorMessage = "Failed to call API at \(url): \(error.localizedDescription)"
            #if DEBUG
            print("❌ Network Error: \(errorMessage)")
            #endif
            throw APIError(message: errorMessage, code: nil)
        }
    }
    
    // MARK: - Decoded JSON API Call (Handles camelCase conversion, returns generic JSON)
    func asyncCallAPIDecoded(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        dataDict: [String: Any] = [:],
        jsonDict: [String: Any] = [:],
        timeout: Bool = false,
        filesDict: [String: Data] = [:]
    ) async throws -> Any {
        
        // Build URL with parameters
        guard var urlComponents = URLComponents(string: url) else {
            throw APIError(message: "Invalid URL: \(url)", code: nil)
        }
        
        if !params.isEmpty {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let finalURL = urlComponents.url else {
            throw APIError(message: "Failed to build URL with parameters", code: nil)
        }
        
        // Create request
        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        
        // Add headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Add body data
        if !jsonDict.isEmpty {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict)
        } else if !dataDict.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let formData = dataDict.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = formData.data(using: .utf8)
        }
        
        // Add files if any
        if !filesDict.isEmpty {
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = createMultipartBody(files: filesDict, boundary: boundary)
        }
        
        // Configure timeout
        if timeout {
            request.timeoutInterval = 30.0
        }
        
        #if DEBUG
        print("🚀 API Request: \(method.uppercased()) \(url)")
        if let headers = headers {
            print("📋 Headers: \(headers)")
        }
        if !jsonDict.isEmpty {
            print("📦 JSON Body: \(jsonDict)")
        }
        if !dataDict.isEmpty {
            print("📦 Data Body: \(dataDict)")
        }
        #endif
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response (like screenshot pattern)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = extractErrorMessage(from: data, statusCode: statusCode)
                #if DEBUG
                print("❌ API Error: \(errorMessage)")
                #endif
                throw APIError(message: errorMessage, code: statusCode)
            }
            
            #if DEBUG
            print("📊 Response Status: \(httpResponse.statusCode)")
            #endif
            
            // Decode JSON with camelCase conversion (like screenshot pattern)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            // Decode to generic JSON object
            let responseData = try JSONSerialization.jsonObject(with: data)
            #if DEBUG
            print("✅ API Response: \(responseData)")
            #endif
            
            return responseData
            
        } catch let apiError as APIError {
            #if DEBUG
            print("❌ API Error: \(apiError.message)")
            #endif
            throw apiError
        } catch {
            let errorMessage = "Failed to call API at \(url): \(error.localizedDescription)"
            #if DEBUG
            print("❌ Network Error: \(errorMessage)")
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
    
    // MARK: - Multipart Body Creation
    private func createMultipartBody(files: [String: Data], boundary: String) -> Data {
        var body = Data()
        
        for (key, data) in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(key)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

// MARK: - JSON Response Utilities
extension APIService {
    
    /// Converts generic JSON response to a specific Codable struct
    /// Usage: let user: User = try apiService.decodeResponse(response, to: User.self)
    func decodeResponse<T: Codable>(_ response: Any, to type: T.Type) throws -> T {
        // Convert Any to Data first
        let jsonData = try JSONSerialization.data(withJSONObject: response)
        
        // Decode with camelCase conversion
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(type, from: jsonData)
    }
    
    /// Converts generic JSON response to a specific Codable struct (static method)
    /// Usage: let user: User = try APIService.decodeJSON(response, to: User.self)
    static func decodeJSON<T: Codable>(_ response: Any, to type: T.Type) throws -> T {
        // Convert Any to Data first
        let jsonData = try JSONSerialization.data(withJSONObject: response)
        
        // Decode with camelCase conversion
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(type, from: jsonData)
    }
}
