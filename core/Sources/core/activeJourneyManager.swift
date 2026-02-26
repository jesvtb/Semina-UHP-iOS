import Combine
import Foundation

public struct JourneySessionCompletedEvent: Sendable {
    public let eventName: String
    public let journeyId: String
    public let stopCount: Int
    public let durationSeconds: Int
    public let isFullyDownloaded: Bool
    public let eventVersion: String

    public init(
        eventName: String = "journey:session_completed",
        journeyId: String,
        stopCount: Int,
        durationSeconds: Int,
        isFullyDownloaded: Bool,
        eventVersion: String = "1.0"
    ) {
        self.eventName = eventName
        self.journeyId = journeyId
        self.stopCount = stopCount
        self.durationSeconds = durationSeconds
        self.isFullyDownloaded = isFullyDownloaded
        self.eventVersion = eventVersion
    }
}

@MainActor
public final class ActiveJourneyManager: ObservableObject {
    @Published public private(set) var activeJourney: ActiveJourney?

    private let activeJourneyStorageKey = "active_journey.session"
    private let onJourneyCompleted: ((JourneySessionCompletedEvent) -> Void)?
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(
        onJourneyCompleted: ((JourneySessionCompletedEvent) -> Void)? = nil
    ) {
        self.onJourneyCompleted = onJourneyCompleted
        self.activeJourney = restoreActiveJourneyFromStorage()
    }

    public func startJourney(from manifest: DownloadManifest) throws {
        let newStories = manifest.stories.enumerated().map { index, story in
            ActiveStory(
                id: story.storyId,
                placeIndex: index,
                title: story.title,
                audioUrl: story.audioUrl,
                localAudioPath: nil,
                duration: nil,
                status: .notDownloaded,
                materials: story.materials
            )
        }

        if let currentJourney = activeJourney,
           currentJourney.status == .inProgress || currentJourney.status == .paused {
            var mergedJourney = currentJourney
            mergedJourney.stories.append(contentsOf: newStories)
            mergedJourney.status = .inProgress
            mergedJourney.currentStopIndex = min(
                mergedJourney.currentStopIndex,
                max(mergedJourney.stories.count - 1, 0)
            )
            if !mergedJourney.sourceJourneyIds.contains(manifest.journeyId) {
                mergedJourney = ActiveJourney(
                    id: mergedJourney.id,
                    journeyId: mergedJourney.journeyId,
                    journeyVersion: mergedJourney.journeyVersion,
                    sourceJourneyIds: mergedJourney.sourceJourneyIds + [manifest.journeyId],
                    startedAt: mergedJourney.startedAt,
                    status: mergedJourney.status,
                    currentStopIndex: mergedJourney.currentStopIndex,
                    completedStopIndices: mergedJourney.completedStopIndices,
                    stories: mergedJourney.stories,
                    liveActivityId: mergedJourney.liveActivityId
                )
            }
            activeJourney = mergedJourney
            persistActiveJourneyToStorage()
            return
        }

        activeJourney = ActiveJourney(
            journeyId: manifest.journeyId,
            journeyVersion: manifest.version,
            sourceJourneyIds: [manifest.journeyId],
            startedAt: Date(),
            status: .inProgress,
            currentStopIndex: 0,
            completedStopIndices: [],
            stories: newStories
        )
        persistActiveJourneyToStorage()
    }

    public func pauseJourney() {
        guard var currentJourney = activeJourney else { return }
        currentJourney.status = .paused
        activeJourney = currentJourney
        persistActiveJourneyToStorage()
    }

    public func resumeJourney() {
        guard var currentJourney = activeJourney else { return }
        currentJourney.status = .inProgress
        activeJourney = currentJourney
        persistActiveJourneyToStorage()
    }

    public func completeJourney(isFullyDownloaded: Bool = true) {
        guard let currentJourney = activeJourney else { return }

        let durationSeconds = max(
            0,
            Int(Date().timeIntervalSince(currentJourney.startedAt))
        )
        let completionEvent = JourneySessionCompletedEvent(
            journeyId: currentJourney.journeyId,
            stopCount: currentJourney.stories.count,
            durationSeconds: durationSeconds,
            isFullyDownloaded: isFullyDownloaded
        )
        onJourneyCompleted?(completionEvent)

        Storage.removeFromUserDefaults(forKey: activeJourneyStorageKey)
        activeJourney = nil
    }

    public func advanceToNextStop() {
        guard var currentJourney = activeJourney else { return }
        let currentIndex = currentJourney.currentStopIndex
        currentJourney.completedStopIndices.insert(currentIndex)

        let nextIndex = currentIndex + 1
        if nextIndex >= currentJourney.stories.count {
            activeJourney = currentJourney
            completeJourney()
            return
        }
        currentJourney.currentStopIndex = nextIndex
        currentJourney.status = .inProgress
        activeJourney = currentJourney
        persistActiveJourneyToStorage()
    }

    public func getCurrentActiveJourney() -> ActiveJourney? {
        activeJourney
    }

    private func persistActiveJourneyToStorage() {
        guard let currentJourney = activeJourney else {
            Storage.removeFromUserDefaults(forKey: activeJourneyStorageKey)
            return
        }
        do {
            let data = try jsonEncoder.encode(currentJourney)
            Storage.saveToUserDefaults(data, forKey: activeJourneyStorageKey)
        } catch {
            return
        }
    }

    private func restoreActiveJourneyFromStorage() -> ActiveJourney? {
        guard let data = Storage.loadFromUserDefaults(
            forKey: activeJourneyStorageKey,
            as: Data.self
        ) else {
            return nil
        }
        do {
            return try jsonDecoder.decode(ActiveJourney.self, from: data)
        } catch {
            return nil
        }
    }
}
