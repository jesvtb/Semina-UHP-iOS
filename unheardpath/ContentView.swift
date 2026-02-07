//
//  ContentView.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI
import core

// MARK: - Content View
struct ContentView: View {
  @EnvironmentObject var authManager: AuthManager
  
  var body: some View {
    Group {
      if authManager.isLoading {
          ProgressView("Checking authentication...")
      } else if authManager.isAuthenticated {
         MainView()
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
   let uhpGateway = UHPGateway()
   let userManager = UserManager()
   let chatManager = ChatManager(uhpGateway: uhpGateway, userManager: userManager)
   let mapFeaturesManager = MapFeaturesManager()
   let toastManager = ToastManager()
   let catalogueManager = CatalogueManager()
   let sseEventRouter = SSEEventRouter(chatManager: chatManager, catalogueManager: catalogueManager, mapFeaturesManager: mapFeaturesManager, toastManager: toastManager)
   ContentView()
     .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
     .environmentObject(uhpGateway)
     .environmentObject(TrackingManager())
     .environmentObject(userManager)
     .environmentObject(chatManager)
     .environmentObject(mapFeaturesManager)
     .environmentObject(toastManager)
     .environmentObject(catalogueManager)
     .environmentObject(sseEventRouter)
     .environmentObject(EventManager())
     .environmentObject(AutocompleteManager(geoapifyApiKey: ""))
     .environment(\.geocoder, Geocoder(geoapifyApiKey: ""))
 }

 #Preview("Loading") {
   ContentView()
     .environmentObject(AuthManager.preview(isAuthenticated: false, isLoading: true))
     .environmentObject(UHPGateway())
     .environmentObject(TrackingManager())
     .environmentObject(UserManager())
 }
 #endif
