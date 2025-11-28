import SwiftUI

// MARK: - Minimal Chat Sheet Implementation
// Essential components for a chat sheet (not in NavigationView):
// 1. ScrollView with ScrollViewReader for messages
// 2. TextField for input
// 3. Send button
// 4. State management for messages
// 5. Auto-scroll to bottom on new messages

// MARK: - Simple Chat Message Model (minimal version)
struct SimpleChatMessage: Identifiable {
  let id = UUID()
  let text: String
  let isUser: Bool
}

// MARK: - Chat Bubble View
struct ChatBubble: View {
  let message: SimpleChatMessage
  
  var body: some View {
    HStack {
      if message.isUser {
        Spacer()
      }
      
      Text(message.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(message.isUser ? Color.blue : Color(.systemGray5))
        .foregroundColor(message.isUser ? .white : .primary)
        .cornerRadius(16)
      
      if !message.isUser {
        Spacer()
      }
    }
  }
}


// MARK: - Chat Input Bar Component
struct ChatInputBar: View {
  @State private var messageText = ""
  @FocusState.Binding var isTextFieldFocused: Bool
  var onSendMessage: (String) -> Void
  
  init(isTextFieldFocused: FocusState<Bool>.Binding, onSendMessage: @escaping (String) -> Void) {
    self._isTextFieldFocused = isTextFieldFocused
    self.onSendMessage = onSendMessage
  }
  
  // Computed property to check if message is empty (trimmed)
  private var isEmpty: Bool {
    messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  
  var body: some View {
    HStack(spacing: 12) {
      MultiLineTextField(
        text: $messageText,
        placeholder: "Ask anything about your journey.",
        onReturnKeyPress: { textToSend in
          // Use the text passed from the text field instead of reading from messageText
          // which may have already been cleared
          sendMessage(with: textToSend)
        }
      )
      .frame(height: 32)
      
      // Show voice button when empty, send button when typing
      if isEmpty {
        Button(action: {
          // TODO: Implement voice mode functionality
          #if DEBUG
          print("🎤 Voice button tapped")
          #endif
        }) {
          Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundColor(.blue)
        }
      } else {
        Button(action: {
          sendMessage()
        }) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
            .foregroundColor(.blue)
        }
      }
    }
    .padding()
    .background(Color(.systemBackground))
  }
  
  private func sendMessage(with text: String? = nil) {
    // Use provided text or fall back to messageText binding
    let textToSend = text ?? messageText
    let trimmedText = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
    
    #if DEBUG
    print("📝 ChatInputBar.sendMessage() called")
    print("   textToSend: '\(textToSend)'")
    print("   trimmedText: '\(trimmedText)'")
    print("   isEmpty: \(trimmedText.isEmpty)")
    #endif
    
    guard !trimmedText.isEmpty else {
      #if DEBUG
      print("⚠️ Message is empty, not sending")
      #endif
      return
    }
    
    // Clear input after capturing the text
    messageText = ""
    
    #if DEBUG
    print("✅ Calling onSendMessage with: '\(trimmedText)'")
    #endif
    
    // Call the callback with the trimmed text
    onSendMessage(trimmedText)
    
    #if DEBUG
    print("✅ onSendMessage callback completed")
    #endif
  }
}

// MARK: - Chat Message View
struct ChatMessageView: View {
  let message: ChatMessage
  
  var body: some View {
    HStack {
      if message.isUser {
        Spacer()
      }
      VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
        Text(message.text)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(message.isUser ? Color.blue : Color(.systemGray5))
          .foregroundColor(message.isUser ? .white : .primary)
          .cornerRadius(16)
        
        if message.isStreaming {
          ProgressView()
            .scaleEffect(0.8)
        }
      }
      
      if !message.isUser {
        Spacer()
      }
    }
  }
}

// MARK: - Chat Messages Scroll View
// Handles all scrolling behavior and lifecycle events
struct ChatMessagesScrollView: View {
  let chatMessages: [ChatMessage]
  @Binding var isChatNearBottom: Bool
  @Binding var hasScrolledInitially: Bool
  
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if chatMessages.isEmpty {
            Text("Chat messages will appear here")
              .foregroundColor(.secondary)
              .padding()
              .id("empty-state")
          } else {
            ForEach(chatMessages) { message in
              ChatMessageView(message: message)
                .id(message.id)
            }
          }
          // Bottom anchor for scrolling
          Color.clear
            .frame(height: 1)
            .id("bottom-anchor")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
      .onAppear {
        handleInitialScroll(proxy: proxy)
      }
      .onChange(of: chatMessages.count) { newCount in
        handleMessageCountChange(proxy: proxy, newCount: newCount)
      }
      .onChange(of: chatMessages.last?.text) { _ in
        handleLastMessageTextChange(proxy: proxy)
      }
      .onChange(of: chatMessages.last?.isStreaming) { _ in
        handleStreamingStateChange(proxy: proxy)
      }
    }
  }
  
  // MARK: - Scroll Handlers
  private func handleInitialScroll(proxy: ScrollViewProxy) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      if let lastMessage = chatMessages.last {
        withAnimation {
          proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
      } else {
        withAnimation {
          proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
      }
    }
  }
  
  private func handleMessageCountChange(proxy: ScrollViewProxy, newCount: Int) {
    guard newCount > 0 else { return }
    let shouldScroll = !hasScrolledInitially || isChatNearBottom
    
    if shouldScroll {
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let lastMessage = chatMessages.last {
          withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
          }
          hasScrolledInitially = true
        }
      }
    }
  }
  
  private func handleLastMessageTextChange(proxy: ScrollViewProxy) {
    guard isChatNearBottom, let lastMessage = chatMessages.last else { return }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 30_000_000)
      withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
      }
    }
  }
  
  private func handleStreamingStateChange(proxy: ScrollViewProxy) {
    if isChatNearBottom, let lastMessage = chatMessages.last, !lastMessage.isStreaming {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(.easeOut(duration: 0.3)) {
          proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
      }
    }
  }
}


// MARK: - Chat Modal View
struct ChatModalView: View {
  @Binding var chatMessages: [ChatMessage]
  @Binding var shouldDismissKeyboard: Bool
  @Binding var currentNotification: NotificationData?
  var onSendMessage: (String) async -> Void
  @Environment(\.dismiss) private var dismiss
  
  @State private var messageText = ""
  @State private var isChatNearBottom = true
  @State private var hasScrolledInitially = false
  @FocusState private var isTextFieldFocused: Bool
  
  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
          // Chat messages area with auto-scrolling behavior
          ChatMessagesScrollView(
            chatMessages: chatMessages,
            isChatNearBottom: $isChatNearBottom,
            hasScrolledInitially: $hasScrolledInitially
          )
          
          // Input bar at bottom - SwiftUI handles keyboard automatically
          ChatInputBar(
            isTextFieldFocused: $isTextFieldFocused,
            onSendMessage: { messageText in
              Task {
                await onSendMessage(messageText)
              }
            }
          )
        }
        .onChange(of: shouldDismissKeyboard) { shouldDismiss in
          if shouldDismiss {
            // Dismiss keyboard
            isTextFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline) // Make toolbar more compact
      .toolbar {
        ChatModalToolbar(onDismiss: {
          dismiss()
        })
      }
      .chatToolbarStyle() // Apply toolbar styling from ChatModalToolbar
      .overlay(alignment: .top) {
        // Notification Banner - overlaid on chat sheet so it's visible when sheet is open
        if let notification = currentNotification {
          NotificationBanner(notification: notification) {
            currentNotification = nil
          }
        }
      }
    }
    .presentationDetents([.height(300)])
    .presentationDragIndicator(.visible)
    .presentationBackground(.clear)
  }
}

// MARK: - Chat Modal Toolbar
struct ChatModalToolbar: ToolbarContent {
  var onDismiss: () -> Void
  
  var body: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      HStack(spacing: 4) {
        Image(systemName: "bubble.left.and.bubble.right")
          .font(.subheadline)
          .foregroundColor(Color("onBkgTextColor90"))
        Text("Ask")
          .font(.subheadline)
          .foregroundColor(Color("onBkgTextColor90"))
      }
    }
    
    ToolbarItem(placement: .navigationBarTrailing) {
      Button(action: onDismiss) {
        Text("Done")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(Color("onBkgTextColor90"))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            Color("onBkgTextColor90")
              .opacity(0.1)
              .cornerRadius(6)
          )
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Chat Toolbar Style Extension
extension View {
  /// Applies transparent toolbar styling for ChatModalView
  func chatToolbarStyle() -> some View {
    self
      .toolbarBackground(.hidden, for: .navigationBar) // Remove toolbar background completely
      .onAppear {
        // Use UIKit to make navigation bar truly transparent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
      }
  }
}

// MARK: - Preview Helper
struct ChatSheetPreviewContainer: View {
  let chatMessages: [ChatMessage]
  @State private var showSheet = true
  let showNotification: Bool
  
  init(chatMessages: [ChatMessage], showNotification: Bool = false) {
    self.chatMessages = chatMessages
    self.showNotification = showNotification
  }
  
  var body: some View {
    // Simulate the underlying view
    ZStack {
      PreviewMockBkg()
      
      // Test notification banner - positioned from above
      if showNotification {
        NotificationBanner(
          notification: NotificationData(
            type: "search",
            message: "This is a test notification banner with a mock message"
          ),
          onDismiss: nil
        )
      }
    }
    .sheet(isPresented: $showSheet) {
      ChatModalView(
        chatMessages: .constant(chatMessages),
        shouldDismissKeyboard: .constant(false),
        currentNotification: .constant(nil),
        onSendMessage: { _ in }
      )
    }
  }
}

struct PreviewMockBkg: View {
  var body: some View {
    VStack {
      Text("Underlying View")
        .font(.title)
        .padding()
      Text("(This simulates the view behind the sheet)")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }
}   

#Preview("Empty Chat") {
  ChatSheetPreviewContainer(chatMessages: [], showNotification: true)
}

#Preview("Chat with Messages") {
  ChatSheetPreviewContainer(chatMessages: [
    ChatMessage(text: "What's the history of this place?", isUser: true, isStreaming: false),
    ChatMessage(text: "This location has a rich history dating back to the 18th century. It was originally built as a trading post and later became a significant cultural center.", isUser: false, isStreaming: false),
    ChatMessage(text: "Can you tell me more about the architecture?", isUser: true, isStreaming: false),
    ChatMessage(text: "The architecture reflects a blend of colonial and local styles. The main building features distinctive columns and a symmetrical design typical of that era.", isUser: false, isStreaming: false),
    ChatMessage(text: "What are the best times to visit?", isUser: true, isStreaming: false),
    ChatMessage(text: "Early morning or late afternoon are ideal times to visit, as the lighting is perfect for photography and the crowds are smaller.", isUser: false, isStreaming: false)
  ])
}