import SwiftUI
import MarkdownUI
import core

// MARK: - Topic Block
/// Represents a single topic block within a catalogue section,
/// with optional header, markdown, cards, and per-item interface config.
struct TopicBlock: Identifiable {
    let id: String
    /// Optional header with overline, headline, subhead, and feature_img fields.
    let header: JSONValue?
    let markdown: String?
    let cards: [JSONValue]?
    /// Per-item rendering config extracted from `_metadata.interface`.
    let interface: JSONValue?
}

// MARK: - Topic Block View
/// Renders a single topic block (markdown + cards).
/// Reads rendering config from the block's per-item `interface` (from `_metadata.interface`).
struct TopicBlockView: View {
    let block: TopicBlock
    
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
            case "sight":
                SightCardContent(cards: cards, config: cardConfig)
            default:
                DynamicCardGrid(cards: cards, config: cardConfig)
            }
        } else {
            // No render_type -> use dynamic card builder with layout config
            DynamicCardGrid(cards: cards, config: cardConfig)
        }
    }
}

// MARK: - Previews
#if DEBUG
#Preview("Topic Block with Header") {
    ScrollView {
        TopicBlockView(block: TopicBlock(
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
        TopicBlockView(block: TopicBlock(
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

#Preview("Topic Block without Header") {
    ScrollView {
        TopicBlockView(block: TopicBlock(
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
