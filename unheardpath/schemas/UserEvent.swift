import Foundation

/// UserEvent model matching Python UserEvent structure
/// Used for sending events to backend endpoints
struct UserEvent: Codable, Sendable {
    let evt_utc: String  // ISO8601 UTC datetime string
    let evt_timezone: String?  // IANA timezone identifier
    let evt_type: String  // Event type (e.g., "location_detected", "chat_sent")
    let evt_data: [String: JSONValue]  // Event data (structure depends on evt_type)
    
    /// Converts UserEvent to JSONValue dictionary for API calls
    func toJSONDict() -> [String: JSONValue] {
        var dict: [String: JSONValue] = [
            "evt_utc": .string(evt_utc),
            "evt_type": .string(evt_type),
            "evt_data": .dictionary(evt_data)
        ]
        if let timezone = evt_timezone {
            dict["evt_timezone"] = .string(timezone)
        }
        return dict
    }
}

/// Builder for creating UserEvent instances with auto-generated UTC and timezone
enum UserEventBuilder {
    /// Creates a UserEvent with auto-generated UTC datetime and timezone
    /// - Parameters:
    ///   - evtType: Event type (e.g., "location_detected", "chat_sent")
    ///   - evtData: Event data dictionary
    /// - Returns: UserEvent instance with current UTC time and device timezone
    nonisolated static func build(evtType: String, evtData: [String: JSONValue]) -> UserEvent {
        let now = Date()
        
        // Create formatter - lightweight enough to create per call
        // This avoids concurrency issues with static shared state
        let utcFormatter = ISO8601DateFormatter()
        utcFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let evtUTC = utcFormatter.string(from: now)
        let evtTimezone = TimeZone.current.identifier
        
        return UserEvent(
            evt_utc: evtUTC,
            evt_timezone: evtTimezone,
            evt_type: evtType,
            evt_data: evtData
        )
    }
}
