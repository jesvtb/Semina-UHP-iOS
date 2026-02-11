//
//  unheardpathApp.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI
import MapboxMaps
import PostHog
import UIKit
@preconcurrency import UserNotifications
import ActivityKit
import core

/// Environment key for injecting Geocoder so views can use reverse geocoding (location → LocationDict).
private struct GeocoderEnvironmentKey: EnvironmentKey {
    static let defaultValue: Geocoder = Geocoder(geoapifyApiKey: "")
}
extension EnvironmentValues {
    var geocoder: Geocoder {
        get { self[GeocoderEnvironmentKey.self] }
        set { self[GeocoderEnvironmentKey.self] = newValue }
    }
}

/// AppDelegate to handle remote notification registration and LiveActivity push notifications
/// According to Apple documentation: https://developer.apple.com/documentation/UIKit/UIApplication/registerForRemoteNotifications()
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set up notification center delegate for handling push notifications
        UNUserNotificationCenter.current().delegate = self
        
        // Register for remote notifications each time the app launches
        // Reference: https://developer.apple.com/documentation/UIKit/UIApplication/registerForRemoteNotifications()
        application.registerForRemoteNotifications()
        AppLifecycleManager.sharedLogger.debug("Registered for remote notifications")
        return true
    }
    
    /// Called when the app successfully registers with APNs and receives a device token
    /// Reference: https://developer.apple.com/documentation/UIKit/UIApplicationDelegate/application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert device token to string format
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        AppLifecycleManager.sharedLogger.debug("Successfully registered for remote notifications")
        AppLifecycleManager.sharedLogger.debug("Device token for Notification: \(tokenString)")
        
        // TODO: Send device token to your provider server
        // Your provider server must have this token before it can deliver notifications to the device
    }
    
    /// Called when the app fails to register with APNs
    /// Reference: https://developer.apple.com/documentation/UIKit/UIApplicationDelegate/application(_:didFailToRegisterForRemoteNotificationsWithError:)
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLifecycleManager.sharedLogger.error("Failed to register for remote notifications", handlerType: "AppDelegate", error: error)
    }
}

// MARK: - UNUserNotificationCenterDelegate
// Separate extension to avoid Swift 6 concurrency warning on protocol conformance
// The delegate methods are marked as nonisolated since they're called by the system
// This is a known Swift 6 strict concurrency limitation with UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    
    /// Called when a remote notification is received while the app is in the foreground
    /// Reference: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        AppLifecycleManager.sharedLogger.debug("Received remote notification while app is in foreground")
        
        // Check if this is a LiveActivity update notification
        if let aps = userInfo["aps"] as? [String: Any],
           let event = aps["event"] as? String {
            AppLifecycleManager.sharedLogger.debug("LiveActivity event: \(event)")
            if let contentState = aps["content-state"] as? [String: Any] {
                AppLifecycleManager.sharedLogger.debug("Content state: \(contentState)")
            }
        }
        
        // For LiveActivity updates, the system handles them automatically
        // We don't need to show a banner, but you can customize this behavior
        // For regular notifications, you might want to show a banner:
        // completionHandler([.banner, .sound, .badge])
        
        // For LiveActivities, we don't show a notification banner since the LiveActivity itself is the UI
        completionHandler([])
    }
    
    /// Called when the user taps on a notification
    /// Reference: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        AppLifecycleManager.sharedLogger.debug("User tapped on notification")
        
        // Check if this is a LiveActivity update notification
        if let aps = userInfo["aps"] as? [String: Any],
           let event = aps["event"] as? String {
            AppLifecycleManager.sharedLogger.debug("LiveActivity event: \(event)")
        }
        
        // Handle notification tap if needed
        // For LiveActivities, the system handles navigation automatically
        
        completionHandler()
    }
}

@main
struct unheardpathApp: App {
    // Connect AppDelegate to SwiftUI App
    // This allows the AppDelegate methods to be called
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // @StateObject creates singleton instances that persist across view updates
    // Similar to React Context Providers - these are created once and shared throughout the app
    @StateObject private var userManager = UserManager()
    @StateObject private var authManager = AuthManager()
    @State private var apiClient = APIClient(logger: AppLifecycleManager.sharedLogger)
    @StateObject private var uhpGateway = UHPGateway()
    @StateObject private var trackingManager = TrackingManager()
    @StateObject private var appLifecycleManager = AppLifecycleManager()
    @StateObject private var mapFeaturesManager = MapFeaturesManager()
    @StateObject private var toastManager = ToastManager()
    @StateObject private var catalogueManager = CatalogueManager()
    @StateObject private var eventManager = EventManager()
    @StateObject private var autocompleteManager: AutocompleteManager
    private let geocoder: Geocoder

    // Logger for app initialization logging
    private var logger: Logger {
        AppLifecycleManager.sharedLogger
    }
    
    init() {
        let geoapifyApiKey = Bundle.main.infoDictionary?["GEOAPIFY_API_KEY"] as? String ?? ""
        _autocompleteManager = StateObject(wrappedValue: AutocompleteManager(geoapifyApiKey: geoapifyApiKey))
        geocoder = Geocoder(geoapifyApiKey: geoapifyApiKey)

        // Configure shared storage (App Group + UHP prefix) for app and widget
        Storage.configure(
            userDefaults: UserDefaults(suiteName: "group.com.semina.unheardpath") ?? .standard,
            keyPrefix: "UHP.",
            documentsURL: nil,
            cachesURL: nil,
            appSupportURL: nil
        )
        // Log app startup configuration
        logger.debug("🚀 Starting App")
        #if DEBUG
        logger.debug("Configuration: DEBUG (Development)")
        #else
        logger.debug("Configuration: RELEASE (Production)")
        #endif

        // Detect version upgrade (sets flags only; cache clearing happens in onAppear)
        appLifecycleManager.checkForVersionUpgrade()

        // CRITICAL: Set UserManager reference BEFORE AuthManager checks session
        authManager.setUserManager(userManager)

        setupMapboxToken()
        setupPostHog()
    }
    
    var body: some Scene {
        WindowGroup {
            AppContentView(
                authManager: authManager,
                apiClient: apiClient,
                trackingManager: trackingManager,
                uhpGateway: uhpGateway,
                userManager: userManager,
                appLifecycleManager: appLifecycleManager,
                mapFeaturesManager: mapFeaturesManager,
                toastManager: toastManager,
                catalogueManager: catalogueManager,
                eventManager: eventManager,
                autocompleteManager: autocompleteManager,
                geocoder: geocoder
            )
            .id("app-content-view") // Stable identity ensures @StateObject persists
        }
    }
    
    /// Sets Mapbox access token programmatically
    /// This ensures the token is available even if Info.plist injection fails on device builds
    /// According to Mapbox docs, setting MapboxOptions.accessToken programmatically
    /// takes precedence over Info.plist, so this is the primary method
    private func setupMapboxToken() {
        guard let token = Bundle.main.infoDictionary?["MBXAccessToken"] as? String,
              !token.isEmpty,
              token.hasPrefix("pk.") else {
            logger.warning("Mapbox token not found in Info.plist or invalid format", handlerType: "unheardpathApp")
            return
        }
        MapboxOptions.accessToken = token
        
        // Verify token is set
        if MapboxOptions.accessToken.isEmpty {
            logger.error("Mapbox token injection failed - using programmatic token", handlerType: "unheardpathApp", error: nil)
        } else {
            logger.debug("Mapbox token configured successfully")
        }
    }
    
    /// Sets up PostHog analytics using values from Info.plist (injected via xcconfig files)
    /// PostHog is enabled only in RELEASE builds, disabled in DEBUG builds
    private func setupPostHog() {
        #if DEBUG
        // PostHog tracking disabled for development builds
        logger.debug("PostHog tracking disabled (DEBUG build)")
        return
        #else

        guard let apiKey = Bundle.main.infoDictionary?["POSTHOG_API_KEY"] as? String,
              !apiKey.isEmpty,
              let host = Bundle.main.infoDictionary?["POSTHOG_HOST"] as? String,
              !host.isEmpty else {
            logger.warning("POSTHOG_API_KEY or POSTHOG_HOST missing/invalid in Info.plist, skipping PostHog setup", handlerType: "unheardpathApp")
            return
        }
        
        let hostWithProtocol = "https://\(host)"
        
        logger.debug("PostHog configured (RELEASE build)")
        
        let config = PostHogConfig(apiKey: apiKey, host: hostWithProtocol)
        PostHogSDK.shared.setup(config)
        #endif
    }
}

/// Helper view that receives app-level managers and sets up content configuration.
/// ChatManager is created here (not in the root App) because creating it in the App init would require
/// reading self (uhpGateway, userManager) before all stored properties are set, which Swift disallows.
private struct AppContentView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let trackingManager: TrackingManager
    let uhpGateway: UHPGateway
    let userManager: UserManager
    let appLifecycleManager: AppLifecycleManager
    let mapFeaturesManager: MapFeaturesManager
    let toastManager: ToastManager
    let catalogueManager: CatalogueManager
    let eventManager: EventManager
    let autocompleteManager: AutocompleteManager
    let geocoder: Geocoder
    let sseEventRouter: SSEEventRouter

    @StateObject private var chatManager: ChatManager

    init(
        authManager: AuthManager,
        apiClient: APIClient,
        trackingManager: TrackingManager,
        uhpGateway: UHPGateway,
        userManager: UserManager,
        appLifecycleManager: AppLifecycleManager,
        mapFeaturesManager: MapFeaturesManager,
        toastManager: ToastManager,
        catalogueManager: CatalogueManager,
        eventManager: EventManager,
        autocompleteManager: AutocompleteManager,
        geocoder: Geocoder
    ) {
        self.authManager = authManager
        self.apiClient = apiClient
        self.trackingManager = trackingManager
        self.uhpGateway = uhpGateway
        self.userManager = userManager
        self.appLifecycleManager = appLifecycleManager
        self.mapFeaturesManager = mapFeaturesManager
        self.toastManager = toastManager
        self.catalogueManager = catalogueManager
        self.eventManager = eventManager
        self.autocompleteManager = autocompleteManager
        self.geocoder = geocoder
        let chatManager = ChatManager(uhpGateway: uhpGateway, userManager: userManager)
        _chatManager = StateObject(wrappedValue: chatManager)
        self.sseEventRouter = SSEEventRouter(
            chatManager: chatManager,
            catalogueManager: catalogueManager,
            mapFeaturesManager: mapFeaturesManager,
            toastManager: toastManager
        )
    }
    
    var body: some View {
        ContentView()
            .environmentObject(authManager) // Pass auth state to all views (like React Context)
            .environmentObject(trackingManager) // Pass tracking manager to all views (GPS tracking)
            .environmentObject(uhpGateway) // Pass UHP Gateway to all views
            .environmentObject(userManager) // Pass user manager to all views
            .environmentObject(chatManager) // Pass chat manager to all views
            .environmentObject(mapFeaturesManager) // Pass map features manager to all views
            .environmentObject(toastManager) // Pass toast manager to all views
            .environmentObject(catalogueManager) // Pass catalogue manager to all views
            .environmentObject(eventManager) // Pass event manager to all views
            .environmentObject(autocompleteManager) // Pass autocomplete manager to all views
            .environment(\.geocoder, geocoder) // Pass geocoder for reverse geocoding (location → LocationDict)
            .environmentObject(sseEventRouter) // Pass SSE event router to all views
            .withScaledSpacing() // Inject scaled spacing values into environment
            .onAppear {
                // Set appLifecycleManager reference - auto-registration happens in didSet
                // TrackingManager automatically registers itself when appLifecycleManager is set
                trackingManager.appLifecycleManager = appLifecycleManager
                
                // Wire up EventManager dependencies (delayed injection pattern)
                eventManager.uhpGateway = uhpGateway
                
                // Wire up TrackingManager dependencies
                trackingManager.eventManager = eventManager

                // Wire up ChatManager dependencies
                chatManager.eventManager = eventManager
                chatManager.loadHistory()
                
                // Wire up catalogue persistence and restore cached content
                let catalogueFileStore = CatalogueFileStore()
                catalogueManager.setPersistence(catalogueFileStore)
                
                Task {
                    // Restore catalogue from cache using last-known location
                    if let lookupLocation = eventManager.latestLookupLocation,
                       let locationDetail = LocationDetailData(eventDict: lookupLocation) {
                        await catalogueManager.restoreFromCache(for: locationDetail)
                    } else if let deviceLocation = eventManager.latestDeviceLocation,
                              let locationDetail = LocationDetailData(eventDict: deviceLocation) {
                        await catalogueManager.restoreFromCache(for: locationDetail)
                    } else {
                        // No location available -- restore last active context
                        await catalogueManager.restoreFromCache()
                    }
                }
            }
            .onOpenURL { url in
                Task {
                    do {
                        AppLifecycleManager.sharedLogger.debug("App-level callback URL: \(url.absoluteString)")
                        
                        // session(from: url) handles both implicit and PKCE flows automatically
                        // It extracts token_hash if present and verifies it, or uses implicit flow tokens
                        // Reference: https://supabase.com/docs/guides/auth/auth-email-passwordless
                        try await supabase.auth.session(from: url)
                        
                        // After session is created from URL, authManager will detect the change
                        // via authStateChanges listener
                    } catch {
                        AppLifecycleManager.sharedLogger.error("Error handling auth callback", handlerType: "AppContentView", error: error)
                    }
                }
            }
            .task {
                // Request location permission when app appears
                trackingManager.requestLocationPermission()
            }
    }
}
