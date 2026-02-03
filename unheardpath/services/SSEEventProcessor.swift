import Foundation
import SwiftUI
import CoreLocation
import core

/// Unified SSE event processor that routes events to the router.
/// Stream yields SSEEvent from core; single-event path parses raw (event, data, id) via SSEEventType.parse.
@MainActor
class SSEEventProcessor {
    weak var router: SSEEventRouter?
    private let logger: Logger

    init(router: SSEEventRouter, logger: Logger = AppLifecycleManager.sharedLogger) {
        self.router = router
        self.logger = logger
    }

    /// Process a single raw SSE event (event type string, data string, id) and route the parsed event.
    nonisolated func processEvent(event eventString: String?, data dataString: String, id: String?) async {
        guard let eventType = SSEEventType(from: eventString) else {
            AppLifecycleManager.sharedLogger.warning("Unknown event type: \(eventString ?? "nil")", handlerType: "SSEEventProcessor")
            return
        }

        do {
            let event: SSEEvent
            if eventType == .map {
                event = try await Task.detached(priority: .userInitiated) {
                    try eventType.parse(event: eventString, data: dataString, id: id)
                }.value
            } else {
                event = try eventType.parse(event: eventString, data: dataString, id: id)
            }

            await MainActor.run {
                Task { @MainActor in
                    await self.router?.route(event)
                }
            }
        } catch {
            AppLifecycleManager.sharedLogger.error("Parse error for \(eventType.rawValue)", handlerType: "SSEEventProcessor", error: error)
        }
    }

    /// Process a stream of parsed SSE events (stream yields SSEEvent directly from core).
    nonisolated func processStream(_ stream: AsyncThrowingStream<SSEEvent, Error>) async throws {
        for try await event in stream {
            await MainActor.run {
                Task { @MainActor in
                    await self.router?.route(event)
                }
            }
        }
    }
}
