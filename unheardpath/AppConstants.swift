//
//  AppConstants.swift
//  unheardpath
//
//  Centralized constants that require manual updates.
//  Update these values when releasing new versions or changing contracts.
//

import Foundation

/// Caseless enum to prevent instantiation — access all values via `AppConstants.xxx`.
enum AppConstants {
    
    // MARK: - Backend Communication
    
    /// Schema version for backend API communication.
    /// Increment when the request/response data shape changes between app and backend
    /// (e.g. new required fields, renamed keys, structural changes).
    /// The backend can use this to handle backward compatibility for older clients.
    static let schemaVersion = "1.0"
    
    // MARK: - Build Identification
    
    /// Label shown for local dev builds when CFBundleVersion is not set by CI.
    /// CI sets CFBundleVersion to "MAJOR.MINOR.PATCH" (e.g. "0.0.16");
    /// local Xcode builds default to "1", which is replaced with this label in DEBUG.
    static let devBuildLabel = "dev"
}
