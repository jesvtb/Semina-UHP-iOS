//
//  unheardpathApp.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI
import MapboxMaps

@main
struct unheardpathApp: App {
    // @StateObject is like React's useState for class instances
    // Creates AuthManager once and checks session during initialization
    // This is similar to creating a Context Provider in React
    @StateObject private var authManager = AuthManager()
    
    init() {
        // Set Mapbox access token programmatically as fallback
        // According to Mapbox docs: https://docs.mapbox.com/ios/maps/guides/swift-ui/
        // Token can be set via MapboxOptions.accessToken OR Info.plist
        // We set it programmatically here to ensure it works on device builds
        // even if Info.plist injection fails
        setupMapboxToken()
        
        // AuthManager.init() is called when @StateObject creates it above
        // This automatically checks for locally stored Supabase session
        // No need to manually call anything - it happens during app initialization
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
        // CRITICAL: Set token directly from Config.xcconfig value
        // This is the actual token from Config.xcconfig - we hardcode it here as a fallback
        // since Info.plist injection may fail on device builds
        // In production, you might want to use a build script or environment variable
        let token = "pk.eyJ1IjoiamVzc2ljYW1pbmd5dSIsImEiOiJjbWZjY3cxd3AwODFvMmxxbzJiNWc4NGY4In0.6hWdeAXgQKoDQNqbPiebzw"
        
        // Try Info.plist first (works in simulator, may fail on device)
        if let infoPlistToken = Bundle.main.infoDictionary?["MBXAccessToken"] as? String,
           !infoPlistToken.isEmpty,
           infoPlistToken.hasPrefix("pk.") {
            MapboxOptions.accessToken = infoPlistToken
            #if DEBUG
            print("✅ Mapbox token set from Info.plist: \(String(infoPlistToken.prefix(20)))...")
            #endif
        } else {
            // Fallback: Use token directly (from Config.xcconfig value)
            // This ensures it works even when Info.plist injection fails
            MapboxOptions.accessToken = token
            #if DEBUG
            print("✅ Mapbox token set programmatically (Info.plist not available)")
            print("   Token prefix: \(String(token.prefix(20)))...")
            print("   Note: Info.plist injection failed - using programmatic token")
            #endif
        }
        
        // Verify token is set
        if MapboxOptions.accessToken.isEmpty {
            #if DEBUG
            fatalError("Mapbox access token is empty! Check Config.xcconfig has MAPBOX_ACCESS_TOKEN set")
            #else
            fatalError("Mapbox access token is required")
            #endif
        }
    }
}
