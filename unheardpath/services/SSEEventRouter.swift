import Foundation
import SwiftUI
import CoreLocation

/// Centralized router for SSE events from both /v1/chat and /v1/orchestrator endpoints
/// Routes events to appropriate managers based on event type
@MainActor
class SSEEventRouter: ObservableObject, SSEEventHandler {
    // Optional manager references - not all endpoints need all managers
    private weak var chatViewModel: ChatViewModel?
    private let contentManager: ContentManager?
    private let mapFeaturesManager: MapFeaturesManager?
    private let toastManager: ToastManager?
    
    // Callbacks for actions that need view coordination
    var onShowInfoSheet: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?
    
    init(
        chatViewModel: ChatViewModel? = nil,
        contentManager: ContentManager? = nil,
        mapFeaturesManager: MapFeaturesManager? = nil,
        toastManager: ToastManager? = nil
    ) {
        self.chatViewModel = chatViewModel
        self.contentManager = contentManager
        self.mapFeaturesManager = mapFeaturesManager
        self.toastManager = toastManager
    }
    
    /// Set ChatViewModel reference after initialization
    /// Called from AppContentView.onAppear after @StateObject is initialized
    func setChatViewModel(_ viewModel: ChatViewModel) {
        self.chatViewModel = viewModel
    }
    
    // MARK: - SSEEventHandler Implementation
    
    func onToast(_ toast: ToastData) async {
        #if DEBUG
        print("📬 SSEEventRouter: Routing toast to ToastManager")
        #endif
        toastManager?.show(toast)
    }
    
    func onChatChunk(content: String, isStreaming: Bool) async {
        #if DEBUG
        print("💬 SSEEventRouter: Routing chat chunk to ChatViewModel")
        #endif
        await chatViewModel?.handleChatChunk(content: content, isStreaming: isStreaming)
    }
    
    func onStop() async {
        #if DEBUG
        print("🛑 SSEEventRouter: Routing stop to ChatViewModel")
        #endif
        await chatViewModel?.handleStop()
    }
    
    func onMap(features: [[String: JSONValue]]) async {
        #if DEBUG
        print("🗺️ SSEEventRouter: Routing map features to MapFeaturesManager")
        #endif
        mapFeaturesManager?.apply(features: features)
        // Also dismiss keyboard when map arrives (UX improvement)
        onDismissKeyboard?()
    }
    
    func onHook(action: String) async {
        #if DEBUG
        print("🪝 SSEEventRouter: Routing hook action: \(action)")
        #endif
        if action.lowercased() == "show info sheet" {
            onShowInfoSheet?()
        }
    }
    
    func onContent(type: ContentViewType, data: ContentSection.ContentSectionData) async {
        #if DEBUG
        print("📄 SSEEventRouter: Routing content (\(type.rawValue)) to ContentManager")
        #endif
        contentManager?.setContent(type: type, data: data)
    }
}
