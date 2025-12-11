import SwiftUI

/// Manages all chat-related state and logic
/// Consolidates ChatState, chat-related LiveUpdateViewModel properties, and chat actions
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - State Properties
    
    // From ChatState
    @Published var messages: [ChatMessage] = []
    @Published var draftMessage: String = ""
    
    // From LiveUpdateViewModel (chat-related only)
    @Published var lastMessage: ChatMessage?
    @Published var currentActivityUpdate: ActivityUpdateData?
    @Published var isMessageExpanded: Bool = false
    
    // MARK: - Dependencies
    private let uhpGateway: UHPGateway
    private let locationManager: LocationManager
    private let userManager: UserManager
    
    // MARK: - Callbacks (for cross-view coordination)
    var onDismissKeyboard: (() -> Void)?
    var onShowInfoSheet: (() -> Void)?
    var onTextFieldFocusChange: ((Bool) -> Void)?
    
    // MARK: - Initialization
    init(
        uhpGateway: UHPGateway,
        locationManager: LocationManager,
        userManager: UserManager
    ) {
        self.uhpGateway = uhpGateway
        self.locationManager = locationManager
        self.userManager = userManager
    }
    
    // MARK: - Message Actions
    
    /// Validates, sends message, and handles streaming response
    func sendMessage() async {
        // Extract and validate draft message
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            #if DEBUG
            print("⚠️ sendMessage: Message is empty after trimming, not sending")
            #endif
            return
        }
        
        // Clear UI state immediately (good UX - user sees input clear right away)
        draftMessage = ""
        onTextFieldFocusChange?(false)
        
        // Add user message to chat immediately
        let userMessage = ChatMessage(text: text, isUser: true, isStreaming: false)
        messages.append(userMessage)
        updateLastMsg(userMessage)
        
        // Create assistant message placeholder for streaming
        messages.append(ChatMessage(text: "", isUser: false, isStreaming: true))
        
        do {
            // Prepare request data - build as [String: JSONValue] from the start
            var jsonDict: [String: JSONValue] = [
                "message": .string(text)
            ]
            
            // Add UTC time in ISO 8601 format
            let now = Date()
            let utcFormatter = ISO8601DateFormatter()
            utcFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            jsonDict["msg_utc"] = .string(utcFormatter.string(from: now))
            
            // Include device timezone identifier (user's current device timezone)
            jsonDict["msg_timezone"] = .string(TimeZone.current.identifier)
            
            // Add user UUID if available
            if let user = userManager.currentUser {
                jsonDict["device_lang"] = .string(user.device_lang)
            }
            
            // Add location details from LocationManager
            // Use empty string if location details are not available
            if let deviceLocationDetails = locationManager.locationDetails {
                jsonDict["last_device_location"] = .dictionary(deviceLocationDetails)
            } else {
                jsonDict["last_device_location"] = .string("")
            }
            
            if let lookupLocationDetails = locationManager.lookupLocationDetails {
                jsonDict["last_lookup_location"] = .dictionary(lookupLocationDetails)
            } else {
                jsonDict["last_lookup_location"] = .string("")
            }
            
            // Note: We're already in @MainActor context, so accessing uhpGateway is safe
            // Swift 6 strict concurrency warning is a false positive here
            let stream = try await uhpGateway.stream(
                endpoint: "/v1/chat",
                jsonDict: jsonDict
            )
            
            var data = ""
            
            // Process SSE events from stream
            for try await event in stream {
                await handleChatStreamEvent(event: event, data: &data)
            }
            
            // Ensure the final assistant message is marked as not streaming
            if let lastIndex = messages.indices.last,
               !messages[lastIndex].isUser {
                let existingMessage = messages[lastIndex]
                let updatedMessage = ChatMessage(
                    id: existingMessage.id,
                    text: existingMessage.text,
                    isUser: existingMessage.isUser,
                    isStreaming: false
                )
                messages[lastIndex] = updatedMessage
                updateLastMsg(updatedMessage)
            }
            
        } catch {
            #if DEBUG
            print("❌ Failed to send chat message: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                print("   API Error: \(apiError.message) (code: \(apiError.code ?? -1))")
            }
            #endif
            
            // Remove the streaming message placeholder on error
            if let lastIndex = messages.indices.last,
               !messages[lastIndex].isUser,
               messages[lastIndex].text.isEmpty {
                messages.removeLast()
            }
        }
    }
    
    // MARK: - LiveUpdateViewModel Methods
    
    /// Dismisses the message bubble and resets expansion state
    func dismissLastMsg() {
        lastMessage = nil
        isMessageExpanded = false
    }
    
    /// Sets a new activity update with animation
    func setActivityUpdate(_ activityUpdate: ActivityUpdateData) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentActivityUpdate = activityUpdate
        }
    }
    
    /// Updates the last message (used when streaming completes)
    func updateLastMsg(_ message: ChatMessage) {
        lastMessage = message
    }
    
    // MARK: - SSE Event Handling
    
    /// Dispatches handling for different SSE event types coming from the chat stream.
    /// Keeps `sendMessage` focused on request/response orchestration while this
    /// function owns the per-event workflows.
    func handleChatStreamEvent(
        event: SSEEvent,
        data: inout String
    ) async {
        let eventType = (event.event ?? "").lowercased()
        
        switch eventType {
        case "notification":
            await handleActivityUpdateEvent(event: event)
            
        case "content":
            await handleContentEvent(event: event, data: &data)
            
        case "finish":
            await handleSSEFinishEvent(event: event)
            
        case "map":
            await handleMapEvent()
            
        case "interface":
            await handleInterfaceEvent(event: event)
            
        default:
            #if DEBUG
            print("⚠️ Unknown or unsupported event type: \(event.event ?? "nil")")
            #endif
        }
    }
    
    /// Handles `finish` SSE events, which signal the end of streaming.
    /// Ensures the progress spinner is stopped and removed from the last
    /// assistant message by setting `isStreaming` to false or dropping an
    /// empty placeholder message.
    private func handleSSEFinishEvent(event: SSEEvent) async {
        #if DEBUG
        print("🏁 Processing finish event")
        print("   Raw data: \(event.data)")
        #endif
        
        await MainActor.run {
            guard let lastIndex = messages.indices.last,
                  !messages[lastIndex].isUser else {
                #if DEBUG
                print("⚠️ No assistant message found to finish")
                #endif
                return
            }
            
            let lastMsg = messages[lastIndex]
            
            if lastMsg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // If it's just an empty streaming placeholder, remove it entirely
                messages.removeLast()
                #if DEBUG
                print("✅ Removed empty streaming assistant placeholder on finish event")
                #endif
            } else {
                // Otherwise, keep the content and just stop streaming
                messages[lastIndex] = ChatMessage(
                    id: lastMsg.id,
                    text: lastMsg.text,
                    isUser: lastMsg.isUser,
                    isStreaming: false
                )
                #if DEBUG
                print("✅ Marked last assistant message as not streaming on finish event")
                #endif
            }
            
            // Update lastMessage for the bubble display
            if let lastMsg = messages.last, !lastMsg.isUser {
                updateLastMsg(lastMsg)
            }
        }
    }
    
    /// Handles `notification` SSE events by parsing the payload and updating
    /// `currentActivityUpdate`. The ActivityUpdateBanner handles its own auto-dismiss.
    /// Note: The SSE event type remains "notification" as it's part of the backend API contract.
    private func handleActivityUpdateEvent(event: SSEEvent) async {
        #if DEBUG
        print("🔔 Processing activity update event (SSE event type: notification)")
        #endif
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                #if DEBUG
                print("⚠️ Failed to parse activity update data as JSON")
                #endif
                return
            }
            
            guard let activityUpdate = ActivityUpdateData(from: dataDict) else {
                #if DEBUG
                print("⚠️ Failed to create activity update from data: \(dataDict)")
                #endif
                return
            }
            
            await MainActor.run {
                #if DEBUG
                print("📬 Activity update received: type=\(activityUpdate.type ?? "nil"), message=\(activityUpdate.message)")
                print("   Setting currentActivityUpdate...")
                #endif
                
                setActivityUpdate(activityUpdate)
                
                #if DEBUG
                print("   currentActivityUpdate set. Value: \(currentActivityUpdate?.message ?? "nil")")
                #endif
                // Note: ActivityUpdateBanner handles its own auto-dismiss
            }
        } catch {
            #if DEBUG
            print("❌ Error handling activity update event: \(error)")
            #endif
        }
    }
    
    /// Handles `content` SSE events by updating the streaming assistant message.
    private func handleContentEvent(
        event: SSEEvent,
        data: inout String
    ) async {
        #if DEBUG
        print("📝 Processing content event")
        #endif
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                #if DEBUG
                print("⚠️ Failed to parse content data as JSON")
                #endif
                return
            }
            
            guard let content = dataDict["content"] as? String else {
                #if DEBUG
                print("⚠️ Content event payload missing 'content' field")
                #endif
                return
            }
            
            data += content
            #if DEBUG
            print("📝 Content chunk received: '\(content)'")
            print("   Total streaming content length: \(data.count)")
            #endif
            
            await MainActor.run {
                if let lastIndex = messages.indices.last,
                   !messages[lastIndex].isUser {
                    let existingMessage = messages[lastIndex]
                    let isStreaming = dataDict["is_streaming"] as? Bool ?? true
                    messages[lastIndex] = ChatMessage(
                        id: existingMessage.id,
                        text: data,
                        isUser: false,
                        isStreaming: isStreaming
                    )
                    #if DEBUG
                    print("✅ Updated assistant message. isStreaming: \(isStreaming)")
                    #endif
                    
                    // Update lastMessage for the bubble display
                    updateLastMsg(messages[lastIndex])
                }
            }
        } catch {
            #if DEBUG
            print("❌ Error handling content event: \(error)")
            #endif
        }
    }
    
    /// Handles `map` SSE events by dismissing the keyboard and resetting
    /// the modal position in `ChatModalView`.
    private func handleMapEvent() async {
        #if DEBUG
        print("🗺️ Processing map event - dismissing keyboard and resetting modal")
        #endif
        
        await MainActor.run {
            onDismissKeyboard?()
        }
    }
    
    /// Handles `interface` SSE events by controlling UI elements like the info sheet.
    /// If message is "show info sheet", sets sheetSnapPoint to .full.
    private func handleInterfaceEvent(event: SSEEvent) async {
        #if DEBUG
        print("🖥️ Processing interface event")
        #endif
        
        do {
            guard let dataDict = try event.parseJSONData() else {
                #if DEBUG
                print("⚠️ Failed to parse interface data as JSON")
                #endif
                return
            }
            
            guard let message = dataDict["message"] as? String else {
                #if DEBUG
                print("⚠️ Interface event payload missing 'message' field")
                #endif
                return
            }
            
            #if DEBUG
            print("🖥️ Interface message received: '\(message)'")
            #endif
            
            await MainActor.run {
                if message.lowercased() == "show info sheet" {
                    #if DEBUG
                    print("📋 Calling onShowInfoSheet callback")
                    #endif
                    
                    onShowInfoSheet?()
                }
            }
        } catch {
            #if DEBUG
            print("❌ Error handling interface event: \(error)")
            #endif
        }
    }
}

