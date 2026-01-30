import Testing
import Foundation
@testable import core

@Suite("Events tests")
struct EventsTests {

    @Test("UserEventBuilder.build produces UserEvent with evt_utc and evt_type")
    func userEventBuilderBuild() {
        let evtData: [String: JSONValue] = ["key": .string("value")]
        let event = UserEventBuilder.build(evtType: "test_type", evtData: evtData)

        expect(
            !event.evt_utc.isEmpty,
            success: "evt_utc is non-empty",
            failure: "evt_utc is empty"
        )
        expect(
            event.evt_type == "test_type",
            success: "evt_type is test_type",
            failure: "evt_type is not test_type: \(event.evt_type)"
        )
        expect(
            event.evt_data["key"]?.stringValue == "value",
            success: "evt_data key equals value",
            failure: "evt_data key is not value: \(event.evt_data["key"]?.stringValue ?? "nil")"
        )
        expect(
            event.evt_timezone != nil,
            success: "evt_timezone is set",
            failure: "evt_timezone is nil"
        )
        expect(
            event.session_id == nil,
            success: "session_id is nil when not passed",
            failure: "session_id is not nil: \(event.session_id ?? "nil")"
        )
    }
}
