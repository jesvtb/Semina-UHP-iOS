import Testing
import Foundation
@testable import unheardpath


@Suite("JSON Tests")
struct JSONTests {
    
    @Test("Test JSON Value")
    func testJSONValue() {
        let json: [String: JSONValue] = [
            "name": .string("John"),
            "age": .int(30),
            "isStudent": .bool(true),
            "height": .double(1.8),
            "children": .array([.string("Alice"), .string("Bob")]),
            "address": .dictionary(["street": .string("123 Main St"), "city": .string("Anytown")]),
            "pets": .null
        ]
        let prettyDict = JSONValue.prettyDict(json)
        let stringDic = JSONValue.encodeToString(json)
        print("Pretty Dict: \(prettyDict)")
        print("Json String: \n\(stringDic ?? "Failed to encode JSON")")
    }
}