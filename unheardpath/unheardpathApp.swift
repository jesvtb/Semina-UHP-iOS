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
    @StateObject private var userManager = UserManager()
    @StateObject private var authManager = AuthManager()
    @StateObject private var apiClient = APIClient()
    @StateObject private var uhpGateway = UHPGateway()
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
            ContentView()
                .environmentObject(authManager) // Pass auth state to all views (like React Context)
                .environmentObject(apiClient) // Pass shared API service to all views
                .environmentObject(locationManager) // Pass location manager to all views
                .environmentObject(uhpGateway) // Pass UHP Gateway to all views
                .environmentObject(userManager) // Pass user manager to all views
                .withScaledSpacing() // Inject scaled spacing values into environment
                .onAppear {
                    // Set UserManager reference in AuthManager after both are created
                    authManager.setUserManager(userManager)
                }
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
