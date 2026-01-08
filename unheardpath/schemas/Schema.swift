import Foundation
import CoreLocation

// MARK: - JSON Value Type (Sendable)
/// A type-safe, Sendable representation of JSON values
enum JSONValue: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case dictionary([String: JSONValue])
    case null
    
    /// Convert to Any for use with JSONSerialization
    var asAny: Any {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .array(let value):
            return value.map { $0.asAny }
        case .dictionary(let value):
            return value.mapValues { $0.asAny }
        case .null:
            return NSNull()
        }
    }
    
}

// MARK: - JSONValue Conversion Extension
extension JSONValue {
    /// Convert from Any (from JSONSerialization) to JSONValue
    /// This enables conversion from [String: Any] to [String: JSONValue] for Swift 6 Sendable compliance
    init?(from any: Any) {
        switch any {
        case let string as String:
            self = .string(string)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let bool as Bool:
            self = .bool(bool)
        case let array as [Any]:
            let jsonArray = array.compactMap { JSONValue(from: $0) }
            guard jsonArray.count == array.count else { return nil }
            self = .array(jsonArray)
        case let dict as [String: Any]:
            var jsonDict: [String: JSONValue] = [:]
            for (key, value) in dict {
                guard let jsonValue = JSONValue(from: value) else { return nil }
                jsonDict[key] = jsonValue
            }
            self = .dictionary(jsonDict)
        case is NSNull:
            self = .null
        default:
            // Handle NSNumber which can be Int or Double
            if let number = any as? NSNumber {
                // Check if it's a boolean first
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    self = .bool(number.boolValue)
                } else {
                    // Try Int first, then Double
                    if let intValue = Int(exactly: number.int64Value) {
                        self = .int(intValue)
                    } else {
                        self = .double(number.doubleValue)
                    }
                }
            } else {
                return nil
            }
        }
    }
    
    /// Convenience method to convert [String: Any] to [String: JSONValue]
    static func dictionary(from dict: [String: Any]) -> [String: JSONValue]? {
        var result: [String: JSONValue] = [:]
        for (key, value) in dict {
            guard let jsonValue = JSONValue(from: value) else { return nil }
            result[key] = jsonValue
        }
        return result
    }
    
    /// Extract string value if this is a string case
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
    
    /// Extract dictionary value if this is a dictionary case
    var dictionaryValue: [String: JSONValue]? {
        if case .dictionary(let value) = self {
            return value
        }
        return nil
    }
    
    /// Extract value for a key from dictionary, returns nil if not a dictionary or key not found
    subscript(key: String) -> JSONValue? {
        guard case .dictionary(let dict) = self else { return nil }
        return dict[key]
    }
}

// MARK: - JSONValue String Encoding/Decoding Extension
extension JSONValue {
    /// Encodes a JSONValue dictionary to a JSON string
    /// - Parameter jsonValue: Dictionary to encode
    /// - Returns: JSON string representation, or nil if encoding fails
    static func encodeToString(_ jsonValue: [String: JSONValue]) -> String? {
        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(jsonValue),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    /// Decodes a JSON string to a JSONValue dictionary
    /// - Parameter jsonString: JSON string to decode
    /// - Returns: Dictionary representation, or nil if decoding fails
    static func decodeFromString(_ jsonString: String) -> [String: JSONValue]? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode([String: JSONValue].self, from: jsonData)
    }
    
    /// Encodes a single JSONValue to a JSON string
    /// - Returns: JSON string representation, or nil if encoding fails
    func encodeToString() -> String? {
        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(self),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    /// Decodes a JSON string to a JSONValue
    /// - Parameter jsonString: JSON string to decode
    /// - Returns: JSONValue representation, or nil if decoding fails
    static func decodeValueFromString(_ jsonString: String) -> JSONValue? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(JSONValue.self, from: jsonData)
    }
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

