import Foundation
import SwiftUI
import CoreLocation
import core

/// Centralized router for SSE events from both /v1/chat and /v1/orchestrator endpoints
/// Routes events to appropriate managers based on event type
@MainActor
class SSEEventRouter: ObservableObject, SSEEventHandler {
    // Optional manager references - not all endpoints need all managers
    // Note: Strong reference is safe here because ChatViewModel only weakly references SSEEventRouter,
    // and both are managed by SwiftUI (as @StateObject and environmentObject), preventing retain cycles
    private var chatViewModel: ChatViewModel?
    private let contentManager: ContentManager?
    private let mapFeaturesManager: MapFeaturesManager?
    private let toastManager: ToastManager?
    
    // Logger for routing and debug
    private let logger: Logger
    
    // Callbacks for actions that need view coordination
    var onShowInfoSheet: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?
    
    init(
        chatViewModel: ChatViewModel? = nil,
        contentManager: ContentManager? = nil,
        mapFeaturesManager: MapFeaturesManager? = nil,
        toastManager: ToastManager? = nil,
        logger: Logger = AppLifecycleManager.sharedLogger
    ) {
        self.chatViewModel = chatViewModel
        self.contentManager = contentManager
        self.mapFeaturesManager = mapFeaturesManager
        self.toastManager = toastManager
        self.logger = logger
    }
    
    /// Set ChatViewModel reference after initialization
    /// Called from AppContentView.onAppear after @StateObject is initialized
    func setChatViewModel(_ viewModel: ChatViewModel) {
        self.chatViewModel = viewModel
    }
    
    // MARK: - SSEEventHandler Implementation
    
    func onToast(_ toast: ToastData) async {
        toastManager?.show(toast)
        logger.debug("Routing toast to ToastManager")
    }
    
    func onChatChunk(content: String, isStreaming: Bool) async {
        await chatViewModel?.handleChatChunk(content: content, isStreaming: isStreaming)
    }
    
    func onStop() async {
        await chatViewModel?.handleStop()
        logger.debug("Routing stop to ChatViewModel")
    }
    
    func onMap(features: [[String: JSONValue]]) async {
        logger.debug("Routing map features to MapFeaturesManager")
        mapFeaturesManager?.apply(features: features)
        // Also dismiss keyboard when map arrives (UX improvement)
        onDismissKeyboard?()
    }
    
    func onHook(action: String) async {
        logger.debug("Routing hook action: \(action)")
        if action.lowercased() == "show info sheet" {
            onShowInfoSheet?()
        }
    }
    
    func onContent(type: ContentViewType, data: ContentSection.ContentSectionData) async {
        logger.debug("Routing content (\(type.rawValue)) to ContentManager")
        contentManager?.setContent(type: type, data: data)
    }
}
