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

#if DEBUG
@MainActor
private struct ActiveJourneyPreviewContainer: View {
    @StateObject private var activeJourneyManager = ActiveJourneyManager()
    @StateObject private var localSynthesisCoordinator = LocalJourneySynthesisCoordinator()
    @State private var hasSeededPreviewJourney = false

    private var previewManifest: DownloadManifest {
        DownloadManifest(
        journeyId: "journey-cover-preview-1",
        version: 1,
        audioDeliveryMode: .cloudPrerendered,
        stories: [
            DownloadManifestStory(
                storyId: "story-1",
                chapterIdx: 0,
                title: "The Two-Year Slope",
                placeName: "Ninen-zaka Slope",
                description: "Stone steps worn smooth by twelve centuries of pilgrims — they say a stumble here costs you two years of life.",
                script: nil,
                audioUrl: "https://example.com/story-1.m4a",
                placeId: "place-1",
                sizeBytes: 1200,
                materials: []
            ),
            DownloadManifestStory(
                storyId: "story-2",
                chapterIdx: 1,
                title: "Temple Bells at Dusk",
                placeName: "Yasaka Shrine",
                description: "At sunset, bronze bells carry across old wooden streets as lanterns begin to glow.",
                script: nil,
                audioUrl: "https://example.com/story-2.m4a",
                placeId: "place-2",
                sizeBytes: 900,
                materials: []
            ),
            DownloadManifestStory(
                storyId: "story-3",
                chapterIdx: 2,
                title: "Lantern Alley",
                placeName: "Gion",
                description: "A narrow lane of tea houses where paper lantern light softens every footstep.",
                script: nil,
                audioUrl: "https://example.com/story-3.m4a",
                placeId: "place-3",
                sizeBytes: 1000,
                materials: []
            )
        ]
    )
    }

    var body: some View {
        ActiveJourneyView(
            activeJourneyManager: activeJourneyManager,
            localSynthesisCoordinator: localSynthesisCoordinator
        ) {
            // Preview-only dismiss callback.
        }
        .task {
            if hasSeededPreviewJourney {
                return
            }
            hasSeededPreviewJourney = true
            do {
                try activeJourneyManager.startJourney(
                    from: previewManifest,
                    journeyTitle: "An Unhurried History of Higashiyama"
                )
            } catch {
                // Keep preview resilient if seeded session setup fails.
            }
        }
    }
}

#Preview("Active Journey Full Screen") {
    ActiveJourneyPreviewContainer()
}
#endif
