//
//  unheardpathApp.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI
import MapboxMaps
import PostHog

@main
struct unheardpathApp: App {
    // @StateObject is like React's useState for class instances
    // Creates AuthManager once and checks session during initialization
    // This is similar to creating a Context Provider in React
    @StateObject private var authManager = AuthManager()
    @StateObject private var apiClient = APIClient()
    @StateObject private var uhpGateway = UHPGateway()
    @StateObject private var locationManager = LocationManager()
    
    init() {
        setupMapboxToken()
        setupPostHog()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager) // Pass auth state to all views (like React Context)
                .environmentObject(apiClient) // Pass shared API service to all views
                .environmentObject(locationManager) // Pass location manager to all views
                .environmentObject(uhpGateway) // Pass UHP Gateway to all views
                .withScaledSpacing() // Inject scaled spacing values into environment
                .onOpenURL { url in
                    Task {
                        do {
                            try await supabase.auth.session(from: url)
                            // After session is created from URL, authManager will detect the change
                            // via authStateChanges listener
                        } catch {
                            print("Error handling auth callback: \(error)")
                        }
                    }
                }
                .task {
                    // Request location permission when app appears
                    locationManager.requestLocationPermission()
                }
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
    /// Both Config.Dev.xcconfig and Config.Release.xcconfig provide required values
    /// which get injected into Info.plist via INFOPLIST_KEY_* build settings
    private func setupPostHog() {
        // Read IS_POSTHOG_TRACKING_ENABLED from Info.plist (required - fail loudly only if key is missing)
        // Info.plist boolean values are read as NSNumber, so we handle both Bool and Int
        guard let trackingValue = Bundle.main.infoDictionary?["IS_POSTHOG_TRACKING_ENABLED"] else {
            fatalError("""
            ❌ IS_POSTHOG_TRACKING_ENABLED not found in Info.plist!
            
            Check:
            1. Config.Debug.xcconfig or Config.Release.xcconfig is set in Xcode Build Settings
            2. INFOPLIST_KEY_IS_POSTHOG_TRACKING_ENABLED is set in Build Settings
            3. IS_POSTHOG_TRACKING_ENABLED is defined in the appropriate .xcconfig file
            4. Clean build folder (Cmd+Shift+K) and rebuild
            """)
        }
        
        // Convert to boolean value - use the value if key exists
        let isPosthogTracking: Bool
        if let boolValue = trackingValue as? Bool {
            isPosthogTracking = boolValue
        } else if let numberValue = trackingValue as? NSNumber {
            isPosthogTracking = numberValue.boolValue
        } else {
            // If invalid type, default to false (disable tracking) rather than crashing
            #if DEBUG
            print("⚠️ IS_POSTHOG_TRACKING_ENABLED has unexpected type in Info.plist, defaulting to false")
            #endif
            isPosthogTracking = false
        }
        
        // If tracking is disabled, skip setup
        guard isPosthogTracking else {
            #if DEBUG
            print("📊 PostHog tracking disabled via Info.plist")
            #endif
            return
        }
        
        // Read POSTHOG_API_KEY and POSTHOG_HOST from Info.plist
        // These are always in Config.xcconfig (base config), so they should always be present
        guard let apiKey = Bundle.main.infoDictionary?["POSTHOG_API_KEY"] as? String,
              !apiKey.isEmpty,
              let host = Bundle.main.infoDictionary?["POSTHOG_HOST"] as? String,
              !host.isEmpty else {
            // If keys are missing, skip PostHog setup (they should always be in Config.xcconfig)
            #if DEBUG
            print("⚠️ POSTHOG_API_KEY or POSTHOG_HOST missing/invalid in Info.plist, skipping PostHog setup")
            #endif
            return
        }
        
        // Add https:// protocol prefix to host (xcconfig contains host only)
        let hostWithProtocol = host.hasPrefix("https://") || host.hasPrefix("http://") ? host : "https://\(host)"
        
        #if DEBUG
        print("📊 PostHog configured from Info.plist")
        #endif
        
        // Configure PostHog SDK
        let config = PostHogConfig(apiKey: apiKey, host: hostWithProtocol)
        PostHogSDK.shared.setup(config)
        
        // Immediately identify user if session exists to prevent events from being associated with random UUID
        // This runs asynchronously but as early as possible after PostHog setup
        Task {
            await identifyUserIfSessionExists()
        }
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
