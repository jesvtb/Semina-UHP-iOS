import SwiftUI
import core

struct ActiveJourneyView: View {
    @ObservedObject var activeJourneyManager: ActiveJourneyManager
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            topBar

            if let journey = activeJourneyManager.getCurrentActiveJourney() {
                progressSection(journey: journey)

                Rectangle()
                    .fill(Color("onBkgTextColor30").opacity(0.08))
                    .frame(height: 180)
                    .overlay(
                        Text("Map preview for active route")
                            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                            .foregroundColor(Color.textSecondary)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.current.spaceXs))

                if let currentStory = currentStory(from: journey) {
                    ActiveStoryView(
                        story: currentStory,
                        audioPlayerManager: audioPlayerManager,
                        distanceLabel: "Next stop"
                    )
                }

                controlBar(journey: journey)
            } else {
                emptyState
            }

            Spacer()
        }
        .padding(Spacing.current.spaceS)
        .background(Color("AppBkgColor").ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            Button("Close") {
                onDismiss()
            }
            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))

            Spacer()
            Text("Journey Active")
                .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article0.baseSize))
        }
    }

    private func progressSection(journey: core.ActiveJourney) -> some View {
        let totalStops = max(journey.stories.count, 1)
        let completedStops = journey.completedStopIndices.count
        let progress = Double(completedStops) / Double(totalStops)

        return VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
            Text("Stop \(min(journey.currentStopIndex + 1, totalStops)) of \(totalStops)")
                .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article0.baseSize))
            ProgressView(value: progress)
                .tint(Color("AccentColor"))
        }
    }

    private func controlBar(journey: core.ActiveJourney) -> some View {
        HStack(spacing: Spacing.current.spaceS) {
            if journey.status == .paused {
                Button("Resume") {
                    activeJourneyManager.resumeJourney()
                }
            } else {
                Button("Pause") {
                    activeJourneyManager.pauseJourney()
                }
            }

            Button("Play Next") {
                activeJourneyManager.advanceToNextStop()
            }

            Button("Stop") {
                activeJourneyManager.completeJourney()
                onDismiss()
            }
        }
        .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
        .foregroundColor(Color("AccentColor"))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            Text("No active journey")
                .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article1.baseSize))
            Text("Start a journey from the cover screen to begin playback.")
                .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                .foregroundColor(Color.textSecondary)
        }
    }

    private func currentStory(from journey: core.ActiveJourney) -> core.ActiveStory? {
        guard journey.currentStopIndex >= 0 else { return nil }
        guard journey.currentStopIndex < journey.stories.count else { return nil }
        return journey.stories[journey.currentStopIndex]
    }
}
