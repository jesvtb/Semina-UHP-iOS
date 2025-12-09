import SwiftUI

// MARK: - Chat Actions
extension TestMainView {
    /// Validates, sends message, and handles streaming response
    @MainActor
    func sendMessage() async {
        // Extract and validate draft message
        let text = chatState.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            #if DEBUG
            print("⚠️ sendMessage: Message is empty after trimming, not sending")
            #endif
            return
        }
        
        // Clear UI state immediately (good UX - user sees input clear right away)
        chatState.draftMessage = ""
        isTextFieldFocused = false
        
        // Add user message to chat immediately
        let userMessage = ChatMessage(text: text, isUser: true, isStreaming: false)
        chatState.messages.append(userMessage)
        liveUpdateViewModel.updateLastMessage(userMessage)
        
        // Create assistant message placeholder for streaming
        chatState.messages.append(ChatMessage(text: "", isUser: false, isStreaming: true))
        
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
                endpoint: "/v1/ask",
                jsonDict: jsonDict
            )
            
            var streamingContent = ""
            
            // Process SSE events from stream
            for try await event in stream {
                await handleChatStreamEvent(event: event, streamingContent: &streamingContent)
            }
            
            // Ensure the final assistant message is marked as not streaming
            if let lastIndex = chatState.messages.indices.last,
               !chatState.messages[lastIndex].isUser {
                let existingMessage = chatState.messages[lastIndex]
                let updatedMessage = ChatMessage(
                    id: existingMessage.id,
                    text: existingMessage.text,
                    isUser: existingMessage.isUser,
                    isStreaming: false
                )
                chatState.messages[lastIndex] = updatedMessage
                liveUpdateViewModel.updateLastMessage(updatedMessage)
            }
            
        } catch {
            #if DEBUG
            print("❌ Failed to send chat message: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                print("   API Error: \(apiError.message) (code: \(apiError.code ?? -1))")
            }
            #endif
            
            // Remove the streaming message placeholder on error
            if let lastIndex = chatState.messages.indices.last,
               !chatState.messages[lastIndex].isUser,
               chatState.messages[lastIndex].text.isEmpty {
                chatState.messages.removeLast()
            }
        }
    }
}

