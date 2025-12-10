//
//  widgetControl.swift
//  widget
//
//  Created by Jessica Luo on 2025-12-10.
//

import AppIntents
import SwiftUI
import WidgetKit

// ControlWidget is only available on iOS 18.0+
@available(iOSApplicationExtension 18.0, *)
struct widgetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.semina.unheardpath.widget",
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Start Timer",
                isOn: value,
                action: StartTimerIntent()
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Timer")
        .description("A an example control that runs a timer.")
    }
}

// ControlValueProvider is part of ControlWidget, so it also requires iOS 18.0+
@available(iOSApplicationExtension 18.0, *)
extension widgetControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let isRunning = true // Check if the timer is running
            return isRunning
        }
    }
}

// StartTimerIntent is used by ControlWidget, so it also requires iOS 18.0+
// SetValueIntent protocol is available from iOS 16.0+, but ControlWidget requires iOS 18.0+
@available(iOSApplicationExtension 18.0, *)
struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"

    // Note: @Parameter property wrapper may generate availability warnings in Swift 6
    // These are warnings (not errors) and don't affect functionality.
    // The warnings occur because the property wrapper's synthesized accessors
    // may have different availability than the struct itself.
    // This is a known Swift 6 limitation with property wrappers in protocols.
    @Parameter(title: "Timer is running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // Start / stop the timer based on `value`.
        return .result()
    }
}
