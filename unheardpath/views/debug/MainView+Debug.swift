import SwiftUI
import core

// MARK: - Debug Components
extension MainView {
    /// User IDs that can access debug views in production builds
    private static let debugAllowedUserIDs: Set<String> = [
        // Add allowed user UUIDs here, e.g.:
        "c1a4eee7-8fb1-496e-be39-a58d6e8257e7",  // Jessica
    ]
    
    /// Whether the current user is allowed to see debug views.
    /// Always true in DEBUG builds; checks allowlist in RELEASE builds.
    var isDebugAccessAllowed: Bool {
        #if DEBUG
        return true
        #else
        return Self.debugAllowedUserIDs.contains(authManager.userID)
        #endif
    }
    
    var debugCacheButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    showCacheDebugSheet = true
                }) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 12))
                        .foregroundColor(Color("onBkgTextColor30"))
                        .padding(8)
                        .background(
                            Color("AppBkgColor")
                                .opacity(0.8)
                                .cornerRadius(8)
                        )
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
                .offset(y: 48) // Position below avatar button
            }
            Spacer()
        }
    }
    
    var debugSSEContentTestButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    showSSEContentTestSheet = true
                }) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color("onBkgTextColor30"))
                        .padding(8)
                        .background(
                            Color("AppBkgColor")
                                .opacity(0.8)
                                .cornerRadius(8)
                        )
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
                .offset(y: 88) // Position below cache button
            }
            Spacer()
        }
    }
    
    var debugPersistenceButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    showPersistenceDebugSheet = true
                }) {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 12))
                        .foregroundColor(Color("onBkgTextColor30"))
                        .padding(8)
                        .background(
                            Color("AppBkgColor")
                                .opacity(0.8)
                                .cornerRadius(8)
                        )
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
                .offset(y: 128) // Position below SSE test button
            }
            Spacer()
        }
    }
    
    var cacheDebugSheet: some View {
        NavigationView {
            CacheDebugContentView(
                onClearCache: {
                    clearCache()
                    showCacheDebugSheet = false
                },
                onDismiss: {
                    showCacheDebugSheet = false
                }
            )
            .environmentObject(eventManager)
        }
    }
    
    func clearCache() {
        DebugVisualizer.clearAllCache()
        #if DEBUG
        print("Cache cleared from debug button")
        #endif
    }
}

#if DEBUG
#Preview("Map Tab with last user message") {
    let uhpGateway = UHPGateway()
    let trackingManager = TrackingManager()
    let userManager = UserManager()
    let authManager = AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7")
    let chatManager = ChatManager(
        uhpGateway: uhpGateway,
        userManager: userManager
    )
    let mapFeaturesManager = MapFeaturesManager()
    let toastManager = ToastManager()
    let catalogueManager = CatalogueManager()
    let sseEventRouter = SSEEventRouter(chatManager: chatManager, catalogueManager: catalogueManager, mapFeaturesManager: mapFeaturesManager, toastManager: toastManager)
    let eventManager = EventManager()
    let autocompleteManager = AutocompleteManager(geoapifyApiKey: "")
    MainView(previewTab: .map, previewLastMessage: ChatMessage(text: "Hello, world!", isUser: true, isStreaming: false))
        .environmentObject(authManager)
        .environmentObject(uhpGateway)
        .environmentObject(trackingManager)
        .environmentObject(userManager)
        .environmentObject(chatManager)
        .environmentObject(mapFeaturesManager)
        .environmentObject(toastManager)
        .environmentObject(catalogueManager)
        .environmentObject(sseEventRouter)
        .environmentObject(eventManager)
        .environmentObject(autocompleteManager)
        .environment(\.geocoder, Geocoder(geoapifyApiKey: ""))
}

#Preview("Journey Tab with last assistant message") {
    let uhpGateway = UHPGateway()
    let trackingManager = TrackingManager()
    let userManager = UserManager()
    let authManager = AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7")
    let chatManager = ChatManager(
        uhpGateway: uhpGateway,
        userManager: userManager
    )
    let mapFeaturesManager = MapFeaturesManager()
    let toastManager = ToastManager()
    let catalogueManager = CatalogueManager()
    let sseEventRouter = SSEEventRouter(chatManager: chatManager, catalogueManager: catalogueManager, mapFeaturesManager: mapFeaturesManager, toastManager: toastManager)
    let eventManager = EventManager()
    let autocompleteManager = AutocompleteManager(geoapifyApiKey: "")
    MainView(previewTab: .journey, previewLastMessage: ChatMessage(text: "Maximus morbi habitasse dictumst curae aenean fermentum senectus nunc elementum quis pretium, dui feugiat gravida sem ad tempor conubia vehicula tortor volutpat, facilisis pulvinar nam fusce praesent ac commodo himenaeos donec lorem. Quis ullamcorper porttitor vitae placerat ad dis eu habitasse venenatis, rhoncus cursus suspendisse in adipiscing posuere mattis tristique donec, rutrum nostra congue velit mauris malesuada montes consequat. Mus est natoque nibh torquent hendrerit scelerisque phasellus consequat auctor praesent, diam neque venenatis quisque cursus vestibulum taciti curae congue, lorem etiam proin accumsan potenti montes tincidunt donec magna.", isUser: false, isStreaming: false))
        .environmentObject(authManager)
        .environmentObject(uhpGateway)
        .environmentObject(trackingManager)
        .environmentObject(userManager)
        .environmentObject(chatManager)
        .environmentObject(mapFeaturesManager)
        .environmentObject(toastManager)
        .environmentObject(catalogueManager)
        .environmentObject(sseEventRouter)
        .environmentObject(eventManager)
        .environmentObject(autocompleteManager)
        .environment(\.geocoder, Geocoder(geoapifyApiKey: ""))
}
#endif
