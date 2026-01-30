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
    @StateObject private var geoapifyGateway = GeoapifyGateway()
    @StateObject private var trackingManager = TrackingManager()
    @StateObject private var locationManager = LocationManager()  // Still needed for geocoding/geofencing
    @StateObject private var appLifecycleManager = AppLifecycleManager()
    @StateObject private var mapFeaturesManager = MapFeaturesManager()
    @StateObject private var toastManager = ToastManager()
    @StateObject private var contentManager = ContentManager()
    @StateObject private var eventManager = EventManager()
    @StateObject private var addressSearchManager = AddressSearchManager()  // Moved to app-level for dependency injection
    
    // Logger for app initialization logging
    private var logger: AppLifecycleLogger {
        AppLifecycleManager.sharedLogger
    }
    
    init() {
        // Log app startup configuration
        logger.debug("🚀 Starting App")
        #if DEBUG
        logger.debug("Configuration: DEBUG (Development)")
        #else
        logger.debug("Configuration: RELEASE (Production)")
        #endif
        
        // CRITICAL: Set UserManager reference BEFORE AuthManager checks session
        // This ensures userManager is available when session check completes
        // and sets currentUser, preventing race conditions
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
                locationManager: locationManager,
                uhpGateway: uhpGateway,
                geoapifyGateway: geoapifyGateway,
                userManager: userManager,
                appLifecycleManager: appLifecycleManager,
                mapFeaturesManager: mapFeaturesManager,
                toastManager: toastManager,
                contentManager: contentManager,
                eventManager: eventManager,
                addressSearchManager: addressSearchManager
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

/// Helper view that initializes ChatViewModel with dependencies and sets up app-level configuration
/// ChatViewModel requires other @StateObject dependencies, so it must be created here where they're available
private struct AppContentView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let trackingManager: TrackingManager
    let locationManager: LocationManager  // Still needed for geocoding/geofencing
    let uhpGateway: UHPGateway
    let geoapifyGateway: GeoapifyGateway
    let userManager: UserManager
    let appLifecycleManager: AppLifecycleManager
    let mapFeaturesManager: MapFeaturesManager
    let toastManager: ToastManager
    let contentManager: ContentManager
    let eventManager: EventManager
    let addressSearchManager: AddressSearchManager
    let sseEventRouter: SSEEventRouter
    
    // Create ChatViewModel as @StateObject with proper dependencies
    @StateObject private var chatViewModel: ChatViewModel
    
    init(
        authManager: AuthManager,
        apiClient: APIClient,
        trackingManager: TrackingManager,
        locationManager: LocationManager,
        uhpGateway: UHPGateway,
        geoapifyGateway: GeoapifyGateway,
        userManager: UserManager,
        appLifecycleManager: AppLifecycleManager,
        mapFeaturesManager: MapFeaturesManager,
        toastManager: ToastManager,
        contentManager: ContentManager,
        eventManager: EventManager,
        addressSearchManager: AddressSearchManager
    ) {
        self.authManager = authManager
        self.apiClient = apiClient
        self.trackingManager = trackingManager
        self.locationManager = locationManager
        self.uhpGateway = uhpGateway
        self.geoapifyGateway = geoapifyGateway
        self.userManager = userManager
        self.appLifecycleManager = appLifecycleManager
        self.mapFeaturesManager = mapFeaturesManager
        self.toastManager = toastManager
        self.contentManager = contentManager
        self.eventManager = eventManager
        self.addressSearchManager = addressSearchManager
        
        // Initialize ChatViewModel (no manager dependencies)
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(
            uhpGateway: uhpGateway,
            userManager: userManager
        ))
        
        // Create SSEEventRouter with all managers
        // Note: chatViewModel will be set in onAppear after StateObject is initialized
        self.sseEventRouter = SSEEventRouter(
            chatViewModel: nil, // Will be set in onAppear
            contentManager: contentManager,
            mapFeaturesManager: mapFeaturesManager,
            toastManager: toastManager
        )
    }
    
    var body: some View {
        ContentView()
            .environmentObject(authManager) // Pass auth state to all views (like React Context)
            // apiClient passed via AppContentView init (core.APIClient is not ObservableObject)
            .environmentObject(trackingManager) // Pass tracking manager to all views (GPS tracking)
            .environmentObject(locationManager) // Pass location manager to all views (geocoding/geofencing)
            .environmentObject(uhpGateway) // Pass UHP Gateway to all views
            .environmentObject(geoapifyGateway) // Pass Geoapify Gateway to all views
            .environmentObject(userManager) // Pass user manager to all views
            .environmentObject(chatViewModel) // Pass chat view model to all views
            .environmentObject(mapFeaturesManager) // Pass map features manager to all views
            .environmentObject(toastManager) // Pass toast manager to all views
            .environmentObject(contentManager) // Pass content manager to all views
            .environmentObject(eventManager) // Pass event manager to all views
            .environmentObject(addressSearchManager) // Pass address search manager to all views
            .environmentObject(sseEventRouter) // Pass SSE event router to all views
            .withScaledSpacing() // Inject scaled spacing values into environment
            .onAppear {
                // Set appLifecycleManager reference - auto-registration happens in didSet
                // TrackingManager automatically registers itself when appLifecycleManager is set
                trackingManager.appLifecycleManager = appLifecycleManager
                
                // Set ChatViewModel reference in router after @StateObject is initialized
                sseEventRouter.setChatViewModel(chatViewModel)
                
                // Wire up EventManager dependencies (delayed injection pattern)
                eventManager.uhpGateway = uhpGateway
                eventManager.locationManager = locationManager
                
                // Wire up TrackingManager dependencies
                trackingManager.eventManager = eventManager
                trackingManager.locationManager = locationManager
                
                // Wire up AddressSearchManager dependencies
                addressSearchManager.eventManager = eventManager
                
                // Wire up ChatViewModel dependencies
                chatViewModel.eventManager = eventManager
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
