import Combine
import Foundation
import core

public struct LocalSynthesisProgress: Sendable {
    public let journeyId: String
    public let completedCount: Int
    public let totalCount: Int
    public let currentStoryId: String?
    public let progressLabel: String

    public var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    public init(
        journeyId: String,
        completedCount: Int,
        totalCount: Int,
        currentStoryId: String? = nil,
        progressLabel: String
    ) {
        self.journeyId = journeyId
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.currentStoryId = currentStoryId
        self.progressLabel = progressLabel
    }
}

public struct LocalSynthesisAnalyticsEvent: Sendable {
    public let eventName: String
    public let properties: [String: AnySendableValue]

    public init(eventName: String, properties: [String: AnySendableValue]) {
        self.eventName = eventName
        self.properties = properties
    }
}

public enum AnySendableValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public var postHogProperty: Any {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        }
    }
}

@MainActor
public final class LocalJourneySynthesisCoordinator: ObservableObject {
    public typealias AnalyticsHandler = @Sendable (LocalSynthesisAnalyticsEvent) -> Void

    @Published public private(set) var synthesisProgressByJourneyId: [String: LocalSynthesisProgress] = [:]
    @Published public private(set) var synthesisErrorByJourneyId: [String: String] = [:]

    private let ttsService: LocalKokoroTTSService
    private let analyticsHandler: AnalyticsHandler?
    private let audioPathMapStorageKey = "journey_manifest.audio_path_map"
    private var backgroundTasks: [String: Task<Void, Never>] = [:]

    public init(
        ttsService: LocalKokoroTTSService = .shared,
        analyticsHandler: AnalyticsHandler? = nil
    ) {
        self.ttsService = ttsService
        self.analyticsHandler = analyticsHandler
    }

    public func prepareJourneyForStart(
        manifest: DownloadManifest,
        blockUntilFirstStoryReady: Bool = true
    ) async throws -> DownloadManifest {
        guard manifest.audioDeliveryMode == .localKokoro else {
            return manifest
        }
        synthesisErrorByJourneyId[manifest.journeyId] = nil

        try LocalKokoroCacheKey.invalidateStaleArtifacts(
            journeyId: manifest.journeyId,
            manifestVersion: manifest.version
        )

        let orderedStories = manifest.stories.sorted {
            ($0.chapterIdx ?? Int.max) < ($1.chapterIdx ?? Int.max)
        }
        guard let firstStory = orderedStories.first else {
            throw LocalKokoroError.scriptEmpty
        }

        if hasPlayableLocalAudio(storyId: firstStory.storyId) {
            updateProgress(
                journeyId: manifest.journeyId,
                completedCount: 1,
                totalCount: orderedStories.count,
                currentStoryId: firstStory.storyId,
                progressLabel: "First stop ready"
            )
            startBackgroundSynthesisIfNeeded(
                manifest: manifest,
                orderedStories: orderedStories,
                startingIndex: 1
            )
            return manifest
        }

        let gateResult = LocalKokoroDeviceGate.evaluate()
        if !gateResult.isSupported {
            if shouldBypassDeviceGateFailure(gateResult.failureReason) {
                emitAnalytics(
                    eventName: "journey:local_device_gate_bypassed",
                    properties: [
                        "journey_id": .string(manifest.journeyId),
                        "reason": .string(gateResult.failureReason?.rawValue ?? "unknown"),
                        "event_version": .string("1.0"),
                    ]
                )
            } else {
                emitAnalytics(
                    eventName: "journey:local_device_gate_failed",
                    properties: [
                        "journey_id": .string(manifest.journeyId),
                        "reason": .string(gateResult.failureReason?.rawValue ?? "unknown"),
                        "event_version": .string("1.0"),
                    ]
                )
                throw LocalKokoroError.deviceNotSupported(
                    gateResult.failureReason?.rawValue ?? "unsupported"
                )
            }
        }

        updateProgress(
            journeyId: manifest.journeyId,
            completedCount: 0,
            totalCount: orderedStories.count,
            currentStoryId: firstStory.storyId,
            progressLabel: "Preparing Audio..."
        )

        if blockUntilFirstStoryReady {
            try await synthesizeStory(
                manifest: manifest,
                story: firstStory,
                storyIndex: 0
            )
            updateProgress(
                journeyId: manifest.journeyId,
                completedCount: 1,
                totalCount: orderedStories.count,
                currentStoryId: firstStory.storyId,
                progressLabel: "First stop ready"
            )
        }

        startBackgroundSynthesisIfNeeded(
            manifest: manifest,
            orderedStories: orderedStories,
            startingIndex: blockUntilFirstStoryReady ? 1 : 0
        )

        return manifest
    }

    public func prepareAllStories(manifest: DownloadManifest) async throws {
        guard manifest.audioDeliveryMode == .localKokoro else { return }
        synthesisErrorByJourneyId[manifest.journeyId] = nil

        let orderedStories = manifest.stories.sorted {
            ($0.chapterIdx ?? Int.max) < ($1.chapterIdx ?? Int.max)
        }
        for (index, story) in orderedStories.enumerated() {
            updateProgress(
                journeyId: manifest.journeyId,
                completedCount: index,
                totalCount: orderedStories.count,
                currentStoryId: story.storyId,
                progressLabel: "Preparing tour \(index + 1)/\(orderedStories.count)"
            )
            try await synthesizeStory(
                manifest: manifest,
                story: story,
                storyIndex: index
            )
            updateProgress(
                journeyId: manifest.journeyId,
                completedCount: index + 1,
                totalCount: orderedStories.count,
                currentStoryId: story.storyId,
                progressLabel: "Prepared \(index + 1)/\(orderedStories.count)"
            )
        }
        markJourneyPrepared(manifest.journeyId)
    }

    public func localAudioPath(forStoryId storyId: String) -> String? {
        loadAudioPathMap()[storyId]
    }

    public func awaitStoryAudioPath(
        journeyId: String,
        storyId: String,
        timeoutSeconds: TimeInterval = 120
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let localPath = localAudioPath(forStoryId: storyId) {
                return localPath
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if synthesisErrorByJourneyId[journeyId] != nil {
                return nil
            }
        }
        return localAudioPath(forStoryId: storyId)
    }

    public func cancelBackgroundSynthesis(journeyId: String) {
        backgroundTasks[journeyId]?.cancel()
        backgroundTasks[journeyId] = nil
    }

    private func shouldBypassDeviceGateFailure(
        _ failureReason: LocalKokoroDeviceGateFailureReason?
    ) -> Bool {
        failureReason == .lowMemory
    }

    private func startBackgroundSynthesisIfNeeded(
        manifest: DownloadManifest,
        orderedStories: [DownloadManifestStory],
        startingIndex: Int
    ) {
        guard startingIndex < orderedStories.count else {
            markJourneyPrepared(manifest.journeyId)
            return
        }

        backgroundTasks[manifest.journeyId]?.cancel()
        backgroundTasks[manifest.journeyId] = Task {
            var completedCount = startingIndex
            for index in startingIndex..<orderedStories.count {
                if Task.isCancelled { return }
                let story = orderedStories[index]
                await MainActor.run {
                    updateProgress(
                        journeyId: manifest.journeyId,
                        completedCount: completedCount,
                        totalCount: orderedStories.count,
                        currentStoryId: story.storyId,
                        progressLabel: "Preparing stop \(index + 1)/\(orderedStories.count)"
                    )
                }
                do {
                    try await synthesizeStory(
                        manifest: manifest,
                        story: story,
                        storyIndex: index
                    )
                    completedCount += 1
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        return
                    }
                    await MainActor.run {
                        synthesisErrorByJourneyId[manifest.journeyId] = error.localizedDescription
                    }
                    return
                }
            }
            await MainActor.run {
                markJourneyPrepared(manifest.journeyId)
                updateProgress(
                    journeyId: manifest.journeyId,
                    completedCount: orderedStories.count,
                    totalCount: orderedStories.count,
                    currentStoryId: nil,
                    progressLabel: "Tour prepared"
                )
            }
        }
    }

    private func synthesizeStory(
        manifest: DownloadManifest,
        story: DownloadManifestStory,
        storyIndex: Int
    ) async throws {
        let script = story.script?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if script.isEmpty {
            throw LocalKokoroError.scriptEmpty
        }

        emitAnalytics(
            eventName: "journey:local_synthesis_started",
            properties: [
                "journey_id": .string(manifest.journeyId),
                "story_id": .string(story.storyId),
                "story_index": .int(storyIndex),
                "script_char_count": .int(script.count),
                "event_version": .string("1.0"),
            ]
        )

        let result: LocalSynthesisResult
        do {
            result = try await ttsService.synthesizeScript(
                script: script,
                journeyId: manifest.journeyId,
                manifestVersion: manifest.version,
                storyId: story.storyId
            )
        } catch {
            if error is CancellationError {
                throw error
            }
            emitAnalytics(
                eventName: "journey:local_synthesis_failed",
                properties: [
                    "journey_id": .string(manifest.journeyId),
                    "story_id": .string(story.storyId),
                    "story_index": .int(storyIndex),
                    "error_type": .string(String(describing: type(of: error))),
                    "is_token_limit": .bool(
                        (error as? LocalizedError)?.errorDescription?
                            .localizedCaseInsensitiveContains("token") ?? false
                    ),
                    "event_version": .string("1.0"),
                ]
            )
            throw error
        }

        var audioPathMap = loadAudioPathMap()
        audioPathMap[story.storyId] = result.outputURL.path
        saveAudioPathMap(audioPathMap)

        emitAnalytics(
            eventName: "journey:local_synthesis_completed",
            properties: [
                "journey_id": .string(manifest.journeyId),
                "story_id": .string(story.storyId),
                "story_index": .int(storyIndex),
                "script_char_count": .int(script.count),
                "chunk_count": .int(result.stats.chunkCount),
                "fallback_sentence_count": .int(result.stats.sentenceFallbackCount),
                "fallback_word_count": .int(result.stats.wordFallbackCount),
                "wall_seconds": .double(result.stats.wallSeconds),
                "audio_duration_seconds": .double(result.audioDurationSeconds),
                "mlx_peak_mb": .double(result.stats.mlxPeakMegabytes),
                "voice": .string(KokoroSynthesisConfig.defaultVoiceName),
                "g2p": .string(KokoroSynthesisConfig.defaultG2PEngine.rawValue),
                "cache_status": .string(result.cacheStatus),
                "event_version": .string("1.0"),
            ]
        )
    }

    private func updateProgress(
        journeyId: String,
        completedCount: Int,
        totalCount: Int,
        currentStoryId: String?,
        progressLabel: String
    ) {
        synthesisProgressByJourneyId[journeyId] = LocalSynthesisProgress(
            journeyId: journeyId,
            completedCount: completedCount,
            totalCount: totalCount,
            currentStoryId: currentStoryId,
            progressLabel: progressLabel
        )
    }

    private func markJourneyPrepared(_ journeyId: String) {
        var downloadedJourneyIds = Set(
            Storage.loadFromUserDefaults(
                forKey: "journey_manifest.downloaded_journeys",
                as: [String].self
            ) ?? []
        )
        downloadedJourneyIds.insert(journeyId)
        Storage.saveToUserDefaults(
            Array(downloadedJourneyIds).sorted(),
            forKey: "journey_manifest.downloaded_journeys"
        )
    }

    private func loadAudioPathMap() -> [String: String] {
        Storage.loadFromUserDefaults(forKey: audioPathMapStorageKey, as: [String: String].self) ?? [:]
    }

    private func saveAudioPathMap(_ map: [String: String]) {
        Storage.saveToUserDefaults(map, forKey: audioPathMapStorageKey)
    }

    private func hasPlayableLocalAudio(storyId: String) -> Bool {
        guard let localAudioPath = localAudioPath(forStoryId: storyId) else {
            return false
        }
        return FileManager.default.fileExists(atPath: localAudioPath)
    }

    private func emitAnalytics(eventName: String, properties: [String: AnySendableValue]) {
        analyticsHandler?(
            LocalSynthesisAnalyticsEvent(
                eventName: eventName,
                properties: properties
            )
        )
    }
}
