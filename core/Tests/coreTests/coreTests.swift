import Testing
import Foundation
@testable import core

// MARK: - JSON test case helpers (universal test resources)

enum JSONTestCases {
    /// Returns the URL for a JSON test case by name (without .json). Tries subdirectory then bundle root.
    static func url(forTestCase name: String, subdirectory: String) -> URL? {
        let base = (name as NSString).deletingPathExtension
        return Bundle.module.url(forResource: base, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: base, withExtension: "json", subdirectory: nil)
    }

    /// Returns test case names (without .json) for all JSON files in `subdirectory`. Use as `arguments:` for one test case per file.
    static func testCaseNames(inSubdirectory subdirectory: String) -> [String] {
        urls(inSubdirectory: subdirectory).map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Returns test case URLs: if `names` is nil or empty, all JSON files in `subdirectory`; otherwise only the named test cases.
    static func testCaseURLs(subdirectory: String, names: [String]? = nil) -> [URL] {
        if let n = names, !n.isEmpty {
            return n.compactMap { url(forTestCase: $0, subdirectory: subdirectory) }
        }
        return urls(inSubdirectory: subdirectory)
    }

    /// Returns URLs of all JSON files in the given subdirectory of the test bundle.
    static func urls(inSubdirectory subdirectory: String) -> [URL] {
        if let bundleURLs = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: subdirectory), !bundleURLs.isEmpty {
            return bundleURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        if let bundleURLs = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil), !bundleURLs.isEmpty {
            return bundleURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        guard let dirURL = Bundle.module.url(forResource: subdirectory, withExtension: nil, subdirectory: nil),
              let entries = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Loads a JSON test case by name and subdirectory. Use this when you have the test case name (e.g. from arguments).
    static func loadJSONDictionary(testCaseName: String, subdirectory: String) throws -> [String: Any] {
        guard let url = url(forTestCase: testCaseName, subdirectory: subdirectory) else {
            struct TestCaseNotFound: Error {}
            throw TestCaseNotFound()
        }
        return try loadJSONDictionary(from: url)
    }

    /// Loads a JSON file into a dictionary for use as test input.
    static func loadJSONDictionary(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            struct TestCaseError: Error {}
            throw TestCaseError()
        }
        return dict
    }
}

func require(_ condition: Bool, success: String, failure: String) throws {

    print("================")
    if condition {
        print("✅ \(success)")
    } else {
        print("❌ \(failure)")
    }
    print("================")
    
    try #require(condition, Comment(stringLiteral: failure))
}

func expect(_ condition: Bool, success: String, failure: String) {
    print("================")
    if condition {
        print("✅ \(success)")
    } else {
        print("❌ \(failure)")
    }
    print("================")
    #expect(condition, Comment(stringLiteral: failure))
}

@Suite("Test Utilities")
struct UtilitiesTests {
    
    @Test("Numbers are positive", arguments: [1, -1])
    func testNumberIsPositive(value: Int) throws {
        // #expect(value > 0)
        try require(
            value > 0, 
            success: "Number is positive", 
            failure: "Number is not positive: \(value)")
    }
}