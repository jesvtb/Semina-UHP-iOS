//
//  AppLaunchTests.swift
//  unheardpathUITests
//
//  Smoke Test Example - Tests basic app functionality
//  Objective: Quick verification that app doesn't crash and core features work
//  Run these first to catch major regressions before deeper testing
//

import XCTest

final class AppLaunchTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    /// Smoke Test Example: App Launch
    /// This is the simplest test - just verify the app launches without crashing
    /// Similar to "does the app start?" checks in CI/CD pipelines
    @MainActor
    func testAppLaunchesSuccessfully() throws {
        // Arrange & Act: Launch the app
        let app = XCUIApplication()
        app.launch()
        
        // Assert: App should be running (not crashed)
        XCTAssertTrue(
            app.state == .runningForeground,
            "App should launch and be running in foreground"
        )
    }
    
    /// Smoke Test Example: Main Screen Visibility
    /// Quick check that basic UI elements are present
    /// This catches major UI breakage before running full test suites
    @MainActor
    func testMainScreenIsVisible() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait a moment for UI to load
        sleep(1)
        
        // Assert: Some UI elements should be visible (app didn't show blank screen)
        let hasVisibleElements = app.staticTexts.count > 0 || 
                                app.buttons.count > 0 || 
                                app.otherElements.count > 0
        
        XCTAssertTrue(
            hasVisibleElements,
            "App should display some UI elements after launch (not blank screen)"
        )
    }
}


