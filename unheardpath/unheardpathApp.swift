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
        #if DEBUG
        print("📱 Registered for remote notifications")
        #endif
        return true
    }
    
    /// Called when the app successfully registers with APNs and receives a device token
    /// Reference: https://developer.apple.com/documentation/UIKit/UIApplicationDelegate/application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert device token to string format
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        #if DEBUG
        print("✅ Successfully registered for remote notifications")
        print("📱 Device token for Notification: \(tokenString)")
        #endif
        
        // TODO: Send device token to your provider server
        // Your provider server must have this token before it can deliver notifications to the device
    }
    
    /// Called when the app fails to register with APNs
    /// Reference: https://developer.apple.com/documentation/UIKit/UIApplicationDelegate/application(_:didFailToRegisterForRemoteNotificationsWithError:)
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        #endif
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
        
        #if DEBUG
        print("📬 Received remote notification while app is in foreground")
        
        // Check if this is a LiveActivity update notification
        if let aps = userInfo["aps"] as? [String: Any],
           let event = aps["event"] as? String {
            print("   LiveActivity event: \(event)")
            if let contentState = aps["content-state"] as? [String: Any] {
                print("   Content state: \(contentState)")
            }
        }
        #endif
        
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
        
        #if DEBUG
        print("👆 User tapped on notification")
        
        // Check if this is a LiveActivity update notification
        if let aps = userInfo["aps"] as? [String: Any],
           let event = aps["event"] as? String {
            print("   LiveActivity event: \(event)")
        }
        #endif
        
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
    
    // @StateObject is like React's useState for class instances
    // Creates AuthManager once and checks session during initialization
    // This is similar to creating a Context Provider in React
    @StateObject private var userManager = UserManager()
    @StateObject private var authManager = AuthManager()
    @StateObject private var apiClient = APIClient()
    @StateObject private var uhpGateway = UHPGateway()
    @StateObject private var geoapifyGateway = GeoapifyGateway()
    @StateObject private var locationManager = LocationManager()
    
    init() {
        // Print configuration at app startup (visible in device logs)
        print("🚀 unheardpath App Starting")
        print("📱 Build Configuration Check:")
        #if DEBUG
        print("   Configuration: DEBUG (Development)")
        #else
        print("   Configuration: RELEASE (Production)")
        #endif
        
        setupMapboxToken()
        setupPostHog()
    }
    
    var body: some Scene {
        WindowGroup {
            AppContentView(
                authManager: authManager,
                apiClient: apiClient,
                locationManager: locationManager,
                uhpGateway: uhpGateway,
                geoapifyGateway: geoapifyGateway,
                userManager: userManager
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
            return
        }
        MapboxOptions.accessToken = token
        print("✅ Mapbox token set from Info.plist: \(String(token.prefix(20)))...")
        
        // Verify token is set
        if MapboxOptions.accessToken.isEmpty {
            print("❌ Mapbox token injection failed - using programmatic token")
        }
    }
    
    /// Sets up PostHog analytics using values from Info.plist (injected via xcconfig files)
    /// PostHog is enabled only in RELEASE builds, disabled in DEBUG builds
    private func setupPostHog() {
        #if DEBUG
        // PostHog tracking disabled for development builds
        print("📊 PostHog tracking disabled (DEBUG build)")
        return
        #else

        guard let apiKey = Bundle.main.infoDictionary?["POSTHOG_API_KEY"] as? String,
              !apiKey.isEmpty,
              let host = Bundle.main.infoDictionary?["POSTHOG_HOST"] as? String,
              !host.isEmpty else {
            print("⚠️ POSTHOG_API_KEY or POSTHOG_HOST missing/invalid in Info.plist, skipping PostHog setup")
            return
        }
        
        let hostWithProtocol = "https://\(host)"
        
        print("📊 PostHog configured (RELEASE build)")
        
        let config = PostHogConfig(apiKey: apiKey, host: hostWithProtocol)
        PostHogSDK.shared.setup(config)
        
        Task {
            await identifyUserIfSessionExists()
        }
        #endif
    }
    
    /// Identifies user with PostHog immediately if a Supabase session exists
    /// This ensures events are associated with the Supabase user ID, not a random UUID
    /// Session expiration only affects JWT token validity, not user identity
    private func identifyUserIfSessionExists() async {
        do {
            let session = try await supabase.auth.session
            // Identify user regardless of session expiration - same user, just needs token refresh
            let userID = session.user.id.uuidString
            PostHogSDK.shared.identify(userID)
            
            // Set global user in UserManager
            await MainActor.run {
                userManager.setUser(uuid: userID)
            }
            
            #if DEBUG
            print("✅ PostHog identified user immediately: \(userID)")
            if session.isExpired {
                print("   Note: Session expired but user ID remains the same")
            }
            #endif
        } catch {
            // No session exists yet - user will be identified when they sign in
            #if DEBUG
            print("ℹ️ No session found for immediate PostHog identification")
            #endif
        }
    }
}

/// Helper view that creates ChatViewModel with proper dependencies
/// This allows ChatViewModel to be created as @StateObject with access to other @StateObject dependencies
private struct AppContentView: View {
    let authManager: AuthManager
    let apiClient: APIClient
    let locationManager: LocationManager
    let uhpGateway: UHPGateway
    let geoapifyGateway: GeoapifyGateway
    let userManager: UserManager
    
    // Create ChatViewModel as @StateObject with proper dependencies
    @StateObject private var chatViewModel: ChatViewModel
    
    init(
        authManager: AuthManager,
        apiClient: APIClient,
        locationManager: LocationManager,
        uhpGateway: UHPGateway,
        geoapifyGateway: GeoapifyGateway,
        userManager: UserManager
    ) {
        self.authManager = authManager
        self.apiClient = apiClient
        self.locationManager = locationManager
        self.uhpGateway = uhpGateway
        self.geoapifyGateway = geoapifyGateway
        self.userManager = userManager
        
        // Initialize ChatViewModel after all above dependencies are available
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(
            uhpGateway: uhpGateway,
            locationManager: locationManager,
            userManager: userManager
        ))
    }
    
    var body: some View {
        ContentView()
            .environmentObject(authManager) // Pass auth state to all views (like React Context)
            .environmentObject(apiClient) // Pass shared API service to all views
            .environmentObject(locationManager) // Pass location manager to all views
            .environmentObject(uhpGateway) // Pass UHP Gateway to all views
            .environmentObject(geoapifyGateway) // Pass Geoapify Gateway to all views
            .environmentObject(userManager) // Pass user manager to all views
            .environmentObject(chatViewModel) // Pass chat view model to all views
            .withScaledSpacing() // Inject scaled spacing values into environment
            .onAppear {
                // Set UserManager reference in AuthManager after both are created
                authManager.setUserManager(userManager)
            }
            .onOpenURL { url in
                Task {
                    do {
                        #if DEBUG
                        print("🔗 App-level callback URL: \(url.absoluteString)")
                        #endif
                        
                        // session(from: url) handles both implicit and PKCE flows automatically
                        // It extracts token_hash if present and verifies it, or uses implicit flow tokens
                        // Reference: https://supabase.com/docs/guides/auth/auth-email-passwordless
                        try await supabase.auth.session(from: url)
                        
                        // After session is created from URL, authManager will detect the change
                        // via authStateChanges listener
                    } catch {
                        #if DEBUG
                        print("❌ Error handling auth callback: \(error)")
                        #endif
                    }
                }
            }
            .task {
                // Request location permission when app appears
                locationManager.requestLocationPermission()
            }
    }
}
