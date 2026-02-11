//
//  storage.swift
//  core
//
//  Configurable storage API: UserDefaults (with key prefix), file operations, and cache.
//

import Foundation

// MARK: - Configuration

private struct StorageConfig {
    var userDefaults: UserDefaults = .standard
    var keyPrefix: String = ""
    var documentsURL: URL?
    var cachesURL: URL?
    var appSupportURL: URL?
}

private let configLock = NSLock()
private nonisolated(unsafe) var _config: StorageConfig?
private var config: StorageConfig {
    configLock.lock()
    defer { configLock.unlock() }
    if let c = _config {
        return c
    }
    return StorageConfig()
}

// MARK: - Storage

public enum Storage {

    /// Configure storage once at app/widget launch. All parameters optional; nil means use defaults (URLs set to nil use FileManager.default).
    public static func configure(
        userDefaults: UserDefaults? = nil,
        keyPrefix: String? = nil,
        documentsURL: URL? = nil,
        cachesURL: URL? = nil,
        appSupportURL: URL? = nil
    ) {
        configLock.lock()
        defer { configLock.unlock() }
        var c = _config ?? StorageConfig()
        if let u = userDefaults { c.userDefaults = u }
        if let k = keyPrefix { c.keyPrefix = k }
        c.documentsURL = documentsURL
        c.cachesURL = cachesURL
        c.appSupportURL = appSupportURL
        _config = c
    }

    // MARK: - Key prefix

    /// The key prefix set at configure (e.g. "UHP."). Use for display or stripping full keys.
    public static var keyPrefix: String { config.keyPrefix }

    private static func prefixedKey(_ key: String) -> String {
        let prefix = config.keyPrefix
        if prefix.isEmpty { return key }
        if key.hasPrefix(prefix) { return key }
        return prefix + key
    }

    // MARK: - UserDefaults

    public static func saveToUserDefaults<T>(_ value: T, forKey key: String) {
        let prefixed = prefixedKey(key)
        let defaults = config.userDefaults
        defaults.set(value, forKey: prefixed)
        defaults.synchronize()
    }

    public static func loadFromUserDefaults<T>(forKey key: String, as type: T.Type) -> T? {
        let prefixed = prefixedKey(key)
        return config.userDefaults.object(forKey: prefixed) as? T
    }

    public static func existsInUserDefaults(forKey key: String) -> Bool {
        let prefixed = prefixedKey(key)
        return config.userDefaults.object(forKey: prefixed) != nil
    }

    public static func removeFromUserDefaults(forKey key: String) {
        let prefixed = prefixedKey(key)
        let defaults = config.userDefaults
        defaults.removeObject(forKey: prefixed)
        defaults.synchronize()
    }

    /// Returns all key-value pairs from the configured UserDefaults where the key has the configured prefix.
    public static func allUserDefaultsKeysWithPrefix() -> [String: Any] {
        let defaults = config.userDefaults
        let prefix = config.keyPrefix
        let allKeys = defaults.dictionaryRepresentation().keys
        let prefixedKeys = prefix.isEmpty ? Array(allKeys) : allKeys.filter { $0.hasPrefix(prefix) }
        var result: [String: Any] = [:]
        for key in prefixedKeys.sorted() {
            if let value = defaults.object(forKey: key) {
                result[key] = value
            }
        }
        return result
    }

    /// Prints all keys in the configured UserDefaults that match the prefix set at configure.
    /// Universal: uses whatever keyPrefix and userDefaults were passed to configure(...).
    public static func printUserDefaultsKeysWithPrefix() {
        let prefix = config.keyPrefix
        let keys = allUserDefaultsKeysWithPrefix()
        let prefixLabel = prefix.isEmpty ? "(no prefix)" : "'\(prefix)'"
        print("🔑 UserDefaults keys with prefix \(prefixLabel)")
        print("═══════════════════════════════════════════════════════════")
        if keys.isEmpty {
            print("  (0 keys found)")
        } else {
            print("  Total: \(keys.count) key\(keys.count == 1 ? "" : "s")")
            for (index, key) in keys.keys.sorted().enumerated() {
                if let value = keys[key] {
                    let valueDescription = formatValueDescriptionForPrint(value)
                    print("  \(index + 1). \(key)")
                    print("     └─ Value: \(valueDescription)")
                }
            }
        }
        print("═══════════════════════════════════════════════════════════")
    }

    private static func formatValueDescriptionForPrint(_ value: Any) -> String {
        if let stringValue = value as? String {
            return "\"\(stringValue.prefix(100))\(stringValue.count > 100 ? "..." : "")\""
        } else if let numberValue = value as? NSNumber {
            return "\(numberValue)"
        } else if let boolValue = value as? Bool {
            return "\(boolValue)"
        } else if let dataValue = value as? Data {
            return "Data(\(dataValue.count) bytes)"
        } else if let arrayValue = value as? [Any] {
            return "Array(\(arrayValue.count) items)"
        } else if let dictValue = value as? [String: Any] {
            return "Dictionary(\(dictValue.count) keys)"
        } else {
            return "\(type(of: value))"
        }
    }

    /// Removes all keys from the configured UserDefaults that match the prefix set at configure.
    /// Universal: uses whatever keyPrefix and userDefaults were passed to configure(...).
    public static func clearUserDefaultsKeysWithPrefix() {
        let prefix = config.keyPrefix
        let keys = allUserDefaultsKeysWithPrefix()
        guard !keys.isEmpty else { return }
        for fullKey in keys.keys {
            let keyWithoutPrefix = prefix.isEmpty ? fullKey : (fullKey.hasPrefix(prefix) ? String(fullKey.dropFirst(prefix.count)) : fullKey)
            removeFromUserDefaults(forKey: keyWithoutPrefix)
        }
    }

    /// Prints storage usage summary (UserDefaults size, documents, caches, available) for the configured Storage.
    public static func printStorageSummary() {
        print("🗄️ Storage Summary:")
        print("---")
        let keys = allUserDefaultsKeysWithPrefix()
        let defaultsSize = keys.values.reduce(0) { total, value in
            let valueString = "\(value)"
            return total + (valueString.data(using: .utf8)?.count ?? 0)
        }
        print("UserDefaults: ~\(defaultsSize / 1024) KB")
        print("Documents: \(totalSizeOfDirectory(at: documentsURL) / 1024 / 1024) MB")
        print("Caches: \(totalSizeOfDirectory(at: cachesURL) / 1024 / 1024) MB")
        if let available = availableStorage() {
            print("Available: \(available / 1024 / 1024) MB")
        }
        print("---")
    }

    // MARK: - Directory URLs

    public static var documentsURL: URL {
        if let url = config.documentsURL { return url }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public static var cachesURL: URL {
        if let url = config.cachesURL { return url }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    public static var appSupportURL: URL {
        if let url = config.appSupportURL {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var temporaryURL: URL {
        FileManager.default.temporaryDirectory
    }

    // MARK: - File (Documents)

    public static func saveToDocuments(data: Data, filename: String, subdirectory: String? = nil) throws -> URL {
        var base = documentsURL
        if let sub = subdirectory {
            base = base.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        let fileURL = base.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    public static func loadFromDocuments(filename: String, subdirectory: String? = nil) throws -> Data {
        var base = documentsURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let fileURL = base.appendingPathComponent(filename)
        return try Data(contentsOf: fileURL)
    }

    public static func existsInDocuments(filename: String, subdirectory: String? = nil) -> Bool {
        var base = documentsURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let fileURL = base.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    public static func deleteFromDocuments(filename: String, subdirectory: String? = nil) throws {
        var base = documentsURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let fileURL = base.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - File (Caches)

    public static func saveToCaches(data: Data, filename: String, subdirectory: String? = nil) throws -> URL {
        var base = cachesURL
        if let sub = subdirectory {
            base = base.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        let fileURL = base.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    public static func loadFromCaches(filename: String, subdirectory: String? = nil) throws -> Data {
        var base = cachesURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let fileURL = base.appendingPathComponent(filename)
        return try Data(contentsOf: fileURL)
    }

    public static func existsInCaches(filename: String, subdirectory: String? = nil) -> Bool {
        var base = cachesURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let fileURL = base.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    public static func deleteFromCaches(filename: String, subdirectory: String? = nil) throws {
        var base = cachesURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let fileURL = base.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Cache (Data)

    private static func cacheFileURL(forKey key: String, subdirectory: String?) -> URL {
        var base = cachesURL
        if let sub = subdirectory {
            base = base.appendingPathComponent(sub)
        }
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return base.appendingPathComponent("\(safeKey).cache")
    }

    @discardableResult
    public static func saveCache(
        _ data: Data,
        forKey key: String,
        maxUserDefaultsSize: Int = 100 * 1024,
        subdirectory: String? = nil
    ) throws -> URL? {
        let prefixed = prefixedKey(key)
        if data.count <= maxUserDefaultsSize {
            config.userDefaults.set(data, forKey: prefixed)
            config.userDefaults.synchronize()
            return nil
        }
        let fileURL = cacheFileURL(forKey: prefixed, subdirectory: subdirectory)
        var base = cachesURL
        if let sub = subdirectory {
            base = base.appendingPathComponent(sub)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        try data.write(to: fileURL)
        return fileURL
    }

    public static func loadCache(
        forKey key: String,
        as type: Data.Type,
        subdirectory: String? = nil
    ) throws -> Data? {
        let prefixed = prefixedKey(key)
        if let data = config.userDefaults.data(forKey: prefixed) {
            return data
        }
        let fileURL = cacheFileURL(forKey: prefixed, subdirectory: subdirectory)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    public static func removeCache(forKey key: String, subdirectory: String? = nil) {
        let prefixed = prefixedKey(key)
        config.userDefaults.removeObject(forKey: prefixed)
        config.userDefaults.synchronize()
        let fileURL = cacheFileURL(forKey: prefixed, subdirectory: subdirectory)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Cache (String)

    @discardableResult
    public static func saveCache(
        _ string: String,
        forKey key: String,
        maxUserDefaultsSize: Int = 100 * 1024,
        subdirectory: String? = nil
    ) throws -> URL? {
        guard let data = string.data(using: .utf8) else {
            throw NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "String not UTF-8"])
        }
        return try saveCache(data, forKey: key, maxUserDefaultsSize: maxUserDefaultsSize, subdirectory: subdirectory)
    }

    public static func loadCache(
        forKey key: String,
        as type: String.Type,
        subdirectory: String? = nil
    ) throws -> String? {
        guard let data = try loadCache(forKey: key, as: Data.self, subdirectory: subdirectory) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Cache (Encodable / Decodable)

    @discardableResult
    public static func saveCache<T: Encodable>(
        _ value: T,
        forKey key: String,
        maxUserDefaultsSize: Int = 100 * 1024,
        subdirectory: String? = nil
    ) throws -> URL? {
        let data = try JSONEncoder().encode(value)
        return try saveCache(data, forKey: key, maxUserDefaultsSize: maxUserDefaultsSize, subdirectory: subdirectory)
    }

    public static func loadCache<T: Decodable>(
        forKey key: String,
        as type: T.Type,
        subdirectory: String? = nil
    ) throws -> T? {
        guard let data = try loadCache(forKey: key, as: Data.self, subdirectory: subdirectory) else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Utilities

    public static func sizeOfFile(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    public static func totalSizeOfDirectory(at url: URL) -> Int64 {
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

    public static func availableStorage() -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return nil
        }
        return freeSize
    }

    public static func listFilesInDocuments(subdirectory: String? = nil) throws -> [String] {
        var base = documentsURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let contents = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
        return contents.map { $0.lastPathComponent }
    }

    public static func listFilesInCaches(subdirectory: String? = nil) throws -> [String] {
        var base = cachesURL
        if let sub = subdirectory { base = base.appendingPathComponent(sub) }
        let contents = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
        return contents.map { $0.lastPathComponent }
    }
}
