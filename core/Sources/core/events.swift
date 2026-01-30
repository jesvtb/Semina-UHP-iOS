import Foundation

/// Generic event model for analytics/event tracking.
/// Used for sending events to backend endpoints (evt_utc, evt_timezone, evt_type, evt_data, session_id).
public struct UserEvent: Codable, Sendable {
    public let evt_utc: String  // ISO8601 UTC datetime string
    public let evt_timezone: String?  // IANA timezone identifier
    public let evt_type: String  // Event type (app-specific)
    public let evt_data: [String: JSONValue]  // Event data (structure depends on evt_type)
    public let session_id: String?  // Session identifier

    public init(evt_utc: String, evt_timezone: String?, evt_type: String, evt_data: [String: JSONValue], session_id: String?) {
        self.evt_utc = evt_utc
        self.evt_timezone = evt_timezone
        self.evt_type = evt_type
        self.evt_data = evt_data
        self.session_id = session_id
    }

    /// Converts UserEvent to JSONValue dictionary for API calls
    public func toJSONDict() -> [String: JSONValue] {
        var dict: [String: JSONValue] = [
            "evt_utc": .string(evt_utc),
            "evt_type": .string(evt_type),
            "evt_data": .dictionary(evt_data)
        ]
        if let timezone = evt_timezone {
            dict["evt_timezone"] = .string(timezone)
        }
        if let sessionId = session_id {
            dict["session_id"] = .string(sessionId)
        }
        return dict
    }
}

/// Builder for creating UserEvent instances with auto-generated UTC and timezone
public enum UserEventBuilder {
    /// Creates a UserEvent with auto-generated UTC datetime and timezone
    /// - Parameters:
    ///   - evtType: Event type (app-specific)
    ///   - evtData: Event data dictionary
    ///   - sessionId: Optional session identifier (default: nil)
    /// - Returns: UserEvent instance with current UTC time and device timezone
    public nonisolated static func build(evtType: String, evtData: [String: JSONValue], sessionId: String? = nil) -> UserEvent {
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
            evt_data: evtData,
            session_id: sessionId
        )
    }
}
