//
//  StorageManager.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-01-XX.
//

import Foundation

/// StorageManager handles both large file storage and caching
/// Similar to a utility class in Python or a service in React
/// Provides unified interface for storing data in appropriate locations
class StorageManager {
    // MARK: - Singleton Pattern
    // Similar to a module-level instance in Python or a Context provider in React
    static let shared = StorageManager()
    
    // Private initializer to enforce singleton pattern
    private init() {}
    
    // MARK: - Directory URLs
    // These are like constants in Python or environment variables in React
    
    /// Documents directory - for user-visible files that should be backed up
    /// Use for: Downloaded content, user-saved files
    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Caches directory - for re-downloadable files
    /// Use for: Large cache files, downloaded media that can be re-fetched
    var cachesURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    
    /// Application Support directory - for app-generated persistent data
    /// Use for: Database files, app configuration
    var appSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Create directory if it doesn't exist (like os.makedirs in Python)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    /// Temporary directory - for short-lived files
    /// Use for: Processing temporary files, downloads in progress
    var temporaryURL: URL {
        FileManager.default.temporaryDirectory
    }
    
    // MARK: - Key Prefix Helper
    // Automatically prefixes all keys with "UHP." for better organization
    
    /// Prefixes a key with "UHP." if it doesn't already have the prefix
    /// - Parameter key: The key to prefix
    /// - Returns: The prefixed key
    private func prefixedKey(_ key: String) -> String {
        if key.hasPrefix("UHP.") {
            return key
        }
        return "UHP.\(key)"
    }
    
    // MARK: - UserDefaults Helper
    // For small data (< 100 KB) - similar to localStorage in React or a config file in Python
    
    /// Save small data to UserDefaults (like localStorage.setItem in React)
    /// Automatically prefixes key with "UHP."
    /// - Parameters:
    ///   - value: The value to save (must be PropertyList compatible)
    ///   - key: The key to store under (will be prefixed with "UHP.")
    func saveToUserDefaults<T>(_ value: T, forKey key: String) {
        let prefixed = prefixedKey(key)
        UserDefaults.standard.set(value, forKey: prefixed)
        UserDefaults.standard.synchronize()
    }
    
    /// Load data from UserDefaults (like localStorage.getItem in React)
    /// Automatically prefixes key with "UHP."
    /// - Parameter key: The key to retrieve (will be prefixed with "UHP.")
    /// - Returns: The stored value, or nil if not found
    func loadFromUserDefaults<T>(forKey key: String, as type: T.Type) -> T? {
        let prefixed = prefixedKey(key)
        return UserDefaults.standard.object(forKey: prefixed) as? T
    }
    
    /// Check if key exists in UserDefaults
    /// Automatically prefixes key with "UHP."
    /// - Parameter key: The key to check (will be prefixed with "UHP.")
    func existsInUserDefaults(forKey key: String) -> Bool {
        let prefixed = prefixedKey(key)
        return UserDefaults.standard.object(forKey: prefixed) != nil
    }
    
    /// Remove data from UserDefaults
    /// Automatically prefixes key with "UHP."
    /// - Parameter key: The key to remove (will be prefixed with "UHP.")
    func removeFromUserDefaults(forKey key: String) {
        let prefixed = prefixedKey(key)
        UserDefaults.standard.removeObject(forKey: prefixed)
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - File Storage Methods
    // For large data (> 100 KB) - similar to file operations in Python
    
    /// Save data to file in Documents directory
    /// - Parameters:
    ///   - data: The data to save
    ///   - filename: The filename (with or without extension)
    ///   - subdirectory: Optional subdirectory within Documents
    /// - Returns: URL of saved file
    /// - Throws: Error if save fails
    func saveToDocuments(data: Data, filename: String, subdirectory: String? = nil) throws -> URL {
        // TODO: Implementation placeholder - to be updated later
        throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "saveToDocuments not yet implemented"])
    }
    
    /// Save data to file in Caches directory
    /// - Parameters:
    ///   - data: The data to save
    ///   - filename: The filename
    ///   - subdirectory: Optional subdirectory within Caches
    /// - Returns: URL of saved file
    /// - Throws: Error if save fails
    func saveToCaches(data: Data, filename: String, subdirectory: String? = nil) throws -> URL {
        // TODO: Implementation placeholder - to be updated later
        throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "saveToCaches not yet implemented"])
    }
    
    /// Load data from file in Documents directory
    /// - Parameters:
    ///   - filename: The filename
    ///   - subdirectory: Optional subdirectory
    /// - Returns: The file data
    /// - Throws: Error if file doesn't exist or can't be read
    func loadFromDocuments(filename: String, subdirectory: String? = nil) throws -> Data {
        // TODO: Implementation placeholder - to be updated later
        throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "loadFromDocuments not yet implemented"])
    }
    
    /// Load data from file in Caches directory
    /// - Parameters:
    ///   - filename: The filename
    ///   - subdirectory: Optional subdirectory
    /// - Returns: The file data
    /// - Throws: Error if file doesn't exist or can't be read
    func loadFromCaches(filename: String, subdirectory: String? = nil) throws -> Data {
        // TODO: Implementation placeholder - to be updated later
        throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "loadFromCaches not yet implemented"])
    }
    
    /// Check if file exists in Documents directory
    func existsInDocuments(filename: String, subdirectory: String? = nil) -> Bool {
        // TODO: Implementation placeholder - to be updated later
        return false
    }
    
    /// Check if file exists in Caches directory
    func existsInCaches(filename: String, subdirectory: String? = nil) -> Bool {
        // TODO: Implementation placeholder - to be updated later
        return false
    }
    
    /// Delete file from Documents directory
    func deleteFromDocuments(filename: String, subdirectory: String? = nil) throws {
        // TODO: Implementation placeholder - to be updated later
    }
    
    /// Delete file from Caches directory
    func deleteFromCaches(filename: String, subdirectory: String? = nil) throws {
        // TODO: Implementation placeholder - to be updated later
    }
    
    // MARK: - Location Data Methods
    // Adapted from LocationManager.saveLocation() pattern
    // Similar to how you'd structure data persistence in Python or React
    
    /// Save location data (adapted from LocationManager pattern)
    /// Automatically chooses UserDefaults for small data
    /// - Parameters:
    ///   - latitude: Location latitude
    ///   - longitude: Location longitude
    ///   - timestamp: Location timestamp (defaults to current time)
    // func saveLocation(latitude: Double, longitude: Double, timestamp: TimeInterval? = nil) {
    //     // Use UserDefaults for small location data (like LocationManager does)
    //     let timestampValue = timestamp ?? Date().timeIntervalSince1970
        
    //     saveToUserDefaults(latitude, forKey: "LocationManager.lastLocation.latitude")
    //     saveToUserDefaults(longitude, forKey: "LocationManager.lastLocation.longitude")
    //     saveToUserDefaults(timestampValue, forKey: "LocationManager.lastLocation.timestamp")
        
    //     #if DEBUG
    //     print("💾 Saved Latest Device Location to UserDefaults: \(latitude), \(longitude)")
    //     #endif
    // }
    
    // /// Load saved location data (adapted from LocationManager pattern)
    // /// - Returns: Tuple of (latitude, longitude, timestamp) or nil if not found
    // func loadLocation() -> (latitude: Double, longitude: Double, timestamp: TimeInterval)? {
    //     guard let latitude = loadFromUserDefaults(forKey: "LocationManager.lastLocation.latitude", as: Double.self),
    //           let longitude = loadFromUserDefaults(forKey: "LocationManager.lastLocation.longitude", as: Double.self),
    //           let timestamp = loadFromUserDefaults(forKey: "LocationManager.lastLocation.timestamp", as: TimeInterval.self) else {
    //         #if DEBUG
    //         print("ℹ️ No saved location found in UserDefaults")
    //         #endif
    //         return nil
    //     }
        
    //     // Validate coordinates are not zero
    //     guard latitude != 0.0 || longitude != 0.0 else {
    //         #if DEBUG
    //         print("ℹ️ Saved location coordinates are zero, ignoring")
    //         #endif
    //         return nil
    //     }
        
    //     #if DEBUG
    //     print("📂 Loaded UserDefaults Last Device Coordinates: \(latitude), \(longitude)")
    //     print("   Saved at: \(Date(timeIntervalSince1970: timestamp))")
    //     #endif
        
    //     return (latitude: latitude, longitude: longitude, timestamp: timestamp)
    // }
    
    // MARK: - Cache Management
    // For managing cached data that might be large
    
    /// Save cache data - automatically chooses storage method based on size
    /// Automatically prefixes key with "UHP."
    /// - Parameters:
    ///   - data: The data to cache (can be Data, Dictionary, Array, etc.)
    ///   - key: Cache key (will be prefixed with "UHP.")
    ///   - maxUserDefaultsSize: Maximum size in bytes to use UserDefaults (default: 100 KB)
    ///   - subdirectory: Optional subdirectory for file storage
    /// - Returns: URL if saved as file, nil if saved to UserDefaults
    /// - Throws: Error if save fails
    @discardableResult
    func saveCache<T>(_ data: T, forKey key: String, maxUserDefaultsSize: Int = 100 * 1024, subdirectory: String? = nil) throws -> URL? {
        // TODO: Implementation placeholder - to be updated later
        throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "saveCache not yet implemented"])
    }
    
    /// Load cache data - automatically detects storage method
    /// Automatically prefixes key with "UHP."
    /// - Parameters:
    ///   - key: Cache key (will be prefixed with "UHP.")
    ///   - type: Expected type (Data, Dictionary, Array, etc.)
    ///   - subdirectory: Optional subdirectory for file storage
    /// - Returns: Cached data or nil if not found
    /// - Throws: Error if load fails
    func loadCache<T>(forKey key: String, as type: T.Type, subdirectory: String? = nil) throws -> T? {
        // TODO: Implementation placeholder - to be updated later
        throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "loadCache not yet implemented"])
    }
    
    /// Remove cache entry (from both UserDefaults and file storage)
    /// Automatically prefixes key with "UHP."
    /// - Parameter key: Cache key (will be prefixed with "UHP.")
    func removeCache(forKey key: String, subdirectory: String? = nil) {
        // TODO: Implementation placeholder - to be updated later
    }
    
    // MARK: - File Size Utilities
    
    /// Get size of file in bytes
    func sizeOfFile(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    /// Get total size of all files in a directory
    func totalSizeOfDirectory(at url: URL) -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        
        return contents.reduce(0) { total, fileURL in
            guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return total
            }
            return total + Int64(size)
        }
    }
    
    /// Get available storage space in bytes
    func availableStorage() -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return nil
        }
        return freeSize
    }
    
    // MARK: - List Files
    
    /// List all files in Documents directory
    func listFilesInDocuments(subdirectory: String? = nil) throws -> [String] {
        var directoryURL = documentsURL
        
        if let subdir = subdirectory {
            directoryURL = directoryURL.appendingPathComponent(subdir)
        }
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return contents.map { $0.lastPathComponent }
    }
    
    /// List all files in Caches directory
    func listFilesInCaches(subdirectory: String? = nil) throws -> [String] {
        var directoryURL = cachesURL
        
        if let subdir = subdirectory {
            directoryURL = directoryURL.appendingPathComponent(subdir)
        }
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return contents.map { $0.lastPathComponent }
    }
    
    // MARK: - Debug Helpers
    
    #if DEBUG
    /// Print storage usage summary
    func printStorageSummary() {
        print("📦 Storage Summary:")
        print("---")
        
        // UserDefaults size (approximate)
        let defaults = UserDefaults.standard
        let defaultsDict = defaults.dictionaryRepresentation()
        let defaultsSize = defaultsDict.values.reduce(0) { total, value in
            let valueString = "\(value)"
            return total + (valueString.data(using: .utf8)?.count ?? 0)
        }
        print("UserDefaults: ~\(defaultsSize / 1024) KB")
        
        // Documents size
        let documentsSize = totalSizeOfDirectory(at: documentsURL)
        print("Documents: \(documentsSize / 1024 / 1024) MB")
        
        // Caches size
        let cachesSize = totalSizeOfDirectory(at: cachesURL)
        print("Caches: \(cachesSize / 1024 / 1024) MB")
        
        // Available storage
        if let available = availableStorage() {
            print("Available: \(available / 1024 / 1024) MB")
        }
        
        print("---")
    }
    #endif
}

