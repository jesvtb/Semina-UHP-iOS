import SwiftUI
import core
import localKokoro

struct ActiveJourneyView: View {
    @ObservedObject var activeJourneyManager: ActiveJourneyManager
    @ObservedObject var localSynthesisCoordinator: LocalJourneySynthesisCoordinator
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @State private var lastAutoStartedStoryId: String?
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if let journey = activeJourneyManager.getCurrentActiveJourney() {
                if let currentStory = currentStory(from: journey) {
                    ActiveStoryView(
                        story: currentStory,
                        audioPlayerManager: audioPlayerManager,
                        journeyTitle: displayJourneyTitle(from: journey),
                        currentStopIndex: journey.currentStopIndex,
                        totalStops: max(journey.stories.count, 1),
                        completedStopIndices: journey.completedStopIndices,
                        synthesisProgress: localSynthesisCoordinator.synthesisProgressByJourneyId[journey.journeyId],
                        onClose: handleClose
                    )
                } else {
                    emptyState
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(Spacing.current.spaceS)
        .background(Color("AppBkgColor").ignoresSafeArea())
        .task(id: activeJourneyManager.getCurrentActiveJourney()?.id) {
            autoPlayCurrentStoryIfNeeded()
        }
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

    private func displayJourneyTitle(from journey: core.ActiveJourney) -> String {
        let normalizedJourneyTitle = journey.journeyTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedJourneyTitle.isEmpty {
            return normalizedJourneyTitle
        }
        return "Active Journey"
    }

    private func handleClose() {
        activeJourneyManager.pauseJourney()
        onDismiss()
    }

    private func autoPlayCurrentStoryIfNeeded() {
        guard let journey = activeJourneyManager.getCurrentActiveJourney(),
              let currentStory = currentStory(from: journey) else {
            return
        }

        if lastAutoStartedStoryId == currentStory.id {
            return
        }
        if audioPlayerManager.currentStoryId == currentStory.id {
            return
        }

        do {
            try audioPlayerManager.playStory(currentStory)
            lastAutoStartedStoryId = currentStory.id
        } catch {
            // Keep the view usable even if auto-play fails; manual play remains available.
            return
        }
    }
}


