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
/// Represents a single content block with optional markdown, cards, and per-item interface config.
struct ContentBlock: Identifiable {
    let id: String
    let markdown: String?
    let cards: [JSONValue]?
    /// Per-item rendering config extracted from `_metadata.interface`.
    let interface: JSONValue?
}

// MARK: - Dynamic Section Renderer
/// Renders catalogue sections using per-item `_metadata.interface` for rendering config.
/// Content items are sorted by `_metadata.geo_scope` specificity (most local first).
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
    
    /// Extract content blocks from content, reading `_metadata` per item for interface config and geo_scope ordering.
    ///
    /// - Flat content (direct markdown/cards at root level): single block with no interface.
    /// - Nested content (keyed items): one block per subsection, sorted by geo_scope specificity (most specific first).
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
            let markdown = dict["markdown"]?.stringValue
            let cards: [JSONValue]? = {
                if let cardsValue = dict["cards"], case .array(let cards) = cardsValue {
                    return cards
                }
                return nil
            }()
            return [ContentBlock(id: "root", markdown: markdown, cards: cards, interface: nil)]
        }
        
        // Nested content - extract each subsection as a block with interface and geo_scope
        var blocks: [(block: ContentBlock, geoLevel: GeoLevel?)] = []
        for (key, value) in rawDict {
            // Skip metadata keys at root level
            if key.hasPrefix("_") { continue }
            // Skip non-dictionary values
            guard case .dictionary(let subsectionDict) = value else { continue }
            
            // Extract _metadata before stripping
            let metadata = subsectionDict["_metadata"]
            let itemInterface = metadata?["interface"]
            let geoScopeStr = metadata?["geo_scope"]?.stringValue
            let geoLevel = geoScopeStr.flatMap { GeoLevel(identifier: $0) }
            
            // Strip metadata from the subsection for rendering
            let cleaned = value.strippingMetadataKeys
            guard case .dictionary(let cleanedDict) = cleaned else { continue }
            
            let markdown = cleanedDict["markdown"]?.stringValue
            let cards: [JSONValue]? = {
                if let cardsValue = cleanedDict["cards"], case .array(let cards) = cardsValue {
                    return cards
                }
                return nil
            }()
            
            // Only include if subsection has markdown or cards
            if markdown != nil || cards != nil {
                let block = ContentBlock(id: key, markdown: markdown, cards: cards, interface: itemInterface)
                blocks.append((block, geoLevel))
            }
        }
        
        // Sort by geo_scope specificity: most specific (highest rawValue) first.
        // Items without geo_scope go to the end.
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
            // Render markdown if present
            if let markdown = block.markdown, !markdown.isEmpty {
                MarkdownRenderer(markdown: markdown, config: markdownConfig)
            }
            
            // Render cards if present
            if let cards = block.cards, !cards.isEmpty {
                cardRenderer(cards: cards)
            }
        }
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

// MARK: - Markdown Renderer
struct MarkdownRenderer: View {
    let markdown: String
    let config: JSONValue?

    private var emColor: Color {
        Color("onBkgTextColor20")
    }
    
    var body: some View {
        Markdown(markdown)
            .markdownTextStyle(\.text) {
                MarkdownUI.FontFamily(.custom(unheardpath.FontFamily.sansRegular))
                MarkdownUI.FontSize(TypographyScale.article0.baseSize)
                ForegroundColor(Color("onBkgTextColor30"))
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontFamily(.custom(unheardpath.FontFamily.serifItalic))
                        MarkdownUI.FontWeight(.bold)
                        MarkdownUI.FontSize(TypographyScale.article3.baseSize)
                        ForegroundColor(Color("onBkgTextColor20"))
                    }
                    .markdownMargin(top: Spacing.current.spaceL, bottom: Spacing.current.spaceL)
                }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontFamily(.custom(unheardpath.FontFamily.serifDisplay))
                        MarkdownUI.FontSize(TypographyScale.article2.baseSize)
                        ForegroundColor(Color("onBkgTextColor20"))
                    }
                    .markdownMargin(top: Spacing.current.spaceL, bottom: Spacing.current.spaceXs)
                }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontWeight(.bold)
                    }
                }
            .markdownTextStyle(\.strong) {
                MarkdownUI.FontWeight(.bold)
                MarkdownUI.ForegroundColor(emColor)
                }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                .markdownTextStyle {
                    MarkdownUI.FontFamily(.custom(unheardpath.FontFamily.sansRegular))
                    MarkdownUI.FontSize(TypographyScale.article0.baseSize)
                    ForegroundColor(Color("onBkgTextColor30"))
                }
                .markdownMargin(top: Spacing.current.spaceXs, bottom: Spacing.current.spaceXs)
                }
            }
}



// MARK: - Previews
#if DEBUG
#Preview("Overview View") {
    ScrollView {
        MarkdownRenderer(markdown: """
        # Welcome to Ancient Rome
        
        This journey takes you through the **heart of the Roman Empire**, exploring iconic landmarks and hidden gems. Consequat penatibus at ridiculus inceptos auctor sit vehicula rhoncus vestibulum, enim quam quis ornare ullamcorper molestie fames. Netus augue purus aenean mus rhoncus ornare montes sapien urna mattis primis odio nullam convallis varius dictum dignissim, etiam inceptos neque aliquet pharetra mauris felis sed magnis congue lorem libero erat condimentum ante nec.

        A molestie ultrices commodo tincidunt bibendum gravida ante congue, nam lorem efficitur dignissim lacinia amet potenti eleifend nisl, accumsan ac blandit scelerisque pharetra dictumst natoque. Pretium praesent venenatis porta quisque fames dictum sit arcu aliquet sapien elit ad est, elementum porttitor faucibus facilisis felis phasellus ac rhoncus maximus neque ut fermentum.

        
        ![Rome Colosseum](https://upload.wikimedia.org/wikipedia/commons/thumb/d/de/Colosseo_2020.jpg/1280px-Colosseo_2020.jpg)

        ## What You'll Discover
        
        - The Colosseum: An architectural marvel
        - The Forum: The center of Roman public life
        - [The Pantheon](https://en.wikipedia.org/wiki/Pantheon,_Rome): A temple to all gods
        
        ## Getting Started
        
        Begin your journey at the Colosseum and follow the path through history.
        
        ```swift
        let journey = Journey(name: "Ancient Rome")
        journey.start()
        ```
        
        Enjoy your exploration!
        """, config: nil)
        .padding()
    }
    .background(Color("AppBkgColor"))
}
#endif
