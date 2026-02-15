import SwiftUI
import CoreGraphics
import UIKit
import MarkdownUI
import core

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
    // SF Symbols Pro (IcoMoon-generated icon font)
    static let sfSymbolsExtra = "SF-Symbols-Pro"
    
    // Source Serif 4
    static let serifDisplay = "SourceSerif4Display-Semibold"
    static let serifRegular = "SourceSerif4-Regular"
    // static let serifItalic = "SourceSerif4Subhead-It"
    static let serifItalic = "SourceSerif4Display-BoldIt"
    // static let serifItalic = "SourceSerif4Display-SemiboldIt"
    
    // Source Sans 3
    static let sansRegular = "SourceSans3-Regular"
    static let sansSemibold = "SourceSans3-Semibold"
    static let sansExtraLight = "SourceSans3-ExtraLight"
}

// MARK: - Icon Font Helper
/// Renders an icon glyph from the SF-Symbols-Pro icon font (IcoMoon-generated)
/// 
/// Usage:
/// ```swift
/// IconFontImage(.arrowUp, size: 24, color: .blue)
/// IconFontImage(.heart, size: 20)
/// IconFontImage(unicode: "\u{E900}", size: 16) // Direct unicode
/// ```
struct IconFontImage: View {
    let unicode: String
    let size: CGFloat
    let color: Color
    
    /// Initialize with an IconGlyph enum case
    init(_ glyph: IconGlyph, size: CGFloat = 20, color: Color = .primary) {
        self.unicode = glyph.rawValue
        self.size = size
        self.color = color
    }
    
    /// Initialize with a raw unicode string for glyphs not yet in the enum
    init(unicode: String, size: CGFloat = 20, color: Color = .primary) {
        self.unicode = unicode
        self.size = size
        self.color = color
    }
    
    var body: some View {
        Text(unicode)
            .font(.custom(FontFamily.sfSymbolsExtra, size: size))
            .foregroundColor(color)
    }
}

// MARK: - Icon Glyph Catalog
/// Unicode code points for SF-Symbols-Pro icon font glyphs
/// 
/// The font contains ~6,300 icons in the Private Use Area (U+E900–U+101AF).
/// Add entries here as you identify glyphs you need.
/// 
/// To discover glyphs, use the "Icon Font Browser" preview in this file,
/// which renders a grid of all available glyphs with their unicode values.
/// 
/// Usage:
/// ```swift
/// IconFontImage(.placeholder)
/// ```
enum IconGlyph: String {
    // To discover more glyphs, use the "Icon Font Browser" previews at
    // the bottom of this file which render a grid with unicode values.
    // Format: case iconName = "\u{XXXX}"
    
    // MARK: Maps & Location
    /// Map pin on folded map (U+E99E)
    case mapPin = "\u{E99E}"
    /// Globe with location pin (U+F652)
    case globeLocation = "\u{F652}"
    /// Map with route and location pins (U+EEA8)
    case mapRoute = "\u{EEA8}"
    /// Google Maps icon (U+F309)
    case googleMaps = "\u{F309}"
    /// Braille / tactile map (U+02B3)
    case tactileMap = "\u{02B3}"
    
    // MARK: Buildings & Landmarks
    /// Taj Mahal / mosque with domes (U+0004)
    case tajMahal = "\u{0004}"
    /// Korean / East Asian temple gate (U+003D)
    case asianTemple = "\u{003D}"
    /// Russian Orthodox church with onion domes (U+F96E)
    case orthodoxChurch = "\u{F96E}"
    /// Domed mosque / cathedral (U+ECFC)
    case mosque = "\u{ECFC}"
    /// Gothic cathedral with spires (U+ECFD)
    case cathedral = "\u{ECFD}"
    
    // MARK: Religion & Culture
    /// Star of David (U+FF32)
    case starOfDavid = "\u{FF32}"
    /// Menorah (U+F522)
    case menorah = "\u{F522}"
    
    // MARK: Communication
    /// Chat bubbles (U+F743)
    case chatBubbles = "\u{F743}"
    /// Chat translation bubbles (U+EE3A)
    case chatTranslation = "\u{EE3A}"
    
    // MARK: Nature & Animals
    /// Pelican / crane bird (U+EEB7)
    case pelican = "\u{EEB7}"
    /// Crescent moon (U+F7D0)
    case crescentMoon = "\u{F7D0}"
    
    // MARK: Travel & Commerce
    /// Ticket / coupon (U+ECFA)
    case ticket = "\u{ECFA}"
    /// Currency exchange EUR/USD (U+EEFA)
    case currencyExchange = "\u{EEFA}"
    /// Closed sign (U+EDD9)
    case closedSign = "\u{EDD9}"
    
    // MARK: Medical & Health
    /// Stethoscope (U+F98E)
    case stethoscope = "\u{F98E}"
    
    // MARK: Brands
    /// Google Plus icon (U+10009)
    case googlePlus = "\u{10009}"
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
    static let defaultBaseSize: CGFloat = 18.0
    
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
            .font(Font.custom(FontFamily.sansSemibold, size: fontSize))
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
    let fontFamily: String
    let tracking: CGFloat
    
    init(
        _ text: String,
        scale: TypographyScale = .article4,
        color: Color = .primary,
        lineHeightMultiple: CGFloat = 1.0,
        alignment: TextAlignment = .leading,
        fontFamily: String = FontFamily.serifDisplay,
        tracking: CGFloat = 0
    ) {
        self.text = text
        self.scale = scale
        self.color = color
        self.lineHeightMultiple = lineHeightMultiple
        self.textAlignment = alignment
        self.fontFamily = fontFamily
        self.tracking = tracking
    }
    
    var body: some View {
        DisplayTextLabel(
            text: text,
            scale: scale,
            color: color,
            lineHeightMultiple: lineHeightMultiple,
            textAlignment: textAlignment,
            fontFamily: fontFamily,
            tracking: tracking,
            preferredWidth: nil // Will be set from superview bounds
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - InsetLabel
/// UILabel subclass that adds a top inset so italic-font ascenders
/// aren't clipped by the label's bounds.  The extra height is reported
/// through `intrinsicContentSize` so Auto Layout / SwiftUI size the
/// hosting view correctly.
private class InsetLabel: UILabel {
    var topInset: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }
    
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.height += topInset
        return size
    }
    
    override func drawText(in rect: CGRect) {
        // Shift the drawing rect down by topInset so the
        // original text position is preserved but extra
        // blank space exists above the first line.
        super.drawText(in: CGRect(
            x: rect.origin.x,
            y: rect.origin.y + topInset,
            width: rect.width,
            height: rect.height - topInset
        ))
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
    let fontFamily: String
    let tracking: CGFloat
    let preferredWidth: CGFloat?
    
    func makeUIView(context: Context) -> InsetLabel {
        let label = InsetLabel()
        label.numberOfLines = 0
        label.clipsToBounds = false
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
    
    func updateUIView(_ uiView: InsetLabel, context: Context) {
        updateLabel(uiView)
        uiView.lineBreakMode = .byWordWrapping // Ensure words don't break
        
        // Prevent the SwiftUI hosting view from clipping italic overshoot
        uiView.superview?.clipsToBounds = false
        
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
    
    private func updateLabel(_ label: InsetLabel) {
        let fontSize = scale.scaledSize(from: baseSize)
        let effectiveLineHeight = fontSize * lineHeightMultiple
        
        // Create font
        let font = UIFont(name: fontFamily, size: fontSize) ?? 
                   UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        label.font = font
        
        // Compute a top inset so the first line's ascenders aren't
        // clipped by the label's bounds.
        //
        // Two sources of overflow:
        // 1. Italic fonts whose ascenders extend beyond the em-square.
        // 2. Tight lineHeightMultiple (≤ ~1.0) that constrains the line
        //    box to less than the font's natural line height, cutting off
        //    the top of the first line.
        let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        let italicExtra: CGFloat = isItalic ? ceil(fontSize * 0.1) : 0
        
        let naturalLineHeight = font.lineHeight // ascent + descent + leading
        if effectiveLineHeight < naturalLineHeight {
            // The constrained line box is smaller than the font needs;
            // roughly half the overflow lands above the first baseline.
            let overflow = ceil((naturalLineHeight - effectiveLineHeight) * 0.5)
            label.topInset = overflow + italicExtra
        } else {
            label.topInset = italicExtra
        }
        
        // Create paragraph style with controlled line height.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        paragraphStyle.maximumLineHeight = effectiveLineHeight
        paragraphStyle.minimumLineHeight = effectiveLineHeight
        paragraphStyle.alignment = nsTextAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping // Ensure proper word wrapping
        
        // Build attributes
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor(color)
        ]
        if tracking != 0 {
            attributes[.kern] = tracking * fontSize
        }
        
        // Apply attributed string
        let attributedString = NSAttributedString(
            string: text,
            attributes: attributes
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

// MARK: - Typography Namespace
/// Namespace for typography-related utilities and functions
struct Typography {
    /// Estimates the number of lines needed to display text with a given font and maximum width
    /// 
    /// - Parameters:
    ///   - text: The text string to measure
    ///   - font: The UIFont to use for measurement
    ///   - maxWidth: The maximum width available for the text
    /// - Returns: The estimated number of lines needed to display the text
    /// 
    /// Example usage:
    /// ```swift
    /// let lineCount = Typography.estimateLineCount(
    ///     for: message.text,
    ///     font: UIFont.systemFont(ofSize: 15),
    ///     maxWidth: UIScreen.main.bounds.width - 80
    /// )
    /// ```
    static func estimateLineCount(for text: String, font: UIFont, maxWidth: CGFloat) -> Int {
        let attributes = [NSAttributedString.Key.font: font]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let lineHeight = font.lineHeight
        let estimatedLines = Int(ceil(textSize.height / lineHeight))
        return estimatedLines
    }
}

// MARK: - Multilingual Font Sample (Preview Helper)
/// Reusable view for comparing fonts across languages in previews
private struct MultilingualFontSample: View {
    let fontLabel: String
    let heading: String
    let sampleText: String
    let headingFont: Font
    let bodyFont: Font
    var isRTL: Bool = false
    
    var body: some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 4) {
            Text(fontLabel)
                .font(.caption)
                .foregroundColor(.blue)
            Text(heading)
                .font(headingFont)
            Text(sampleText)
                .font(bodyFont)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Multilingual Font Comparison Preview
#Preview("Multilingual Font Comparison") {
    let headingSize: CGFloat = TypographyScale.article3.baseSize
    let bodySize: CGFloat = TypographyScale.article0.baseSize
    
    ScrollView {
        VStack(alignment: .leading, spacing: 40) {
            
            // ━━━ English — Brand Font ━━━
            VStack(alignment: .leading, spacing: 4) {
                Text("ENGLISH — BRAND FONT")
                    .font(.caption2).foregroundColor(.secondary).padding(.bottom, 4)
                Text("Ancient Rome")
                    .font(.custom(FontFamily.serifDisplay, size: headingSize))
                Text("The ancient streets of Rome hold stories waiting to be discovered beneath centuries of history.")
                    .font(.custom(FontFamily.sansRegular, size: bodySize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
            
            // ━━━ Japanese ━━━
            VStack(alignment: .leading, spacing: 16) {
                Text("JAPANESE — FONT COMPARISON")
                    .font(.caption2).foregroundColor(.secondary)
                
                
                MultilingualFontSample(
                    fontLabel: "4. Hiragino Mincho ProN (Serif — W6 / W3)",
                    heading: "古代ローマ",
                    sampleText: "ローマの古代の街並みには、何世紀もの歴史の下に発見を待つ物語が眠っています。",
                    headingFont: .custom("HiraMinProN-W6", size: headingSize),
                    bodyFont: .custom("HiraMinProN-W3", size: bodySize)
                )
                
            }
            
            Divider()
            
            // ━━━ Chinese (Simplified) ━━━
            VStack(alignment: .leading, spacing: 16) {
                Text("CHINESE (SIMPLIFIED) — FONT COMPARISON")
                    .font(.caption2).foregroundColor(.secondary)
                
                MultilingualFontSample(
                    fontLabel: "1. System Default (SF → PingFang SC cascade)",
                    heading: "古罗马",
                    sampleText: "罗马古老的街道上，隐藏着等待在数百年历史中被发现的故事。",
                    headingFont: .system(size: headingSize, weight: .semibold),
                    bodyFont: .system(size: bodySize)
                )
                
                MultilingualFontSample(
                    fontLabel: "2. System Serif (New York → serif cascade)",
                    heading: "古罗马",
                    sampleText: "罗马古老的街道上，隐藏着等待在数百年历史中被发现的故事。",
                    headingFont: .system(size: headingSize, weight: .semibold, design: .serif),
                    bodyFont: .system(size: bodySize, design: .serif)
                )
                
                MultilingualFontSample(
                    fontLabel: "3. PingFang SC (Semibold / Regular)",
                    heading: "古罗马",
                    sampleText: "罗马古老的街道上，隐藏着等待在数百年历史中被发现的故事。",
                    headingFont: .custom("PingFangSC-Semibold", size: headingSize),
                    bodyFont: .custom("PingFangSC-Regular", size: bodySize)
                )
                
                MultilingualFontSample(
                    fontLabel: "4. Songti SC (Serif — Bold / Regular)",
                    heading: "古罗马",
                    sampleText: "罗马古老的街道上，隐藏着等待在数百年历史中被发现的故事。",
                    headingFont: .custom("STSongti-SC-Bold", size: headingSize),
                    bodyFont: .custom("STSongti-SC-Regular", size: bodySize)
                )
                
                MultilingualFontSample(
                    fontLabel: "5. System Rounded",
                    heading: "古罗马",
                    sampleText: "罗马古老的街道上，隐藏着等待在数百年历史中被发现的故事。",
                    headingFont: .system(size: headingSize, weight: .semibold, design: .rounded),
                    bodyFont: .system(size: bodySize, design: .rounded)
                )
            }
            
            Divider()
            
            // ━━━ Arabic ━━━
            VStack(alignment: .leading, spacing: 16) {
                Text("ARABIC — FONT COMPARISON")
                    .font(.caption2).foregroundColor(.secondary)
                
                MultilingualFontSample(
                    fontLabel: "2. System Serif",
                    heading: "روما القديمة",
                    sampleText: "تحتفظ شوارع روما القديمة بقصص تنتظر أن تُكتشف تحت قرون من التاريخ.",
                    headingFont: .system(size: headingSize, weight: .semibold, design: .serif),
                    bodyFont: .system(size: bodySize, design: .serif),
                    isRTL: true
                )
                
            }
            
            Divider()
            
            // ━━━ Mixed Language (travel context) ━━━
            VStack(alignment: .leading, spacing: 16) {
                Text("MIXED LANGUAGE — TRAVEL CONTEXT")
                    .font(.caption2).foregroundColor(.secondary)
                
                MultilingualFontSample(
                    fontLabel: "System Default — English + Japanese",
                    heading: "Exploring 東京 (Tokyo)",
                    sampleText: "Visit the 浅草寺 (Sensō-ji) temple, one of Tokyo's oldest and most significant Buddhist temples.",
                    headingFont: .system(size: headingSize, weight: .semibold),
                    bodyFont: .system(size: bodySize)
                )
                
                MultilingualFontSample(
                    fontLabel: "System Serif — English + Chinese",
                    heading: "Discovering 北京 (Beijing)",
                    sampleText: "Walk along the 长城 (Great Wall), a marvel of ancient engineering stretching across northern China.",
                    headingFont: .system(size: headingSize, weight: .semibold, design: .serif),
                    bodyFont: .system(size: bodySize, design: .serif)
                )
                
                MultilingualFontSample(
                    fontLabel: "System Default — English + Arabic",
                    heading: "Exploring القاهرة (Cairo)",
                    sampleText: "Discover the أهرامات الجيزة (Pyramids of Giza), standing as timeless monuments to human achievement.",
                    headingFont: .system(size: headingSize, weight: .semibold),
                    bodyFont: .system(size: bodySize)
                )
            }
        }
        .padding()
    }
}

// MARK: - Line Height Preview
#Preview("Line Height Test") {
    let sampleText = "The quick brown fox jumps over the lazy dog. This is a longer sentence to test how line height behaves across multiple lines of text."
    
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {


            VStack(alignment: .leading, spacing: 8) {
                Text("SerifDisplay · article3 · tight lineHeight (DisplayText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                DisplayText(
                    sampleText, 
                    scale: .article3, 
                    lineHeightMultiple: 1.2, 
                    fontFamily: FontFamily.serifItalic,
                )
                    .background(Color.green.opacity(0.15))
                
                Text("fontSize: \(TypographyScale.article3.baseSize, specifier: "%.1f")pt · lineHeightMultiple: 1.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // SerifDisplay at article3 with tight line height (DisplayText)
            VStack(alignment: .leading, spacing: 8) {
                Text("SerifDisplay · article3 · tight lineHeight (DisplayText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                DisplayText(sampleText, scale: .article3, lineHeightMultiple: 1.2)
                    .background(Color.green.opacity(0.15))
                
                Text("fontSize: \(TypographyScale.article3.baseSize, specifier: "%.1f")pt · lineHeightMultiple: 1.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // SansSemiBold at article0
            VStack(alignment: .leading, spacing: 8) {
                Text("SansSemiBold · article0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(sampleText)
                    .font(Font.custom(FontFamily.sansSemibold, size: TypographyScale.article0.baseSize))
                    .background(Color.yellow.opacity(0.15))
                
                Text("fontSize: \(TypographyScale.article0.baseSize, specifier: "%.1f")pt")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // SerifDisplay at article3
            VStack(alignment: .leading, spacing: 8) {
                Text("SerifDisplay · article3")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(sampleText)
                    .font(Font.custom(FontFamily.serifDisplay, size: TypographyScale.article3.baseSize))
                    .background(Color.blue.opacity(0.15))
                
                Text("fontSize: \(TypographyScale.article3.baseSize, specifier: "%.1f")pt")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
         

            
        }
        .padding()
    }
}

// MARK: - Icon Font Glyph Browser Preview
/// Visual browser for discovering glyphs in the SF-Symbols-Pro icon font.
/// 
/// Shows icons in a scrollable grid with their Unicode values.
/// Use this preview to identify which glyphs you want, then add them
/// to the `IconGlyph` enum above.
///
/// Adjust `startCodePoint` and `endCodePoint` to browse different ranges:
/// - Main range: 0xE900 – 0x101AF (~6,300 icons)
/// - Scattered: 0xE007, 0xE013, 0xE01A, 0xE01E, 0xE049, 0xE052, 0xE055–0xE057, 0xE077–0xE07C
private struct IconFontBrowser: View {
    let startCodePoint: Int
    let endCodePoint: Int
    let iconSize: CGFloat
    let columns: Int
    
    init(
        start: Int = 0xE900,
        end: Int = 0xE9FF,
        iconSize: CGFloat = 28,
        columns: Int = 6
    ) {
        self.startCodePoint = start
        self.endCodePoint = end
        self.iconSize = iconSize
        self.columns = columns
    }
    
    private var codePoints: [Int] {
        Array(startCodePoint...endCodePoint)
    }
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Range header
                Text("SF-Symbols-Pro Glyph Browser")
                    .font(.headline)
                Text("Range: U+\(String(format: "%04X", startCodePoint)) – U+\(String(format: "%04X", endCodePoint)) (\(endCodePoint - startCodePoint + 1) slots)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Tap a glyph to copy its code. Add to IconGlyph enum as:\ncase name = \"\\u{XXXX}\"")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Glyph grid
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(codePoints, id: \.self) { codePoint in
                        if let scalar = Unicode.Scalar(codePoint) {
                            VStack(spacing: 2) {
                                Text(String(scalar))
                                    .font(.custom(FontFamily.sfSymbolsExtra, size: iconSize))
                                    .frame(width: 44, height: 44)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                                
                                Text(String(format: "%04X", codePoint))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

#Preview("Icon Font Browser · E900–E9FF") {
    IconFontBrowser(start: 0xE900, end: 0xE9FF)
}

#Preview("Icon Font Browser · EA00–EAFF") {
    IconFontBrowser(start: 0xEA00, end: 0xEAFF)
}

#Preview("Icon Font Browser · EB00–EBFF") {
    IconFontBrowser(start: 0xEB00, end: 0xEBFF)
}

#Preview("Icon Font Browser · EC00–ECFF") {
    IconFontBrowser(start: 0xEC00, end: 0xECFF)
}

#Preview("Icon Font Browser · Scattered PUA") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scattered PUA Glyphs")
                .font(.headline)
            
            let scatteredCodes: [Int] = [
                0xE007, 0xE013, 0xE01A, 0xE01E,
                0xE049, 0xE052, 0xE055, 0xE056, 0xE057,
                0xE077, 0xE078, 0xE079, 0xE07A, 0xE07B, 0xE07C
            ]
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 8) {
                ForEach(scatteredCodes, id: \.self) { codePoint in
                    if let scalar = Unicode.Scalar(codePoint) {
                        VStack(spacing: 2) {
                            Text(String(scalar))
                                .font(.custom(FontFamily.sfSymbolsExtra, size: 28))
                                .frame(width: 52, height: 52)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                            
                            Text(String(format: "U+%04X", codePoint))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Cataloged Icon Reference (Grouped)
/// Shows all icons from the IconGlyph enum grouped by category,
/// with enum case name and unicode value for each icon.
private struct CatalogedIconRow: View {
    let glyph: IconGlyph
    let label: String
    
    var body: some View {
        HStack(spacing: 12) {
            IconFontImage(glyph, size: 28, color: .primary)
                .frame(width: 40, height: 40)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(".\(label)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text(unicodeHex(for: glyph))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func unicodeHex(for glyph: IconGlyph) -> String {
        guard let scalar = glyph.rawValue.unicodeScalars.first else { return "?" }
        return String(format: "U+%04X", scalar.value)
    }
}

private struct CatalogedIconGroup: View {
    let title: String
    let icons: [(glyph: IconGlyph, label: String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1.2)
            
            ForEach(icons, id: \.label) { item in
                CatalogedIconRow(glyph: item.glyph, label: item.label)
            }
        }
    }
}

#Preview("Cataloged Icons by Group") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Text("SF-Symbols-Pro — Cataloged Icons")
                .font(.headline)
            Text("All icons added to IconGlyph enum, grouped by category.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            CatalogedIconGroup(title: "Maps & Location", icons: [
                (.mapPin, "mapPin"),
                (.globeLocation, "globeLocation"),
                (.mapRoute, "mapRoute"),
                (.googleMaps, "googleMaps"),
                (.tactileMap, "tactileMap"),
            ])
            
            Divider()
            
            CatalogedIconGroup(title: "Buildings & Landmarks", icons: [
                (.tajMahal, "tajMahal"),
                (.asianTemple, "asianTemple"),
                (.orthodoxChurch, "orthodoxChurch"),
                (.mosque, "mosque"),
                (.cathedral, "cathedral"),
            ])
            
            Divider()
            
            CatalogedIconGroup(title: "Religion & Culture", icons: [
                (.starOfDavid, "starOfDavid"),
                (.menorah, "menorah"),
            ])
            
            Divider()
            
            CatalogedIconGroup(title: "Communication", icons: [
                (.chatBubbles, "chatBubbles"),
                (.chatTranslation, "chatTranslation"),
            ])
            
            Divider()
            
            CatalogedIconGroup(title: "Nature & Animals", icons: [
                (.pelican, "pelican"),
                (.crescentMoon, "crescentMoon"),
            ])
            
            Divider()
            
            CatalogedIconGroup(title: "Travel & Commerce", icons: [
                (.ticket, "ticket"),
                (.currencyExchange, "currencyExchange"),
                (.closedSign, "closedSign"),
            ])
            
            Divider()
            
            CatalogedIconGroup(title: "Medical", icons: [
                (.stethoscope, "stethoscope"),
            ])
            
            Divider()
            
            CatalogedIconGroup(title: "Brands", icons: [
                (.googlePlus, "googlePlus"),
            ])
        }
        .padding()
    }
}