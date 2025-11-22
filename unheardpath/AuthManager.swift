//
//  AuthManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI
import Supabase

/// Manages authentication state for the app
/// Similar to React Context or Redux store - provides global auth state
/// Checks for locally stored session during initialization
@MainActor
class AuthManager: ObservableObject {
    // @Published is like React's useState - changes trigger view updates
    @Published var isAuthenticated = false
    @Published var isLoading = true // Track loading state
    
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
            
            // Check if session is expired (required when using emitLocalSessionAsInitialSession: true)
            if session.isExpired {
                #if DEBUG
                print("⚠️ Initial session found but expired - user needs to sign in again")
                print("   User ID: \(session.user.id)")
                print("   Expires at: \(Date(timeIntervalSince1970: session.expiresAt))")
                #endif
                isAuthenticated = false
            } else {
                isAuthenticated = true
                #if DEBUG
                print("✅ Initial session found and valid - user is authenticated")
                print("   User ID: \(session.user.id)")
                #endif
            }
        } catch {
            #if DEBUG
            print("ℹ️ No initial session - user needs to sign in: \(error.localizedDescription)")
            #endif
            isAuthenticated = false
        }
        
        isLoading = false
        
        // Now listen for auth state changes (like React useEffect with auth dependency)
        await listenToAuthChanges()
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
                
                // Check if session exists and is not expired
                if let session = state.session, !session.isExpired {
                    isAuthenticated = true
                } else {
                    isAuthenticated = false
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

