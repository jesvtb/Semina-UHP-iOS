import SwiftUI

extension Color {
    /// Primary brand color from Assets.xcassets
    /// Uses "Color" colorset from Assets.xcassets
    static let appPrimary = Color("Color")
    
    /// Background color from Assets.xcassets
    /// Uses "BackgroundColor" colorset which supports light/dark mode
    static let appBackground = Color("BackgroundColor")
}

#Preview {
    VStack {
        Color("AccentColor")
        .frame(width: 100, height: 100)
    }
    .background(Color("AppBkgColor"))
}
