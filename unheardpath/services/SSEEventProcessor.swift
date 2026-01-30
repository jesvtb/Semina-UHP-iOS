import Foundation
import SwiftUI
import CoreLocation
import core

/// Type alias for GeoJSON features array
typealias GeoJSONFeatures = [[String: JSONValue]]

/// Helper function to parse GeoJSON features (can be called from Task.detached)
private func parseGeoJSONFeatures(from dataString: String) -> GeoJSONFeatures? {
    let trimmedData = dataString.trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard !trimmedData.isEmpty,
          let jsonData = trimmedData.data(using: .utf8) else {
        return nil
    }
    
    let jsonObject: Any
    do {
        jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
    } catch {
        // Note: This is a private helper function, so we can't use logger here
        // The error will be handled by the caller (handleMapEvent)
        return nil
    }
    
    guard let geojsonValue = JSONValue(from: jsonObject) else {
        return nil
    }
    
    guard case .array(let featuresArray) = geojsonValue else {
        return nil
    }
    
    // Use shared helper function to extract features
    let features = extractFeaturesFromArray(featuresArray)
    
    return features.isEmpty ? nil : features
}

/// Protocol for handling specific SSE event types
/// Implementers can choose which events they want to handle
/// Note: For struct types (like View), use SSEEventHandlerWrapper
@MainActor
protocol SSEEventHandler: AnyObject {
    /// Handle "toast" events
    func onToast(_ toast: ToastData) async
    
    /// Handle "chat" events (content streaming)
    /// - Parameters:
    ///   - content: Content chunk received
    ///   - isStreaming: Whether streaming is still in progress
    func onChatChunk(content: String, isStreaming: Bool) async
    
    /// Handle "stop" events, which signal the end of streaming
    func onStop() async
    
    /// Handle "map" events with parsed GeoJSON features
    /// - Parameter features: Array of GeoJSON feature dictionaries
    func onMap(features: [[String: JSONValue]]) async
    
    /// Handle "hook" events
    /// - Parameter action: Action string from hook event
    func onHook(action: String) async
    
    /// Handle "content" events (overview, location details, POIs)
    /// - Parameters:
    ///   - type: Content view type (overview, locationDetail, pointsOfInterest)
    ///   - data: Content section data
    func onContent(type: ContentViewType, data: ContentSection.ContentSectionData) async
}

/// Wrapper class to allow struct types (like View) to act as SSE event handlers
/// This enables weak references while allowing structs to conform to the handler pattern
@MainActor
class SSEEventHandlerWrapper: SSEEventHandler {
    private let onToastHandler: ((ToastData) async -> Void)?
    private let onChatChunkHandler: ((String, Bool) async -> Void)?
    private let onStopHandler: (() async -> Void)?
    private let onMapHandler: (([[String: JSONValue]]) async -> Void)?
    private let onHookHandler: ((String) async -> Void)?
    private let onContentHandler: ((ContentViewType, ContentSection.ContentSectionData) async -> Void)?
    
    init(
        onToast: ((ToastData) async -> Void)? = nil,
        onChatChunk: ((String, Bool) async -> Void)? = nil,
        onStop: (() async -> Void)? = nil,
        onMap: (([[String: JSONValue]]) async -> Void)? = nil,
        onHook: ((String) async -> Void)? = nil,
        onContent: ((ContentViewType, ContentSection.ContentSectionData) async -> Void)? = nil
    ) {
        self.onToastHandler = onToast
        self.onChatChunkHandler = onChatChunk
        self.onStopHandler = onStop
        self.onMapHandler = onMap
        self.onHookHandler = onHook
        self.onContentHandler = onContent
    }
    
    func onToast(_ toast: ToastData) async {
        await onToastHandler?(toast)
    }
    
    func onChatChunk(content: String, isStreaming: Bool) async {
        await onChatChunkHandler?(content, isStreaming)
    }
    
    func onStop() async {
        await onStopHandler?()
    }
    
    func onMap(features: [[String: JSONValue]]) async {
        await onMapHandler?(features)
    }
    
    func onHook(action: String) async {
        await onHookHandler?(action)
    }
    
    func onContent(type: ContentViewType, data: ContentSection.ContentSectionData) async {
        await onContentHandler?(type, data)
    }
}

/// Default implementations (no-op) so implementers only need to override what they need
extension SSEEventHandler {
    func onToast(_ toast: ToastData) async {}
    func onChatChunk(content: String, isStreaming: Bool) async {}
    func onStop() async {}
    func onMap(features: [[String: JSONValue]]) async {}
    func onHook(action: String) async {}
    func onContent(type: ContentViewType, data: ContentSection.ContentSectionData) async {}
}

/// Unified SSE event processor that routes events to appropriate handlers
/// Centralizes parsing logic and ensures consistent handling across endpoints
@MainActor
class SSEEventProcessor {
    weak var handler: SSEEventHandler?
    // Store logger for MainActor methods, but use shared logger directly in nonisolated methods
    private let logger: Logger
    
    init(handler: SSEEventHandler, logger: Logger = AppLifecycleManager.sharedLogger) {
        self.handler = handler
        self.logger = logger
    }
    
    /// Process a single SSE event and route it to the appropriate handler
    /// - Parameters:
    ///   - event: SSEEvent to process
    ///   - accumulatedData: Accumulated chat content (for streaming chat events)
    nonisolated func processEvent(_ event: SSEEvent, accumulatedData: inout String) async {
        let eventType = (event.event ?? "").lowercased()
        
        switch eventType {
        case "toast":
            await handleToastEvent(event)
            
        case "chat":
            await handleChatEvent(event, accumulatedData: &accumulatedData)
            
        case "stop":
            await handleStopEvent()
            
        case "map":
            await handleMapEvent(event)
            
        case "hook":
            await handleHookEvent(event)
            
        case "overview", "content":  // Support both specific and generic names
            await handleContentEvent(event)
            
        default:
            // Use shared logger directly in nonisolated context
            AppLifecycleManager.sharedLogger.warning("Unknown or unsupported event type: \(event.event ?? "nil")", handlerType: "SSEEventProcessor")
        }
    }
    
    /// Process a stream of SSE events
    /// - Parameter stream: AsyncThrowingStream of SSEEvent
    nonisolated func processStream(_ stream: AsyncThrowingStream<SSEEvent, Error>) async throws {
        var accumulatedData = ""
        
        for try await event in stream {
            await processEvent(event, accumulatedData: &accumulatedData)
        }
    }
    
    // MARK: - Private Event Handlers
    
    /// Handles toast events by parsing and delegating to handler
    private func handleToastEvent(_ event: SSEEvent) async {
        logger.debug("Processing toast event")
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                logger.warning("Failed to parse toast data as JSON", handlerType: "SSEEventProcessor")
                return
            }
            
            guard let toastData = ToastData(from: dataDict) else {
                logger.warning("Failed to create toast from data: \(dataDict)", handlerType: "SSEEventProcessor")
                return
            }
            
            await handler?.onToast(toastData)
        } catch {
            logger.error("Error handling toast event", handlerType: "SSEEventProcessor", error: error)
        }
    }
    
    /// Handles chat events by accumulating content and delegating to handler
    private func handleChatEvent(_ event: SSEEvent, accumulatedData: inout String) async {
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                logger.warning("Failed to parse chat data as JSON", handlerType: "SSEEventProcessor")
                return
            }
            
            guard let content = dataDict["content"] as? String else {
                logger.warning("Content event payload missing 'content' field. Available keys: \(dataDict.keys.joined(separator: ", "))", handlerType: "SSEEventProcessor")
                return
            }
            
            accumulatedData += content
            let isStreaming = dataDict["is_streaming"] as? Bool ?? true
            
            guard let handler = handler else {
                logger.warning("handleChatEvent: Handler is nil, cannot route chat chunk", handlerType: "SSEEventProcessor")
                return
            }
            
            await handler.onChatChunk(content: accumulatedData, isStreaming: isStreaming)
        } catch {
            logger.error("Error handling chat event", handlerType: "SSEEventProcessor", error: error)
        }
    }
    
    /// Handles stop events by delegating to handler
    private func handleStopEvent() async {
        // #if DEBUG
        // print("🏁 Processing stop event")
        // #endif
        
        await handler?.onStop()
    }
    
    /// Handles map events by parsing GeoJSON off-main, then delegating to handler
    nonisolated private func handleMapEvent(_ event: SSEEvent) async {
        // Parse GeoJSON features off the main actor using Task.detached
        // This ensures heavy JSON parsing doesn't block the main actor
        // Inline parsing to avoid isolation/Sendable issues
        let eventData = event.data
        let parsedFeatures = await Task.detached(priority: .userInitiated) {
            parseGeoJSONFeatures(from: eventData)
        }.value
        
        guard let features = parsedFeatures, !features.isEmpty else {
            // Use shared logger directly in nonisolated context
            AppLifecycleManager.sharedLogger.warning("Failed to parse map event features, skipping handler", handlerType: "SSEEventProcessor")
            return
        }
        
        // Delegate to handler on main actor
        // Access handler through MainActor isolation - handler methods are @MainActor so await handles the hop
        await MainActor.run {
            if let handler = self.handler {
                Task { @MainActor in
                    await handler.onMap(features: features)
                }
            }
        }
    }
    
    /// Handles hook events by parsing and delegating to handler
    private func handleHookEvent(_ event: SSEEvent) async {
        logger.debug("Processing hook event")
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                logger.warning("Failed to parse hook data as JSON", handlerType: "SSEEventProcessor")
                return
            }
            
            guard let action = dataDict["action"] as? String else {
                logger.warning("Hook event payload missing 'action' field", handlerType: "SSEEventProcessor")
                return
            }
            
            logger.debug("Hook action received: '\(action)'")
            
            await handler?.onHook(action: action)
        } catch {
            logger.error("Error handling hook event", handlerType: "SSEEventProcessor", error: error)
        }
    }
    
    /// Handles content events (overview, location details, POIs)
    private func handleContentEvent(_ event: SSEEvent) async {
        logger.debug("Processing content event")
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                logger.warning("Failed to parse content data as JSON", handlerType: "SSEEventProcessor")
                return
            }
            
            guard let typeString = dataDict["type"] as? String else {
                logger.warning("Content event payload missing 'type' field", handlerType: "SSEEventProcessor")
                return
            }
            
            guard let contentType = ContentViewType(rawValue: typeString) else {
                logger.warning("Unknown content type: \(typeString)", handlerType: "SSEEventProcessor")
                return
            }
            
            guard let dataValue = dataDict["data"] else {
                logger.warning("Content event payload missing 'data' field", handlerType: "SSEEventProcessor")
                return
            }
            
            // Parse data using ContentTypeRegistry
            // Note: parse method is @MainActor, so we need to call from main actor context
            let contentData = await MainActor.run {
                ContentTypeRegistry.shared().parse(type: contentType, dataValue: dataValue)
            }
            
            guard let contentData = contentData else {
                logger.warning("Failed to parse content type: \(contentType.rawValue)", handlerType: "SSEEventProcessor")
                return
            }
            
            await handler?.onContent(type: contentType, data: contentData)
            
            logger.debug("Content event handled: \(contentType.rawValue)")
        } catch {
            logger.error("Error handling content event", handlerType: "SSEEventProcessor", error: error)
        }
    }
}

// MARK: - Helper Functions

/// Extracts GeoJSON features from a JSONValue array
/// Shared helper to avoid duplicate parsing logic
/// - Parameter featuresArray: Array of JSONValue items (should be dictionaries)
/// - Returns: Array of feature dictionaries, or empty array if parsing fails
private func extractFeaturesFromArray(_ featuresArray: [JSONValue]) -> [[String: JSONValue]] {
    return featuresArray.compactMap { featureValue -> [String: JSONValue]? in
        guard case .dictionary(let featureDict) = featureValue else {
            return nil
        }
        return featureDict
    }
}
