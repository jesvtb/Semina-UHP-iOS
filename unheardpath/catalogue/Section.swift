import SwiftUI
import core

// MARK: - Catalogue View Registry
/// Creates views for catalogue sections using config-driven rendering
struct CatalogueViewRegistry {
    static func view(for section: CatalogueSection) -> some View {
        DynamicSectionRenderer(section: section)
    }
}

// MARK: - Dynamic Section Renderer
/// Renders catalogue sections using per-item `_metadata.interface` for rendering config.
/// Content items are sorted by `_metadata.location.geoscope` specificity (most local first).
struct DynamicSectionRenderer: View {
    let section: CatalogueSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceM) {
            // Extract content blocks and render each one
            ForEach(extractTopicBlocks(from: section.content)) { block in
                TopicBlockView(block: block)
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
    private func extractTopicBlocks(from content: JSONValue) -> [TopicBlock] {
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
            return [TopicBlock(id: "root", header: header, markdown: markdown, cards: cards, interface: nil)]
        }
        
        // Nested content - extract each topic as a block with interface and geoscope
        var blocks: [(block: TopicBlock, geoLevel: GeoLevel?)] = []
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
                let block = TopicBlock(id: key, header: header, markdown: markdown, cards: cards, interface: itemInterface)
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
