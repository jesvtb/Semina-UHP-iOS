import Foundation
import CoreLocation
import Combine

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

// MARK: - JSONValue Codable (standard JSON, no type wrapper)
extension JSONValue {
    /// Encodes as standard JSON (e.g. .double(114.11) → 114.11, not {"double":{"_0":114.11}}).
    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for element in value {
                try container.encode(element)
            }
        case .dictionary(let value):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, val) in value {
                try container.encode(val, forKey: DynamicCodingKey(stringValue: key))
            }
        }
    }

    /// Decodes from standard JSON (e.g. 114.11 → .double(114.11)).
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .null
                return
            }
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
                return
            }
            if let value = try? container.decode(Int.self) {
                self = .int(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self = .double(value)
                return
            }
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
        }
        if var container = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !container.isAtEnd {
                arr.append(try container.decode(JSONValue.self))
            }
            self = .array(arr)
            return
        }
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var dict: [String: JSONValue] = [:]
        for key in container.allKeys {
            dict[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self = .dictionary(dict)
    }
}

/// CodingKey for dynamic dictionary keys when encoding/decoding JSONValue.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
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

    static func prettyDict(_ jsonValue: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let jsonData = try? encoder.encode(jsonValue),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }
        // print(jsonString)
        return "\n\(jsonString)\n"
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
    static func decode(_ jsonString: String) -> JSONValue? {
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

