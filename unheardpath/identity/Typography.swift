import SwiftUI
import CoreGraphics

// MARK: - Typography System
// Matches brand typography from brand.scss
// 
// Brand Font Usage:
// - SourceSerif4Display-Semibold: Headlines (font-weight: 600)
// - SourceSerif4: Body text (Regular, Italic)
// - SourceSans3: UI elements (Regular, Semibold, ExtraLight)

// MARK: - Font Family Names
/// Centralized font family constants (PostScript names)
enum FontFamily {
    // Source Serif 4
    static let serifDisplay = "SourceSerif4Display-Semibold"
    static let serifRegular = "SourceSerif4-Regular"
    static let serifItalic = "SourceSerif4Subhead-It"
    
    // Source Sans 3
    static let sansRegular = "SourceSans3-Regular"
    static let sansSemibold = "SourceSans3-Semibold"
    static let sansExtraLight = "SourceSans3-ExtraLight"
}

// MARK: - Typography Scale
/// Typography scale matching brand.scss article scale
/// Uses a single base size with ratios for all sizes
/// Base size scales with Dynamic Type, all other sizes scale proportionally
enum TypographyScale {
    case articleMinus2  // 0.72rem - 0.88rem
    case articleMinus1  // 0.9rem - 1.1rem
    case article0       // 1.125rem - 1.375rem (body) - BASE
    case article1       // 1.4063rem - 1.7188rem
    case article2       // 1.7578rem - 2.1484rem
    case article3       // 2.1973rem - 2.6855rem (heading)
    case article4       // 2.7466rem - 3.3569rem
    case article5       // 3.4332rem - 4.1962rem
    case article6       // 4.2915rem - 5.2452rem (title/headline1)
    
    /// Ratio relative to article0 (base = 1.0)
    /// Calculated from brand.scss values: each size / article0 base (1.125rem)
    var ratio: CGFloat {
        switch self {
        case .articleMinus2: return 0.72 / 1.125      // 0.64
        case .articleMinus1: return 0.9 / 1.125        // 0.8
        case .article0: return 1.0                     // Base
        case .article1: return 1.4063 / 1.125           // 1.25
        case .article2: return 1.7578 / 1.125          // 1.5625
        case .article3: return 2.1973 / 1.125          // 1.9536
        case .article4: return 2.7466 / 1.125          // 2.442
        case .article5: return 3.4332 / 1.125          // 3.052
        case .article6: return 4.2915 / 1.125          // 3.814
        }
    }
    
    /// Base size for the scale at default text size (18pt = article0)
    /// This is the reference size - all other sizes are calculated from this using ratios
    static let defaultBaseSize: CGFloat = 17.0
    
    /// Calculates the scaled size based on a base size and this scale's ratio
    /// Usage: TypographyScale.article6.scaledSize(from: baseSize)
    func scaledSize(from baseSize: CGFloat) -> CGFloat {
        return baseSize * ratio
    }
    
    /// Legacy: Base size for the scale (used for non-scaled contexts)
    /// @deprecated: Use scaledSize(from:) with a Dynamic Type base size instead
    var baseSize: CGFloat {
        return Self.defaultBaseSize * ratio
    }
}

// MARK: - View Extensions for Typography
extension View {
    /// Applies title typography style with font and tight line spacing
    /// Usage: Text("Title").title()
    /// 
    /// Automatically scales with Dynamic Type using a single base size
    /// Note: If line spacing doesn't appear tight enough, SwiftUI's .lineSpacing()
    /// may not respect negative values. Try adjusting or use the UILabel-based approach.
    func title(size: TypographyScale = .article6) -> some View {
        self.modifier(TitleStyle(size: size))
    }
    
    /// Applies heading typography style
    /// Usage: Text("Heading").heading()
    /// 
    /// Automatically scales with Dynamic Type using a single base size
    func heading(size: TypographyScale = .article3) -> some View {
        self.modifier(HeadingStyle(size: size))
    }
    
    /// Applies body typography style
    /// Usage: Text("Body text").bodyText()
    /// 
    /// Automatically scales with Dynamic Type using a single base size
    func bodyText(size: TypographyScale = .article0) -> some View {
        self.modifier(BodyTextStyle(size: size))
    }
    
    /// Applies rubric typography style (small uppercase)
    /// Usage: Text("RUBRIC").rubric()
    /// 
    /// Automatically scales with Dynamic Type using a single base size
    func rubric(size: TypographyScale = .articleMinus1) -> some View {
        self.modifier(RubricStyle(size: size))
    }
    
    /// Applies rubric line style with tight line height and custom color
    /// Uses modern AttributedString approach for precise line-height control
    /// 
    /// Recommended usage (with AttributedString for precise control):
    /// ```swift
    /// Text(Typography.rubricLineAttributedString("text", color: .red))
    /// ```
    /// 
    /// Alternative usage (with modifier, approximate line height):
    /// ```swift
    /// Text("text").rubricLine(color: .red)
    /// ```
    func rubricLine(size: TypographyScale = .articleMinus1, color: Color = .primary) -> some View {
        self.modifier(RubricLineStyle(size: size, color: color))
    }
    
    /// Applies body paragraph style with readable line height for multiline text
    /// Uses modern AttributedString approach for precise line-height control
    /// Usage: Text("Long paragraph text...").bodyParagraph(color: .primary)
    /// Usage with center alignment: Text("Long paragraph text...").bodyParagraph(color: .primary, alignment: .center)
    func bodyParagraph(size: TypographyScale = .article0, color: Color = .primary, alignment: TextAlignment = .leading) -> some View {
        self.modifier(BodyParagraphStyle(size: size, color: color, alignment: alignment))
    }
   
}

// MARK: - Typography ViewModifiers
/// Note: If precise line-height control is needed in the future (e.g., exact 1em line-height),
/// consider using AttributedString with NSParagraphStyle for pixel-perfect control.
/// Example: Create AttributedString with paragraphStyle.lineHeightMultiple = 1.0

struct TitleStyle: ViewModifier {
    @ScaledMetric(relativeTo: .body) var baseSize: CGFloat = TypographyScale.defaultBaseSize
    
    let size: TypographyScale
    
    init(size: TypographyScale = .article6) {
        self.size = size
    }
    
    func body(content: Content) -> some View {
        let fontSize = size.scaledSize(from: baseSize)
        // Negative spacing to achieve 1em line-height
        // Most fonts default to ~1.2x, so subtract ~20% of font size
        let lineSpacing = -(fontSize * 0.2)
        
        return content
            .font(Font.custom(FontFamily.serifDisplay, size: fontSize))
            .lineSpacing(lineSpacing)
    }
}

struct HeadingStyle: ViewModifier {
    @ScaledMetric(relativeTo: .body) var baseSize: CGFloat = TypographyScale.defaultBaseSize
    
    let size: TypographyScale
    
    init(size: TypographyScale = .article3) {
        self.size = size
    }
    
    func body(content: Content) -> some View {
        let fontSize = size.scaledSize(from: baseSize)
        return content
            .font(Font.custom(FontFamily.serifRegular, size: fontSize))
    }
}

struct BodyTextStyle: ViewModifier {
    @ScaledMetric(relativeTo: .body) var baseSize: CGFloat = TypographyScale.defaultBaseSize
    
    let size: TypographyScale
    
    init(size: TypographyScale = .article0) {
        self.size = size
    }
    
    func body(content: Content) -> some View {
        let fontSize = size.scaledSize(from: baseSize)
        return content
            .font(Font.custom(FontFamily.sansRegular, size: fontSize))
    }
}

struct RubricStyle: ViewModifier {
    @ScaledMetric(relativeTo: .body) var baseSize: CGFloat = TypographyScale.defaultBaseSize
    
    let size: TypographyScale
    
    init(size: TypographyScale = .articleMinus1) {
        self.size = size
    }
    
    func body(content: Content) -> some View {
        let fontSize = size.scaledSize(from: baseSize)
        return content
            .font(Font.custom(FontFamily.sansRegular, size: fontSize))
            .textCase(.uppercase)
            .tracking(fontSize * 0.15) // letter-spacing: 0.15em
    }
}

struct RubricLineStyle: ViewModifier {
    @ScaledMetric(relativeTo: .body) var baseSize: CGFloat = TypographyScale.defaultBaseSize
    
    let size: TypographyScale
    let color: Color
    
    init(size: TypographyScale = .articleMinus1, color: Color = .primary) {
        self.size = size
        self.color = color
    }
    
    func body(content: Content) -> some View {
        let fontSize = size.scaledSize(from: baseSize)
        return content
            .font(Font.custom(FontFamily.sansRegular, size: fontSize))
            .foregroundColor(color)
            .textCase(.uppercase)
            .tracking(fontSize * 0.15)
    }
}

struct BodyParagraphStyle: ViewModifier {
    @ScaledMetric(relativeTo: .body) var baseSize: CGFloat = TypographyScale.defaultBaseSize
    
    let size: TypographyScale
    let color: Color
    let alignment: TextAlignment
    
    init(size: TypographyScale = .article0, color: Color = .primary, alignment: TextAlignment = .leading) {
        self.size = size
        self.color = color
        self.alignment = alignment
    }
    
    func body(content: Content) -> some View {
        let fontSize = size.scaledSize(from: baseSize)
        return content
            .font(Font.custom(FontFamily.sansRegular, size: fontSize))
            .foregroundColor(color)
            .tracking(fontSize * 0.01) // letter-spacing: 0.01em per brand.scss
            .lineSpacing(fontSize * 0.2) // Approximate 1.4em line height (1.4 * fontSize - fontSize = 0.4 * fontSize)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(alignment)
    }
    
    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct DisplayText: View {
    let text: String
    let scale: TypographyScale
    let color: Color
    let lineHeightMultiple: CGFloat
    let textAlignment: TextAlignment
    
    init(
        _ text: String,
        scale: TypographyScale = .article4,
        color: Color = .primary,
        lineHeightMultiple: CGFloat = 1.0,
        alignment: TextAlignment = .leading
    ) {
        self.text = text
        self.scale = scale
        self.color = color
        self.lineHeightMultiple = lineHeightMultiple
        self.textAlignment = alignment
    }
    
    var body: some View {
        DisplayTextLabel(
            text: text,
            scale: scale,
            color: color,
            lineHeightMultiple: lineHeightMultiple,
            textAlignment: textAlignment,
            preferredWidth: nil // Will be set from superview bounds
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - DisplayTextLabel (Internal UIViewRepresentable)
/// Internal UIViewRepresentable implementation for DisplayText
private struct DisplayTextLabel: UIViewRepresentable {
    @ScaledMetric(relativeTo: .body) var baseSize: CGFloat = TypographyScale.defaultBaseSize
    
    let text: String
    let scale: TypographyScale
    let color: Color
    let lineHeightMultiple: CGFloat
    let textAlignment: TextAlignment
    let preferredWidth: CGFloat?
    
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = nsTextAlignment
        label.lineBreakMode = .byWordWrapping // Ensure words don't break
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        // Set preferredMaxLayoutWidth immediately if we have it
        if let width = preferredWidth, width > 0 {
            label.preferredMaxLayoutWidth = width
        }
        
        updateLabel(label)
        
        return label
    }
    
    func updateUIView(_ uiView: UILabel, context: Context) {
        updateLabel(uiView)
        uiView.lineBreakMode = .byWordWrapping // Ensure words don't break
        
        // Update preferredMaxLayoutWidth when layout changes
        // Use superview bounds if preferredWidth not provided
        DispatchQueue.main.async {
            let availableWidth: CGFloat
            if let width = preferredWidth, width > 0 {
                availableWidth = width
            } else if let superview = uiView.superview {
                availableWidth = superview.bounds.width
            } else {
                return
            }
            
            if availableWidth > 0 && uiView.preferredMaxLayoutWidth != availableWidth {
                uiView.preferredMaxLayoutWidth = availableWidth
                uiView.setNeedsLayout()
                uiView.layoutIfNeeded()
            }
        }
    }
    
    private func updateLabel(_ label: UILabel) {
        let fontSize = scale.scaledSize(from: baseSize)
        
        // Create font
        let font = UIFont(name: FontFamily.serifDisplay, size: fontSize) ?? 
                   UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        label.font = font
        
        // Create paragraph style with tight line height (matching Headline1Label exactly)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        paragraphStyle.maximumLineHeight = fontSize
        paragraphStyle.minimumLineHeight = fontSize
        paragraphStyle.alignment = nsTextAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping // Ensure proper word wrapping
        
        // Apply attributed string
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: UIColor(color)
            ]
        )
        label.attributedText = attributedString
        label.textAlignment = nsTextAlignment
    }
    
    private var nsTextAlignment: NSTextAlignment {
        switch textAlignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}


