import SwiftUI

extension Color {
    /// Primary brand color from Assets.xcassets
    /// Uses "Color" colorset from Assets.xcassets
    static let appPrimary = Color("Color")
    
    /// Background color from Assets.xcassets
    /// Uses "BackgroundColor" colorset which supports light/dark mode
    static let appBackground = Color("BackgroundColor")
    
    // MARK: - Text Colors
    /// Primary text color (90% opacity on background)
    static let textPrimary = Color("onBkgTextColor90")
    
    /// Secondary text color (60% opacity on background)
    static let textSecondary = Color("onBkgTextColor60")
}

#Preview {
    VStack {
        Color("AccentColor")
        .frame(width: 100, height: 100)
    }
    .background(Color("AppBkgColor"))
}
