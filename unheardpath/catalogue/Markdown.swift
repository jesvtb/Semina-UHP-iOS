import SwiftUI
import MarkdownUI
import core

// MARK: - Catalogue View Registry
/// Creates views for catalogue sections using config-driven rendering
struct CatalogueViewRegistry {
    static func view(for section: CatalogueSection) -> some View {
        DynamicSectionRenderer(section: section)
    }
}

// MARK: - Content Block
/// Represents a single content block with optional header, markdown, cards, and per-item interface config.
struct ContentBlock: Identifiable {
    let id: String
    /// Optional header with overline, headline, subhead, and feature_img fields.
    let header: JSONValue?
    let markdown: String?
    let cards: [JSONValue]?
    /// Per-item rendering config extracted from `_metadata.interface`.
    let interface: JSONValue?
}

// MARK: - Dynamic Section Renderer
/// Renders catalogue sections using per-item `_metadata.interface` for rendering config.
/// Content items are sorted by `_metadata.location.geoscope` specificity (most local first).
struct DynamicSectionRenderer: View {
    let section: CatalogueSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceM) {
            // Extract content blocks and render each one
            ForEach(extractContentBlocks(from: section.content)) { block in
                ContentBlockView(block: block)
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
    
    /// Extract content blocks from content, reading `_metadata` per item for interface config and geoscope ordering.
    ///
    /// - Flat content (direct markdown/cards at root level): single block with no interface.
    /// - Nested content (keyed items): one block per topic, sorted by geoscope specificity (most specific first).
    ///
    /// Keys starting with `_` (e.g. `_metadata`) are stripped before rendering.
    private func extractContentBlocks(from content: JSONValue) -> [ContentBlock] {
        guard case .dictionary(let rawDict) = content else { return [] }
        
        // Check if content is flat (has direct markdown or cards keys — legacy/simple content)
        let hasDirectMarkdown = rawDict["markdown"]?.stringValue != nil
        let hasDirectCards: Bool = {
            if let cardsValue = rawDict["cards"], case .array(let cards) = cardsValue, !cards.isEmpty {
                return true
            }
            return false
        }()
        
        if hasDirectMarkdown || hasDirectCards {
            // Flat content - single block (strip metadata)
            let cleaned = content.strippingMetadataKeys
            guard case .dictionary(let dict) = cleaned else { return [] }
            let header = rawDict["header"]
            let markdown = dict["markdown"]?.stringValue
            let cards: [JSONValue]? = {
                if let cardsValue = dict["cards"], case .array(let cards) = cardsValue {
                    return cards
                }
                return nil
            }()
            return [ContentBlock(id: "root", header: header, markdown: markdown, cards: cards, interface: nil)]
        }
        
        // Nested content - extract each topic as a block with interface and geoscope
        var blocks: [(block: ContentBlock, geoLevel: GeoLevel?)] = []
        for (key, value) in rawDict {
            // Skip metadata keys at root level
            if key.hasPrefix("_") { continue }
            // Skip non-dictionary values
            guard case .dictionary(let topicDict) = value else { continue }
            
            // Extract _metadata before stripping
            let metadata = topicDict["_metadata"]
            let itemInterface = metadata?["interface"]
            let geoScopeStr = metadata?["location"]?["geoscope"]?.stringValue
            let geoLevel = geoScopeStr.flatMap { GeoLevel(identifier: $0) }
            
            // Strip metadata from the topic for rendering
            let cleaned = value.strippingMetadataKeys
            guard case .dictionary(let cleanedDict) = cleaned else { continue }
            
            let header = topicDict["header"]
            let markdown = cleanedDict["markdown"]?.stringValue
            let cards: [JSONValue]? = {
                if let cardsValue = cleanedDict["cards"], case .array(let cards) = cardsValue {
                    return cards
                }
                return nil
            }()
            
            // Only include if topic has header, markdown, or cards
            if header != nil || markdown != nil || cards != nil {
                let block = ContentBlock(id: key, header: header, markdown: markdown, cards: cards, interface: itemInterface)
                blocks.append((block, geoLevel))
            }
        }
        
        // Sort by geoscope specificity: most specific (highest rawValue) first.
        // Items without geoscope go to the end.
        blocks.sort { a, b in
            let aOrder = a.geoLevel?.rawValue ?? -1
            let bOrder = b.geoLevel?.rawValue ?? -1
            return aOrder > bOrder
        }
        
        return blocks.map { $0.block }
    }
}

// MARK: - Content Block View
/// Renders a single content block (markdown + cards).
/// Reads rendering config from the block's per-item `interface` (from `_metadata.interface`).
struct ContentBlockView: View {
    let block: ContentBlock
    
    /// Card rendering config from `_metadata.interface.card`.
    private var cardConfig: JSONValue? { block.interface?["card"] }
    /// Markdown rendering config from `_metadata.interface.markdown`.
    private var markdownConfig: JSONValue? { block.interface?["markdown"] }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            // Render header if present
            if let header = block.header {
                TopicHeaderView(header: header)
            }
            
            // Render markdown if present
            if let markdown = block.markdown, !markdown.isEmpty {
                MarkdownRenderer(markdown: markdown, config: markdownConfig)
            }
            
            // Render cards if present
            if let cards = block.cards, !cards.isEmpty {
                cardRenderer(cards: cards)
                    .padding(.horizontal, Spacing.current.textSideMargin)
            }
        }
        .padding(.bottom, Spacing.current.spaceXl)
    }
    
    @ViewBuilder
    private func cardRenderer(cards: [JSONValue]) -> some View {
        if let renderType = cardConfig?["render_type"]?.stringValue {
            // Explicit render_type -> use typed renderer with strict keys
            switch renderType {
            case "dish":
                DishCardContent(cards: cards, config: cardConfig)
            case "event":
                EventCardContent(cards: cards, config: cardConfig)
            case "journey":
                JourneyCardContent(cards: cards, config: cardConfig)
            case "feature":
                FeatureCardList(cards: cards, config: cardConfig)
            default:
                DynamicCardGrid(cards: cards, config: cardConfig)
            }
        } else {
            // No render_type -> use dynamic card builder with layout config
            DynamicCardGrid(cards: cards, config: cardConfig)
        }
    }
}

// MARK: - Semantic Link Category
/// Categories for inline semantic annotation links in catalogue markdown.
/// URL format: `scheme://encoded_term` e.g. `landscape://the%20Alps`
enum SemanticLinkCategory: String, CaseIterable {
    case landscape
    case cuisine
    case dish
    case place
    
    /// Parse a URL into a semantic link category and decoded term.
    /// Returns nil for non-semantic URLs (e.g. regular http links).
    static func parse(_ url: URL) -> (category: SemanticLinkCategory, term: String)? {
        guard let scheme = url.scheme,
              let category = SemanticLinkCategory(rawValue: scheme) else {
            return nil
        }
        // Term is encoded as the host portion: scheme://encoded_term
        let term = url.host(percentEncoded: false) ?? ""
        return (category, term)
    }
}

// MARK: - Markdown Renderer
struct MarkdownRenderer: View {
    let markdown: String
    let config: JSONValue?
    
    @State private var tappedLink: (category: SemanticLinkCategory, term: String)?
    
    var body: some View {
        Markdown(markdown)
            .markdownTextStyle(\.text) {
                MarkdownUI.FontFamily(.custom(FontFamily.sansRegular))
                MarkdownUI.FontSize(TypographyScale.article0.baseSize)
                MarkdownUI.ForegroundColor(Color.textSecondary)
            }
            .markdownTextStyle(\.strong) {
                MarkdownUI.FontWeight(.semibold)
                MarkdownUI.ForegroundColor(Color.textPrimary)
            }
            .markdownTextStyle(\.link) {
                MarkdownUI.ForegroundColor(Color("AccentColor"))
                MarkdownUI.FontWeight(.medium)
                MarkdownUI.UnderlineStyle(.init(pattern: .dot, color: Color("AccentColor").opacity(0.5)))
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .padding(.horizontal, Spacing.current.textSideMargin)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontFamily(.custom(FontFamily.sansExtraLight))
                        MarkdownUI.FontSize(TypographyScale.article3.baseSize)
                        MarkdownUI.ForegroundColor(Color.textPrimary)
                    }
                    .padding(.top, Spacing.current.spaceXs)
                    .padding(.horizontal, Spacing.current.textSideMargin)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontWeight(.bold)
                        MarkdownUI.FontSize(TypographyScale.article1.baseSize)
                        MarkdownUI.ForegroundColor(Color.textPrimary)
                    }
                    .padding(.horizontal, Spacing.current.textSideMargin)
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontFamily(.custom(FontFamily.sansRegular))
                        MarkdownUI.FontSize(TypographyScale.article0.baseSize)
                        MarkdownUI.ForegroundColor(Color.textPrimary)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color("AccentColor"))
                            .frame(width: 4)
                    }
                    .padding(.horizontal, Spacing.current.spaceM)
                    .padding(.bottom, Spacing.current.spaceS)

            }
            .markdownBlockStyle(\.table) { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(color: .clear))
                    .markdownMargin(top: 16, bottom: 16)
            }
            .environment(\.openURL, OpenURLAction { url in
                if let parsed = SemanticLinkCategory.parse(url) {
                    tappedLink = parsed
                    return .handled
                }
                return .systemAction
            })
    }
}



// MARK: - Previews
#if DEBUG
#Preview("Content Block with Header") {
    ScrollView {
        ContentBlockView(block: ContentBlock(
            id: "preview",
            header: .dictionary([
                "overline": .string("HISTORY & CULTURE"),
                "headline": .string("An Unorthodox History of Istanbul"),
                "subhead": .string("From Byzantine splendor to Ottoman grandeur"),
                "feature_img": .string("https://www.esplanade.com/-/media/Esplanade/Images/Whats-On/all-events/2024/T/the-performing-art-of-the-samurai-japans-traditional-noh-drama-01.ashx?rev=c03c943571d04b05b7e5f6bc9ca3c4ac&hash=2D1A2C28F99A90CEDA9E77D1B5C3DC88")
            ]),
            markdown: """
            The ancient streets of [Rome](place://Rome) hold stories waiting to be discovered beneath centuries of history. Walk through the **Colosseum**, where gladiators once fought, and imagine the roar of *fifty thousand spectators*. Sample the legendary [cacio e pepe](dish://cacio%20e%20pepe) and explore the stunning [Apennine Mountains](landscape://Apennine%20Mountains) nearby.

            As you wander through the city, you'll encounter a variety of landmarks and attractions. [The Colosseum](place://Colosseum) is the largest ancient amphitheatre ever built, and [the Roman Forum](place://Roman%20Forum) is the center of day-to-day life in Rome for centuries.


            ## Key Landmarks

            ### The Colosseum

            Built in **AD 72–80**, the Colosseum is the largest ancient amphitheatre ever built.

            > While the Colosseum stands, Rome shall stand; when the Colosseum falls, Rome shall fall.
            > — *Venerable Bede, 8th century*

            ### The Roman Forum

            The Forum was the center of day-to-day life in Rome for centuries.

            | Detail | Info |
            |--------|------|
            | Best time to visit | Early morning or late afternoon |
            | Duration | Allow 2–3 hours |
            """,
            cards: nil,
            interface: nil
        ))
        ContentBlockView(block: ContentBlock(
            id: "preview2",
            header: .dictionary([
                "overline": .string("FOOD & TRADITION"),
                "headline": .string("The Flavors of Istanbul"),
                "subhead": .string("A Culinary Journey Along the Bosphorus"),
                "feature_img": .string("https://www.istanbul.com/uploads/d/9/0/d909bb89a54038e57e601eacfad19740.jpg")
            ]),
            markdown: """
            Istanbul's cuisine is a living testament to its crossroads location, blending influences from Anatolia, the Mediterranean, and beyond. On bustling streets, you might try flaky [börek](dish://borek) or spicy [menemen](dish://menemen) for breakfast.

            ## Culinary Highlights

            - **Street Food:** Sample crispy simit from a morning vendor on the Galata Bridge.
            - **Seafood:** Dine on grilled fish at a restaurant with views of the Bosphorus.
            - **Markets:** Wander through the Spice Bazaar and breathe in aromas of sumac, saffron, and turmeric.

            ### Experience It Yourself

            > "If one had but a single glance to give the world, one should gaze on Istanbul."  
            > — *Alphonse de Lamartine*

            | Specialty | Where to Find |
            |-----------|---------------|
            | Baklava   | Karaköy Güllüoğlu |
            | Turkish Coffee | Mandabatmaz   |
            """,
            cards: nil,
            interface: nil
        ))
        // .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("Content Block without Header") {
    ScrollView {
        ContentBlockView(block: ContentBlock(
            id: "no-header",
            header: nil,
            markdown: """
            This journey takes you through the **heart of the Roman Empire**, exploring iconic landmarks and hidden gems.

            ## What You'll Discover

            - The Colosseum: An architectural marvel
            - The Forum: The center of Roman public life

            ## Getting Started

            Begin your journey at the Colosseum and follow the path through history.
            """,
            cards: nil,
            interface: nil
        ))
    }
    .background(Color("AppBkgColor"))
}
#endif
