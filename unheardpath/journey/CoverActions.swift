import SwiftUI
import MapKit
import core
import localKokoro

// MARK: - Journey Action Buttons
/// Download, Start, and Get-to-Start buttons for a journey.
struct JourneyActionButtons: View {
    let journey: Journey
    @ObservedObject private var journeyManifestDownloader: JourneyManifestDownloader
    @ObservedObject private var activeJourneyManager: ActiveJourneyManager
    @ObservedObject private var localSynthesisCoordinator: LocalJourneySynthesisCoordinator

    @State private var isShowingActiveJourney = false
    @State private var isPreparingAudio = false
    @State private var preparationLabel = ""
    @State private var errorMessage: String?

    private static let sharedJourneyManifestDownloader = JourneyManifestDownloader(
        baseURL: resolveGatewayBaseURL(),
        accessTokenProvider: {
            try await supabase.auth.session.accessToken
        }
    )

    private static let sharedActiveJourneyManager = ActiveJourneyManager()

    private static let sharedLocalSynthesisCoordinator = LocalJourneySynthesisCoordinator(
        analyticsHandler: LocalKokoroAnalytics.makeAnalyticsHandler()
    )

    init(journey: Journey) {
        self.journey = journey
        _journeyManifestDownloader = ObservedObject(
            wrappedValue: Self.sharedJourneyManifestDownloader
        )
        _activeJourneyManager = ObservedObject(
            wrappedValue: Self.sharedActiveJourneyManager
        )
        _localSynthesisCoordinator = ObservedObject(
            wrappedValue: Self.sharedLocalSynthesisCoordinator
        )
    }

    var body: some View {
        VStack(spacing: Spacing.current.spaceXs) {
            HStack(spacing: Spacing.current.spaceS) {
                Button {
                    handleDownloadTap()
                } label: {
                    Text(downloadButtonLabel)
                        .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article0.baseSize))
                        .foregroundColor(Color("AccentColor"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.current.spaceXs)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.current.space3xs)
                                .stroke(Color("AccentColor"), lineWidth: 1)
                        )
                }
                .disabled(isDownloadDisabled)

                Button {
                    handleStartTap()
                } label: {
                    Text(startButtonLabel)
                        .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article0.baseSize))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.current.spaceXs)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.current.space3xs)
                                .fill(Color("AccentColor"))
                        )
                }
                .disabled(isStartDisabled)
            }

            if journey.firstPlaceCoordinate != nil {
                Button {
                    openDirectionsToFirstPlace()
                } label: {
                    Text("Get to Start")
                        .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                        .foregroundColor(Color("AccentColor"))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if isPreparingAudio, !preparationLabel.isEmpty {
                Text(preparationLabel)
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color("onBkgTextColor30"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fullScreenCover(isPresented: $isShowingActiveJourney) {
            ActiveJourneyView(
                activeJourneyManager: activeJourneyManager,
                localSynthesisCoordinator: localSynthesisCoordinator
            ) {
                isShowingActiveJourney = false
            }
        }
    }

    private var isDownloadDisabled: Bool {
        journey.journeyId == nil
            || journeyManifestDownloader.journeyDownloadStateById[journey.journeyId ?? ""] == .downloading
            || isPreparingAudio
    }

    private var isStartDisabled: Bool {
        journey.journeyId == nil || isPreparingAudio
    }

    private var startButtonLabel: String {
        isPreparingAudio ? "Preparing..." : "Start"
    }

    private func openDirectionsToFirstPlace() {
        guard let coordinate = journey.firstPlaceCoordinate else { return }
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        destination.name = journey.firstPlaceName ?? "Start"
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private var downloadButtonLabel: String {
        guard let journeyId = journey.journeyId else {
            return journey.isLocalKokoroDelivery ? "Prepare Tour" : "Download"
        }

        if journey.isLocalKokoroDelivery {
            if let progress = localSynthesisCoordinator.synthesisProgressByJourneyId[journeyId],
               progress.completedCount < progress.totalCount,
               progress.totalCount > 0 {
                return "Preparing \(Int(progress.progress * 100))%"
            }
        }

        let state = journeyManifestDownloader.journeyDownloadStateById[journeyId] ?? .idle
        switch state {
        case .downloading:
            let progress = journeyManifestDownloader.journeyProgressById[journeyId] ?? 0
            return "Downloading \(Int(progress * 100))%"
        case .downloaded:
            return journey.isLocalKokoroDelivery ? "Prepared" : "Downloaded"
        case .failed:
            return journey.isLocalKokoroDelivery ? "Retry Prepare" : "Retry Download"
        case .idle:
            if journeyManifestDownloader.isJourneyDownloaded(journeyId: journeyId) {
                return journey.isLocalKokoroDelivery ? "Prepared" : "Downloaded"
            }
            return journey.isLocalKokoroDelivery ? "Prepare Tour" : "Download"
        }
    }

    private func handleDownloadTap() {
        guard let journeyId = journey.journeyId else {
            errorMessage = "This journey does not expose a journey_id yet."
            return
        }
        errorMessage = nil

        if journey.isLocalKokoroDelivery {
            Task {
                await handleLocalPrepareTap(journeyId: journeyId, prepareAllStories: true)
            }
            return
        }

        Task {
            do {
                try await journeyManifestDownloader.downloadJourney(journeyId)
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleStartTap() {
        guard let journeyId = journey.journeyId else {
            errorMessage = "This journey does not expose a journey_id yet."
            return
        }
        errorMessage = nil
        Task {
            do {
                var manifest = try await loadManifest(journeyId: journeyId)
                if manifest.audioDeliveryMode == .localKokoro {
                    isPreparingAudio = true
                    preparationLabel = "Preparing Audio..."
                    manifest = try await localSynthesisCoordinator.prepareJourneyForStart(
                        manifest: manifest,
                        blockUntilFirstStoryReady: true
                    )
                    isPreparingAudio = false
                    preparationLabel = ""
                }
                try activeJourneyManager.startJourney(
                    from: manifest,
                    localAudioPathProvider: { storyId in
                        localSynthesisCoordinator.localAudioPath(forStoryId: storyId)
                            ?? JourneyManifestDownloader.resolveStoredLocalAudioPath(storyId: storyId)
                    }
                )
                isShowingActiveJourney = true
            } catch {
                isPreparingAudio = false
                preparationLabel = ""
                errorMessage = "Start failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleLocalPrepareTap(journeyId: String, prepareAllStories: Bool) async {
        do {
            isPreparingAudio = true
            preparationLabel = "Preparing tour audio..."
            let manifest = try await loadManifest(journeyId: journeyId)
            try saveManifestIfNeeded(manifest: manifest)
            if prepareAllStories {
                try await localSynthesisCoordinator.prepareAllStories(manifest: manifest)
            } else {
                _ = try await localSynthesisCoordinator.prepareJourneyForStart(manifest: manifest)
            }
            journeyManifestDownloader.markJourneyAsDownloaded(journeyId)
            isPreparingAudio = false
            preparationLabel = ""
        } catch {
            isPreparingAudio = false
            preparationLabel = ""
            errorMessage = "Prepare failed: \(error.localizedDescription)"
        }
    }

    private func loadManifest(journeyId: String) async throws -> DownloadManifest {
        if let localManifest = try journeyManifestDownloader.loadManifestFromDisk(journeyId: journeyId) {
            return localManifest
        }
        return try await journeyManifestDownloader.fetchDownloadManifest(journeyId)
    }

    private func saveManifestIfNeeded(manifest: DownloadManifest) throws {
        if try journeyManifestDownloader.loadManifestFromDisk(journeyId: manifest.journeyId) == nil {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let manifestData = try encoder.encode(manifest)
            _ = try Storage.saveToApplicationSupport(
                data: manifestData,
                filename: "manifest.json",
                subdirectory: "journeys/\(manifest.journeyId)"
            )
        }
    }

    private static func resolveGatewayBaseURL() -> String {
        guard let debugHost = Bundle.main.infoDictionary?["UHP_GATEWAY_HOST_DEBUG"] as? String,
              !debugHost.isEmpty,
              let releaseHost = Bundle.main.infoDictionary?["UHP_GATEWAY_HOST_RELEASE"] as? String,
              !releaseHost.isEmpty else {
            return "https://api.unheardpath.com"
        }
        #if DEBUG
        return "http://\(debugHost)"
        #else
        return "https://\(releaseHost)"
        #endif
    }
}
