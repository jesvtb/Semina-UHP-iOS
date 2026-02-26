import AVFoundation
import Combine
import Foundation

public struct PlaybackProgress: Sendable {
    public let storyId: String
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let progress: Double

    public init(
        storyId: String,
        currentTime: TimeInterval,
        duration: TimeInterval,
        progress: Double
    ) {
        self.storyId = storyId
        self.currentTime = currentTime
        self.duration = duration
        self.progress = progress
    }
}

public final class AudioPlayerManager: NSObject, ObservableObject {
    @Published public private(set) var currentStoryId: String?
    @Published public private(set) var isPlaying: Bool = false

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var playbackProgressContinuation: AsyncStream<PlaybackProgress>.Continuation?

    public lazy var currentPlaybackProgress: AsyncStream<PlaybackProgress> = {
        AsyncStream { continuation in
            self.playbackProgressContinuation = continuation
        }
    }()

    deinit {
        if let player, let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
    }

    public func playStory(_ story: ActiveStory) throws {
        let playbackURL: URL
        if let localAudioPath = story.localAudioPath {
            playbackURL = URL(fileURLWithPath: localAudioPath)
        } else if let remoteURL = URL(string: story.audioUrl) {
            playbackURL = remoteURL
        } else {
            throw APIError(message: "Story has no valid audio URL.", code: nil)
        }

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)
        #endif

        cleanupPlayerObservers()
        let playerItem = AVPlayerItem(url: playbackURL)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        self.currentStoryId = story.id
        self.isPlaying = true
        startProgressObserver(player: player, storyId: story.id)
        player.play()
    }

    public func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
    }

    public func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    public func stop() {
        guard let player else { return }
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
    }

    public func seek(to position: TimeInterval) {
        guard let player else { return }
        let clampedPosition = max(position, 0)
        let target = CMTime(seconds: clampedPosition, preferredTimescale: 600)
        player.seek(to: target)
    }

    private func cleanupPlayerObservers() {
        if let player, let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }

    private func startProgressObserver(player: AVPlayer, storyId: String) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let playbackProgressContinuation = self.playbackProgressContinuation
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { currentTime in
            let durationSeconds = player.currentItem?.duration.seconds ?? 0
            let normalizedDuration = durationSeconds.isFinite && durationSeconds > 0
                ? durationSeconds : 0
            let currentSeconds = max(0, currentTime.seconds)
            let progress = normalizedDuration > 0
                ? min(currentSeconds / normalizedDuration, 1.0)
                : 0
            playbackProgressContinuation?.yield(
                PlaybackProgress(
                    storyId: storyId,
                    currentTime: currentSeconds,
                    duration: normalizedDuration,
                    progress: progress
                )
            )
        }
    }
}
