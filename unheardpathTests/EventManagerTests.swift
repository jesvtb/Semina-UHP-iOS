import Testing
import Foundation
@testable import unheardpath


@Suite("Event Manager Tests")
struct EventManagerTests {
    
    @Test("Test adding an event to the current session")
    @MainActor func testAddEvent() async throws {
        let eventManager = EventManager()
        let originalCount = eventManager.thisSession.count
        
        let evtData: [String: JSONValue] = [
            "message": .string("Test message"),
            "device_lang": .string("en")
        ]

        let event = UserEventBuilder.build(evtType: "chat_sent", evtData: evtData)

        _ = try await eventManager.addEvent(event, skipBackendSend: true)

        try check(
            eventManager.thisSession.count == originalCount + 1, 
            success: "Event is added to current session", 
            failure: "Event is not added to current session")
        try check(
            eventManager.thisSession.first?.evt_type == "chat_sent", 
            success: "Event type matched", 
            failure: "Event type not matched: \(eventManager.thisSession.first?.evt_type ?? "nil")")
        try check(
            eventManager.thisSession.first?.evt_data["message"]?.stringValue == "Test message", 
            success: "Event data matched", 
            failure: "Event data not matched: \(eventManager.thisSession.first?.evt_data["message"]?.stringValue ?? "nil")")
    }

    @Test("Test loading events from UserDefaults")
    @MainActor func testLoadEvents() async throws {
        let eventManager = EventManager()
        eventManager.loadEvents()
        try check(
            eventManager.thisSession.count > 0, 
            success: "Events are loaded from UserDefaults", 
            failure: "Events are not loaded from UserDefaults")
        try check(
            eventManager.pastSessions.count > 0, 
            success: "Past sessions are loaded from UserDefaults", 
            failure: "Past sessions are not loaded from UserDefaults")
    }
}

