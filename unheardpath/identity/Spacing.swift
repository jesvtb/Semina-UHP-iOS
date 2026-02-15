import SwiftUI
import UIKit

// MARK: - Spacing System
// Consistent spacing values for padding and margins
// Scales with iPhone screen size, matching brand.scss viewport-based scaling
// Each spacing token scales based on screen width using clamp-like behavior
// Optimized for iPhone devices (320pt - 428pt screen widths)

// MARK: - Spacing Scale Configuration
/// Single source of truth for spacing scale factors
/// Each entry defines: (min, base, vwFactor, max) in points
/// Matches brand.scss clamp() behavior: clamp(min, base + vwFactor * viewportWidth/100, max)
private let spacingScaleConfig: [String: (min: CGFloat, base: CGFloat, vwFactor: CGFloat, max: CGFloat)] = [
    // --space-3xs: clamp(0.25rem, 0.2107rem + 0.1959vw, 0.375rem)
    "space3xs": (4, 3.37, 0.1959, 6),
    
    // --space-2xs: clamp(0.5625rem, 0.5232rem + 0.1959vw, 0.6875rem)
    "space2xs": (9, 8.37, 0.1959, 11),
    
    // --space-xs: clamp(0.8125rem, 0.7339rem + 0.3918vw, 1.0625rem)
    "spaceXs": (13, 11.74, 0.3918, 17),
    
    // --space-s: clamp(1.125rem, 1.0464rem + 0.3918vw, 1.375rem)
    "spaceS": (18, 16.74, 0.3918, 22),
    
    // --space-m: clamp(1.6875rem, 1.5696rem + 0.5877vw, 2.0625rem)
    "spaceM": (27, 25.11, 0.5877, 33),
    
    // --space-l: clamp(2.25rem, 2.0928rem + 0.7835vw, 2.75rem)
    "spaceL": (36, 33.48, 0.7835, 44),
    
    // --space-xl: clamp(3.3125rem, 3.0571rem + 1.2733vw, 4.125rem)
    "spaceXl": (53, 48.91, 1.2733, 66),
    
    // --space-2xl: clamp(4.4375rem, 4.1035rem + 1.665vw, 5.5rem)
    "space2xl": (71, 65.65, 1.665, 88),
    
    // --space-3xl: clamp(6.6875rem, 6.1963rem + 2.4486vw, 8.25rem)
    "space3xl": (107, 99.14, 2.4486, 132)
]

// MARK: - Device Size Constants
/// iPhone screen width handling with simple caching
private struct DeviceSizeConstants {
    /// Cached screen width (iPhone screen widths are limited, so simple cache is sufficient)
    @MainActor private static var _cachedScreenWidth: CGFloat?
    
    /// Get current iPhone screen width in points (cached for performance)
    @MainActor
    static var currentScreenWidth: CGFloat {
        if let cached = _cachedScreenWidth {
            return cached
        }
        let width = UIScreen.main.bounds.width
        _cachedScreenWidth = width
        return width
    }
    
    /// Invalidate cache (call on orientation change)
    @MainActor
    static func invalidateCache() {
        _cachedScreenWidth = nil
    }
    
    /// Clamp a value between min and max based on viewport width
    /// Implements CSS clamp() behavior: clamp(min, base + vw * factor, max)
    static func clampValue(
        min: CGFloat,
        base: CGFloat,
        vwFactor: CGFloat,
        max: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let vwValue = (viewportWidth / 100) * vwFactor
        let preferred = base + vwValue
        return Swift.max(min, Swift.min(max, preferred))
    }
    
    /// Calculate spacing value for a given token and screen width
    static func spacingValue(for token: String, screenWidth: CGFloat) -> CGFloat {
        guard let config = spacingScaleConfig[token] else {
            return 0
        }
        return clampValue(
            min: config.min,
            base: config.base,
            vwFactor: config.vwFactor,
            max: config.max,
            viewportWidth: screenWidth
        )
    }
}

// MARK: - Spacing Values
/// Container for scaled spacing values
/// Automatically scales with iPhone screen size
/// Matches brand.scss spacing token naming
struct SpacingValues {
    let space3xs: CGFloat
    let space2xs: CGFloat
    let spaceXs: CGFloat
    let spaceS: CGFloat
    let spaceM: CGFloat
    let spaceL: CGFloat
    let spaceXl: CGFloat
    let space2xl: CGFloat
    let space3xl: CGFloat
    
    /// Creates scaled spacing values based on screen width
    /// Each token scales based on device size using clamp-like behavior
    /// Usage: SpacingValues.scaled(for: screenWidth)
    static func scaled(for screenWidth: CGFloat) -> SpacingValues {
        return SpacingValues(
            space3xs: DeviceSizeConstants.spacingValue(for: "space3xs", screenWidth: screenWidth),
            space2xs: DeviceSizeConstants.spacingValue(for: "space2xs", screenWidth: screenWidth),
            spaceXs: DeviceSizeConstants.spacingValue(for: "spaceXs", screenWidth: screenWidth),
            spaceS: DeviceSizeConstants.spacingValue(for: "spaceS", screenWidth: screenWidth),
            spaceM: DeviceSizeConstants.spacingValue(for: "spaceM", screenWidth: screenWidth),
            spaceL: DeviceSizeConstants.spacingValue(for: "spaceL", screenWidth: screenWidth),
            spaceXl: DeviceSizeConstants.spacingValue(for: "spaceXl", screenWidth: screenWidth),
            space2xl: DeviceSizeConstants.spacingValue(for: "space2xl", screenWidth: screenWidth),
            space3xl: DeviceSizeConstants.spacingValue(for: "space3xl", screenWidth: screenWidth)
        )
    }
    
    // MARK: Semantic Aliases
    
    /// Horizontal margin for text blocks (paragraphs, headings, DisplayText) in catalogue content.
    /// Keeps images and other full-bleed elements unaffected.
    var textSideMargin: CGFloat { spaceS }
    
    /// Cached spacing values (iPhone has limited screen sizes, so simple cache is sufficient)
    nonisolated(unsafe) private static var _cachedValues: SpacingValues?
    nonisolated(unsafe) private static var _cachedScreenWidth: CGFloat?
    
    /// Creates scaled spacing values for current iPhone (with caching)
    /// Usage: SpacingValues.scaled()
    @MainActor
    static func scaled() -> SpacingValues {
        let screenWidth = DeviceSizeConstants.currentScreenWidth
        
        // Return cached value if screen width hasn't changed
        if let cached = _cachedValues, let cachedWidth = _cachedScreenWidth, cachedWidth == screenWidth {
            return cached
        }
        
        // Calculate and cache
        let values = scaled(for: screenWidth)
        _cachedValues = values
        _cachedScreenWidth = screenWidth
        
        return values
    }
    
    /// Invalidate cache (call on orientation change)
    @MainActor
    static func invalidateCache() {
        _cachedValues = nil
        _cachedScreenWidth = nil
        DeviceSizeConstants.invalidateCache()
    }
}

// MARK: - Environment Key for Spacing
private struct SpacingKey: EnvironmentKey {
    nonisolated(unsafe) static var defaultValue: SpacingValues = SpacingValues(
        space3xs: 4,
        space2xs: 9,
        spaceXs: 13,
        spaceS: 18,
        spaceM: 27,
        spaceL: 36,
        spaceXl: 53,
        space2xl: 71,
        space3xl: 107
    )
}

extension EnvironmentValues {
    /// Access scaled spacing values from environment
    /// Usage: @Environment(\.spacing) var spacing
    var spacing: SpacingValues {
        get { self[SpacingKey.self] }
        set { self[SpacingKey.self] = newValue }
    }
}

// MARK: - Spacing ViewModifier
/// ViewModifier that calculates and injects scaled spacing values into environment
/// Uses current screen width to scale spacing based on device size
struct SpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.spacing, SpacingValues.scaled())
    }
}

// MARK: - View Extensions for Spacing
extension View {
    /// Applies scaled spacing modifier to the view
    /// This injects scaled spacing values into the environment
    /// Usage: ContentView().withScaledSpacing()
    func withScaledSpacing() -> some View {
        self.modifier(SpacingModifier())
    }
    
    /// Gets scaled spacing values from environment
    /// Usage: @Environment(\.spacing) var spacing
    /// Then use: spacing.spaceM, spacing.spaceL, etc.
}

// MARK: - Scaled Spacing Helper
/// Helper struct that provides scaled spacing values based on device screen size
/// Use this in views where you need spacing that scales with device size
/// 
/// Usage:
/// ```swift
/// struct MyView: View {
///     @ScaledSpacing private var spacing
///     
///     var body: some View {
///         VStack(spacing: spacing.spaceM) {
///             Text("Hello")
///                 .padding(spacing.spaceL)
///         }
///     }
/// }
/// ```
@propertyWrapper
struct ScaledSpacing: DynamicProperty {
    @MainActor
    var wrappedValue: SpacingValues {
        SpacingValues.scaled()
    }
    
    init() {}
}

// MARK: - Global Spacing Access
/// Global accessor for spacing values - no need to declare @Environment in every view
/// Automatically uses scaled spacing based on device size
/// 
/// Usage:
/// ```swift
/// struct MyView: View {
///     var body: some View {
///         VStack(spacing: Spacing.current.spaceM) {
///             Text("Hello")
///                 .padding(Spacing.current.spaceL)
///         }
///     }
/// }
/// ```
struct Spacing {
    /// Get current scaled spacing values
    /// Automatically scales based on device screen size
    @MainActor
    static var current: SpacingValues {
        SpacingValues.scaled()
    }
}

// MARK: - Tab Bar Height
let tabBarHeight: CGFloat = 49

// MARK: - Preview
#Preview("Spacing Scale") {
    SpacingPreview()
}

struct SpacingPreview: View {
    @ScaledSpacing private var spacing
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing.spaceM) {
                Text("Spacing Scale Preview")
                    .font(.title)
                    .padding(.bottom, spacing.spaceS)
                
                Text("Each square shows the spacing value as width and height")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, spacing.spaceXs)
                
                // Display all spacing tokens
                SpacingSquare(label: "3xs", size: spacing.space3xs)
                SpacingSquare(label: "2xs", size: spacing.space2xs)
                SpacingSquare(label: "xs", size: spacing.spaceXs)
                SpacingSquare(label: "s", size: spacing.spaceS)
                SpacingSquare(label: "m", size: spacing.spaceM)
                SpacingSquare(label: "l", size: spacing.spaceL)
                SpacingSquare(label: "xl", size: spacing.spaceXl)
                SpacingSquare(label: "2xl", size: spacing.space2xl)
                SpacingSquare(label: "3xl", size: spacing.space3xl)
            }
            .padding(spacing.spaceM)
        }
        .background(Color("AppBkgColor"))
    }
}

struct SpacingSquare: View {
    let label: String
    let size: CGFloat
    
    var body: some View {
        HStack(spacing: 16) {
            // Square with spacing value as width and height
            Rectangle()
                .fill(Color("AccentColor"))
                .frame(width: size, height: size)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("space\(label)")
                    .font(.headline)
                Text("\(Int(size.rounded()))pt")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

