import SwiftUI
import MapKit
import core

// MARK: - Journey Action Buttons
/// Download, Start, and Get-to-Start buttons for a journey.
struct JourneyActionButtons: View {
    let journey: Journey
    @StateObject private var journeyManifestDownloader: JourneyManifestDownloader
    @StateObject private var activeJourneyManager = ActiveJourneyManager()

    @State private var isShowingActiveJourney = false
    @State private var errorMessage: String?

    init(journey: Journey) {
        self.journey = journey
        _journeyManifestDownloader = StateObject(
            wrappedValue: JourneyManifestDownloader(
                baseURL: Self.resolveGatewayBaseURL(),
                accessTokenProvider: {
                    try await supabase.auth.session.accessToken
                }
            )
        )
    }

    var body: some View {
        VStack(spacing: Spacing.current.spaceXs) {
            // Primary actions
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
                .disabled(journey.journeyId == nil || journeyManifestDownloader.journeyDownloadStateById[journey.journeyId ?? ""] == .downloading)

                Button {
                    handleStartTap()
                } label: {
                    Text("Start")
                        .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article0.baseSize))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.current.spaceXs)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.current.space3xs)
                                .fill(Color("AccentColor"))
                        )
                }
                .disabled(journey.journeyId == nil)
            }

            // Secondary action — open device map to navigate to first place
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fullScreenCover(isPresented: $isShowingActiveJourney) {
            ActiveJourneyView(activeJourneyManager: activeJourneyManager) {
                isShowingActiveJourney = false
            }
        }
    }

    /// Opens the device's default map app with walking directions to the first place.
    private func openDirectionsToFirstPlace() {
        guard let coordinate = journey.firstPlaceCoordinate else { return }
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        destination.name = journey.firstPlaceName ?? "Start"
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private var downloadButtonLabel: String {
        guard let journeyId = journey.journeyId else { return "Download" }

        let state = journeyManifestDownloader.journeyDownloadStateById[journeyId] ?? .idle
        switch state {
        case .downloading:
            let progress = journeyManifestDownloader.journeyProgressById[journeyId] ?? 0
            return "Downloading \(Int(progress * 100))%"
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Retry Download"
        case .idle:
            return journeyManifestDownloader.isJourneyDownloaded(journeyId: journeyId) ? "Downloaded" : "Download"
        }
    }

    private func handleDownloadTap() {
        guard let journeyId = journey.journeyId else {
            errorMessage = "This journey does not expose a journey_id yet."
            return
        }
        errorMessage = nil
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
                let manifest: DownloadManifest
                if let localManifest = try journeyManifestDownloader.loadManifestFromDisk(journeyId: journeyId) {
                    manifest = localManifest
                } else {
                    manifest = try await journeyManifestDownloader.fetchDownloadManifest(journeyId)
                }
                try activeJourneyManager.startJourney(from: manifest)
                isShowingActiveJourney = true
            } catch {
                errorMessage = "Start failed: \(error.localizedDescription)"
            }
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
