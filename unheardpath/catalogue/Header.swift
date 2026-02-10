import SwiftUI
import core

// MARK: - Section Header View
/// Renders an optional header with overline, headline, subhead, and feature image.
/// All fields are optional — only non-empty values are rendered.
struct SectionHeaderView: View {
    let header: JSONValue
    
    private var overline: String {
        header["overline"]?.stringValue ?? ""
    }
    private var headline: String {
        header["headline"]?.stringValue ?? ""
    }
    private var subhead: String {
        header["subhead"]?.stringValue ?? ""
    }
    private var featureImg: String {
        header["feature_img"]?.stringValue ?? ""
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: TypographyScale.articleMinus1.baseSize) {
            // Overline — DisplayText · SansRegular · wide tracking
            if !overline.isEmpty {
                DisplayText(
                    overline,
                    scale: .articleMinus1,
                    color: Color.textSecondary,
                    lineHeightMultiple: 1.0,
                    fontFamily: FontFamily.sansRegular,
                    tracking: 0.2
                )
            }
            
            // Headline — DisplayText · SerifItalic · tight line height
            if !headline.isEmpty {
                DisplayText(
                    headline,
                    scale: .article3,
                    color: Color.textPrimary,
                    lineHeightMultiple: 1.3,
                    fontFamily: FontFamily.serifItalic
                )
            }
            
            // Subhead
            if !subhead.isEmpty {
                Text(subhead)
                    .font(Font.custom(FontFamily.serifRegular, size: TypographyScale.article1.baseSize))
                    .foregroundColor(Color.textSecondary)
                    .padding(.bottom, 12)
            }
            
            // Feature image
            if !featureImg.isEmpty {
                AsyncImage(url: URL(string: featureImg)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        Text("Failed to load image")
                    } else {
                        ProgressView()
                    }
                }
            }
        }
    }
}

// MARK: - Previews
#if DEBUG
#Preview("Section Header") {
    ScrollView {
        SectionHeaderView(header: .dictionary([
            "overline": .string("HISTORY & CULTURE"),
            "headline": .string("An Unorthodox History of Istanbul"),
            "subhead": .string("From Byzantine splendor to Ottoman grandeur"),
            "feature_img": .string("https://www.esplanade.com/-/media/Esplanade/Images/Whats-On/all-events/2024/T/the-performing-art-of-the-samurai-japans-traditional-noh-drama-01.ashx?rev=c03c943571d04b05b7e5f6bc9ca3c4ac&hash=2D1A2C28F99A90CEDA9E77D1B5C3DC88")
        ]))
        .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("Section Header - Partial") {
    ScrollView {
        SectionHeaderView(header: .dictionary([
            "headline": .string("The Roman Forum"),
            "subhead": .string("Center of ancient Roman public life")
        ]))
        .padding()
    }
    .background(Color("AppBkgColor"))
}
#endif
