//
//  AuthManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI
import Supabase
import PostHog

/// Manages authentication state for the app
/// Similar to React Context or Redux store - provides global auth state
/// Checks for locally stored session during initialization
@MainActor
class AuthManager: ObservableObject {
    // @Published is like React's useState - changes trigger view updates
    @Published var isAuthenticated = false
    @Published var isLoading = true // Track loading state
    @Published var userID = ""
    
    // Similar to React useEffect - runs once when object is created
    init() {
        // Start checking for session immediately (async task in init)
        Task {
            await checkInitialSession()
        }
    }
    
    /// Checks for locally stored Supabase session
    /// This runs during app initialization, not when view appears
    private func checkInitialSession() async {
        isLoading = true
        
        // Check initial session state
        // IMPORTANT: With emitLocalSessionAsInitialSession: true, we must check if session is expired
        do {
            let session = try await supabase.auth.session
            userID = session.user.id.uuidString
            print("🔍 User ID: \(userID)")
            // print("🔍 Initial session: \(session)")
            // Check if session is expired (required when using emitLocalSessionAsInitialSession: true)
            if session.isExpired {
                #if DEBUG
                print("⚠️ Session expired - user needs to sign in again")
                print("   Expires at: \(Date(timeIntervalSince1970: session.expiresAt))")
                #endif
                isAuthenticated = false
                
                
                // captureSessionRetrievalEvent(sessionFound: true, isExpired: true, userId: userID)
            } else {
                isAuthenticated = true
                #if DEBUG
                print("✅ Session alive - user is authenticated")
                #endif
                // captureSessionRetrievalEvent(sessionFound: true, isExpired: false, userId: userID)
            }
            PostHogSDK.shared.identify(userID, userProperties: ["is_signed_in": isAuthenticated], userPropertiesSetOnce: ["is_signed_up": true])
        } catch {
            #if DEBUG
            print("ℹ️ No initial session - user needs to sign in: \(error.localizedDescription)")
            #endif
            isAuthenticated = false
            
            // Capture PostHog event for no session found
            captureSessionRetrievalEvent(sessionFound: false, isExpired: false, userId: nil)
        }
        
        isLoading = false
        
        // Now listen for auth state changes (like React useEffect with auth dependency)
        await listenToAuthChanges()
    }
    
    /// Captures PostHog event when retrieving initial session
    /// Follows PostHog naming convention: category:object_action (past tense)
    private func captureSessionRetrievalEvent(sessionFound: Bool, isExpired: Bool, userId: String?) {
        var properties: [String: Any] = [
            "session_found": sessionFound,
            "is_expired": isExpired,
            "event_version": "1.0"
        ]
        
        if let userId = userId {
            properties["user_id"] = userId
        }
        
        PostHogSDK.shared.capture("authentication:initial_session_retrieved", properties: properties)
    }
    
    /// Listens to Supabase auth state changes
    /// Similar to React's useEffect that subscribes to auth events
    private func listenToAuthChanges() async {
        for await state in supabase.auth.authStateChanges {
            #if DEBUG
            print("🔄 Auth state changed: \(state.event)")
            #endif
            
            if [.initialSession, .signedIn, .signedOut].contains(state.event) {
                let wasAuthenticated = isAuthenticated
                
                // Check if session exists (regardless of expiration)
                if let session = state.session {
                    // Identify user with PostHog whenever we have a session
                    // Session expiration only affects JWT token validity, not user identity
                    // Same user ID should be used for PostHog regardless of expiration
                    let userID = session.user.id.uuidString
                    PostHogSDK.shared.identify(userID)
                    #if DEBUG
                    print("✅ PostHog identified user on auth state change: \(userID)")
                    #endif
                    
                    // Check if session is expired for authentication state
                    if session.isExpired {
                        isAuthenticated = false
                    } else {
                        isAuthenticated = true
                    }
                } else {
                    isAuthenticated = false
                    // Reset PostHog when user signs out
                    if state.event == .signedOut {
                        PostHogSDK.shared.reset()
                        #if DEBUG
                        print("🔄 PostHog reset after sign out")
                        #endif
                    }
                }
                
                #if DEBUG
                if isAuthenticated != wasAuthenticated {
                    print("✅ Authentication state updated: \(isAuthenticated ? "Signed In" : "Signed Out")")
                }
                #endif
            }
        }
    }
}

