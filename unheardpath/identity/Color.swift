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
    static let textPrimary = Color("onBkgTextColor20")
    
    /// Secondary text color (60% opacity on background)
    static let textSecondary = Color("onBkgTextColor30")
}

#Preview {
    VStack {
        Color("AccentColor")
        .frame(width: 100, height: 100)
    }
    .background(Color("AppBkgColor"))
}

#Preview("Text Color") {
    VStack {
        Spacer()
        
        
        DisplayText("An Unorthodox History of Istanbul", color: Color("onBkgTextColor20"))
        
        Text("Nullam purus ante tempor etiam sem cubilia erat phasellus odio maximus torquent quis lorem efficitur, ligula metus vitae ultrices sociosqu ex magnis nascetur pulvinar accumsan hac elementum. Litora inceptos cursus pharetra eget nunc felis tempor lacinia accumsan morbi tellus lacus, malesuada facilisi aenean hac donec tristique himenaeos velit adipiscing penatibus maecenas. Eros vestibulum blandit eget aliquet tellus convallis varius mi morbi sodales pharetra, nostra ligula nulla sollicitudin posuere montes urna tristique dolor ex.")
            .bodyText()
            .foregroundColor(Color("onBkgTextColor30"))
        Spacer()
    }
    .padding(.horizontal, Spacing.current.spaceS)
    .background(Color("AppBkgColor"))
}
