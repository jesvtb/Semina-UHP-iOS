//
//  Mapbox.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation

// MARK: - Mapbox Configuration
/// Mapbox access token initialized from Info.plist
/// Configuration values are set via Config.xcconfig and injected into Info.plist
/// The Mapbox iOS SDK automatically reads MBXAccessToken from Info.plist
let mapboxAccessToken: String = {
  // In preview mode, return a dummy token to prevent crashes
  #if DEBUG
  if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
    // Return a dummy token for previews - won't work but won't crash
    return "pk.preview_token"
  }
  #endif
  
  // Try to get token from Info.plist first
  let token: String
  if let infoPlistToken = Bundle.main.infoDictionary?["MBXAccessToken"] as? String,
     !infoPlistToken.isEmpty {
    token = infoPlistToken
  } else {
    // Fallback: Use the token directly from Config.xcconfig
    // This matches the token in Config.xcconfig and unheardpathApp.swift
    // This ensures the helper works even when Info.plist injection fails on device
    token = "pk.eyJ1IjoiamVzc2ljYW1pbmd5dSIsImEiOiJjbWZjY3cxd3AwODFvMmxxbzJiNWc4NGY4In0.6hWdeAXgQKoDQNqbPiebzw"
    
    #if DEBUG
    print("⚠️ MBXAccessToken not in Info.plist - using fallback token from Config.xcconfig")
    print("   This is expected on device builds where Info.plist injection may fail")
    print("   The token is set programmatically in unheardpathApp.init()")
    #endif
  }
  
  // Validate token format
  #if DEBUG
  if token.hasPrefix("pk.") {
    print("✅ Using Mapbox public token (pk.eyJ...)")
  } else if token.hasPrefix("sk.") {
    print("⚠️ Warning: Using secret token (sk.eyJ...) - consider using public token for client-side")
  } else {
    print("⚠️ Warning: Token format looks unusual. Expected 'pk.eyJ...' or 'sk.eyJ...'")
  }
  print("🗺️ Mapbox Token (first 20 chars): \(String(token.prefix(20)))...")
  #endif
  
  return token
}()
