import SwiftUI

/// A back button with a chevron icon and "Back" label.
/// Supports two visual styles: light (for use over images) and default (for use over the app background).
struct BackButton: View {
    let lightStyle: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: Spacing.current.space2xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: TypographyScale.article0.baseSize))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        lightStyle ? .white : Color("onBkgTextColor30"),
                        lightStyle ? .black.opacity(0.3) : Color("onBkgTextColor30").opacity(0.15)
                    )
                Text("Back")
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.article0.baseSize))
                    .foregroundColor(lightStyle ? .white : Color("onBkgTextColor30"))
            }
        }
        .buttonStyle(.plain)
    }
}
