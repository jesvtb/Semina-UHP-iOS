import Testing
@testable import core

// @Test func example() async throws {
//     // Write your test here and use APIs like `#expect(...)` to check expected conditions.
// }

func require(_ condition: Bool, success: String, failure: String) throws {

    print("================")
    if condition {
        print("✅ \(success)")
    } else {
        // We print before the throw because #require will exit the function
        print("❌ \(failure)")
    }
    print("================")
    
    try #require(condition, Comment(stringLiteral: failure))
}

/// Validation helper that prints success/failure and uses #expect so tests report the failure message.
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