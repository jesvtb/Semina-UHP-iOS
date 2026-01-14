import Foundation

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
        #if DEBUG
        print("⚠️ Failed to parse map event data as JSON: \(error.localizedDescription)")
        #endif
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
    
    init(
        onToast: ((ToastData) async -> Void)? = nil,
        onChatChunk: ((String, Bool) async -> Void)? = nil,
        onStop: (() async -> Void)? = nil,
        onMap: (([[String: JSONValue]]) async -> Void)? = nil,
        onHook: ((String) async -> Void)? = nil
    ) {
        self.onToastHandler = onToast
        self.onChatChunkHandler = onChatChunk
        self.onStopHandler = onStop
        self.onMapHandler = onMap
        self.onHookHandler = onHook
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
}

/// Default implementations (no-op) so implementers only need to override what they need
extension SSEEventHandler {
    func onToast(_ toast: ToastData) async {}
    func onChatChunk(content: String, isStreaming: Bool) async {}
    func onStop() async {}
    func onMap(features: [[String: JSONValue]]) async {}
    func onHook(action: String) async {}
}

/// Unified SSE event processor that routes events to appropriate handlers
/// Centralizes parsing logic and ensures consistent handling across endpoints
@MainActor
class SSEEventProcessor {
    weak var handler: SSEEventHandler?
    
    init(handler: SSEEventHandler) {
        self.handler = handler
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
            
        default:
            #if DEBUG
            print("⚠️ Unknown or unsupported event type: \(event.event ?? "nil")")
            #endif
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
        #if DEBUG
        print("🔔 Processing toast event")
        #endif
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                #if DEBUG
                print("⚠️ Failed to parse toast data as JSON")
                #endif
                return
            }
            
            guard let toastData = ToastData(from: dataDict) else {
                #if DEBUG
                print("⚠️ Failed to create toast from data: \(dataDict)")
                #endif
                return
            }
            
            await handler?.onToast(toastData)
        } catch {
            #if DEBUG
            print("❌ Error handling toast event: \(error)")
            #endif
        }
    }
    
    /// Handles chat events by accumulating content and delegating to handler
    private func handleChatEvent(_ event: SSEEvent, accumulatedData: inout String) async {
        // #if DEBUG
        // print("📝 Processing chat event")
        // #endif
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                #if DEBUG
                print("⚠️ Failed to parse chat data as JSON")
                #endif
                return
            }
            
            guard let content = dataDict["content"] as? String else {
                #if DEBUG
                print("⚠️ Content event payload missing 'content' field")
                #endif
                return
            }
            
            accumulatedData += content
            let isStreaming = dataDict["is_streaming"] as? Bool ?? true
            
            // #if DEBUG
            // print("📝 Content chunk received: '\(content)'")
            // print("   Total streaming content length: \(accumulatedData.count)")
            // #endif
            
            await handler?.onChatChunk(content: accumulatedData, isStreaming: isStreaming)
        } catch {
            #if DEBUG
            print("❌ Error handling chat event: \(error)")
            #endif
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
            #if DEBUG
            print("⚠️ Failed to parse map event features, skipping handler")
            #endif
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
        #if DEBUG
        print("🖥️ Processing hook event")
        #endif
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                #if DEBUG
                print("⚠️ Failed to parse hook data as JSON")
                #endif
                return
            }
            
            guard let action = dataDict["action"] as? String else {
                #if DEBUG
                print("⚠️ Hook event payload missing 'action' field")
                #endif
                return
            }
            
            #if DEBUG
            print("🖥️ Hook action received: '\(action)'")
            #endif
            
            await handler?.onHook(action: action)
        } catch {
            #if DEBUG
            print("❌ Error handling hook event: \(error)")
            #endif
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
