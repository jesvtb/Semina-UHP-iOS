import SwiftUI
import core

struct ActiveStoryView: View {
    let story: core.ActiveStory
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    let journeyTitle: String
    let currentStopIndex: Int
    let totalStops: Int
    let completedStopIndices: Set<Int>
    let onClose: () -> Void

    var body: some View {
        ActivePlayerView(
            story: story,
            audioPlayerManager: audioPlayerManager,
            journeyTitle: journeyTitle,
            stopName: story.title,
            stopDescription: story.description,
            currentStopIndex: currentStopIndex,
            totalStops: totalStops,
            completedStopIndices: completedStopIndices,
            onClose: onClose
        )
    }
}
