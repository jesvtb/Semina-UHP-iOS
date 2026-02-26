import SwiftUI
import core

struct ActiveStoryView: View {
    let story: core.ActiveStory
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    let distanceLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            Text(story.title)
                .font(.custom(FontFamily.serifDisplay, size: TypographyScale.article2.baseSize))
                .foregroundColor(Color.textPrimary)

            HStack(spacing: Spacing.current.spaceS) {
                Label(distanceLabel, systemImage: "location")
                Label(story.status.rawValue, systemImage: "waveform")
            }
            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
            .foregroundColor(Color.textSecondary)

            if !story.materials.isEmpty {
                Text("Materials available: \(story.materials.count)")
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color("AccentColor"))
            }

            ActivePlayerView(story: story, audioPlayerManager: audioPlayerManager)
        }
        .padding(Spacing.current.spaceS)
        .background(
            RoundedRectangle(cornerRadius: Spacing.current.spaceXs)
                .fill(Color("onBkgTextColor30").opacity(0.06))
        )
    }
}
