//
//  widgetLiveActivity.swift
//  widget
//
//  Created by Jessica Luo on 2025-12-10.
//

import ActivityKit
import WidgetKit
import SwiftUI

public struct widgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        public var emoji: String
        
        public init(emoji: String) {
            self.emoji = emoji
        }
    }

    // Fixed non-changing properties about your activity go here!
    public var name: String
    
    public init(name: String) {
        self.name = name
    }
}

struct widgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: widgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            // Enhanced UI for better visibility based on 2024 guides
            VStack(spacing: 8) {
                Text("Hello \(context.state.emoji)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(context.attributes.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Status")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.emoji)
                            .font(.title)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text("Hello \(context.state.emoji)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Live Activity Test")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Text(context.state.emoji)
                        .font(.title3)
                    Text(context.attributes.name)
                        .font(.caption)
                        .lineLimit(1)
                }
            } compactTrailing: {
                Text(context.state.emoji)
                    .font(.title3)
            } minimal: {
                Text(context.state.emoji)
                    .font(.title2)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.cyan)
        }
    }
}

extension widgetAttributes {
    fileprivate static var preview: widgetAttributes {
        widgetAttributes(name: "World")
    }
}

extension widgetAttributes.ContentState {
    fileprivate static var smiley: widgetAttributes.ContentState {
        widgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: widgetAttributes.ContentState {
         widgetAttributes.ContentState(emoji: "🤩")
     }
}

// MARK: - Preview
// Note: Preview may require main app to be built first
// If preview fails, try: Product > Build (⌘B) for main app, then preview again
#Preview("Lock Screen", as: .content, using: widgetAttributes.preview) {
   widgetLiveActivity()
} contentStates: {
    widgetAttributes.ContentState.smiley
    widgetAttributes.ContentState.starEyes
}
