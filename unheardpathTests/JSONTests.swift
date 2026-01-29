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
        // guard let jsonString = JSONValue.encodeToString(json) else {
        //     return
        // }
        // print(jsonString)
        let jsonDict = json.mapValues { $0.asAny }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to encode JSON")
            return
        }
        print("JSON String: \n\(jsonString)")

        let encodedJSONStr = JSONValue.encodeToString(json)
        print("Encoded JSON String: \n\(encodedJSONStr ?? "Failed to encode JSON")")

    }
}