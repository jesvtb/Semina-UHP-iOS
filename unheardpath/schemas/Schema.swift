import Foundation

struct ChatMessage: Identifiable {
  let id: UUID
  let text: String
  let isUser: Bool
  let isStreaming: Bool
  
  init(id: UUID = UUID(), text: String, isUser: Bool, isStreaming: Bool) {
    self.id = id
    self.text = text
    self.isUser = isUser
    self.isStreaming = isStreaming
  }
}


// MARK: - Notification Model
struct NotificationData {
  let type: String?
  let message: String
  
  init?(from dict: [String: Any]) {
    guard let message = dict["message"] as? String else {
      return nil
    }
    self.type = dict["type"] as? String
    self.message = message
  }
  
  // Convenience initializer for creating mock notifications
  init(type: String? = nil, message: String) {
    self.type = type
    self.message = message
  }
}


enum TabSelection: Int {
  case journey = 0
  case map = 1
  case chat = 2
  case profile = 3
}


// MARK: - User Model
struct User: Identifiable {
  let id: UUID
  let uuid: String  // Supabase user UUID as string
  
  init(id: UUID = UUID(), uuid: String) {
    self.id = id
    self.uuid = uuid
  }
}


// MARK: - User Manager
/// Manages global user state for the app
/// Similar to React Context - provides global user access
@MainActor
class UserManager: ObservableObject {
  @Published var currentUser: User?
  
  /// Updates the current user
  func setUser(uuid: String) {
    currentUser = User(uuid: uuid)
    #if DEBUG
    print("✅ UserManager: Set current user with UUID: \(uuid)")
    #endif
  }
  
  /// Clears the current user
  func clearUser() {
    currentUser = nil
    #if DEBUG
    print("🔄 UserManager: Cleared current user")
    #endif
  }
}

