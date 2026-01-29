import Foundation
import CoreLocation
import Combine
import core
/// CodingKey for dynamic dictionary keys when encoding/decoding JSONValue.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

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


// MARK: - Activity Update Model
struct ToastData {
  let type: String?
  let message: String
  
  init?(from dict: [String: Any]) {
    guard let message = dict["message"] as? String else {
      return nil
    }
    self.type = dict["type"] as? String
    self.message = message
  }
  
  // Convenience initializer for creating mock activity updates
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
  let id: UUID?
  let device_lang: String
  
  init(isAnonymous: Bool? = false, user_id: UUID? = nil, device_lang: String) {
    if isAnonymous == false {
      self.id = UUID()
    } else if let user_id = user_id {
      self.id = user_id
    } else {
      self.id = nil
    }
    self.device_lang = device_lang
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
    var device_lang = "en"
    if #available(iOS 16.0, *) {
        device_lang = Locale.current.language.languageCode?.identifier ?? device_lang
    } else {
        device_lang = Locale.current.languageCode ?? device_lang
    }
    let userUUID = UUID(uuidString: uuid)
    currentUser = User(isAnonymous: false, user_id: userUUID, device_lang: device_lang)
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

