//
//  Supabase.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Supabase
import Foundation
import HTTPTypes

// MARK: - Supabase Client
// / Supabase client initialized from Info.plist
/// Configuration values are set via Config.xcconfig and injected into Info.plist
let supabase: SupabaseClient = {
  // Try to use real Supabase configuration from Info.plist
  // If values are missing, the guard statements below will provide helpful error messages
  // This works in both preview mode and actual app runs if Info.plist is properly configured
  
  // Debug: Print all Info.plist keys to help diagnose issues
  #if DEBUG
  if let infoDict = Bundle.main.infoDictionary {
    print("Available Info.plist keys: \(infoDict.keys.sorted().joined(separator: ", "))")
  }
  #endif
  
  guard let urlString = Bundle.main.infoDictionary?["SupabaseProjectUrl"] as? String,
        !urlString.isEmpty else {
    #if DEBUG
    // Provide helpful error message with available keys
    let availableKeys = Bundle.main.infoDictionary?.keys.sorted().joined(separator: ", ") ?? "none"
    fatalError("""
    SupabaseProjectUrl must be set in Info.plist (via Config.xcconfig)
    
    Available Info.plist keys: \(availableKeys)
    
    Make sure:
    1. Config.xcconfig has SUPABASE_PROJECT_URL set
    2. Config.xcconfig has INFOPLIST_KEY_SupabaseProjectUrl = $(SUPABASE_PROJECT_URL)
    3. Clean build folder (Cmd+Shift+K) and rebuild
    """)
    #else
    fatalError("SupabaseProjectUrl must be set in Info.plist (via Config.xcconfig)")
    #endif
  }
  
  // Clean and validate the URL
  let cleanedUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: "/$", with: "", options: .regularExpression) // Remove trailing slash
  
  guard let url = URL(string: cleanedUrlString),
        url.scheme == "https",
        let host = url.host(),
        host.hasSuffix(".supabase.co") else {
    #if DEBUG
    fatalError("""
    Invalid Supabase URL format: \(cleanedUrlString)
    
    Expected format: https://[project-ref].supabase.co
    Example: https://mrrssxdxblwhdsejdlxp.supabase.co
    
    Make sure:
    1. URL starts with https://
    2. URL ends with .supabase.co
    3. No trailing slash
    4. No path after the domain
    """)
    #else
    fatalError("Invalid Supabase URL format")
    #endif
  }
  
  #if DEBUG
  print("🔗 Supabase URL: \(url.absoluteString)")
  let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  if isPreview {
    print("📱 Running in SwiftUI preview mode")
  }
  #endif
  
  guard let key = Bundle.main.infoDictionary?["SupabasePublishableKey"] as? String, !key.isEmpty else {
    #if DEBUG
    fatalError("""
    SupabasePublishableKey must be set in Info.plist (via Config.xcconfig)
    
    Make sure:
    1. Config.xcconfig has SUPABASE_PUBLISHABLE_KEY set
    2. Config.xcconfig has INFOPLIST_KEY_SupabasePublishableKey = $(SUPABASE_PUBLISHABLE_KEY)
    3. Clean build folder (Cmd+Shift+K) and rebuild
    """)
    #else
    fatalError("SupabasePublishableKey must be set in Info.plist (via Config.xcconfig)")
    #endif
  }
  
  // Validate API key format
  #if DEBUG
  if key.hasPrefix("sb_publishable_") {
    print("✅ Using new publishable key format (sb_publishable_...)")
    print("   Note: This is the new Supabase API key format introduced in 2025")
    print("   Reference: https://github.com/orgs/supabase/discussions/29260")
  } else if key.hasPrefix("eyJ") {
    print("✅ Using legacy anon key format (JWT)")
  } else if key.hasPrefix("sb_") {
    print("✅ Using new key format (sb_...)")
  } else {
    print("⚠️ Warning: API key format looks unusual. Expected 'eyJ...' (JWT) or 'sb_...' (publishable/secret key)")
  }
  print("🔑 Supabase Key (first 30 chars): \(String(key.prefix(30)))...")
  #endif
  
  // Configure Supabase client with SSL/TLS support for enforced SSL databases
  // 
  // IMPORTANT: No SSL certificates need to be included in the app bundle!
  // iOS automatically uses the system's built-in certificate store to validate
  // SSL certificates for HTTPS connections. Supabase uses standard SSL certificates
  // that are trusted by iOS by default.
  //
  // The Supabase Swift client uses URLSession which:
  // - Automatically validates SSL certificates using iOS system certificate store
  // - Respects NSAppTransportSecurity settings from Info.plist
  // - Handles certificate chain validation automatically
  //
  // For SSL-enforced databases, the current setup is sufficient:
  // 1. URL uses https:// (already validated above)
  // 2. Info.plist has proper NSAppTransportSecurity settings (already configured)
  // 3. TLS version is 1.2 (configured in Info.plist)
  // 4. System certificate store handles SSL validation automatically
  //
  // You only need to include custom certificates if:
  // - Using self-signed certificates
  // - Using custom CA certificates not in iOS system store
  // - Using certificate pinning (not recommended for Supabase)
  
  // Configure Supabase client with AuthOptions to fix session emission issue
  // Reference: Supabase AuthClient known issue - "Initial session emitted after attempting to refresh"
  // Fix: Set emitLocalSessionAsInitialSession: true to ensure locally stored session is always emitted
  let client = SupabaseClient(
    supabaseURL: url,
    supabaseKey: key,
    options: SupabaseClientOptions(
      auth: SupabaseClientOptions.AuthOptions(
        emitLocalSessionAsInitialSession: true
      )
    )
  )
  
  #if DEBUG
  print("🔒 Supabase client configured with HTTPS and SSL/TLS support")
  print("   TLS minimum version: 1.2 (configured in Info.plist)")
  print("   SSL certificate validation: Automatic via iOS system certificate store")
  print("   SSL enforced database: Fully supported - no custom certificates needed")
  print("   ✅ AuthClient configured with emitLocalSessionAsInitialSession: true")
  print("      This fixes the known issue where initial session emission was incorrect")
  #endif
  
  return client
}()

// MARK: - Verification
func verifySupabaseConfiguration() -> (isValid: Bool, url: String?, keyPrefix: String?, error: String?) {
  guard let urlString = Bundle.main.infoDictionary?["SupabaseProjectUrl"] as? String,
        !urlString.isEmpty else {
    return (false, nil, nil, "SupabaseProjectUrl is missing or empty in Info.plist")
  }
  
  guard let key = Bundle.main.infoDictionary?["SupabasePublishableKey"] as? String,
        !key.isEmpty else {
    return (false, urlString, nil, "SupabasePublishableKey is missing or empty in Info.plist")
  }
  
  guard URL(string: urlString) != nil else {
    return (false, urlString, String(key.prefix(10)), "SupabaseProjectUrl is not a valid URL")
  }
  
  return (true, urlString, String(key.prefix(10)), nil)
}


// let supabase: SupabaseClient = {
  
//   return SupabaseClient(
//     supabaseURL: URL(string: "https://mrrssxdxblwhdsejdlxp.supabase.co")!,
//     supabaseKey: "sb_publishable_mBb4Rnl2jdhbCR9EjcOK_A_WyZK2DzM"
//   )
// }()

