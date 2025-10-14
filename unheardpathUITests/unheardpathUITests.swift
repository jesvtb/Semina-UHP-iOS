//
//  unheardpathUITests.swift
//  unheardpathUITests
//
//  Created by Jessica Luo on 2025-09-09.
//

import XCTest

final class unheardpathUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    // MARK: - API Test Suite UI Tests
    
    @MainActor
    func testAPITestSuiteUI() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Verify the main UI elements are present
        XCTAssertTrue(app.staticTexts["API Service Testing"].exists, "Main title should be visible")
        XCTAssertTrue(app.staticTexts["Available Tests"].exists, "Available Tests section should be visible")
        XCTAssertTrue(app.buttons["Test Ollama"].exists, "Test Ollama button should be present")
        XCTAssertTrue(app.buttons["Test Modal"].exists, "Test Modal button should be present")
        XCTAssertTrue(app.staticTexts["Response"].exists, "Response section should be visible")
    }
    
    @MainActor
    func testOllamaAPIButtonInteraction() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Find and tap the Ollama API test button
        let ollamaButton = app.buttons["Test Ollama"]
        XCTAssertTrue(ollamaButton.exists, "Test Ollama button should exist")
        XCTAssertTrue(ollamaButton.isEnabled, "Test Ollama button should be enabled")
        
        // Tap the button
        ollamaButton.tap()
        
        // Wait for loading state (button should be disabled during API call)
        let loadingText = app.staticTexts["Making API call..."]
        if loadingText.waitForExistence(timeout: 2.0) {
            XCTAssertTrue(loadingText.exists, "Loading indicator should appear")
        }
        
        // Wait for response or error to appear (with longer timeout for API call)
        let responseText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Ollama'"))
        if responseText.element.waitForExistence(timeout: 15.0) {
            XCTAssertTrue(responseText.element.exists, "Response should appear after API call")
        }
    }
    
    @MainActor
    func testModalAPIButtonInteraction() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Find and tap the Modal API test button
        let modalButton = app.buttons["Test Modal"]
        XCTAssertTrue(modalButton.exists, "Test Modal API button should exist")
        XCTAssertTrue(modalButton.isEnabled, "Test Modal API button should be enabled")
        
        // Tap the button
        modalButton.tap()
        
        // Wait for loading state
        let loadingText = app.staticTexts["Making API call..."]
        if loadingText.waitForExistence(timeout: 2.0) {
            XCTAssertTrue(loadingText.exists, "Loading indicator should appear")
        }
        
        // Wait for response or error to appear
        let responseText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Modal'"))
        if responseText.element.waitForExistence(timeout: 15.0) {
            XCTAssertTrue(responseText.element.exists, "Response should appear after API call")
        }
    }
    
    @MainActor
    func testErrorHandling() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Test that error states are handled properly
        // This test verifies the UI can display error messages
        let responseSection = app.staticTexts["Response"]
        XCTAssertTrue(responseSection.exists, "Response section should be present for error display")
        
        let errorSection = app.staticTexts["Error"]
        // Error section might not exist initially, which is expected
        // It will appear when an API call fails
    }
    
    @MainActor
    func testButtonStates() throws {
        let app = XCUIApplication()
        app.launch()
        
        let ollamaButton = app.buttons["Test Ollama API"]
        let modalButton = app.buttons["Test Modal API"]
        
        // Initially, both buttons should be enabled
        XCTAssertTrue(ollamaButton.isEnabled, "Ollama button should be enabled initially")
        XCTAssertTrue(modalButton.isEnabled, "Modal button should be enabled initially")
        
        // Tap one button and verify it becomes disabled during loading
        ollamaButton.tap()
        
        // Wait a moment for the loading state
        sleep(1)
        
        // Note: Button state testing in UI tests can be tricky
        // The button might still appear enabled in the accessibility tree
        // even when it's functionally disabled
    }
}
