import SwiftUI

// MARK: - Minimal Chat Sheet Implementation
// Essential components for a chat sheet (not in NavigationView):
// 1. ScrollView with ScrollViewReader for messages
// 2. TextField for input
// 3. Send button
// 4. State management for messages
// 5. Auto-scroll to bottom on new messages

struct ChatView: View {
  @State private var messages: [SimpleChatMessage] = []
  @State private var inputText: String = ""
  @FocusState private var isInputFocused: Bool
  
  var body: some View {
    VStack(spacing: 0) {
      // 1. Messages ScrollView - Essential for displaying chat history
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 12) {
            ForEach(messages) { message in
              ChatBubble(message: message)
                .id(message.id)
            }
          }
          .padding()
        }
        .onChange(of: messages.count) { _ in
          // Auto-scroll to bottom when new message arrives
          if let lastMessage = messages.last {
            withAnimation {
              proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
          }
        }
      }
      
      // 2. Input Bar - Essential for user input
      HStack(spacing: 12) {
        // TextField with vertical expansion support
        TextField("Type a message...", text: $inputText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...5)
          .focused($isInputFocused)
        
        // Send button
        Button(action: sendMessage) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
            .foregroundColor(inputText.isEmpty ? .gray : .blue)
        }
        .disabled(inputText.isEmpty)
      }
      .padding()
      .background(Color(.systemBackground))
    }
  }
  
  private func sendMessage() {
    guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    
    // Add user message
    messages.append(SimpleChatMessage(text: inputText, isUser: true))
    
    // Clear input
    inputText = ""
    
    // TODO: Send to API and add assistant response
  }
}

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

#Preview {
  ChatView()
  .frame(maxWidth: .infinity, maxHeight: .infinity)
}