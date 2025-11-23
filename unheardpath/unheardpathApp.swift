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
    @StateObject private var apiService = APIService.shared
    @StateObject private var locationManager = LocationManager()
    
    init() {
        // Debug: Always print available Info.plist keys during initialization
        // This helps diagnose Config.xcconfig injection issues
        #if DEBUG
        if let infoDict = Bundle.main.infoDictionary {
            let availableKeys = infoDict.keys.sorted().joined(separator: ", ")
            print("🔍 Available Info.plist keys at app init: \(availableKeys)")
        }
        #endif
        
        // Set Mapbox access token programmatically as fallback
        // According to Mapbox docs: https://docs.mapbox.com/ios/maps/guides/swift-ui/
        // Token can be set via MapboxOptions.accessToken OR Info.plist
        // We set it programmatically here to ensure it works on device builds
        // even if Info.plist injection fails
        setupMapboxToken()
        setupPostHog()
        
        // AuthManager.init() is called when @StateObject creates it above
        // This automatically checks for locally stored Supabase session
        // PostHog SDK handles captures gracefully even if not fully initialized
        // Location permission will be requested in .task modifier when app appears
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager) // Pass auth state to all views (like React Context)
                .environmentObject(apiService) // Pass shared API service to all views
                .environmentObject(locationManager) // Pass location manager to all views
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
    
    /// Sets up PostHog analytics using values from Info.plist (injected via Config.xcconfig)
    /// Similar to Supabase setup - reads configuration from Bundle.main.infoDictionary
    /// REQUIRES: PostHogAPIKey and PostHogHost must be in Info.plist (injected from Config.xcconfig)
    /// This runs in all modes including preview - Info.plist values must be available
    private func setupPostHog() {
        guard let apiKey = Bundle.main.infoDictionary?["PostHogAPIKey"] as? String,
              !apiKey.isEmpty,
              let host = Bundle.main.infoDictionary?["PostHogHost"] as? String,
              !host.isEmpty,
              host.hasPrefix("https://") || host.hasPrefix("http://") else {
            return
        }
        
        #if DEBUG
        print("📊 PostHog configured from Info.plist")
        print("   API Key: \(String(apiKey.prefix(20)))...")
        print("   Host: \(host)")
        #endif
        
        // Configure PostHog SDK
        let config = PostHogConfig(apiKey: apiKey, host: host)
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
