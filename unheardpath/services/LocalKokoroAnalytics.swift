import Foundation
import PostHog
import localKokoro

enum LocalKokoroAnalytics {
    static func makeAnalyticsHandler() -> LocalJourneySynthesisCoordinator.AnalyticsHandler {
        { event in
            #if DEBUG
            return
            #else
            var properties: [String: Any] = [:]
            for (key, value) in event.properties {
                properties[key] = value.postHogProperty
            }
            PostHogSDK.shared.capture(event.eventName, properties: properties)
            #endif
        }
    }
}
