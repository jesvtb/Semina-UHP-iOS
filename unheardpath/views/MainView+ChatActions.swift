import SwiftUI

// MARK: - Chat Actions
extension TestMainView {
    func sendMessage() {
        guard draftMessage.isEmpty == false else { return }
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        Task {
            await sendChatMessage(text)
        }
        
        draftMessage = ""
        isTextFieldFocused = false // Dismiss keyboard after sending
    }
    
    // MARK: - Chat Message Handling
    @MainActor
    func sendChatMessage(_ messageText: String) async {
        #if DEBUG
        print("🚀 sendChatMessage() called with message: '\(messageText)'")
        #endif
        
        // Validate message is not empty
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            #if DEBUG
            print("⚠️ sendChatMessage: Message is empty after trimming, not sending")
            #endif
            return
        }
        
        // Add user message to chat immediately on main actor
        await MainActor.run {
            let userMessage = ChatMessage(text: trimmedMessage, isUser: true, isStreaming: false)
            messages.append(userMessage)
            // Update lastMessage for the bubble display
            liveUpdateViewModel.updateLastMessage(userMessage)
            #if DEBUG
            print("✅ User message added to chat. Total messages: \(messages.count)")
            #endif
        }
        
        // Create assistant message placeholder for streaming
        await MainActor.run {
            messages.append(ChatMessage(text: "", isUser: false, isStreaming: true))
            #if DEBUG
            print("✅ Assistant placeholder added. Total messages: \(messages.count)")
            #endif
        }
        
        do {
            // Prepare request data - build as [String: JSONValue] from the start
            var jsonDict: [String: JSONValue] = [
                "message": .string(trimmedMessage)
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
            
            #if DEBUG
            print("💬 Preparing API request:")
            print("   Endpoint: /v1/ask")
            print("   Method: POST")
            print("   Message: '\(trimmedMessage)'")
            let jsonDictAsAnyForDebug = jsonDict.mapValues { $0.asAny }
            print("   JSON Dict: \(jsonDictAsAnyForDebug)")
            #endif
            
            // Use streaming API to receive notifications and content
            #if DEBUG
            print("📡 Calling uhpGateway.stream()...")
            #endif

            // Note: We're already in @MainActor context, so accessing uhpGateway is safe
            // Swift 6 strict concurrency warning is a false positive here
            let stream = try await uhpGateway.stream(
                endpoint: "/v1/ask",
                jsonDict: jsonDict
            )
            #if DEBUG
            print("✅ Stream received from uhpGateway.stream()")
            #endif
            
            #if DEBUG
            print("✅ Stream created, starting to process events...")
            #endif
            
            var streamingContent = ""
            
            // Process SSE events from stream
            var eventCount = 0
            for try await event in stream {
                eventCount += 1
                #if DEBUG
                print("📨 SSE Event #\(eventCount) received:")
                print("   Event type: \(event.event ?? "nil")")
                print("   Data: \(event.data.prefix(100))...")
                #endif
                
                await handleChatStreamEvent(event: event, streamingContent: &streamingContent)
            }
            
            // Ensure the final assistant message is marked as not streaming
            await MainActor.run {
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
                    // Update lastMessage for the bubble display
                    liveUpdateViewModel.updateLastMessage(updatedMessage)
                    #if DEBUG
                    print("✅ Stream finished, marked last assistant message as not streaming")
                    #endif
                }
            }
            
            #if DEBUG
            print("✅ Stream processing completed. Total events: \(eventCount)")
            #endif
            
        } catch {
            #if DEBUG
            print("❌ Failed to send chat message:")
            print("   Error: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error localized description: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                print("   API Error message: \(apiError.message)")
                print("   API Error code: \(apiError.code ?? -1)")
            }
            #endif
            
            // Remove the streaming message placeholder on error
            await MainActor.run {
                if let lastIndex = messages.indices.last,
                   !messages[lastIndex].isUser,
                   messages[lastIndex].text.isEmpty {
                    messages.removeLast()
                    #if DEBUG
                    print("✅ Removed empty streaming message placeholder after error")
                    #endif
                }
            }
        }
    }
}

