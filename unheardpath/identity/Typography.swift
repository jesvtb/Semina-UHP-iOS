import SwiftUI

// MARK: - Typography System
// Matches brand typography from brand.scss
// 
// Brand Font Usage:
// - SourceSerif4Display-Semibold: Headlines (font-weight: 600)
// - SourceSerif4: Body text (Regular, Italic)
// - SourceSans3: UI elements (Regular, Semibold, ExtraLight)

struct Typography {
    // MARK: - Font Names (PostScript names)
    static let sourceSerif4DisplaySemibold = "SourceSerif4Display-Semibold"
    
    // MARK: - Headlines
    /// Headline 1 - Large display text (60pt)
    /// Uses SourceSerif4Display-Semibold per brand guidelines
    /// Line height: 1em (tight, typical for display fonts)
    static let headline1 = Font.custom(sourceSerif4DisplaySemibold, size: 60)
    
    /// Headline 1 line spacing
    /// For 60pt font with line-height: 1em, we use negative spacing to tighten
    /// Most fonts have default line-height ~1.2x font size, so we subtract ~12-15pt
    /// This matches brand.scss %Title style: line-height: 1em (tight, no extra space)
    /// Note: SwiftUI may require more negative values to achieve tight spacing
    static let headline1LineSpacing: CGFloat = -40
    
    // MARK: - Font Verification (Debug Only)
    #if DEBUG
    /// Verifies that custom fonts are properly loaded
    /// Call this during app initialization to debug font loading issues
    static func verifyFonts() {
        print("🔍 Verifying custom fonts...")
        
        // Check if our custom font is available
        if UIFont(name: sourceSerif4DisplaySemibold, size: 40) != nil {
            print("✅ \(sourceSerif4DisplaySemibold) is available")
        } else {
            print("❌ \(sourceSerif4DisplaySemibold) is NOT available")
            print("   Make sure:")
            print("   1. Font file is in the main app bundle (e.g., fonts/ folder, not Assets.xcassets)")
            print("   2. Font is added to the app target in Xcode")
            print("   3. Font is registered in Info.plist under UIAppFonts (filename only, iOS searches recursively)")
            print("   4. PostScript name matches: \(sourceSerif4DisplaySemibold)")
        }
        
        // List all available font families for debugging
        print("\n📋 Available font families:")
        for family in UIFont.familyNames.sorted() {
            if family.contains("Source") {
                print("   Family: \(family)")
                for name in UIFont.fontNames(forFamilyName: family) {
                    print("      - \(name)")
                }
            }
        }
    }
    #endif
}

// MARK: - View Extension for Typography
extension View {
    /// Applies headline1 typography style with font and tight line spacing
    /// Usage: Text("Title").headline1()
    /// 
    /// Note: If line spacing doesn't appear tight enough, SwiftUI's .lineSpacing()
    /// may not respect negative values. Try adjusting headline1LineSpacing or use
    /// the UILabel-based approach for precise control.
    func headline1() -> some View {
        self
            .font(Typography.headline1)
            .lineSpacing(Typography.headline1LineSpacing)
    }
}

// MARK: - UILabel-based Headline1 (Alternative for precise line-height control)
/// Use this if SwiftUI's lineSpacing doesn't work with negative values
/// Usage: Headline1Label(text: "Title")
struct Headline1Label: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let textAlignment: NSTextAlignment
    let textColor: UIColor
    
    init(text: String, fontSize: CGFloat = 60, lineHeightMultiple: CGFloat = 1.0, textAlignment: NSTextAlignment = .left, textColor: UIColor = .label) {
        self.text = text
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.textAlignment = textAlignment
        self.textColor = textColor
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = textAlignment
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        // Create font
        let font = UIFont(name: "SourceSerif4Display-Semibold", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        label.font = font
        
        // Create paragraph style with tight line height
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        paragraphStyle.maximumLineHeight = fontSize
        paragraphStyle.minimumLineHeight = fontSize
        paragraphStyle.alignment = textAlignment
        
        // Apply attributed string
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: textColor
            ]
        )
        label.attributedText = attributedString
        
        return label
    }
    
    func updateUIView(_ uiView: UILabel, context: Context) {
        // Update if text or color changes
        let font = UIFont(name: "SourceSerif4Display-Semibold", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        paragraphStyle.maximumLineHeight = fontSize
        paragraphStyle.minimumLineHeight = fontSize
        paragraphStyle.alignment = textAlignment
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: textColor
            ]
        )
        uiView.attributedText = attributedString
        uiView.textAlignment = textAlignment
        
        // Update preferredMaxLayoutWidth when layout changes
        DispatchQueue.main.async {
            if let superview = uiView.superview {
                let availableWidth = superview.bounds.width
                if uiView.preferredMaxLayoutWidth != availableWidth && availableWidth > 0 {
                    uiView.preferredMaxLayoutWidth = availableWidth
                    uiView.setNeedsLayout()
                }
            }
        }
    }
    
    class Coordinator {
        // Can be used for additional state if needed
    }
}

// MARK: - View Extension for Headline1Label
extension Headline1Label {
    /// Sets the text color for the label
    func foregroundColor(_ color: Color) -> Headline1Label {
        Headline1Label(
            text: self.text,
            fontSize: self.fontSize,
            lineHeightMultiple: self.lineHeightMultiple,
            textAlignment: self.textAlignment,
            textColor: UIColor(color)
        )
    }
}

