import SwiftUI
import core

struct ActivePlayerView: View {
    let story: core.ActiveStory
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    let journeyTitle: String
    let stopName: String
    let stopDescription: String?
    let currentStopIndex: Int
    let totalStops: Int
    let completedStopIndices: Set<Int>
    let onClose: () -> Void

    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var progress: Double = 0
    @State private var playbackErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            segmentedStopBar

            HStack(alignment: .center, spacing: Spacing.current.spaceXs) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: TypographyScale.article0.baseSize))
                    .foregroundColor(Color.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(Color("onBkgTextColor30").opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    Text(journeyTitle)
                        .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Text("Stop \(min(currentStopIndex + 1, totalStops)) of \(totalStops)")
                        .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: TypographyScale.articleMinus1.baseSize, weight: .light))
                        .foregroundColor(Color.textSecondary.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                Text("Now walking")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color("AccentColor"))
                    .textCase(.uppercase)
                    .tracking(1.2)

                DisplayText(
                    stopName,
                    scale: .article2,
                    color: Color.textPrimary,
                    lineHeightMultiple: 1.3,
                    fontFamily: FontFamily.serifDisplay
                )

                if let stopDescription = normalizedStopDescription {
                    Text(stopDescription)
                        .font(.custom(FontFamily.serifRegular, size: TypographyScale.articleMinus1.baseSize))
                        .foregroundColor(Color.textSecondary.opacity(0.9))
                        .lineLimit(3)
                }
            }

            Spacer(minLength: Spacing.current.spaceM)

            HStack(spacing: Spacing.current.spaceM) {
                seekButton(systemName: "backward.end.fill", seconds: -10)

                playPauseButton

                seekButton(systemName: "forward.end.fill", seconds: 10)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Text(formatSeconds(currentTime))
                Spacer()
                Text(formatSeconds(duration))
            }
            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
            .foregroundColor(Color.textSecondary)

            if let playbackErrorMessage {
                Text(playbackErrorMessage)
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // .padding(.horizontal, Spacing.current.spaceS)
        .padding(.vertical, Spacing.current.spaceXs)
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

    private var normalizedStopDescription: String? {
        let trimmedDescription = stopDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedDescription.isEmpty {
            return nil
        }
        return trimmedDescription
    }

    private var segmentedStopBar: some View {
        HStack(spacing: Spacing.current.space3xs) {
            ForEach(0..<max(totalStops, 1), id: \.self) { stopIndex in
                stopSegment(stopIndex: stopIndex)
            }
        }
    }

    @ViewBuilder
    private func stopSegment(stopIndex: Int) -> some View {
        let segmentState = segmentState(for: stopIndex)
        let activePlaybackWidth = min(max(progress, 0), 1)
        let activeSynthesisWidth = min(max(progress + 0.35, 0), 1)

        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color("onBkgTextColor30").opacity(0.16))

                if segmentState == .completed {
                    Capsule()
                        .fill(Color("AccentColor").opacity(0.75))
                } else if segmentState == .active {
                    Capsule()
                        .fill(Color("onBkgTextColor30").opacity(0.45))
                        .frame(width: geometry.size.width * activeSynthesisWidth)

                    Capsule()
                        .fill(Color("AccentColor"))
                        .frame(width: geometry.size.width * activePlaybackWidth)
                } else if segmentState == .synthesizing {
                    Capsule()
                        .fill(Color("onBkgTextColor30").opacity(0.45))
                        .frame(width: geometry.size.width * 0.38)
                }
            }
        }
        .frame(height: segmentState == .active ? 5 : 3)
        .frame(maxWidth: .infinity)
        .overlay {
            if segmentState == .active {
                Capsule()
                    .stroke(Color("AccentColor").opacity(0.35), lineWidth: 0.8)
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            if audioPlayerManager.currentStoryId == story.id && audioPlayerManager.isPlaying {
                audioPlayerManager.pause()
            } else if audioPlayerManager.currentStoryId == story.id {
                audioPlayerManager.resume()
            } else {
                do {
                    try audioPlayerManager.playStory(story)
                    playbackErrorMessage = nil
                } catch {
                    playbackErrorMessage = error.localizedDescription
                }
            }
        } label: {
            Image(systemName: audioPlayerManager.currentStoryId == story.id && audioPlayerManager.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: TypographyScale.article1.baseSize, weight: .semibold))
                .foregroundColor(Color("AppBkgColor"))
                .frame(width: 60, height: 60)
                .background(Color("AccentColor"))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func seekButton(systemName: String, seconds: TimeInterval) -> some View {
        Button {
            let targetTime = if seconds < 0 {
                max(currentTime + seconds, 0)
            } else {
                min(currentTime + seconds, duration)
            }
            audioPlayerManager.seek(to: targetTime)
        } label: {
            VStack(spacing: Spacing.current.space3xs) {
                Image(systemName: systemName)
                    .font(.system(size: TypographyScale.article1.baseSize))
                    .foregroundColor(Color.textPrimary)
                Text("10s")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color.textSecondary.opacity(0.9))
            }
        }
        .buttonStyle(.plain)
    }

    private func segmentState(for stopIndex: Int) -> StopSegmentState {
        if completedStopIndices.contains(stopIndex) {
            return .completed
        }
        if stopIndex == currentStopIndex {
            return .active
        }
        if stopIndex == currentStopIndex + 1 {
            return .synthesizing
        }
        return .queued
    }
}

private enum StopSegmentState: Equatable {
    case completed
    case active
    case synthesizing
    case queued
}
