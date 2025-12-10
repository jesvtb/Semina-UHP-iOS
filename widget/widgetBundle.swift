//
//  widgetBundle.swift
//  widget
//
//  Created by Jessica Luo on 2025-12-10.
//

import WidgetKit
import SwiftUI

@main
struct widgetBundle: WidgetBundle {
    var body: some Widget {
        widget()
        // Live Activities require iOS 16.1+, but deployment target is 16.6 so it's always available
        if #available(iOSApplicationExtension 16.1, *) {
            widgetLiveActivity()
        }
        // widgetControl is conditionally included - it's marked with @available(iOSApplicationExtension 18.0, *)
        // so it will only be available on iOS 18+ devices
        if #available(iOSApplicationExtension 18.0, *) {
            widgetControl()
        }
    }
}
