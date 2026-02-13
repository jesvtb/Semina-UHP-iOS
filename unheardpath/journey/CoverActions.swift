import SwiftUI
import MapKit
import core

// MARK: - Journey Action Buttons
/// Download, Start, and Get-to-Start buttons for a journey.
struct JourneyActionButtons: View {
    let journey: Journey

    var body: some View {
        VStack(spacing: Spacing.current.spaceXs) {
            // Primary actions
            HStack(spacing: Spacing.current.spaceS) {
                Button {
                    // TODO: Download journey for offline use
                } label: {
                    Text("Download")
                        .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article0.baseSize))
                        .foregroundColor(Color("AccentColor"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.current.spaceXs)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.current.space3xs)
                                .stroke(Color("AccentColor"), lineWidth: 1)
                        )
                }

                Button {
                    // TODO: Start the journey
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
            }

            // Secondary action — open device map to navigate to first stop
            if journey.firstStopCoordinate != nil {
                Button {
                    openDirectionsToFirstStop()
                } label: {
                    Text("Get to Start")
                        .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                        .foregroundColor(Color("AccentColor"))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    /// Opens the device's default map app with walking directions to the first stop.
    private func openDirectionsToFirstStop() {
        guard let coordinate = journey.firstStopCoordinate else { return }
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        destination.name = journey.firstStopName ?? "Start"
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
