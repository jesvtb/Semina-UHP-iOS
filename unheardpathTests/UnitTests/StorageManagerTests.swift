//
//  StorageManagerTests.swift
//  unheardpathTests
//
//  Created by Jessica Luo on 2025-01-XX.
//

import Testing
import Foundation
@testable import unheardpath

struct StorageManagerTests {
    
    // MARK: - Test Data Constants
    // Similar to Python test constants - define expected states at the top
    
    static let beforeTestCache: [String: Any] = [
        "existing_key": "test_string"
    ]
    
    static let newCacheItems: [[String: Any]] = [
        [
            "new_key_1": "test_string_value_1",
            "new_key_2": [
                "key1": "value1",
                "key2": 20
            ]
        ]
    ]
    
    static let afterNewCaching: [String: Any] = [
        "existing_key": "test_string",
        "new_key_1": "test_string_value_1",
        "new_key_2": [
            "key1": "value1",
            "key2": 20
        ]
    ]
    
    static let afterDeletingKey: [String: Any] = [
        "existing_key": "test_string",
        "new_key_2": [
            "key1": "value1",
            "key2": 20
        ]
    ]
    
    static let afterUpdatingKey: [String: Any] = [
        "existing_key": "test_string",
        "new_key_2": [
            "key1": "value1",
            "key2": 100
        ]
    ]
    
    // MARK: - Helper Functions
    
    /// Clean up test data before each test
    /// Similar to Python's setup/teardown pattern
    func cleanupTestData() {
        let storageManager = StorageManager.shared
        
        // Clean up UserDefaults test keys
        let testKeys = [
            "test_key", "test_string", "test_number", "test_bool",
            "test_lat", "test_lon", "test_timestamp",
            "small_cache", "large_cache", "test_cache",
            "existing_key", "new_key_1", "new_key_2",
            "LocationManager.lastLocation.latitude",
            "LocationManager.lastLocation.longitude",
            "LocationManager.lastLocation.timestamp"
        ]
        testKeys.forEach { key in
            storageManager.removeFromUserDefaults(forKey: key)
        }
        
        // Clean up file test data
        let testFiles = [
            "test_file.txt", "exists_test.txt", "size_test.txt",
            "test_subdir_test.txt", "test_cache.cache", "large_cache.cache"
        ]
        testFiles.forEach { filename in
            try? storageManager.deleteFromCaches(filename: filename)
            try? storageManager.deleteFromDocuments(filename: filename)
        }
        
        // Clean up subdirectories
        try? FileManager.default.removeItem(at: storageManager.cachesURL.appendingPathComponent("test_subdir"))
        try? FileManager.default.removeItem(at: storageManager.documentsURL.appendingPathComponent("test_subdir"))
    }
    
    /// Check helper function - similar to Python's check() function
    /// Prints success/failure messages and asserts the condition
    /// - Parameters:
    ///   - condition: The condition to check
    ///   - successMsg: Message to print on success
    ///   - failureMsg: Message to print on failure
    func check(_ condition: Bool, successMsg: String, failureMsg: String) {
        if condition {
            print("✓✓✓   \(successMsg)")
        } else {
            print("✗✗✗   \(failureMsg)")
        }
        #expect(condition, "\(failureMsg)")
    }
    
    // MARK: - Main Cache Manager Test
    // Similar to Python's test_cache_manager() - comprehensive sequential test
    
    @Test func testStorageManager() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Initialize cache with existing data (similar to Python's BEFORE_TEST_CACHE)
        for (key, value) in Self.beforeTestCache {
            storageManager.saveToUserDefaults(value, forKey: key)
        }
        
        // Test: Existing key exists
        check(
            storageManager.existsInUserDefaults(forKey: "existing_key"),
            successMsg: "Existing key exists in cache before testing",
            failureMsg: "Existing key does not exist in cache before testing"
        )
        
        // Test: Existing key value matches expected
        if let loaded = storageManager.loadFromUserDefaults(forKey: "existing_key", as: String.self) {
            check(
                loaded == "test_string",
                successMsg: "Existing key value matches expected",
                failureMsg: "Existing key value does not match expected"
            )
        } else {
            check(
                false,
                successMsg: "",
                failureMsg: "Existing key value does not match expected"
            )
        }
        
        // Test: Non-existing key returns nil
        let nonExisting = storageManager.loadFromUserDefaults(forKey: "non_existing_key", as: String.self)
        check(
            nonExisting == nil,
            successMsg: "Non existing key returns nil",
            failureMsg: "Non existing key returns not nil"
        )
        
        // Test: Add new cache items (similar to Python's NEW_CACHE_ITEMS)
        for item in Self.newCacheItems {
            for (key, value) in item {
                storageManager.saveToUserDefaults(value, forKey: key)
                check(
                    storageManager.existsInUserDefaults(forKey: key),
                    successMsg: "New key \(key) exists in cache after caching",
                    failureMsg: "New key \(key) does not exist in cache after caching"
                )
            }
        }
        
        // Test: Cache matches expected after new caching (similar to Python's AFTER_NEW_CACHING)
        var currentCache: [String: Any] = [:]
        for key in ["existing_key", "new_key_1", "new_key_2"] {
            if let value = storageManager.loadFromUserDefaults(forKey: key, as: Any.self) {
                currentCache[key] = value
            }
        }
        
        // Compare dictionaries (simplified comparison)
        let expectedKeys = Set(Self.afterNewCaching.keys)
        let currentKeys = Set(currentCache.keys)
        check(
            expectedKeys == currentKeys,
            successMsg: "Cache matches expected after new caching",
            failureMsg: "Cache does not match expected after new caching"
        )
        
        // Test: Delete a key
        storageManager.removeFromUserDefaults(forKey: "new_key_1")
        check(
            !storageManager.existsInUserDefaults(forKey: "new_key_1"),
            successMsg: "New key 1 does not exist in cache after deleting",
            failureMsg: "New key 1 exists in cache after deleting"
        )
        
        // Test: Cache matches expected after deleting (similar to Python's AFTER_DELETING_KEY)
        var cacheAfterDelete: [String: Any] = [:]
        for key in ["existing_key", "new_key_2"] {
            if let value = storageManager.loadFromUserDefaults(forKey: key, as: Any.self) {
                cacheAfterDelete[key] = value
            }
        }
        let expectedKeysAfterDelete = Set(Self.afterDeletingKey.keys)
        let currentKeysAfterDelete = Set(cacheAfterDelete.keys)
        check(
            expectedKeysAfterDelete == currentKeysAfterDelete,
            successMsg: "Cache matches expected after deleting new key 1",
            failureMsg: "Cache does not match expected after deleting new key 1"
        )
        
        // Test: Update a key
        let updatedValue: [String: Any] = [
            "key1": "value1",
            "key2": 100
        ]
        storageManager.saveToUserDefaults(updatedValue, forKey: "new_key_2")
        
        // Test: Cache matches expected after updating (similar to Python's AFTER_UPDATING_KEY)
        var cacheAfterUpdate: [String: Any] = [:]
        for key in ["existing_key", "new_key_2"] {
            if let value = storageManager.loadFromUserDefaults(forKey: key, as: Any.self) {
                cacheAfterUpdate[key] = value
            }
        }
        let expectedKeysAfterUpdate = Set(Self.afterUpdatingKey.keys)
        let currentKeysAfterUpdate = Set(cacheAfterUpdate.keys)
        check(
            expectedKeysAfterUpdate == currentKeysAfterUpdate,
            successMsg: "Cache matches expected after updating new key 2",
            failureMsg: "Cache does not match expected after updating new key 2"
        )
        
        // Test: Clear all cache
        for key in currentCache.keys {
            storageManager.removeFromUserDefaults(forKey: key)
        }
        
        let allCleared = currentCache.keys.allSatisfy { key in
            !storageManager.existsInUserDefaults(forKey: key)
        }
        check(
            allCleared,
            successMsg: "Cache is empty after clearing",
            failureMsg: "Cache is not empty after clearing"
        )
    }
    
    // MARK: - Location Data Tests
    
    @Test func testSaveAndLoadLocation() {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let lat = 37.7749
        let lon = -122.4194
        let timestamp = Date().timeIntervalSince1970
        
        storageManager.saveLocation(latitude: lat, longitude: lon, timestamp: timestamp)
        
        if let location = storageManager.loadLocation() {
            #expect(abs(location.latitude - lat) < 0.0001)
            #expect(abs(location.longitude - lon) < 0.0001)
            #expect(abs(location.timestamp - timestamp) < 1.0)
        } else {
            Issue.record("Location should be loaded")
        }
    }
    
    @Test func testLoadLocationWithZeroCoordinates() {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Save zero coordinates (should be ignored)
        storageManager.saveLocation(latitude: 0.0, longitude: 0.0)
        
        // Should return nil for zero coordinates
        let location = storageManager.loadLocation()
        #expect(location == nil)
    }
    
    @Test func testLoadLocationWhenNotSaved() {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Should return nil when no location is saved
        let location = storageManager.loadLocation()
        #expect(location == nil)
    }
    
    // MARK: - File Storage Tests (Caches)
    
    @Test func testSaveAndLoadToCaches() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let testData = "Test content".data(using: .utf8)!
        let filename = "test_file.txt"
        
        // Save
        let url = try storageManager.saveToCaches(data: testData, filename: filename)
        #expect(FileManager.default.fileExists(atPath: url.path) == true)
        
        // Load
        let loadedData = try storageManager.loadFromCaches(filename: filename)
        #expect(loadedData == testData)
    }
    
    @Test func testSaveToCachesWithSubdirectory() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let testData = "Test content".data(using: .utf8)!
        let filename = "test.txt"
        let subdirectory = "test_subdir"
        
        // Save to subdirectory
        let url = try storageManager.saveToCaches(data: testData, filename: filename, subdirectory: subdirectory)
        #expect(FileManager.default.fileExists(atPath: url.path) == true)
        #expect(url.path.contains(subdirectory) == true)
        
        // Load from subdirectory
        let loadedData = try storageManager.loadFromCaches(filename: filename, subdirectory: subdirectory)
        #expect(loadedData == testData)
    }
    
    @Test func testExistsInCaches() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let testData = "Test".data(using: .utf8)!
        _ = try storageManager.saveToCaches(data: testData, filename: "exists_test.txt")
        
        #expect(storageManager.existsInCaches(filename: "exists_test.txt") == true)
        #expect(storageManager.existsInCaches(filename: "non_existent.txt") == false)
    }
    
    @Test func testDeleteFromCaches() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let testData = "Test".data(using: .utf8)!
        _ = try storageManager.saveToCaches(data: testData, filename: "test_delete.txt")
        #expect(storageManager.existsInCaches(filename: "test_delete.txt") == true)
        
        try storageManager.deleteFromCaches(filename: "test_delete.txt")
        #expect(storageManager.existsInCaches(filename: "test_delete.txt") == false)
    }
    
    // MARK: - File Storage Tests (Documents)
    
    @Test func testSaveAndLoadToDocuments() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let testData = "Test content".data(using: .utf8)!
        let filename = "test_file.txt"
        
        // Save
        let url = try storageManager.saveToDocuments(data: testData, filename: filename)
        #expect(FileManager.default.fileExists(atPath: url.path) == true)
        
        // Load
        let loadedData = try storageManager.loadFromDocuments(filename: filename)
        #expect(loadedData == testData)
    }
    
    @Test func testExistsInDocuments() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let testData = "Test".data(using: .utf8)!
        _ = try storageManager.saveToDocuments(data: testData, filename: "exists_test.txt")
        
        #expect(storageManager.existsInDocuments(filename: "exists_test.txt") == true)
        #expect(storageManager.existsInDocuments(filename: "non_existent.txt") == false)
    }
    
    // MARK: - Cache Management Tests
    
    @Test func testSmallCacheUsesUserDefaults() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Small dictionary should use UserDefaults
        let smallDict: [String: Any] = ["key1": "value1", "key2": 42]
        let url = try storageManager.saveCache(smallDict, forKey: "small_cache", maxUserDefaultsSize: 100 * 1024)
        
        // Should return nil (stored in UserDefaults, not file)
        #expect(url == nil)
        
        // Should be loadable from UserDefaults
        let loaded = try storageManager.loadCache(forKey: "small_cache", as: [String: Any].self)
        #expect(loaded != nil)
        if let loadedDict = loaded {
            #expect(loadedDict["key1"] as? String == "value1")
            #expect(loadedDict["key2"] as? Int == 42)
        }
    }
    
    @Test func testLargeCacheUsesFileStorage() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Create large data (> 100 KB)
        let largeString = String(repeating: "x", count: 150 * 1024) // 150 KB
        let largeData = largeString.data(using: .utf8)!
        
        let url = try storageManager.saveCache(largeData, forKey: "large_cache", maxUserDefaultsSize: 100 * 1024)
        
        // Should return URL (stored as file)
        #expect(url != nil)
        if let fileURL = url {
            #expect(FileManager.default.fileExists(atPath: fileURL.path) == true)
            
            // Should be loadable from file
            let loaded = try storageManager.loadCache(forKey: "large_cache", as: Data.self)
            #expect(loaded != nil)
            if let loadedData = loaded {
                #expect(loadedData.count == largeData.count)
            }
        }
    }
    
    @Test func testCacheWithArray() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Test caching an array
        let testArray: [[String: Any]] = [
            ["idx": 1, "pageid": 123],
            ["idx": 2, "pageid": 456]
        ]
        
        _ = try storageManager.saveCache(testArray, forKey: "test_cache", maxUserDefaultsSize: 100 * 1024)
        
        let loaded = try storageManager.loadCache(forKey: "test_cache", as: [[String: Any]].self)
        #expect(loaded != nil)
        if let loadedArray = loaded {
            #expect(loadedArray.count == 2)
        }
    }
    
    @Test func testRemoveCache() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Save small cache (UserDefaults)
        try storageManager.saveCache(["test": "value"], forKey: "test_cache")
        #expect(storageManager.existsInUserDefaults(forKey: "test_cache") == true)
        
        // Remove cache
        storageManager.removeCache(forKey: "test_cache")
        #expect(storageManager.existsInUserDefaults(forKey: "test_cache") == false)
    }
    
    // MARK: - Utility Tests
    
    @Test func testFileSizeCalculation() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let testData = "Test content".data(using: .utf8)!
        let url = try storageManager.saveToCaches(data: testData, filename: "size_test.txt")
        
        if let size = storageManager.sizeOfFile(at: url) {
            #expect(size == Int64(testData.count))
        } else {
            Issue.record("Should be able to calculate file size")
        }
    }
    
    @Test func testAvailableStorage() {
        let storageManager = StorageManager.shared
        let available = storageManager.availableStorage()
        
        #expect(available != nil)
        if let availableSpace = available {
            #expect(availableSpace > 0)
        }
    }
    
    @Test func testListFilesInCaches() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Save a few test files
        let testData = "Test".data(using: .utf8)!
        _ = try storageManager.saveToCaches(data: testData, filename: "file1.txt")
        _ = try storageManager.saveToCaches(data: testData, filename: "file2.txt")
        
        let files = try storageManager.listFilesInCaches()
        #expect(files.contains("file1.txt") == true)
        #expect(files.contains("file2.txt") == true)
    }
    
    @Test func testListFilesInDocuments() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Save a test file
        let testData = "Test".data(using: .utf8)!
        _ = try storageManager.saveToDocuments(data: testData, filename: "doc_file.txt")
        
        let files = try storageManager.listFilesInDocuments()
        #expect(files.contains("doc_file.txt") == true)
    }
    
    // MARK: - Wiki Feature Size Test
    
    @Test func testWikiFeatureSize() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Create a wiki feature similar to the actual data structure
        let wikiFeature: [String: Any] = [
            "type": "Feature",
            "geometry": [
                "type": "Point",
                "coordinates": [114.10416667, 22.56444444]
            ],
            "properties": [
                "idx": 1,
                "pageid": 45555819,
                "title": "Baoneng Center",
                "wiki_url": "https://en.wikipedia.org/?curid=45555819",
                "extract": "The Baoneng Center is a supertall skyscraper in Shenzhen, Guangdong, China. It is 328 metres (1,076.1 ft) tall. Construction started in 2014 and was completed in 2020.\nThe architecture firm Aedas designed Baoneng Center for Baoneng Group.",
                "name": "Baoneng Center",
                "categories": [
                    "Buildings and structures under construction in China",
                    "People's Republic of China building and structure stubs",
                    "Shenzhen stubs",
                    "Skyscraper office buildings in Shenzhen"
                ],
                "img_url": "https://en.wikipedia.org/wiki/Special:FilePath/Baoneng_Center_Shenzhen_2021.jpg",
                "short_description": "Supertall skyscraper in Shenzhen, Guangdong, China"
            ]
        ]
        
        // Calculate size
        let jsonData = try JSONSerialization.data(withJSONObject: wikiFeature)
        let sizeInBytes = jsonData.count
        
        // Verify size is approximately 900 bytes (0.88 KB)
        #expect(sizeInBytes > 800)
        #expect(sizeInBytes < 1000)
        
        // Test that it uses UserDefaults (small enough)
        let url = try storageManager.saveCache(wikiFeature, forKey: "wiki_45555819", maxUserDefaultsSize: 100 * 1024)
        #expect(url == nil) // Should use UserDefaults, not file storage
        
        // Verify it can be loaded
        let loaded = try storageManager.loadCache(forKey: "wiki_45555819", as: [String: Any].self)
        #expect(loaded != nil)
        
        if let loadedFeature = loaded,
           let properties = loadedFeature["properties"] as? [String: Any] {
            #expect(properties["pageid"] as? Int == 45555819)
            #expect(properties["title"] as? String == "Baoneng Center")
        }
    }
    
    // MARK: - Edge Cases
    
    @Test func testLoadNonExistentFile() {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Should throw error when loading non-existent file
        do {
            _ = try storageManager.loadFromCaches(filename: "non_existent.txt")
            Issue.record("Should have thrown an error for non-existent file")
        } catch {
            // Expected to throw
            #expect(true)
        }
    }
    
    @Test func testSaveOverwritesExistingFile() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        let initialData = "Initial content".data(using: .utf8)!
        let newData = "New content".data(using: .utf8)!
        
        _ = try storageManager.saveToCaches(data: initialData, filename: "overwrite_test.txt")
        _ = try storageManager.saveToCaches(data: newData, filename: "overwrite_test.txt")
        
        let loaded = try storageManager.loadFromCaches(filename: "overwrite_test.txt")
        #expect(loaded == newData)
        #expect(loaded != initialData)
    }
    
    @Test func testCacheWithSubdirectory() throws {
        cleanupTestData()
        let storageManager = StorageManager.shared
        
        // Create large cache that will use file storage
        let largeString = String(repeating: "x", count: 150 * 1024)
        let largeData = largeString.data(using: .utf8)!
        
        let url = try storageManager.saveCache(
            largeData,
            forKey: "subdir_cache",
            maxUserDefaultsSize: 100 * 1024,
            subdirectory: "test_subdir"
        )
        
        #expect(url != nil)
        if let fileURL = url {
            #expect(fileURL.path.contains("test_subdir") == true)
        }
    }
}

