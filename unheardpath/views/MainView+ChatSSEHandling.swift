import SwiftUI

// MARK: - Chat SSE Workflows
extension TestMainView {
  
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
  func handleSSEFinishEvent(event: SSEEvent) async {
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
        lastMessage = lastMsg
      }
    }
  }
  
  /// Handles `notification` SSE events by parsing the payload and updating
  /// `currentNotification`. The ProgressNotificationBanner handles its own auto-dismiss.
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
        // Note: ProgressNotificationBanner handles its own auto-dismiss
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
        if let lastIndex = messages.indices.last,
           !messages[lastIndex].isUser {
          let existingMessage = messages[lastIndex]
          let isStreaming = dataDict["is_streaming"] as? Bool ?? true
          messages[lastIndex] = ChatMessage(
            id: existingMessage.id,
            text: streamingContent,
            isUser: false,
            isStreaming: isStreaming
          )
          #if DEBUG
          print("✅ Updated assistant message. isStreaming: \(isStreaming)")
          #endif
          
          // Update lastMessage for the bubble display
          lastMessage = messages[lastIndex]
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
  
  /// Handles `interface` SSE events by controlling UI elements like the info sheet.
  /// If message is "show info sheet", sets sheetSnapPoint to .full.
  func handleInterfaceEvent(event: SSEEvent) async {
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
          print("📋 Setting sheetSnapPoint to .full")
          #endif
          
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            sheetSnapPoint = .full
          }
        }
      }
    } catch {
      #if DEBUG
      print("❌ Error handling interface event: \(error)")
      #endif
    }
  }
}

