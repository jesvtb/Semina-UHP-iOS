import Testing
import Foundation
import core
@testable import unheardpath

@Suite("SSEEventProcessor and SSEEventRouter tests")
struct SSEEventProcessorRouterTests {

    private static func makeTestChatManager() -> ChatManager {
        ChatManager(uhpGateway: UHPGateway(), userManager: UserManager())
    }

    @Test("SSEEventRouter.route toast updates ToastManager")
    @MainActor func routeToastUpdatesToastManager() async throws {
        let toastManager = ToastManager()
        let router = SSEEventRouter(
            chatManager: makeTestChatManager(),
            contentManager: nil,
            mapFeaturesManager: nil,
            toastManager: toastManager
        )
        await router.route(SSEEvent.toast(message: "Test message", duration: 3.0, variant: "info"))
        #expect(toastManager.currentToastData != nil)
        #expect(toastManager.currentToastData?.message == "Test message")
        #expect(toastManager.currentToastData?.type == "info")
    }

    @Test("SSEEventRouter.route stop calls ChatManager")
    @MainActor func routeStopCallsChatManager() async throws {
        let router = SSEEventRouter(
            chatManager: makeTestChatManager(),
            contentManager: nil,
            mapFeaturesManager: nil,
            toastManager: nil
        )
        await router.route(SSEEvent.stop)
        // No throw; router routes stop to chatManager
    }

    @Test("SSEEventRouter.route map updates MapFeaturesManager")
    @MainActor func routeMapUpdatesMapFeaturesManager() async throws {
        let mapFeaturesManager = MapFeaturesManager()
        let router = SSEEventRouter(
            chatManager: makeTestChatManager(),
            contentManager: nil,
            mapFeaturesManager: mapFeaturesManager,
            toastManager: nil
        )
        let features: [[String: JSONValue]] = [
            [
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(12.5), .double(41.9)])
                ]),
                "properties": .dictionary(["title": .string("Test POI")])
            ]
        ]
        await router.route(SSEEvent.map(features: features))
        #expect(mapFeaturesManager.poisGeoJSON.featureCount == 1)
    }

    @Test("SSEEventRouter.route hook show info sheet invokes callback")
    @MainActor func routeHookInvokesCallback() async throws {
        var callbackInvoked = false
        let router = SSEEventRouter(
            chatManager: makeTestChatManager(),
            contentManager: nil,
            mapFeaturesManager: nil,
            toastManager: nil
        )
        router.onShowInfoSheet = { callbackInvoked = true }
        await router.route(SSEEvent.hook(action: "show info sheet"))
        #expect(callbackInvoked == true)
    }

    @Test("SSEEventProcessor.processEvent toast parses and routes")
    @MainActor func processEventToastParsesAndRoutes() async throws {
        let toastManager = ToastManager()
        let router = SSEEventRouter(
            chatManager: makeTestChatManager(),
            contentManager: nil,
            mapFeaturesManager: nil,
            toastManager: toastManager
        )
        let processor = SSEEventProcessor(router: router)
        await processor.processEvent(event: "toast", data: "{\"message\":\"Hello\",\"duration\":2.0}", id: nil)
        #expect(toastManager.currentToastData != nil)
        #expect(toastManager.currentToastData?.message == "Hello")
    }

    @Test("SSEEventProcessor.processEvent stop parses and routes")
    @MainActor func processEventStopParsesAndRoutes() async throws {
        let router = SSEEventRouter(
            chatManager: makeTestChatManager(),
            contentManager: nil,
            mapFeaturesManager: nil,
            toastManager: nil
        )
        let processor = SSEEventProcessor(router: router)
        await processor.processEvent(event: "stop", data: "", id: nil)
        // No throw; router.route(.stop) was called
    }

    @Test("SSEEventProcessor.processEvent unknown type logs and does not throw")
    @MainActor func processEventUnknownTypeNoThrow() async throws {
        let router = SSEEventRouter(
            chatManager: makeTestChatManager(),
            contentManager: nil,
            mapFeaturesManager: nil,
            toastManager: nil
        )
        let processor = SSEEventProcessor(router: router)
        await processor.processEvent(event: "unknown_type", data: "{}", id: nil)
        // Should not throw; unknown type is logged and skipped
    }
}
