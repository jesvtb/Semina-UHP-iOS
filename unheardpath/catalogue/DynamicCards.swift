import SwiftUI
import core

// MARK: - Card Constants
/// Shared layout constants for all card types (journey, event, dish, generic/place).
@MainActor
enum CardConstants {
    /// Standard corner radius for cards, tied to the spacing scale.
    static var cornerRadius: CGFloat { Spacing.current.space3xs }
}

// MARK: - Dynamic Card Grid
/// A reusable grid layout for any card type. Renders cards in a configurable grid,
/// delegating the internal card view to a `@ViewBuilder` closure.
/// Config options:
/// - `inColsofCount`: Number of columns (default: 2)
/// - `colGap`: Horizontal gap between columns (default: Spacing.current.spaceS)
/// - `rowGap`: Vertical gap between rows (default: Spacing.current.spaceS)
/// - `aspectRatio`: Card width/height ratio (default: 0.85, meaning height > width)
/// - `cornerRadius`: Card corner radius (default: 12)
struct DynamicCardGrid<CardContent: View>: View {
    let cards: [JSONValue]
    let config: JSONValue?
    let cardContent: (JSONValue) -> CardContent
    
    init(cards: [JSONValue], config: JSONValue?, @ViewBuilder cardContent: @escaping (JSONValue) -> CardContent) {
        self.cards = cards
        self.config = config
        self.cardContent = cardContent
    }
    
    private var columnCount: Int {
        config?["inColsofCount"]?.doubleValue.map { Int($0) } ?? 2
    }
    
    private var colGap: CGFloat {
        config?["colGap"]?.doubleValue.map { CGFloat($0) } ?? Spacing.current.spaceS
    }
    
    private var rowGap: CGFloat {
        config?["rowGap"]?.doubleValue.map { CGFloat($0) } ?? Spacing.current.spaceS
    }
    
    private var aspectRatio: CGFloat {
        config?["aspectRatio"]?.doubleValue.map { CGFloat($0) } ?? 0.85
    }
    
    var cornerRadius: CGFloat {
        config?["cornerRadius"]?.doubleValue.map { CGFloat($0) } ?? CardConstants.cornerRadius
    }
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width)
            // Width determined by: (availableWidth - gaps) / columnCount
            let totalGapWidth = colGap * CGFloat(columnCount - 1)
            let columnWidth = (availableWidth - totalGapWidth) / CGFloat(columnCount)
            // Height derived from width and aspect ratio
            let cardHeight = columnWidth / aspectRatio
            
            let columns = Array(repeating: GridItem(.fixed(columnWidth), spacing: colGap), count: columnCount)
            
            LazyVGrid(columns: columns, spacing: rowGap) {
                ForEach(cards.indices, id: \.self) { index in
                    cardContent(cards[index])
                        .frame(width: columnWidth, height: cardHeight)
                }
            }
            .frame(width: availableWidth)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: gridContentHeight)
    }
    
    private var gridContentHeight: CGFloat {
        let cardCount = cards.count
        let rowCount = (cardCount + columnCount - 1) / columnCount
        guard rowCount > 0 else { return 0 }
        // Estimate based on typical screen width
        let estimatedAvailableWidth: CGFloat = UIScreen.main.bounds.width - 32 // rough padding estimate
        let totalGapWidth = colGap * CGFloat(columnCount - 1)
        let estimatedColumnWidth = (estimatedAvailableWidth - totalGapWidth) / CGFloat(columnCount)
        let rowHeight = estimatedColumnWidth / aspectRatio
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowGap
    }
}

// MARK: - DynamicCardGrid Convenience (GenericCard default)
extension DynamicCardGrid where CardContent == GenericCard {
    /// Convenience initializer that defaults to `GenericCard` for the card content.
    init(cards: [JSONValue], config: JSONValue?) {
        let radius = config?["cornerRadius"]?.doubleValue.map { CGFloat($0) } ?? CardConstants.cornerRadius
        self.init(cards: cards, config: config) { data in
            GenericCard(data: data, cornerRadius: radius)
        }
    }
}

// MARK: - Generic Card
/// A generic card view that uses flexible key conventions
/// Fills available space - parent determines dimensions
struct GenericCard: View {
    let data: JSONValue
    let cornerRadius: CGFloat
    
    init(data: JSONValue, cornerRadius: CGFloat = CardConstants.cornerRadius) {
        self.data = data
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardBackground
            gradientOverlay
            textOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color("onBkgTextColor30").opacity(0.15), lineWidth: 1)
        )
    }
    
    /// Primary text: tries title, name, local_name
    private var primaryText: String? {
        guard case .dictionary(let dict) = data else { return nil }
        return dict["title"]?.stringValue
            ?? dict["name"]?.stringValue
            ?? dict["local_name"]?.stringValue
    }
    
    /// Secondary text: tries subtitle, global_name
    private var secondaryText: String? {
        guard case .dictionary(let dict) = data else { return nil }
        let text = dict["subtitle"]?.stringValue ?? dict["global_name"]?.stringValue
        // Don't show secondary text if it's the same as primary
        return text != primaryText ? text : nil
    }
    
    /// Image URL: tries image_url, img_url
    private var imageURL: URL? {
        guard case .dictionary(let dict) = data else { return nil }
        let urlString = dict["img_url"]?.stringValue
        return urlString.flatMap { URL(string: $0) }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        GeometryReader { geometry in
            if let imageURL = imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                            .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                    }
                }
            } else {
                Rectangle()
                    .fill(Color("onBkgTextColor30").opacity(0.15))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
                    )
            }
        }
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity(0.1),
                Color.black.opacity(0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let primary = primaryText {
                DisplayText(
                    primary,
                    scale: .article1,
                    color: .white,
                    lineHeightMultiple: 1.0,
                    fontFamily: FontFamily.sansSemibold
                )
            }
            if let secondary = secondaryText {
                DisplayText(
                    secondary,
                    scale: .articleMinus1,
                    color: .white.opacity(0.9),
                    lineHeightMultiple: 1.0,
                    fontFamily: FontFamily.sansRegular
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.space2xs)
        .clipped()
    }
}

// MARK: - Previews
#if DEBUG

// Sample card data for previews
private let sampleCards: [JSONValue] = [
    .dictionary([
        "title": .string("Hagia Sophia"),
        "subtitle": .string("Byzantine Architecture"),
        "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg")
    ]),
    .dictionary([
        "title": .string("Blue Mosque"),
        "subtitle": .string("Ottoman Architecture"),
        "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/b/b0/Sultan_Ahmed_Mosque_Istanbul_Turkey_retouched.jpg")
    ]),
    .dictionary([
        "name": .string("Grand Bazaar"),
        "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/5/5e/Istanbul_Grand_Bazaar.jpg")
    ]),
    .dictionary([
        "title": .string("Topkapi Palace"),
        "subtitle": .string("Imperial Residence"),
        "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/f/f3/Topkap%C4%B1_-_01.jpg")
    ]),
    .dictionary([
        "title": .string("Basilica Cistern"),
        "subtitle": .string("Underground Wonder")
    ]),
    .dictionary([
        "title": .string("Galata Tower"),
        "subtitle": .string("Medieval Landmark"),
        "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/3/3b/Galata_Tower_%282%29.jpg")
    ])
]

#Preview("Default 2-Column Grid") {
    ScrollView {
        DynamicCardGrid(cards: sampleCards, config: nil)
            .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("3-Column Grid") {
    ScrollView {
        DynamicCardGrid(
            cards: sampleCards,
            config: .dictionary([
                "inColsofCount": .double(3),
                "aspectRatio": .double(1.0)
            ])
        )
        .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("Single Column, Landscape Cards") {
    ScrollView {
        DynamicCardGrid(
            cards: sampleCards,
            config: .dictionary([
                "inColsofCount": .double(1),
                "aspectRatio": .double(1.8)
            ])
        )
        .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("Custom Gaps") {
    ScrollView {
        DynamicCardGrid(
            cards: sampleCards,
            config: .dictionary([
                "inColsofCount": .double(2),
                "colGap": .double(4),
                "rowGap": .double(16),
                "aspectRatio": .double(0.75)
            ])
        )
        .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("Generic Card") {
    GenericCard(data: .dictionary([
        "title": .string("Hagia Sophia"),
        "subtitle": .string("Byzantine Architecture"),
        "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg")
    ]))
    .frame(width: 180, height: 220)
    .padding()
    .background(Color("AppBkgColor"))
}

#endif
