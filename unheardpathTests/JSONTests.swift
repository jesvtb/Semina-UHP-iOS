import Testing
import Foundation
@testable import unheardpath


@Suite("JSON Tests")
struct JSONTests {
    
    // Approved
    @Test("Test JSON Value")
    func testJSONValue() throws {
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
        print("Pretty Dict: \(prettyDict)")
        
        let stringJson = JSONValue.encodeToString(json)
        print("Json String: \n\(stringJson ?? "Failed to encode JSON")")

        let decodedValues = JSONValue.decode(stringJson ?? "")
        print("Decoded Values: \(decodedValues?.dictionaryValue ?? [:])")
        
        let name = decodedValues?["name"]
        print("Decoded Values Name: \(name?.stringValue ?? "Failed to decode name")")

        try check(
            name?.stringValue == "John", 
            success: "Name is John", 
            failure: "Name is not John: \(name?.stringValue ?? "nil")")
    }
}