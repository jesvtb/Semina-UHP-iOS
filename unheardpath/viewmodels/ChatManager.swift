import Foundation
import SwiftUI
import core
/// Manages all chat-related state and logic
/// Consolidates ChatState, chat-related LiveUpdateViewModel properties, and chat actions
@MainActor
class ChatManager: ObservableObject {
    // MARK: - State Properties
    
    // From ChatState
    @Published var messages: [ChatMessage] = []
    @Published var draftMessage: String = ""
    
    // From LiveUpdateViewModel (chat-related only)
    @Published var lastMessage: ChatMessage?
    @Published var isMessageExpanded: Bool = false
    
    // MARK: - Dependencies
    private let uhpGateway: UHPGateway
    private let userManager: UserManager
    private let logger: Logger
    
    // Router reference set by AppContentView after initialization
    weak var sseEventRouter: SSEEventRouter?
    
    // EventManager reference (set after initialization, for event tracking)
    weak var eventManager: EventManager?
    
    /// Last assistant message id we already persisted as chat_received. Avoids duplicate UserDefaults writes when SSE sends multiple stop events.
    private var lastPersistedChatReceivedMessageId: String?
    
    // MARK: - Callbacks (for cross-view coordination)
    var onDismissKeyboard: (() -> Void)?
    var onShowInfoSheet: (() -> Void)?
    var onTextFieldFocusChange: ((Bool) -> Void)?
    
    // MARK: - Initialization
    init(
        uhpGateway: UHPGateway,
        userManager: UserManager,
        logger: Logger = AppLifecycleManager.sharedLogger
    ) {
        self.uhpGateway = uhpGateway
        self.userManager = userManager
        self.logger = logger
    }
    
    /// Restores chat messages from EventManager's persisted events (UserDefaults).
    /// Call once at app launch after eventManager is set so the Chat view shows past sent and received messages.
    func loadHistory() {
        guard let eventManager = eventManager else { return }
        let chatEvents = eventManager.chatEventsInOrder()
        messages = chatEvents.map { event in
            let text = event.evt_data["message"]?.stringValue ?? ""
            let isUser = event.evt_type == "chat_sent"
            return ChatMessage(text: text, isUser: isUser, isStreaming: false)
        }
        lastMessage = messages.last
    }
    
    // MARK: - Message Actions
    
    /// Validates, sends message, and handles streaming response
    func sendMessage() async {
        // Extract and validate draft message
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            logger.debug("sendMessage: Message is empty after trimming, not sending")
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
        lastPersistedChatReceivedMessageId = nil
        
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
                logger.debug("Using fallback device_lang: \(device_lang) (user not initialized yet)")
            }
            
            // Build evt_data with message and device_lang (no location details)
            let evtData: [String: JSONValue] = [
                "message": .string(text),
                "device_lang": .string(device_lang)
            ]
            
            // Create chat_sent event for EventManager tracking
            let chatSentEvent = UserEventBuilder.build(
                evtType: "chat_sent",
                evtData: evtData,
                sessionId: eventManager?.sessionId
            )
            
            // Track event in EventManager and get SSE stream
            // EventManager handles persistence and backend sending, returns stream for SSE processing
            guard let stream = try await eventManager?.addEvent(chatSentEvent) else {
                logger.debug("sendMessage: No stream returned from EventManager")
                return
            }
            
            // Process SSE events using unified router
            guard let router = sseEventRouter else {
                logger.debug("sendMessage: SSEEventRouter not available")
                return
            }
            let processor = SSEEventProcessor(router: router)
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
                        logger.debug("sendMessage cleanup: Removed empty streaming placeholder after stream completion")
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
                        logger.debug("sendMessage cleanup: Marked message as not streaming after stream completion")
                    }
                }
            }
            
        } catch {
            logger.error("Failed to send chat message: \(error.localizedDescription)", handlerType: "ChatManager", error: error)
            if let apiError = error as? APIError {
                logger.debug("API Error: \(apiError.message) (code: \(apiError.code ?? -1))")
            }
            
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
    /// Called by SSEEventRouter when chat events arrive. Accumulates chunks into the current assistant message.
    func handleChatChunk(content: String, isStreaming: Bool) async {
        if let lastIndex = messages.indices.last, !messages[lastIndex].isUser {
            let existingMessage = messages[lastIndex]
            let accumulatedText = existingMessage.text + content
            messages[lastIndex] = ChatMessage(
                id: existingMessage.id,
                text: accumulatedText,
                isUser: false,
                isStreaming: isStreaming
            )
            updateLastMsg(messages[lastIndex])
        } else {
            let assistantMessage = ChatMessage(text: content, isUser: false, isStreaming: isStreaming)
            messages.append(assistantMessage)
            updateLastMsg(assistantMessage)
        }
    }
    
    /// Handles stop event from SSE stream
    /// Called by SSEEventRouter when stop events arrive
    func handleStop() async {
        guard let lastIndex = messages.indices.last, !messages[lastIndex].isUser else {
            logger.debug("handleStop: No assistant message found to stop")
            return
        }
        
        let lastMsg = messages[lastIndex]
        
        if lastMsg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.removeLast()
            logger.debug("handleStop: Removed empty streaming assistant placeholder")
        } else {
            messages[lastIndex] = ChatMessage(
                id: lastMsg.id,
                text: lastMsg.text,
                isUser: lastMsg.isUser,
                isStreaming: false
            )
            logger.debug("handleStop: Marked last assistant message as not streaming")
        }
        
        if let lastMsg = messages.last, !lastMsg.isUser {
            updateLastMsg(lastMsg)
            
            // Persist chat_received only once per assistant message (SSE may send multiple stop events)
            let messageIdString = lastMsg.id.uuidString
            if lastPersistedChatReceivedMessageId == messageIdString {
                return
            }
            lastPersistedChatReceivedMessageId = messageIdString
            
            // Create chat_received event after streaming completes
            // Get device_lang for event data
            var device_lang = "en"
            if let user = userManager.currentUser {
                device_lang = user.device_lang
            } else {
                if #available(iOS 16.0, *) {
                    device_lang = Locale.current.language.languageCode?.identifier ?? device_lang
                } else {
                    device_lang = Locale.current.languageCode ?? device_lang
                }
            }
            
            // Create chat_received event with final message content
            let chatReceivedEventData: [String: JSONValue] = [
                "message": .string(lastMsg.text),
                "device_lang": .string(device_lang)
            ]
            
            let chatReceivedEvent = UserEventBuilder.build(
                evtType: "chat_received",
                evtData: chatReceivedEventData,
                sessionId: eventManager?.sessionId
            )
            
            // Track event in EventManager (persist only, backend already has it)
            if let eventManager = eventManager {
                do {
                    try await eventManager.addEvent(chatReceivedEvent)
                } catch {
                    logger.error("Failed to add chat_received event: \(error.localizedDescription)", handlerType: "ChatManager", error: error)
                }
            }
        }
    }
}

