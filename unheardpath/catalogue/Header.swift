import SwiftUI
import core

// MARK: - Topic Header View
/// Renders an optional header with overline, headline, subhead, and feature image.
/// All fields are optional — only non-empty values are rendered.
struct TopicHeaderView: View {
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
        VStack(alignment: .leading) {
            // Accent square + Overline
            if !overline.isEmpty {
                HStack(spacing: Spacing.current.spaceXs) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .offset(y: -2)
                    
                    DisplayText(
                        overline,
                        scale: .articleMinus1,
                        color: Color.textSecondary,
                        // color: Color("AccentColor"),
                        lineHeightMultiple: 1.0,
                        fontFamily: FontFamily.sansRegular,
                        tracking: 0.2
                    )
                }
                .padding(.horizontal, Spacing.current.textSideMargin)
            }
            
            // Headline — DisplayText · SerifItalic · tight line height
            if !headline.isEmpty {
                DisplayText(
                    headline,
                    scale: .article3,
                    color: Color.textPrimary,
                    // color: Color("AccentColor"),
                    lineHeightMultiple: 1.1,
                    fontFamily: FontFamily.serifItalic
                )
                .padding(.leading, Spacing.current.textSideMargin)
                .padding(.trailing, Spacing.current.spaceXl)
                
                // .padding(.top, Spacing.current.spaceXs)
            }
            
            // Subhead — DisplayText · SansRegular · subtle tracking
            if !subhead.isEmpty {
                DisplayText(
                    subhead,
                    scale: .article1,
                    color: Color.textSecondary.opacity(0.8),
                    lineHeightMultiple: 1.25,
                    fontFamily: FontFamily.sansRegular,
                    tracking: 0.005
                )
                .padding(.horizontal, Spacing.current.textSideMargin)
            }
            
            // Feature image
            if !featureImg.isEmpty {
                AsyncImage(url: URL(string: featureImg)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                            .padding(.vertical, Spacing.current.spaceXs)
                    } else if phase.error != nil {
                        EmptyView()
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
#Preview("Topic Header") {
    ScrollView {
        TopicHeaderView(header: .dictionary([
            "overline": .string("HISTORY & CULTURE"),
            "headline": .string("An Unorthodox History of Istanbul"),
            "subhead": .string("From Byzantine splendor to Ottoman grandeur"),
            "feature_img": .string("https://www.esplanade.com/-/media/Esplanade/Images/Whats-On/all-events/2024/T/the-performing-art-of-the-samurai-japans-traditional-noh-drama-01.ashx?rev=c03c943571d04b05b7e5f6bc9ca3c4ac&hash=2D1A2C28F99A90CEDA9E77D1B5C3DC88")
        ]))
    }
    .background(Color("AppBkgColor"))
}

#Preview("Topic Header - Partial") {
    ScrollView {
        TopicHeaderView(header: .dictionary([
            "headline": .string("The Roman Forum"),
            "subhead": .string("Center of ancient Roman public life")
        ]))
    }
    .background(Color("AppBkgColor"))
}
#endif
