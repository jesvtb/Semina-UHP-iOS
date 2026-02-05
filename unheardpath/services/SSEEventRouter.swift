import Foundation
import SwiftUI
import CoreLocation
import core

/// Centralized router for SSE events from both /v1/chat and /v1/orchestrator endpoints
/// Routes parsed payloads to appropriate managers based on event type
@MainActor
class SSEEventRouter: ObservableObject {
    private let chatManager: ChatManager
    private let catalogueManager: CatalogueManager?
    private let mapFeaturesManager: MapFeaturesManager?
    private let toastManager: ToastManager?
    private let logger: Logger

    var onShowInfoSheet: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?

    init(
        chatManager: ChatManager,
        catalogueManager: CatalogueManager? = nil,
        mapFeaturesManager: MapFeaturesManager? = nil,
        toastManager: ToastManager? = nil,
        logger: Logger = AppLifecycleManager.sharedLogger
    ) {
        self.chatManager = chatManager
        self.catalogueManager = catalogueManager
        self.mapFeaturesManager = mapFeaturesManager
        self.toastManager = toastManager
        self.logger = logger
    }

    /// Route a parsed SSE event to the appropriate manager
    func route(_ event: SSEEvent) async {
        switch event {
        case .toast(let message, _, let variant):
            let toastData = ToastData(type: variant, message: message)
            toastManager?.show(toastData)
            logger.debug("Routing toast to ToastManager")

        case .chat(let chatId, let chunk, let isStreaming):
            await chatManager.handleChatChunk(chatId: chatId, content: chunk, isStreaming: isStreaming)

        case .stop:
            await chatManager.handleStop()
            logger.debug("Routing stop to ChatManager")

        case .map(let features):
            mapFeaturesManager?.apply(features: features)
            onDismissKeyboard?()
            logger.debug("Routed map with \(features.count) features")

        case .hook(let action):
            logger.debug("Routing hook action: \(action)")
            if action.lowercased() == "show info sheet" {
                onShowInfoSheet?()
            }

        case .catalogue(let typeString, let dataValue):
            // Extract action (default to "replace")
            let actionString = dataValue["action"]?.stringValue ?? "replace"
            let action = CatalogueAction(rawValue: actionString) ?? .replace
            
            // Extract display title (from server or derive from type)
            let displayTitle = dataValue["display_title"]?.stringValue
                ?? typeString.replacingOccurrences(of: "_", with: " ").capitalized
            
            // Extract config and content
            let config = dataValue["config"]
            let content = dataValue["content"] ?? .dictionary([:])
            
            // Route to CatalogueManager with action
            catalogueManager?.handleCatalogue(
                sectionType: typeString,
                displayTitle: displayTitle,
                action: action,
                config: config,
                content: content
            )
            logger.debug("Routed catalogue: \(typeString) with action: \(actionString)")
        }
    }
}
