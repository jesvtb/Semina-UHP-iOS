//
//  ContentView.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI

// MARK: - Content View
struct ContentView: View {
  // @EnvironmentObject is like React's useContext - gets the AuthManager from parent
  // This is passed from unheardpathApp via .environmentObject()
  // Similar to how React Context provides values to child components
  @EnvironmentObject var authManager: AuthManager
  
  var body: some View {
    Group {
      // Show loading state while checking session (happens during app init)
      if authManager.isLoading {
          ProgressView("Checking authentication...")
      } else if authManager.isAuthenticated {
        SignedInHomeView()
      } else {
        AuthView()
      }
    }
    // Skip auth state changes in preview mode
    .task {
      #if DEBUG
      guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
        return
      }
      #endif
      // Auth state is now managed by AuthManager, which checks during app initialization
      // No need to check here - it's already done in AuthManager.init()
    }
  }
}

  
#Preview("Unauthenticated") {
  ContentView()
    .environmentObject(AuthManager.preview(isAuthenticated: false, isLoading: false))
    .environmentObject(APIClient())
    .environmentObject(UHPGateway())
    .environmentObject(LocationManager())
}

#Preview("Authenticated") {
  ContentView()
    .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
    .environmentObject(APIClient())
    .environmentObject(UHPGateway())
    .environmentObject(LocationManager())
}

#Preview("Loading") {
  ContentView()
    .environmentObject(AuthManager.preview(isAuthenticated: false, isLoading: true))
    .environmentObject(APIClient())
    .environmentObject(UHPGateway())
    .environmentObject(LocationManager())
}
