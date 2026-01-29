import Testing
import Foundation
@testable import core

@Suite("API Tests")
struct APITests {
    
    @Test("Test API Client")
    func testAPIClient() throws {
        let client = APIClient()
    }
}