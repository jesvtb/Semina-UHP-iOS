//
//  APITestUtilities.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import Foundation
import core


// MARK: - API Test Configuration
struct APITestConfig: Sendable {
    let name: String
    let url: String
    let method: String
    let headers: [String: String]?
    let params: [String: String]
    let jsonDict: [String: JSONValue]
    let expectedSuccess: Bool
    let description: String
    
    init(
        name: String,
        url: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        params: [String: String] = [:],
        jsonDict: [String: JSONValue] = [:],
        expectedSuccess: Bool = true,
        description: String = ""
    ) {
        self.name = name
        self.url = url
        self.method = method
        self.headers = headers
        self.params = params
        self.jsonDict = jsonDict
        self.expectedSuccess = expectedSuccess
        self.description = description
    }
}

// MARK: - API Test Utilities
class APITestUtilities {
    
    // MARK: - Test Configurations
    static let testConfigurations: [APITestConfig] = [
        // External APIs (may fail if services unavailable)
        APITestConfig(
            name: "Ollama",
            url: "http://192.168.50.171:11434/v1/models",
            expectedSuccess: false,
            description: "Local Ollama instance - may fail if not running"
        ),
        APITestConfig(
            name: "Request Building",
            url: "https://httpbin.org/get",
            headers: ["Test-Header": "Test-Value"],
            params: ["param1": "value1", "param2": "value2"],
            expectedSuccess: true,
            description: "Tests request building with headers and params"
        ),
        APITestConfig(
            name: "Semina API",
            url: "https://api.unheardpath.com/v1/test/connection",
            expectedSuccess: true,
            description: "Test Semina API"
        ),
        APITestConfig(
            name: "Semina API Local",
            url: "http://192.168.50.171:1031/v1/test/connection",
            expectedSuccess: true,
            description: "Test Semina API Local"
        ),
        
    ]
}

// MARK: - Debug Visualizer
/// Owns debug responsibilities for Storage/UserDefaults inspection and cache clearing.
/// Use from debug UI or Xcode console (e.g. `DebugVisualizer.printAllUserDefaults()`).
#if DEBUG
enum DebugVisualizer {

    /// Prints all UserDefaults data stored by this app (Storage prefix, e.g. "UHP.").
    /// Call from Xcode debug console: `po DebugVisualizer.printAllUserDefaults()`
    static func printAllUserDefaults() {
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()

        print("🗄️ UserDefaults Contents for Unheard Path:")
        print("Total keys in UserDefaults: \(dict.count)")
        print("---")

        let appKeys = dict.keys.filter { $0.hasPrefix("UHP.") }

        print("App-specific keys: \(appKeys.count)")
        print("---")

        for key in appKeys.sorted() {
            if let value = dict[key] {
                let valueString = "\(value)"
                let size = valueString.data(using: .utf8)?.count ?? 0

                print("🔑 \(key)")
                print("   Size: \(size) bytes (~\(size / 1024) KB)")

                if size < 500 {
                    print("   Value: \(valueString.prefix(200))")
                } else {
                    if let dictValue = value as? [String: Any] {
                        print("   Value: [Dictionary with \(dictValue.count) keys]")
                        if let features = dictValue["features"] as? [[String: Any]] {
                            print("   Features count: \(features.count)")
                        }
                    } else {
                        print("   Value: [Large object, \(size) bytes]")
                    }
                }
                print("")
            }
        }

        let totalSize = appKeys.compactMap { key -> Int? in
            guard let value = dict[key] else { return nil }
            return "\(value)".data(using: .utf8)?.count
        }.reduce(0, +)

        print("---")
        print("📊 Summary:")
        print("   Total app keys: \(appKeys.count)")
        print("   Total size: \(totalSize) bytes (~\(totalSize / 1024) KB)")
        print("   Estimated limit: ~1-2 MB (you're using \(String(format: "%.1f", Double(totalSize) / 1024 / 1024 * 100))% of 1 MB)")
    }

    /// Clears all Storage-backed UserDefaults keys (app cache).
    static func clearAllCache() {
        let count = Storage.allUserDefaultsKeysWithPrefix().count
        Storage.clearUserDefaultsKeysWithPrefix()
        print("🗑️ Cleared \(count) cache entries")
    }
}
#endif
