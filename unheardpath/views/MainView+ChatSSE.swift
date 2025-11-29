import SwiftUI

// MARK: - Chat SSE Workflows
extension MainView {
  
  /// Dispatches handling for different SSE event types coming from the chat stream.
  /// Keeps `sendChatMessage` focused on request/response orchestration while this
  /// function owns the per-event workflows.
  func handleChatStreamEvent(
    event: SSEEvent,
    streamingContent: inout String
  ) async {
    let eventType = (event.event ?? "").lowercased()
    
    switch eventType {
    case "notification":
      await handleNotificationEvent(event: event)
      
    case "content":
      await handleContentEvent(event: event, streamingContent: &streamingContent)
      
    case "finish":
      await handleSSEFinishEvent(event: event)
      
    case "map":
      await handleMapEvent()
      
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
  func handleSSEFinishEvent(event: SSEEvent) async {
    #if DEBUG
    print("🏁 Processing finish event")
    print("   Raw data: \(event.data)")
    #endif
    
    await MainActor.run {
      guard let lastIndex = chatMessages.indices.last,
            !chatMessages[lastIndex].isUser else {
        #if DEBUG
        print("⚠️ No assistant message found to finish")
        #endif
        return
      }
      
      let lastMessage = chatMessages[lastIndex]
      
      if lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        // If it's just an empty streaming placeholder, remove it entirely
        chatMessages.removeLast()
        #if DEBUG
        print("✅ Removed empty streaming assistant placeholder on finish event")
        #endif
      } else {
        // Otherwise, keep the content and just stop streaming
        chatMessages[lastIndex] = ChatMessage(
          id: lastMessage.id,
          text: lastMessage.text,
          isUser: lastMessage.isUser,
          isStreaming: false
        )
        #if DEBUG
        print("✅ Marked last assistant message as not streaming on finish event")
        #endif
      }
    }
  }
  
  /// Handles `notification` SSE events by parsing the payload and updating
  /// `currentNotification`, including auto-dismiss behavior.
  func handleNotificationEvent(event: SSEEvent) async {
    #if DEBUG
    print("🔔 Processing notification event")
    #endif
    
    do {
      guard let dataDict = try event.parseJSONData() else {
        #if DEBUG
        print("⚠️ Failed to parse notification data as JSON")
        #endif
        return
      }
      
      guard let notification = NotificationData(from: dataDict) else {
        #if DEBUG
        print("⚠️ Failed to create notification from data: \(dataDict)")
        #endif
        return
      }
      
      await MainActor.run {
        #if DEBUG
        print("📬 Notification received: type=\(notification.type ?? "nil"), message=\(notification.message)")
        print("   Setting currentNotification...")
        #endif
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          currentNotification = notification
        }
        
        #if DEBUG
        print("   currentNotification set. Value: \(currentNotification?.message ?? "nil")")
        #endif
        
        // Auto-dismiss after 5 seconds
        Task {
          try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
          await MainActor.run {
            #if DEBUG
            print("   Auto-dismissing notification after 5 seconds")
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              currentNotification = nil
            }
          }
        }
      }
    } catch {
      #if DEBUG
      print("❌ Error handling notification event: \(error)")
      #endif
    }
  }
  
  /// Handles `content` SSE events by updating the streaming assistant message.
  func handleContentEvent(
    event: SSEEvent,
    streamingContent: inout String
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
      
      streamingContent += content
      #if DEBUG
      print("📝 Content chunk received: '\(content)'")
      print("   Total streaming content length: \(streamingContent.count)")
      #endif
      
      await MainActor.run {
        if let lastIndex = chatMessages.indices.last,
           !chatMessages[lastIndex].isUser {
          let existingMessage = chatMessages[lastIndex]
          let isStreaming = dataDict["is_streaming"] as? Bool ?? true
          chatMessages[lastIndex] = ChatMessage(
            id: existingMessage.id,
            text: streamingContent,
            isUser: false,
            isStreaming: isStreaming
          )
          #if DEBUG
          print("✅ Updated assistant message. isStreaming: \(isStreaming)")
          #endif
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
  func handleMapEvent() async {
    #if DEBUG
    print("🗺️ Processing map event - dismissing keyboard and resetting modal")
    #endif
    
    await MainActor.run {
      shouldDismissKeyboard = true
      // Reset the flag after a brief delay to allow the change to be detected
      Task {
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        await MainActor.run {
          shouldDismissKeyboard = false
        }
      }
    }
  }
}


