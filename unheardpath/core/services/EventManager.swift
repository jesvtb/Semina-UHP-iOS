//
//  EventManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2026-01-28.
//

import Foundation
import SwiftUI
import core

/// Session data structure for archived sessions
struct SessionData: Codable, Sendable {
    let sessionId: String
    let events: [UserEvent]
    let startedAt: String?  // ISO8601 string
    let lastActivityAt: String?  // ISO8601 string
}

/// Location type for deduplication
enum LocationType: Sendable {
    case device
    case search
}

/// Result of the location send gate: one check decides skip, send same location with new time, or send new location.
enum LocationSendDecision: Sendable {
    /// Do nothing: no geocode, no send, no UserDefaults update.
    case skip
    /// Send existing latest location dict with new time (device only; no geocode).
    case sendSameLocationNewTime
    /// Geocode (if device) and send new location; or send the given location dict (search).
    case sendNewLocation
}

/// Manages user events, derives locations from events, handles persistence, and prevents duplicate sends.
/// Mirrors backend's User model from retail_user.py
@MainActor
class EventManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var thisSession: [UserEvent] = []
    @Published var pastSessions: [String: SessionData] = [:]
    @Published var latestDeviceLocation: [String: JSONValue]?
    @Published var latestSearchLocation: [String: JSONValue]?
    
    // MARK: - Session Properties
    
    var sessionId: String
    private(set) var sessionStartedAt: Date?
    private(set) var lastActivityAt: Date?
    
    // MARK: - Dependencies (set after init)
    
    weak var uhpGateway: UHPGateway?
    
    // MARK: - Persistence Keys
    
    private let thisSessionKey = "EventManager.thisSession"
    private let pastSessionsKey = "EventManager.pastSessions"
    private let sessionIdKey = "EventManager.sessionId"
    private let sessionMetadataKey = "EventManager.sessionMetadata"
    private let lastDeviceLocationKey = "LastDeviceLocation"      // Widget compatibility
    private let lastSearchLocationKey = "LastSearchLocation"
    
    // MARK: - Configuration
    
    private let inactivityTimeoutMinutes: Int = 30
    private let maxSessionDurationMinutes: Int = 240  // 4 hours
    /// Distance threshold (meters) for location send gate; used for both device and search.
    private let locationDistanceThresholdMeters: Double = 200.0
    /// Time threshold (seconds) for device location send gate; e.g. 12 hours.
    private let locationTimeThresholdSeconds: TimeInterval = 12 * 3600
    
    // MARK: - Logger
    
    private let logger: Logger
    
    // MARK: - Initialization
    
    init(logger: Logger = AppLifecycleManager.sharedLogger) {
        self.logger = logger
        
        // Generate or load session ID
        if let savedSessionId = Storage.loadFromUserDefaults(forKey: sessionIdKey, as: String.self) {
            self.sessionId = savedSessionId
        } else {
            self.sessionId = UUID().uuidString
            Storage.saveToUserDefaults(sessionId, forKey: sessionIdKey)
        }
        
        // Load events on init
        loadEvents()
    }
    
    // MARK: - Main Event Workflow
    
    /// Main workflow method that handles complete event lifecycle
    /// - Parameters:
    ///   - event: The event to add
    ///   - skipBackendSend: If true, skip backend sending (useful when sending separately for SSE processing)
    /// - Returns: The SSE stream for chat events (if applicable), nil otherwise
    @discardableResult
    func addEvent(_ event: UserEvent, skipBackendSend: Bool = false) async throws -> AsyncThrowingStream<SSEEvent, Error>? {
        // Check session timeout before adding event
        if checkSessionTimeout() {
            await archiveSession()
        }
        
        // Ensure event has session_id
        let eventWithSession: UserEvent
        if event.session_id == nil {
            // Create new event with session_id
            eventWithSession = UserEvent(
                evt_utc: event.evt_utc,
                evt_timezone: event.evt_timezone,
                evt_type: event.evt_type,
                evt_data: event.evt_data,
                session_id: sessionId
            )
        } else {
            eventWithSession = event
        }
        
        // Add event to in-memory session
        thisSession.append(eventWithSession)
        
        // Update session timestamps
        updateSessionTimestamps()
        
        // If location event: derive locations and always send to backend
        if eventWithSession.evt_type == "location_detected" || eventWithSession.evt_type == "location_searched" {
            // Update latest derived locations from all sessions
            setLatestLocations()
            
            // Send event to backend (no deduplication; TrackingManager already throttles updates)
            let stream = try await sendEventToBackend(eventWithSession)
            
            // Persist all events automatically
            saveEvents()
            
            return stream
        } else if eventWithSession.evt_type == "chat_sent" {
            // Chat events: send if not skipped (returns stream for SSE processing)
            if !skipBackendSend {
                let stream = try await sendEventToBackend(eventWithSession)
                // Persist all events automatically
                saveEvents()
                return stream
            }
        } else if eventWithSession.evt_type == "chat_liked" || eventWithSession.evt_type == "chat_disliked" || eventWithSession.evt_type == "chat_bookmarked" {
            // Reaction events: send to backend (same /v1/chat); consume stream so connection closes, no SSE UI processing
            if let stream = try await sendEventToBackend(eventWithSession) {
                for try await _ in stream {}
            }
            saveEvents()
            return nil
        } else if eventWithSession.evt_type == "chat_received" {
            // Chat received: persist only (backend creates its own)
            doNothing()
        }
        
        // Persist all events automatically
        saveEvents()
        
        return nil
    }

    /// Placeholder for "do nothing" branches (e.g. chat_received: persist only, no backend send).
    private func doNothing() {}

    // MARK: - Location Derivation
    
    /// Scan events in reverse, set latest locations (mirrors backend logic)
    func setLatestLocations() {
        // Reset to ensure we pick the most recent events
        latestDeviceLocation = nil
        latestSearchLocation = nil
        
        // Get all events from all sessions (current + past)
        let allEvents = consolidateEvents()
        
        // Iterate in reverse to find the last occurrence of each event type
        for event in allEvents.reversed() {
            if event.evt_type == "location_detected" {
                if latestDeviceLocation == nil {
                    logger.debug("Set latest device location from events")
                    latestDeviceLocation = extractLocationFromEvent(event)
                }
            } else if event.evt_type == "location_searched" {
                if latestSearchLocation == nil {
                    logger.debug("Set latest search location from events")
                    latestSearchLocation = extractLocationFromEvent(event)
                }
            }
            
            // Break early if both locations have been found
            if latestDeviceLocation != nil && latestSearchLocation != nil {
                break
            }
        }
        
        // If no location_searched was found in history, use the same latest_device_location
        if latestSearchLocation == nil && latestDeviceLocation != nil {
            latestSearchLocation = latestDeviceLocation
        }
    }
    
    /// Extract location dictionary from event's evt_data
    private func extractLocationFromEvent(_ event: UserEvent) -> [String: JSONValue]? {
        // Location events store location in evt_data directly
        // The evt_data IS the NewLocation dictionary
        return event.evt_data
    }
    
    /// Consolidate events from thisSession and pastSessions
    private func consolidateEvents() -> [UserEvent] {
        var allEvents: [UserEvent] = []
        
        // Add current session events
        allEvents.append(contentsOf: thisSession)
        
        // Add past session events
        for sessionData in pastSessions.values {
            allEvents.append(contentsOf: sessionData.events)
        }
        
        return allEvents
    }
    
    /// Returns all chat_sent and chat_received events from current and past sessions, sorted by evt_utc ascending.
    /// Used to restore chat history on app relaunch.
    func chatEventsInOrder() -> [UserEvent] {
        let allEvents = consolidateEvents()
        return allEvents
            .filter { $0.evt_type == "chat_sent" || $0.evt_type == "chat_received" }
            .sorted { $0.evt_utc < $1.evt_utc }
    }
    
    // MARK: - Deduplication
    
    /// Single gate for location events: returns skip, send same location with new time (device only), or send new location.
    /// - Parameters:
    ///   - location: Location dict (must contain coordinate.lat/lng); for device can be a minimal dict from CLLocation.
    ///   - type: .device or .search
    /// - Returns: .skip = do nothing; .sendSameLocationNewTime = use latest location dict + new time (device, no geocode); .sendNewLocation = geocode and send (device) or send this dict (search).
    func locationSendDecision(_ location: [String: JSONValue], type: LocationType) -> LocationSendDecision {
        let comparisonLocation: [String: JSONValue]?
        switch type {
        case .device:
            comparisonLocation = latestDeviceLocation
        case .search:
            comparisonLocation = latestSearchLocation
        }

        guard let comparison = comparisonLocation else {
            return .sendNewLocation
        }

        guard let newCoord = extractCoordinate(from: location),
              let oldCoord = extractCoordinate(from: comparison) else {
            return .sendNewLocation
        }

        let distance = calculateDistance(newCoord, oldCoord)

        switch type {
        case .device:
            let now = Date()
            guard let lastSentAt = lastDeviceLocationSentAt() else {
                return .sendNewLocation
            }
            let timeSince = now.timeIntervalSince(lastSentAt)
            if distance <= locationDistanceThresholdMeters && timeSince < locationTimeThresholdSeconds {
                return .skip
            }
            if distance <= locationDistanceThresholdMeters && timeSince >= locationTimeThresholdSeconds {
                return .sendSameLocationNewTime
            }
            return .sendNewLocation
        case .search:
            if distance <= locationDistanceThresholdMeters && newCoord.latitude == oldCoord.latitude && newCoord.longitude == oldCoord.longitude {
                return .skip
            }
            return .sendNewLocation
        }
    }

    /// Convenience: returns true when we should send (i.e. not skip). Use when only send/skip matters (e.g. search after geocode).
    func shouldSendLocation(_ location: [String: JSONValue], type: LocationType) -> Bool {
        switch locationSendDecision(location, type: type) {
        case .skip: return false
        case .sendSameLocationNewTime, .sendNewLocation: return true
        }
    }

    
    /// Extract coordinate from location dictionary
    private func extractCoordinate(from location: [String: JSONValue]) -> (latitude: Double, longitude: Double)? {
        guard case .dictionary(let coordDict) = location["coordinate"],
              case .double(let lat) = coordDict["lat"],
              case .double(let lng) = coordDict["lng"] else {
            return nil
        }
        return (lat, lng)
    }
    
    /// Calculate distance between two coordinates in meters (Haversine formula)
    private func calculateDistance(_ coord1: (latitude: Double, longitude: Double),
                                   _ coord2: (latitude: Double, longitude: Double)) -> Double {
        let earthRadius: Double = 6371000  // meters

        let lat1Rad = coord1.latitude * .pi / 180
        let lat2Rad = coord2.latitude * .pi / 180
        let deltaLatRad = (coord2.latitude - coord1.latitude) * .pi / 180
        let deltaLngRad = (coord2.longitude - coord1.longitude) * .pi / 180

        let a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLngRad / 2) * sin(deltaLngRad / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadius * c
    }

    /// Returns the timestamp of the most recent device location (location_detected) event sent, or nil if none.
    private func lastDeviceLocationSentAt() -> Date? {
        let allEvents = consolidateEvents()
        guard let lastEvent = allEvents.filter({ $0.evt_type == "location_detected" }).max(by: { $0.evt_utc < $1.evt_utc }) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = formatter.date(from: lastEvent.evt_utc) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: lastEvent.evt_utc)
    }

    // MARK: - Backend Communication
    
    /// Send event to backend via uhpGateway
    /// Returns the stream for chat events (needed for SSE processing), nil for other events
    func sendEventToBackend(_ event: UserEvent) async throws -> AsyncThrowingStream<SSEEvent, Error>? {
        guard let uhpGateway = uhpGateway else {
            logger.warning("Cannot send event: uhpGateway not set", handlerType: "EventManager")
            return nil
        }
        
        // Determine endpoint based on event type
        let endpoint: String
        if event.evt_type == "chat_sent" || event.evt_type == "chat_liked" || event.evt_type == "chat_disliked" || event.evt_type == "chat_bookmarked" {
            endpoint = "/v1/chat"
        } else if event.evt_type == "location_detected" || event.evt_type == "location_searched" {
            endpoint = "/v1/orchestor"
        } else {
            logger.warning("Unknown event type for backend send: \(event.evt_type)", handlerType: "EventManager")
            return nil
        }
        
        // Stream event to backend
        let stream = try await uhpGateway.streamUserEvent(
            endpoint: endpoint,
            evtType: event.evt_type,
            evtData: event.evt_data
        )
        
        logger.debug("Sent \(event.evt_type) event to backend")
        
        // Return stream for chat events (needed for SSE processing)
        // if event.evt_type == "chat_sent" {
        //     return stream
        // }

        return stream
        
        // For location events, process stream but don't return it
        // (SSE processing happens elsewhere if needed)
        // return nil
    }
    
    // MARK: - Session Management
    
    /// Check if session timeout has been exceeded
    private func checkSessionTimeout() -> Bool {
        guard let lastActivity = lastActivityAt else {
            // No previous activity, session is active
            return false
        }
        
        let now = Date()
        let timeSinceLastActivity = now.timeIntervalSince(lastActivity)
        let inactivityThreshold = TimeInterval(inactivityTimeoutMinutes * 60)
        
        // Check inactivity timeout
        if timeSinceLastActivity > inactivityThreshold {
            logger.debug("Session timeout: \(Int(timeSinceLastActivity / 60)) minutes since last activity")
            return true
        }
        
        // Check max duration
        if let startedAt = sessionStartedAt {
            let sessionDuration = now.timeIntervalSince(startedAt)
            let maxDuration = TimeInterval(maxSessionDurationMinutes * 60)
            if sessionDuration > maxDuration {
                logger.debug("Session max duration exceeded: \(Int(sessionDuration / 60)) minutes")
                return true
            }
        }
        
        return false
    }
    
    /// Archive current session to past_sessions
    func archiveSession() async {
        guard !thisSession.isEmpty else {
            return
        }
        
        // Create session data
        let sessionData = SessionData(
            sessionId: sessionId,
            events: thisSession,
            startedAt: sessionStartedAt?.ISO8601Format(),
            lastActivityAt: lastActivityAt?.ISO8601Format()
        )
        
        // Add to past sessions
        pastSessions[sessionId] = sessionData
        
        // Clear current session
        thisSession = []
        
        // Generate new session ID
        sessionId = UUID().uuidString
        sessionStartedAt = nil
        lastActivityAt = nil
        
        logger.debug("Archived session \(sessionData.sessionId) with \(sessionData.events.count) events")
    }
    
    /// Update session timestamps
    private func updateSessionTimestamps() {
        let now = Date()
        
        // Set session_started_at from first event
        if sessionStartedAt == nil && !thisSession.isEmpty {
            sessionStartedAt = now
        }
        
        // Update last_activity_at
        lastActivityAt = now
    }
    
    // MARK: - Persistence
    
    /// Save events to UserDefaults
    func saveEvents() {
        // Encode thisSession
        if let thisSessionData = try? JSONEncoder().encode(thisSession),
           let thisSessionString = String(data: thisSessionData, encoding: .utf8) {
            Storage.saveToUserDefaults(thisSessionString, forKey: thisSessionKey)
        }
        
        // Encode pastSessions
        if let pastSessionsData = try? JSONEncoder().encode(pastSessions),
           let pastSessionsString = String(data: pastSessionsData, encoding: .utf8) {
            Storage.saveToUserDefaults(pastSessionsString, forKey: pastSessionsKey)
        }
        
        // Save session metadata
        Storage.saveToUserDefaults(sessionId, forKey: sessionIdKey)
        
        var metadata: [String: String] = [:]
        if let startedAt = sessionStartedAt {
            metadata["sessionStartedAt"] = startedAt.ISO8601Format()
        }
        if let lastActivity = lastActivityAt {
            metadata["lastActivityAt"] = lastActivity.ISO8601Format()
        }
        if !metadata.isEmpty {
            Storage.saveToUserDefaults(metadata, forKey: sessionMetadataKey)
        }
        
        // Save derived locations for widget and app-level use
        if let deviceLocation = latestDeviceLocation,
           let locationString = JSONValue.encodeToString(deviceLocation) {
            Storage.saveToUserDefaults(locationString, forKey: lastDeviceLocationKey)
        }
        
        if let searchLocation = latestSearchLocation,
           let searchLocationString = JSONValue.encodeToString(searchLocation) {
            Storage.saveToUserDefaults(searchLocationString, forKey: lastSearchLocationKey)
        }
        
        logger.debug("Saved events: \(thisSession.count) in current session, \(pastSessions.count) past sessions")
        printLastSavedEvents(count: 5)
    }
    
    /// Logs the last N saved events (by evt_utc, most recent first) for debugging.
    /// - Parameter count: Number of events to print (default: 5)
    /// evt_data is pretty-printed as standard JSON (JSONValue now encodes as standard JSON, not type-wrapped).
    private func printLastSavedEvents(count: Int = 5) {
        let allEvents = consolidateEvents()
        let sortedEvents = allEvents.sorted { $0.evt_utc > $1.evt_utc }
        let totalCount = sortedEvents.count
        let lastEvents = sortedEvents.prefix(count)
        logger.debug("Last \(count) events:\n=====================")
        for (relativeIndex, event) in lastEvents.enumerated() {
            let position = relativeIndex + 1
            let sessionLastDigits = event.session_id?.suffix(4) ?? "nil"
            let evtDataPretty = JSONValue.prettyDict(event.evt_data)
            logger.debug("\n❊ Event \(position)/\(totalCount) | \(event.evt_type) | session: \(sessionLastDigits) \n\(evtDataPretty)\n")
        }
    }
    
    /// Load events from UserDefaults
    func loadEvents() {
        // Load thisSession
        if let thisSessionString = Storage.loadFromUserDefaults(forKey: thisSessionKey, as: String.self),
           let thisSessionData = thisSessionString.data(using: .utf8),
           let loadedSession = try? JSONDecoder().decode([UserEvent].self, from: thisSessionData) {
            thisSession = loadedSession
        }
        
        // Load pastSessions
        if let pastSessionsString = Storage.loadFromUserDefaults(forKey: pastSessionsKey, as: String.self),
           let pastSessionsData = pastSessionsString.data(using: .utf8),
           let loadedPastSessions = try? JSONDecoder().decode([String: SessionData].self, from: pastSessionsData) {
            pastSessions = loadedPastSessions
        }
        
        // Load session metadata
        if let loadedSessionId = Storage.loadFromUserDefaults(forKey: sessionIdKey, as: String.self) {
            sessionId = loadedSessionId
        }
        
        if let metadata = Storage.loadFromUserDefaults(forKey: sessionMetadataKey, as: [String: String].self) {
            if let startedAtString = metadata["sessionStartedAt"],
               let startedAt = ISO8601DateFormatter().date(from: startedAtString) {
                sessionStartedAt = startedAt
            }
            if let lastActivityString = metadata["lastActivityAt"],
               let lastActivity = ISO8601DateFormatter().date(from: lastActivityString) {
                lastActivityAt = lastActivity
            }
        }
        
        // Derive locations from loaded events
        setLatestLocations()
        
        logger.debug("Loaded events: \(thisSession.count) in current session, \(pastSessions.count) past sessions")
    }
}
