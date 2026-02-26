import SwiftUI
import core

struct ActivePlayerView: View {
    let story: core.ActiveStory
    @ObservedObject var audioPlayerManager: AudioPlayerManager

    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: Spacing.current.spaceXs) {
            Slider(
                value: Binding(
                    get: { progress },
                    set: { newValue in
                        progress = newValue
                        if duration > 0 {
                            audioPlayerManager.seek(to: duration * newValue)
                        }
                    }
                ),
                in: 0...1
            )

            HStack {
                Text(formatSeconds(currentTime))
                Spacer()
                Text(formatSeconds(duration))
            }
            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
            .foregroundColor(Color.textSecondary)

            HStack(spacing: Spacing.current.spaceS) {
                Button {
                    let target = max(currentTime - 15, 0)
                    audioPlayerManager.seek(to: target)
                } label: {
                    Image(systemName: "gobackward.15")
                }

                Button {
                    if audioPlayerManager.currentStoryId == story.id && audioPlayerManager.isPlaying {
                        audioPlayerManager.pause()
                    } else if audioPlayerManager.currentStoryId == story.id {
                        audioPlayerManager.resume()
                    } else {
                        try? audioPlayerManager.playStory(story)
                    }
                } label: {
                    Image(systemName: audioPlayerManager.currentStoryId == story.id && audioPlayerManager.isPlaying ? "pause.fill" : "play.fill")
                }

                Button {
                    let target = min(currentTime + 15, duration)
                    audioPlayerManager.seek(to: target)
                } label: {
                    Image(systemName: "goforward.15")
                }
            }
            .font(.system(size: TypographyScale.article1.baseSize))
            .foregroundColor(Color("AccentColor"))
        }
        .task {
            for await playbackProgress in audioPlayerManager.currentPlaybackProgress {
                guard playbackProgress.storyId == story.id else { continue }
                currentTime = playbackProgress.currentTime
                duration = playbackProgress.duration
                progress = playbackProgress.progress
            }
        }
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, Int(seconds))
        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
