import Foundation
import SwiftUI
import CoreLocation
import core

/// Centralized router for SSE events from both /v1/chat and /v1/orchestrator endpoints
/// Routes parsed payloads to appropriate managers based on event type
@MainActor
class SSEEventRouter: ObservableObject {
    private var chatManager: ChatManager?
    private let contentManager: ContentManager?
    private let mapFeaturesManager: MapFeaturesManager?
    private let toastManager: ToastManager?
    private let logger: Logger

    var onShowInfoSheet: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?

    init(
        chatManager: ChatManager? = nil,
        contentManager: ContentManager? = nil,
        mapFeaturesManager: MapFeaturesManager? = nil,
        toastManager: ToastManager? = nil,
        logger: Logger = AppLifecycleManager.sharedLogger
    ) {
        self.chatManager = chatManager
        self.contentManager = contentManager
        self.mapFeaturesManager = mapFeaturesManager
        self.toastManager = toastManager
        self.logger = logger
    }

    /// Set ChatManager reference after initialization
    func setChatManager(_ manager: ChatManager) {
        self.chatManager = manager
    }

    /// Set content directly (e.g. for testing or when already holding ContentSectionData).
    /// For parsed SSE events use route(.content(typeString:dataValue:)) instead.
    func setContent(type: ContentViewType, data: ContentSection.ContentSectionData) {
        contentManager?.setContent(type: type, data: data)
    }

    /// Route a parsed SSE event to the appropriate manager
    func route(_ event: SSEEvent) async {
        switch event {
        case .toast(let message, _, let variant):
            let toastData = ToastData(type: variant, message: message)
            toastManager?.show(toastData)
            logger.debug("Routing toast to ToastManager")

        case .chat(let chunk, let isStreaming):
            await chatManager?.handleChatChunk(content: chunk, isStreaming: isStreaming)

        case .stop:
            await chatManager?.handleStop()
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

        case .content(let typeString, let dataValue):
            guard let contentType = ContentViewType(rawValue: typeString) else {
                logger.warning("Unknown content type: \(typeString)", handlerType: "SSEEventRouter")
                return
            }
            guard let contentData = ContentTypeRegistry.shared().parse(type: contentType, dataValue: dataValue.asAny) else {
                logger.warning("Failed to parse content type: \(typeString)", handlerType: "SSEEventRouter")
                return
            }
            contentManager?.setContent(type: contentType, data: contentData)
            logger.debug("Routed content: \(typeString)")
        }
    }
}
