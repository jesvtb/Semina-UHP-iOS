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
  
  // Read Supabase URL from Info.plist (injected from Config.xcconfig)
  // If missing, use invalid placeholder that will cause operations to fail gracefully
  let urlString: String
  if let infoPlistUrl = Bundle.main.infoDictionary?["SupabaseProjectUrl"] as? String,
     !infoPlistUrl.isEmpty {
    urlString = infoPlistUrl
  } else {
    let availableKeys = Bundle.main.infoDictionary?.keys.sorted().joined(separator: ", ") ?? "none"
    print("""
    ❌ SupabaseProjectUrl must be set in Info.plist (via Config.xcconfig)
    
    Make sure:
    1. Config.xcconfig has SUPABASE_PROJECT_URL set
    2. project.pbxproj has INFOPLIST_KEY_SupabaseProjectUrl = "$(SUPABASE_PROJECT_URL)" in build settings
    3. Clean build folder (Cmd+Shift+K) and rebuild
    
    The key should be injected automatically from Config.xcconfig during build.
    Supabase operations will fail until this is configured.
    """)
    // Use invalid placeholder - operations will fail but app won't crash
    urlString = "https://invalid-supabase-url.supabase.co"
  }
  
  // Clean and validate the URL
  let cleanedUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: "/$", with: "", options: .regularExpression) // Remove trailing slash
  
  // Validate URL format
  let url: URL
  if let validatedUrl = URL(string: cleanedUrlString),
     validatedUrl.scheme == "https",
     let host = validatedUrl.host(),
     host.hasSuffix(".supabase.co") {
    url = validatedUrl
  } else {
    print("""
    ❌ Invalid Supabase URL format: \(cleanedUrlString)
    
    Expected format: https://[project-ref].supabase.co
    Example: https://mrrssxdxblwhdsejdlxp.supabase.co
    
    Make sure:
    1. URL starts with https://
    2. URL ends with .supabase.co
    3. No trailing slash
    4. No path after the domain
    
    Supabase operations will fail until URL is properly configured.
    """)
    // Use invalid placeholder - operations will fail but app won't crash
    url = URL(string: "https://invalid-supabase-url.supabase.co")!
  }
  
  #if DEBUG
  print("🔗 Supabase URL: \(url.absoluteString)")
  let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  if isPreview {
    print("📱 Running in SwiftUI preview mode")
  }
  #endif
  
  // Read Supabase API key from Info.plist (injected from Config.xcconfig)
  // If missing, use invalid placeholder that will cause operations to fail gracefully
  let key: String
  if let infoPlistKey = Bundle.main.infoDictionary?["SupabasePublishableKey"] as? String,
     !infoPlistKey.isEmpty {
    key = infoPlistKey
  } else {
    print("""
    ❌ SupabasePublishableKey must be set in Info.plist (via Config.xcconfig)
    
    Make sure:
    1. Config.xcconfig has SUPABASE_PUBLISHABLE_KEY set
    2. project.pbxproj has INFOPLIST_KEY_SupabasePublishableKey = "$(SUPABASE_PUBLISHABLE_KEY)" in build settings
    3. Clean build folder (Cmd+Shift+K) and rebuild
    
    The key should be injected automatically from Config.xcconfig during build.
    Supabase operations will fail until this is configured.
    """)
    // Use invalid placeholder - operations will fail but app won't crash
    key = "invalid_key_missing_from_info_plist"
  }
  
  // Validate API key format
  #if DEBUG
  if key.hasPrefix("sb_publishable_") {
    print("✅ Using new publishable key format (sb_publishable_...)")
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

