import Testing

func check(_ condition: Bool, success: String, failure: String) throws {

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

@Suite("Test Utilities")
struct UtilitiesTests {
    
    @Test("Numbers are positive", arguments: [1, -1])
    func testNumberIsPositive(value: Int) throws {
        // #expect(value > 0)
        try check(
            value > 0, 
            success: "Number is positive", 
            failure: "Number is not positive: \(value)")
    }
}