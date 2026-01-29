import Foundation
import Combine

struct APIError: Codable, Error {
    let message: String
    let code: Int?
}

public class APIClient: ObservableObject {
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        // Allow streaming connections to continue in background (with limitations)
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true // Wait for network to become available
        self.session = URLSession(configuration: config)
    }

    public func buildRequest(
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

        if !dataDict.isEmpty {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: dataDict)
                request.httpBody = jsonData
            } catch {
                throw APIError(message: "Failed to serialize data: \(error.localizedDescription)", code: nil)
            }
        }

        if method.uppercased().contains("POST") || method.uppercased().contains("PUT") || method.uppercased().contains("PATCH") {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: jsonDictAsAny)
                request.httpBody = jsonData
            } catch {
                throw APIError(message: "Failed to serialize JSON: \(error.localizedDescription)", code: nil)
            }
        }

        // Configure timeout
        if let timeout = timeout, timeout {
            request.timeoutInterval = 10.0
        }
        
        
        return request
    }
}