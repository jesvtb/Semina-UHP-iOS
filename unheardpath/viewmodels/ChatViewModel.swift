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
    @Published var isMessageExpanded: Bool = false
    
    // MARK: - Dependencies
    private let uhpGateway: UHPGateway
    private let locationManager: LocationManager
    private let userManager: UserManager
    private let authManager: AuthManager
    
    // Router reference set by AppContentView after initialization
    weak var sseEventRouter: SSEEventRouter?
    
    // MARK: - Callbacks (for cross-view coordination)
    var onDismissKeyboard: (() -> Void)?
    var onShowInfoSheet: (() -> Void)?
    var onTextFieldFocusChange: ((Bool) -> Void)?
    
    // MARK: - Initialization
    init(
        uhpGateway: UHPGateway,
        locationManager: LocationManager,
        userManager: UserManager,
        authManager: AuthManager
    ) {
        self.uhpGateway = uhpGateway
        self.locationManager = locationManager
        self.userManager = userManager
        self.authManager = authManager
    }
    
    // MARK: - Message Actions
    
    /// Validates, sends message, and handles streaming response
    func sendMessage() async {
        // Validate authentication state before sending
        guard authManager.isAuthenticated else {
            #if DEBUG
            print("⚠️ sendMessage: User is not authenticated, cannot send message")
            #endif
            return
        }
        
        // Wait for authentication check to complete if still loading
        if authManager.isLoading {
            #if DEBUG
            print("⚠️ sendMessage: Authentication check in progress, waiting...")
            #endif
            // Wait a bit for auth to complete (max 2 seconds)
            var waitCount = 0
            while authManager.isLoading && waitCount < 20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                waitCount += 1
            }
            
            // Check again after waiting
            guard authManager.isAuthenticated else {
                #if DEBUG
                print("⚠️ sendMessage: Authentication failed after waiting")
                #endif
                return
            }
        }
        
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
            // Prepare request data using UserEvent structure
            // Get device_lang - use fallback if user not initialized yet
            var device_lang = "en"
            if let user = userManager.currentUser {
                device_lang = user.device_lang
            } else {
                // Fallback to device language if user not initialized yet
                // This handles race conditions during app startup
                if #available(iOS 16.0, *) {
                    device_lang = Locale.current.language.languageCode?.identifier ?? device_lang
                } else {
                    device_lang = Locale.current.languageCode ?? device_lang
                }
                #if DEBUG
                print("⚠️ Using fallback device_lang: \(device_lang) (user not initialized yet)")
                #endif
            }
            
            // Build evt_data with message and device_lang (no location details)
            let evtData: [String: JSONValue] = [
                "message": .string(text),
                "device_lang": .string(device_lang)
            ]
            
            // Use streamUserEvent convenience method
            let stream = try await uhpGateway.streamUserEvent(
                endpoint: "/v1/chat",
                evtType: "chat_sent",
                evtData: evtData
            )
            
            // Process SSE events using unified router
            guard let router = sseEventRouter else {
                #if DEBUG
                print("⚠️ sendMessage: SSEEventRouter not available")
                #endif
                return
            }
            let processor = SSEEventProcessor(handler: router)
            try await processor.processStream(stream)
            
            // Safety net: Ensure the final assistant message is marked as not streaming
            // This handles cases where the stream ends without an explicit "stop" event
            // (e.g., network errors, stream completion without stop event)
            // Note: If onStop() was called, this is idempotent (checks isStreaming first)
            if let lastIndex = messages.indices.last,
               !messages[lastIndex].isUser {
                let existingMessage = messages[lastIndex]
                
                // Only update if still streaming (idempotent check)
                if existingMessage.isStreaming {
                    if existingMessage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Remove empty placeholder if stream ended without content
                        messages.removeLast()
                        #if DEBUG
                        print("✅ sendMessage cleanup: Removed empty streaming placeholder after stream completion")
                        #endif
                    } else {
                        // Mark as not streaming
                        let updatedMessage = ChatMessage(
                            id: existingMessage.id,
                            text: existingMessage.text,
                            isUser: existingMessage.isUser,
                            isStreaming: false
                        )
                        messages[lastIndex] = updatedMessage
                        updateLastMsg(updatedMessage)
                        #if DEBUG
                        print("✅ sendMessage cleanup: Marked message as not streaming after stream completion")
                        #endif
                    }
                }
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
    
    /// Updates the last message (used when streaming completes)
    func updateLastMsg(_ message: ChatMessage) {
        lastMessage = message
    }
    
    // MARK: - Chat Event Handling (called by SSEEventRouter)
    
    /// Handles chat content chunks from SSE stream
    /// Called by SSEEventRouter when chat events arrive
    func handleChatChunk(content: String, isStreaming: Bool) async {
        if let lastIndex = messages.indices.last, !messages[lastIndex].isUser {
            let existingMessage = messages[lastIndex]
            messages[lastIndex] = ChatMessage(
                id: existingMessage.id,
                text: content,
                isUser: false,
                isStreaming: isStreaming
            )
            updateLastMsg(messages[lastIndex])
        }
    }
    
    /// Handles stop event from SSE stream
    /// Called by SSEEventRouter when stop events arrive
    func handleStop() async {
        guard let lastIndex = messages.indices.last, !messages[lastIndex].isUser else {
            #if DEBUG
            print("⚠️ handleStop: No assistant message found to stop")
            #endif
            return
        }
        
        let lastMsg = messages[lastIndex]
        
        if lastMsg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.removeLast()
            #if DEBUG
            print("✅ handleStop: Removed empty streaming assistant placeholder")
            #endif
        } else {
            messages[lastIndex] = ChatMessage(
                id: lastMsg.id,
                text: lastMsg.text,
                isUser: lastMsg.isUser,
                isStreaming: false
            )
            #if DEBUG
            print("✅ handleStop: Marked last assistant message as not streaming")
            #endif
        }
        
        if let lastMsg = messages.last, !lastMsg.isUser {
            updateLastMsg(lastMsg)
        }
    }
}

