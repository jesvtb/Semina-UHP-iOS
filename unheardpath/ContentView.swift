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
  @EnvironmentObject var authManager: AuthManager
  
  var body: some View {
    Group {
      if authManager.isLoading {
          ProgressView("Checking authentication...")
      } else if authManager.isAuthenticated {
        // MainView()
         TestMainView()
      } else {
        AuthView()
      }
    }
  }
}


 #if DEBUG
 #Preview("Unauthenticated") {
   ContentView()
     .environmentObject(AuthManager.preview(isAuthenticated: false, isLoading: false))
     .environmentObject(UHPGateway())
     .environmentObject(TrackingManager())
     .environmentObject(UserManager())
 }

 #Preview("Authenticated") {
   ContentView()
     .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
     .environmentObject(UHPGateway())
     .environmentObject(TrackingManager())
     .environmentObject(UserManager())
 }

 #Preview("Loading") {
   ContentView()
     .environmentObject(AuthManager.preview(isAuthenticated: false, isLoading: true))
     .environmentObject(UHPGateway())
     .environmentObject(TrackingManager())
     .environmentObject(UserManager())
 }
 #endif
