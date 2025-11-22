//
//  ContentView.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI

// MARK: - Content View
struct ContentView: View {
  @State var isAuthenticated = false
  
  var body: some View {
    Group {
      if isAuthenticated {
        SignedInHomeView()
      } else {
        AuthView()
      }
    }
    .task {
      // Skip auth state changes in preview mode
      #if DEBUG
      guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
        return
      }
      #endif
      
      for await state in supabase.auth.authStateChanges {
        if [.initialSession, .signedIn, .signedOut].contains(state.event) {
          isAuthenticated = state.session != nil
        }
      }
    }
  }
}

// MARK: - Welcome Header Component
struct WelcomeHeaderView: View {
  var body: some View {
    VStack(spacing: 8) {
      Text("Welcome to unheardpath")
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundColor(.primary)

      Text("Your main app content goes here")
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
  }
}

#Preview {
  ContentView()
}
