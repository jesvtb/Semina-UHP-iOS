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
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager) // Pass auth state to all views (like React Context)
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
        // Read PostHog API key from Info.plist (injected from Config.xcconfig)
        // MUST be present - no fallback values
        guard let apiKey = Bundle.main.infoDictionary?["PostHogAPIKey"] as? String,
              !apiKey.isEmpty else {
            let availableKeys = Bundle.main.infoDictionary?.keys.sorted().joined(separator: ", ") ?? "none"
            print("""
            ❌ PostHogAPIKey must be set in Info.plist (via Config.xcconfig)
            
            Available Info.plist keys: \(availableKeys)
            
            Make sure:
            1. Config.xcconfig has POSTHOG_API_KEY set
            2. project.pbxproj has INFOPLIST_KEY_PostHogAPIKey = "$(POSTHOG_API_KEY)" in build settings
            3. Clean build folder (Cmd+Shift+K) and rebuild
            
            The key should be injected automatically from Config.xcconfig during build.
            PostHog will not be initialized without a valid API key.
            """)
            return // Skip PostHog setup if API key is missing
        }
        
        // Read PostHog host from Info.plist (injected from Config.xcconfig)
        // MUST be present - no fallback values
        guard let host = Bundle.main.infoDictionary?["PostHogHost"] as? String,
              !host.isEmpty else {
            print("""
            ❌ PostHogHost must be set in Info.plist (via Config.xcconfig)
            
            Make sure:
            1. Config.xcconfig has POSTHOG_HOST set
            2. project.pbxproj has INFOPLIST_KEY_PostHogHost = "$(POSTHOG_HOST)" in build settings
            3. Clean build folder (Cmd+Shift+K) and rebuild
            
            The key should be injected automatically from Config.xcconfig during build.
            PostHog will not be initialized without a valid host.
            """)
            return // Skip PostHog setup if host is missing
        }
        // Validate host URL format
        guard host.hasPrefix("https://") || host.hasPrefix("http://") else {
            print("""
            ❌ Invalid PostHog host format: \(host)
            
            Host must start with https:// or http://
            Example: https://www.unheardpath.com/relay-TjH4
            PostHog will not be initialized with an invalid host format.
            """)
            return // Skip PostHog setup if host format is invalid
        }
        
        #if DEBUG
        print("📊 PostHog configured from Info.plist")
        print("   API Key: \(String(apiKey.prefix(20)))...")
        print("   Host: \(host)")
        #endif
        
        // Configure PostHog SDK
        let config = PostHogConfig(apiKey: apiKey, host: host)
        PostHogSDK.shared.setup(config)
    }
}
