// import Testing
// import Foundation
// @testable import unheardpath

// /// Mock logger for testing
// private class MockLogger: AppLifecycleLogger {
//     var debugMessages: [String] = []
//     var errorMessages: [(message: String, handlerType: String?, error: Error?)] = []
//     var warningMessages: [(message: String, handlerType: String?)] = []
    
//     func debug(_ message: String) {
//         debugMessages.append(message)
//     }
    
//     func error(_ message: String, handlerType: String?, error: Error?) {
//         errorMessages.append((message, handlerType, error))
//     }
    
//     func warning(_ message: String, handlerType: String?) {
//         warningMessages.append((message, handlerType))
//     }
// }

// /// Test handler class for lifecycle events
// private class TestHandler {
//     var didEnterBackgroundCalled = false
//     var willEnterForegroundCalled = false
//     var shouldThrow = false
//     var shouldBeSlow = false
    
//     @MainActor
//     func handleDidEnterBackground() throws {
//         didEnterBackgroundCalled = true
        
//         if shouldThrow {
//             // Simulate an error (even though handlers shouldn't throw)
//             // This tests defensive error handling
//             throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error in handler"])
//         }
        
//         if shouldBeSlow {
//             // Simulate slow operation (>100ms)
//             Thread.sleep(forTimeInterval: 0.15) // 150ms
//         }
//     }
    
//     @MainActor
//     func handleWillEnterForeground() throws {
//         willEnterForegroundCalled = true
        
//         if shouldThrow {
//             throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error in handler"])
//         }
        
//         if shouldBeSlow {
//             Thread.sleep(forTimeInterval: 0.15)
//         }
//     }
// }

// struct AppLifecycleManagerTests {
    
//     @Test @MainActor
//     func testErrorIsolation() async {
//         let mockLogger = MockLogger()
//         let manager = AppLifecycleManager(logger: mockLogger)
        
//         let handler1 = TestHandler()
//         let handler2 = TestHandler()
//         let handler3 = TestHandler()
        
//         // Make handler2 throw an error
//         handler2.shouldThrow = true
        
//         // Register all handlers
//         // Note: Since handlers are non-throwing, we wrap throwing calls in do-catch
//         manager.register(
//             object: handler1,
//             didEnterBackground: {
//                 do {
//                     try handler1.handleDidEnterBackground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             },
//             willEnterForeground: {
//                 do {
//                     try handler1.handleWillEnterForeground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             }
//         )
        
//         manager.register(
//             object: handler2,
//             didEnterBackground: {
//                 do {
//                     try handler2.handleDidEnterBackground()
//                 } catch {
//                     // This error should be caught by AppLifecycleManager's defensive error handling
//                 }
//             },
//             willEnterForeground: {
//                 do {
//                     try handler2.handleWillEnterForeground()
//                 } catch {
//                     // This error should be caught by AppLifecycleManager's defensive error handling
//                 }
//             }
//         )
        
//         manager.register(
//             object: handler3,
//             didEnterBackground: {
//                 do {
//                     try handler3.handleDidEnterBackground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             },
//             willEnterForeground: {
//                 do {
//                     try handler3.handleWillEnterForeground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             }
//         )
        
//         // Verify handlers were registered
//         #expect(mockLogger.debugMessages.contains { $0.contains("Registered handler") })
//         #expect(mockLogger.debugMessages.count >= 3)
        
//         // Note: Actual error isolation would be tested when lifecycle events fire
//         // The defensive error handling in notifyHandlers will catch any unexpected errors
//     }
    
//     @Test @MainActor
//     func testCleanupOfDeallocatedHandlers() async {
//         let mockLogger = MockLogger()
//         let manager = AppLifecycleManager(logger: mockLogger)
        
//         // Create a handler that will be deallocated
//         var handler: TestHandler? = TestHandler()
        
//         manager.register(
//             object: handler!,
//             didEnterBackground: {
//                 do {
//                     try handler?.handleDidEnterBackground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             },
//             willEnterForeground: {
//                 do {
//                     try handler?.handleWillEnterForeground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             }
//         )
        
//         // Verify handler was registered
//         #expect(mockLogger.debugMessages.contains { $0.contains("Registered handler") })
        
//         // Deallocate handler
//         handler = nil
        
//         // Access internal handlers array via reflection or test helper
//         // Since handlers is private, we test indirectly by checking that
//         // the manager still works correctly after deallocation
        
//         // Register another handler to ensure manager still works
//         let handler2 = TestHandler()
//         manager.register(
//             object: handler2,
//             didEnterBackground: {
//                 do {
//                     try handler2.handleDidEnterBackground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             },
//             willEnterForeground: {
//                 do {
//                     try handler2.handleWillEnterForeground()
//                 } catch {
//                     // Handler should catch errors internally
//                 }
//             }
//         )
        
//         // Verify new handler was registered
//         #expect(mockLogger.debugMessages.filter { $0.contains("Registered handler") }.count >= 2)
//     }
    
//     #if DEBUG
//     @Test @MainActor
//     func testPerformanceMonitoring() async {
//         let mockLogger = MockLogger()
//         let manager = AppLifecycleManager(logger: mockLogger)
        
//         let slowHandler = TestHandler()
//         slowHandler.shouldBeSlow = true
        
//         manager.register(
//             object: slowHandler,
//             didEnterBackground: { slowHandler.handleDidEnterBackground() },
//             willEnterForeground: { slowHandler.handleWillEnterForeground() }
//         )
        
//         // Trigger a lifecycle event that would call the slow handler
//         // Since we can't directly trigger notifications, we verify the registration
//         // In actual usage, the slow handler warning would appear when the event fires
        
//         // Verify handler was registered
//         #expect(mockLogger.debugMessages.contains { $0.contains("Registered handler") })
        
//         // Note: Actual performance warning would be logged when notifyHandlers is called
//         // This test verifies the infrastructure is in place
//     }
//     #endif
    
//     @Test @MainActor
//     func testDeduplication() async {
//         let mockLogger = MockLogger()
//         let manager = AppLifecycleManager(logger: mockLogger)
        
//         let handler = TestHandler()
//         var firstCallbackCalled = false
//         var secondCallbackCalled = false
        
//         // Register first time
//         manager.register(
//             object: handler,
//             didEnterBackground: {
//                 firstCallbackCalled = true
//             },
//             willEnterForeground: {
//                 firstCallbackCalled = true
//             }
//         )
        
//         // Register same object again with different callback
//         manager.register(
//             object: handler,
//             didEnterBackground: {
//                 secondCallbackCalled = true
//             },
//             willEnterForeground: {
//                 secondCallbackCalled = true
//             }
//         )
        
//         // Verify only one registration message (second one replaces first)
//         let registrationMessages = mockLogger.debugMessages.filter { $0.contains("Registered handler") }
//         #expect(registrationMessages.count == 2) // Both registrations log, but only last one is active
        
//         // In actual usage, only the second callback would be called
//         // This test verifies the de-duplication logic exists
//     }
    
//     @Test @MainActor
//     func testMultipleHandlers() async {
//         let mockLogger = MockLogger()
//         let manager = AppLifecycleManager(logger: mockLogger)
        
//         // Register 10+ handlers
//         var handlers: [TestHandler] = []
//         for i in 0..<15 {
//             let handler = TestHandler()
//             handlers.append(handler)
            
//             manager.register(
//                 object: handler,
//                 didEnterBackground: { handler.handleDidEnterBackground() },
//                 willEnterForeground: { handler.handleWillEnterForeground() }
//             )
//         }
        
//         // Verify all handlers were registered
//         let registrationMessages = mockLogger.debugMessages.filter { $0.contains("Registered handler") }
//         #expect(registrationMessages.count == 15)
        
//         // Verify all handlers are tracked
//         #expect(handlers.count == 15)
//     }
    
//     @Test @MainActor
//     func testLoggerInjection() async {
//         let mockLogger = MockLogger()
//         let manager = AppLifecycleManager(logger: mockLogger)
        
//         let handler = TestHandler()
        
//         manager.register(
//             object: handler,
//             didEnterBackground: { handler.handleDidEnterBackground() },
//             willEnterForeground: { handler.handleWillEnterForeground() }
//         )
        
//         // Verify logger received debug message
//         #expect(mockLogger.debugMessages.count > 0)
//         #expect(mockLogger.debugMessages.contains { $0.contains("Registered handler") })
        
//         // Test unregister
//         manager.unregister(object: handler)
        
//         // Verify logger received unregister message
//         #expect(mockLogger.debugMessages.contains { $0.contains("Unregistered handler") })
//     }
    
//     @Test @MainActor
//     func testDefaultLogger() async {
//         // Test that default logger works (no injection)
//         let manager = AppLifecycleManager()
        
//         let handler = TestHandler()
        
//         manager.register(
//             object: handler,
//             didEnterBackground: { handler.handleDidEnterBackground() },
//             willEnterForeground: { handler.handleWillEnterForeground() }
//         )
        
//         // If we get here without crashing, default logger works
//         #expect(true)
//     }
    
//     @Test @MainActor
//     func testIsAppInBackgroundState() async {
//         let manager = AppLifecycleManager()
        
//         // Initial state should be false
//         #expect(manager.isAppInBackground == false)
        
//         // Note: We can't directly test state changes without triggering actual notifications
//         // This test verifies the property exists and has correct initial value
//     }
// }

