import Testing
import Foundation
@testable import core

/// Storage tests use a shared lock so only one runs at a time (Storage has global config).
private let storageTestLock = NSLock()

@Suite("Storage tests")
struct StorageTests {

    @Test("UserDefaults: save, load, exists, remove, key prefix")
    func userDefaults() throws {
        storageTestLock.lock()
        defer { storageTestLock.unlock() }

        let prefix = "test.\(UUID().uuidString)."
        Storage.configure(userDefaults: .standard, keyPrefix: prefix)

        Storage.saveToUserDefaults("hello", forKey: "key1")
        let loaded: String? = Storage.loadFromUserDefaults(forKey: "key1", as: String.self)
        expect(loaded == "hello", success: "Loaded value equals saved \"hello\"", failure: "Loaded value is not \"hello\": \(String(describing: loaded))")

        expect(Storage.existsInUserDefaults(forKey: "key1") == true, success: "key1 exists in UserDefaults", failure: "key1 does not exist in UserDefaults")
        Storage.removeFromUserDefaults(forKey: "key1")
        expect(Storage.existsInUserDefaults(forKey: "key1") == false, success: "key1 removed from UserDefaults", failure: "key1 still exists in UserDefaults after remove")

        Storage.saveToUserDefaults("value", forKey: "mykey")
        let loadedMykey: String? = Storage.loadFromUserDefaults(forKey: "mykey", as: String.self)
        expect(loadedMykey == "value", success: "Loaded mykey equals saved \"value\"", failure: "Loaded mykey is not \"value\": \(String(describing: loadedMykey))")
    }

    @Test("File Documents: save, load, exists, delete")
    func fileDocuments() throws {
        storageTestLock.lock()
        defer { storageTestLock.unlock() }

        let prefix = "test.\(UUID().uuidString)."
        let tempDocuments = FileManager.default.temporaryDirectory
            .appendingPathComponent("storageTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDocuments, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDocuments) }

        Storage.configure(userDefaults: .standard, keyPrefix: prefix, documentsURL: tempDocuments, cachesURL: nil, appSupportURL: nil)

        let data = Data("file content".utf8)
        let url = try Storage.saveToDocuments(data: data, filename: "test.txt")
        expect(FileManager.default.fileExists(atPath: url.path), success: "Saved file exists at url", failure: "Saved file does not exist at \(url.path)")

        let loadedFile = try Storage.loadFromDocuments(filename: "test.txt")
        expect(loadedFile == data, success: "Loaded file content matches saved data", failure: "Loaded file content does not match saved data")

        expect(Storage.existsInDocuments(filename: "test.txt") == true, success: "test.txt exists in documents", failure: "test.txt does not exist in documents")
        try Storage.deleteFromDocuments(filename: "test.txt")
        expect(Storage.existsInDocuments(filename: "test.txt") == false, success: "test.txt removed from documents", failure: "test.txt still exists in documents after delete")
    }

    @Test("File Caches: save, load")
    func fileCaches() throws {
        storageTestLock.lock()
        defer { storageTestLock.unlock() }

        let prefix = "test.\(UUID().uuidString)."
        let tempDocuments = FileManager.default.temporaryDirectory
            .appendingPathComponent("storageTests")
            .appendingPathComponent(UUID().uuidString)
        let tempCaches = FileManager.default.temporaryDirectory
            .appendingPathComponent("storageTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDocuments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempCaches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDocuments); try? FileManager.default.removeItem(at: tempCaches) }

        Storage.configure(userDefaults: .standard, keyPrefix: prefix, documentsURL: tempDocuments, cachesURL: tempCaches, appSupportURL: nil)

        let cacheData = Data("cache content".utf8)
        _ = try Storage.saveToCaches(data: cacheData, filename: "cache.dat")
        let loadedCache = try Storage.loadFromCaches(filename: "cache.dat")
        expect(loadedCache == cacheData, success: "Loaded cache matches saved cache data", failure: "Loaded cache does not match saved cache data")
    }

    @Test("Cache layer: small in UserDefaults, large in file, removeCache")
    func cacheLayer() throws {
        storageTestLock.lock()
        defer { storageTestLock.unlock() }

        let prefix = "test.\(UUID().uuidString)."
        let tempCaches = FileManager.default.temporaryDirectory
            .appendingPathComponent("storageTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempCaches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempCaches) }

        Storage.configure(userDefaults: .standard, keyPrefix: prefix, documentsURL: nil, cachesURL: tempCaches, appSupportURL: nil)

        let small = Data("small".utf8)
        let urlSmall = try Storage.saveCache(small, forKey: "small", maxUserDefaultsSize: 100)
        expect(urlSmall == nil, success: "Small payload stored in UserDefaults (no file url)", failure: "Small payload unexpectedly got file url: \(String(describing: urlSmall))")
        let loadedSmall = try Storage.loadCache(forKey: "small", as: Data.self)
        expect(loadedSmall == small, success: "Loaded small cache matches saved data", failure: "Loaded small cache does not match saved data")

        let large = Data(repeating: 0xAB, count: 200 * 1024)
        let urlLarge = try Storage.saveCache(large, forKey: "large", maxUserDefaultsSize: 100 * 1024)
        expect(urlLarge != nil, success: "Large payload stored in file (file url returned)", failure: "Large payload expected file url but got nil")
        let loadedLarge = try Storage.loadCache(forKey: "large", as: Data.self)
        expect(loadedLarge == large, success: "Loaded large cache matches saved data", failure: "Loaded large cache does not match saved data")

        Storage.saveToUserDefaults(Data("x".utf8), forKey: "ck")
        Storage.removeCache(forKey: "ck")
        let loadedCk = try Storage.loadCache(forKey: "ck", as: Data.self)
        expect(loadedCk == nil, success: "Cache key \"ck\" removed and load returns nil", failure: "Loaded ck is not nil after remove: \(String(describing: loadedCk))")
    }

    @Test("Utilities: sizeOfFile, totalSizeOfDirectory, listFilesInDocuments")
    func utilities() throws {
        storageTestLock.lock()
        defer { storageTestLock.unlock() }

        let prefix = "test.\(UUID().uuidString)."
        let tempDocuments = FileManager.default.temporaryDirectory
            .appendingPathComponent("storageTests")
            .appendingPathComponent(UUID().uuidString)
        let tempCaches = FileManager.default.temporaryDirectory
            .appendingPathComponent("storageTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDocuments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempCaches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDocuments); try? FileManager.default.removeItem(at: tempCaches) }

        Storage.configure(userDefaults: .standard, keyPrefix: prefix, documentsURL: tempDocuments, cachesURL: tempCaches, appSupportURL: nil)

        let utilData = Data("hello".utf8)
        let utilUrl = try Storage.saveToDocuments(data: utilData, filename: "s.txt")
        let size = Storage.sizeOfFile(at: utilUrl)
        expect(size == 5, success: "File size is 5 bytes", failure: "File size is not 5: \(String(describing: size))")

        let total = Storage.totalSizeOfDirectory(at: tempDocuments)
        expect(total >= 5, success: "Total directory size is at least 5 bytes", failure: "Total directory size is less than 5: \(total)")

        _ = try Storage.saveToDocuments(data: Data("a".utf8), filename: "a.txt")
        _ = try Storage.saveToDocuments(data: Data("b".utf8), filename: "b.txt")
        let list = try Storage.listFilesInDocuments()
        expect(list.contains("a.txt"), success: "List contains a.txt", failure: "List does not contain a.txt: \(list)")
        expect(list.contains("b.txt"), success: "List contains b.txt", failure: "List does not contain b.txt: \(list)")
    }
}
