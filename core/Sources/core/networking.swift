//
//  networking.swift
//  core
//

import Foundation

// MARK: - API Error

public struct APIError: Codable, Error, Sendable {
    public let message: String
    public let code: Int?

    public init(message: String, code: Int?) {
        self.message = message
        self.code = code
    }
}

// MARK: - SSE (Server-Sent Events) Models

public enum ParseError: Error, Sendable {
    case missingField(String)
    case invalidFormat(String)
}

/// Typed SSE event: one case per event kind with parsed payload. Stream and router use this type only.
public enum SSEEvent: Sendable {
    case toast(message: String, duration: TimeInterval?, variant: String?)
    /// chatId: backend-provided chat UUID string; maps to ChatMessage.id when present.
    case chat(chatId: String?, chunk: String, isStreaming: Bool)
    case stop
    case map(features: [[String: JSONValue]])
    case hook(action: String)
    case catalogue(typeString: String, dataValue: JSONValue)
}

public enum SSEEventType: String, Sendable {
    case toast
    case chat
    case stop
    case map
    case hook
    case catalogue

    public init?(from eventString: String?) {
        guard let normalized = eventString?.lowercased() else { return nil }
        self.init(rawValue: normalized)
    }

    /// Parse raw SSE fields into a typed event. Used by the stream and by single-event callers.
    public func parse(event eventString: String?, data dataString: String, id: String?) throws -> SSEEvent {
        let dataDict = JSONValue.decode(dataString)?.dictionaryValue
        switch self {
        case .toast:
            guard let dict = dataDict,
                  let message = dict["message"]?.stringValue else {
                throw ParseError.missingField("message")
            }
            let duration = dict["duration"]?.doubleValue
            let variant = dict["variant"]?.stringValue
            return .toast(message: message, duration: duration, variant: variant)

        case .chat:
            guard let dict = dataDict,
                  let content = dict["content"]?.stringValue else {
                throw ParseError.missingField("content")
            }
            let isStreaming = dict["is_streaming"]?.boolValue ?? true
            // Prefer chat_id from payload; fall back to SSE id line if present.
            let chatId = dict["chat_id"]?.stringValue ?? id
            return .chat(chatId: chatId, chunk: content, isStreaming: isStreaming)

        case .stop:
            return .stop

        case .map:
            guard let data = dataString.data(using: .utf8) else {
                throw ParseError.invalidFormat("Cannot convert data to UTF-8")
            }
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            let features: [[String: JSONValue]]
            if let array = jsonObject as? [[String: Any]] {
                features = try GeoJSON.extractFeatures(from: array)
            } else if let dict = jsonObject as? [String: Any] {
                features = try GeoJSON.extractFeatures(from: dict)
            } else {
                throw ParseError.invalidFormat("Map data is not an array of features or a FeatureCollection object")
            }
            return .map(features: features)

        case .hook:
            guard let dict = dataDict,
                  let action = dict["action"]?.stringValue else {
                throw ParseError.missingField("action")
            }
            return .hook(action: action)

        case .catalogue:
            guard let dict = dataDict,
                  let section = dict["section"]?.stringValue else {
                throw ParseError.missingField("section")
            }
            // Pass entire data dict - router extracts action, display_title, content (with per-item _metadata)
            let dataValue = JSONValue.decode(dataString) ?? .dictionary([:])
            return .catalogue(typeString: section, dataValue: dataValue)
        }
    }

}

// MARK: - APIClient

public final class APIClient: Sendable {
    private let session: URLSession
    private let logger: Logger

    public init(logger: Logger? = nil) {
        self.logger = logger ?? NoOpLogger()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Request Building

    /// Builds a URLRequest from the provided parameters.
    nonisolated public func buildRequest(
        url: String,
        method: String,
        headers: [String: String]? = nil,
        params: [String: String]? = nil,
        dataDict: [String: Any]? = nil,
        jsonDict: [String: JSONValue]? = nil,
        timeout: Bool? = nil,
        filesDict: [String: Data]? = nil
    ) throws -> URLRequest {
        guard var urlComponents = URLComponents(string: url) else {
            throw APIError(message: "Invalid URL: \(url)", code: nil)
        }

        if let params = params, !params.isEmpty {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let finalURL = urlComponents.url else {
            throw APIError(message: "Failed to build URL", code: nil)
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method.uppercased()

        let requestHeaders = headers ?? [:]
        for (key, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let filesDict = filesDict ?? [:]
        let dataDict = dataDict ?? [:]
        let jsonDict = jsonDict ?? [:]
        let jsonDictAsAny = jsonDict.mapValues { $0.asAny }

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
            do {
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

        if let timeout = timeout, timeout {
            request.timeoutInterval = 10.0
        }

        #if DEBUG
        logger.debug("API Request: \(method.uppercased()) \(url)")
        if !jsonDict.isEmpty {
            logger.debug("JSON Body: \(jsonDictAsAny)")
        }
        if !dataDict.isEmpty {
            logger.debug("Data Body: \(dataDict)")
        }
        #endif

        return request
    }

    // MARK: - SSE Stream Processing

    nonisolated private static func processSSEStream(
        asyncBytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
        logger: Logger
    ) async throws {
        var currentEvent: String?
        var currentData = ""
        var currentId: String?
        var hasEventType = false
        var hasData = false
        var hasYielded = false
        var lastYieldedData = ""

        func yieldPayloadIfComplete(force: Bool = false) {
            guard hasEventType, hasData, !currentData.isEmpty else { return }
            let dataChanged = currentData != lastYieldedData
            guard !hasYielded || dataChanged else {
                if force {
                    currentEvent = nil
                    currentData = ""
                    currentId = nil
                    hasEventType = false
                    hasData = false
                    hasYielded = false
                    lastYieldedData = ""
                }
                return
            }
            guard let eventType = SSEEventType(from: currentEvent) else {
                logger.warning("Unknown SSE event type: \(currentEvent ?? "nil")", handlerType: "APIClient")
                lastYieldedData = currentData
                hasYielded = true
                if force {
                    currentEvent = nil
                    currentData = ""
                    currentId = nil
                    hasEventType = false
                    hasData = false
                    hasYielded = false
                    lastYieldedData = ""
                }
                return
            }
            do {
                let event = try eventType.parse(event: currentEvent, data: currentData, id: currentId)
                continuation.yield(event)
            } catch {
                logger.error("SSE parse error for \(eventType.rawValue): \(error)", handlerType: "APIClient", error: error)
            }
            lastYieldedData = currentData
            hasYielded = true
            if force {
                currentEvent = nil
                currentData = ""
                currentId = nil
                hasEventType = false
                hasData = false
                hasYielded = false
                lastYieldedData = ""
            }
        }

        for try await line in asyncBytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.isEmpty {
                if hasEventType && hasData && !currentData.isEmpty {
                    let dataChanged = currentData != lastYieldedData
                    if !hasYielded || dataChanged {
                        yieldPayloadIfComplete(force: true)
                    } else {
                        currentEvent = nil
                        currentData = ""
                        currentId = nil
                        hasEventType = false
                        hasData = false
                        hasYielded = false
                        lastYieldedData = ""
                    }
                } else {
                    currentEvent = nil
                    currentData = ""
                    currentId = nil
                    hasEventType = false
                    hasData = false
                    hasYielded = false
                    lastYieldedData = ""
                }
                continue
            }

            if let colonIndex = trimmedLine.firstIndex(of: ":") {
                let field = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

                switch field.lowercased() {
                case "event":
                    if hasEventType && hasData && !currentData.isEmpty && !hasYielded {
                        yieldPayloadIfComplete(force: true)
                    } else {
                        currentEvent = nil
                        currentData = ""
                        currentId = nil
                        hasEventType = false
                        hasData = false
                        hasYielded = false
                        lastYieldedData = ""
                    }
                    currentEvent = value
                    hasEventType = true
                    hasYielded = false
                    lastYieldedData = ""

                case "data":
                    if currentData.isEmpty {
                        currentData = value
                    } else {
                        currentData += "\n" + value
                    }
                    hasData = true
                    if hasEventType && !hasYielded {
                        yieldPayloadIfComplete()
                    }

                case "id":
                    currentId = value
                default:
                    break
                }
            } else if trimmedLine.hasPrefix(":") {
                continue
            }
        }

        yieldPayloadIfComplete(force: true)
        logger.debug("SSE Stream Completed")
        continuation.finish()
    }

    // MARK: - Async API Call

    nonisolated public func asyncCallAPI(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        dataDict: [String: Any] = [:],
        jsonDict: [String: JSONValue] = [:],
        timeout: Bool = false,
        filesDict: [String: Data] = [:]
    ) async throws -> Data {
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

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = Self.extractErrorMessage(from: data, statusCode: statusCode)
                logger.error("API Error from \(url): \(errorMessage)", handlerType: "APIClient", error: nil)
                throw APIError(message: errorMessage, code: statusCode)
            }

            logger.debug("Response Status from \(url): \(httpResponse.statusCode)")
            return data

        } catch let apiError as APIError {
            logger.error("API Error from \(url): \(apiError.message)", handlerType: "APIClient", error: apiError)
            throw apiError
        } catch {
            let errorMessage = "Failed to call API at \(url): \(error.localizedDescription)"
            logger.error("Network Error from \(url): \(errorMessage)", handlerType: "APIClient", error: error)
            throw APIError(message: errorMessage, code: nil)
        }
    }

    // MARK: - Error Message Extraction

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
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        return "HTTP \(statusCode) Error"
    }

    // MARK: - Stream API

    nonisolated public func streamAPI(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        params: [String: String]? = nil,
        dataDict: [String: Any]? = nil,
        jsonDict: [String: JSONValue]? = nil,
        timeout: Bool? = nil,
        filesDict: [String: Data]? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let request: URLRequest
        do {
            var mergedHeaders = headers ?? [:]
            mergedHeaders["Accept"] = "text/event-stream"
            mergedHeaders["Cache-Control"] = "no-cache"
            mergedHeaders["Connection"] = "keep-alive"

            var baseRequest = try buildRequest(
                url: url,
                method: method,
                headers: mergedHeaders,
                params: params,
                dataDict: dataDict,
                jsonDict: jsonDict,
                timeout: nil,
                filesDict: filesDict
            )
            baseRequest.timeoutInterval = timeout == true ? 10.0 : 300.0
            request = baseRequest
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        return AsyncThrowingStream { continuation in
            let capturedRequest = request
            let capturedSession = session
            let capturedLogger = logger
            let capturedUrl = url
            let capturedMethod = method

            Task.detached {
                do {
                    capturedLogger.debug("Starting SSE Stream: \(capturedMethod.uppercased()) \(capturedUrl)")

                    let (asyncBytes, response) = try await capturedSession.bytes(for: capturedRequest)

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

                    capturedLogger.debug("SSE Stream Connected: Status \(httpResponse.statusCode)")

                    try await Self.processSSEStream(
                        asyncBytes: asyncBytes,
                        continuation: continuation,
                        logger: capturedLogger
                    )

                } catch let apiError as APIError {
                    capturedLogger.error("SSE Stream Error: \(apiError.message)", handlerType: "APIClient", error: apiError)
                    continuation.finish(throwing: apiError)
                } catch {
                    let errorMessage = "Failed to stream API at \(url): \(error.localizedDescription)"
                    capturedLogger.error("SSE Network Error: \(errorMessage)", handlerType: "APIClient", error: error)
                    continuation.finish(throwing: APIError(message: errorMessage, code: nil))
                }
            }
        }
    }
}

// MARK: - JSON Response Utilities

public extension APIClient {
    /// Converts generic JSON response to a specific Codable type.
    func decodeResponse<T: Codable>(_ response: Any, to type: T.Type) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: jsonData)
    }

    /// Converts generic JSON response to a specific Codable type (static).
    static func decodeJSON<T: Codable>(_ response: Any, to type: T.Type) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: jsonData)
    }
}
