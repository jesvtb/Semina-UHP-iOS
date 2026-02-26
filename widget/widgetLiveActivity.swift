import ActivityKit
import WidgetKit
import SwiftUI

@available(iOSApplicationExtension 16.1, *)
public struct widgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentStopIndex: Int
        public var totalStops: Int
        public var currentStoryTitle: String
        public var journeyStatus: String
        public var progressPercent: Double

        public init(
            currentStopIndex: Int,
            totalStops: Int,
            currentStoryTitle: String,
            journeyStatus: String,
            progressPercent: Double
        ) {
            self.currentStopIndex = currentStopIndex
            self.totalStops = totalStops
            self.currentStoryTitle = currentStoryTitle
            self.journeyStatus = journeyStatus
            self.progressPercent = progressPercent
        }
    }

    public var journeyName: String
    public var journeyId: String

    public init(journeyName: String, journeyId: String) {
        self.journeyName = journeyName
        self.journeyId = journeyId
    }
}

@available(iOSApplicationExtension 16.1, *)
struct widgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: widgetAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.journeyName)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.currentStoryTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                ProgressView(value: clampedProgress(context.state.progressPercent))
                    .tint(.cyan)
                Text("Stop \(context.state.currentStopIndex + 1)/\(max(context.state.totalStops, 1)) • \(prettyStatus(context.state.journeyStatus))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .activityBackgroundTint(Color.cyan.opacity(0.15))
            .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.journeyName)
                            .font(.caption)
                            .lineLimit(1)
                        Text("Stop \(context.state.currentStopIndex + 1)/\(max(context.state.totalStops, 1))")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(clampedProgress(context.state.progressPercent) * 100))%")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(context.state.currentStoryTitle)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(prettyStatus(context.state.journeyStatus))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "figure.walk")
            } compactTrailing: {
                Text("\(Int(clampedProgress(context.state.progressPercent) * 100))%")
                    .font(.caption2)
            } minimal: {
                Image(systemName: "figure.walk")
            }
            .keylineTint(Color.cyan)
        }
    }

    private func clampedProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func prettyStatus(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

@available(iOSApplicationExtension 16.1, *)
extension widgetAttributes {
    fileprivate static var preview: widgetAttributes {
        widgetAttributes(journeyName: "Istanbul Old Town", journeyId: "preview-journey")
    }
}

@available(iOSApplicationExtension 16.1, *)
extension widgetAttributes.ContentState {
    fileprivate static var inProgress: widgetAttributes.ContentState {
        widgetAttributes.ContentState(
            currentStopIndex: 1,
            totalStops: 5,
            currentStoryTitle: "The Walls of Constantinople",
            journeyStatus: "in_progress",
            progressPercent: 0.4
        )
    }
}
