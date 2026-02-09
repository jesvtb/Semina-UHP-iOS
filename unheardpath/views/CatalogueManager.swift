import SwiftUI
import MarkdownUI
import CoreLocation
import core

// MARK: - Catalogue Section
/// A catalogue section with dynamic type and raw JSONValue content.
/// Content items carry their own `_metadata` (geo_scope, interface) per key.
struct CatalogueSection: Identifiable, Sendable {
    let id: String              // Unique ID (from server or generated)
    let sectionType: String     // Dynamic: "overview", "cuisine", "architecture", etc.
    let displayTitle: String    // Tab label (from server or derived)
    var content: JSONValue      // Raw content - keyed items with _metadata per key
    
    init(id: String = UUID().uuidString, sectionType: String, displayTitle: String, content: JSONValue) {
        self.id = id
        self.sectionType = sectionType
        self.displayTitle = displayTitle
        self.content = content
    }
}

// MARK: - Generic Card System

/// A dish card item
struct Dish: Identifiable {
    let localName: String
    let globalName: String
    let description: String
    let imageURL: URL?

    var id: String { "\(localName)|\(globalName)" }
}

/// Enum representing different card types
enum CardItem: Identifiable {
    case dish(Dish)
    case feature(PointFeature)
    
    var id: String {
        switch self {
        case .dish(let dish): return "dish_\(dish.id)"
        case .feature(let feature): return "feature_\(feature.id)"
        }
    }
}

/// Generic section data with markdown intro and cards
struct CardSectionData {
    let markdown: String
    let cards: [CardItem]
}

// MARK: - Card Section View Constants
private let cardCornerRadius: CGFloat = 12
private let cardAspectRatio: CGFloat = 0.85
private let cardMinHeight: CGFloat = 140

// MARK: - Environment Key for Catalogue Popup
/// Controls whether card taps show popups (disabled when sheet is not at full height)
private struct PopupEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isPopupEnabled: Bool {
        get { self[PopupEnabledKey.self] }
        set { self[PopupEnabledKey.self] = newValue }
    }
}

/// View for rendering a section with markdown intro and a collection of cards (dish grid or feature list)
struct CardsCollection: View {
    let data: CardSectionData
    @State private var selectedDish: Dish?
    @Environment(\.isPopupEnabled) private var isPopupEnabled

    private let gridSpacing = Spacing.current.spaceS

    var body: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            // Markdown intro
            if !data.markdown.isEmpty {
                Markdown(data.markdown)
                    .markdownTextStyle(\.text) {
                        ForegroundColor(Color("onBkgTextColor30"))
                    }
            }

            // Render cards based on type
            cardsContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.vertical, Spacing.current.spaceXs)
        .sheet(item: $selectedDish) { dish in
            DishPopupView(dish: dish) {
                selectedDish = nil
            }
        }
    }
    
    @ViewBuilder
    private var cardsContent: some View {
        // Determine card type from first card (all cards in a section are same type)
        if let firstCard = data.cards.first {
            switch firstCard {
            case .dish:
                dishGridContent
            case .feature:
                featureListContent
            }
        }
    }
    
    // MARK: - Dish Grid Layout
    @ViewBuilder
    private var dishGridContent: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width)
            let columnWidth = (availableWidth - gridSpacing) / 2
            let columns = [
                GridItem(.fixed(columnWidth), spacing: gridSpacing),
                GridItem(.fixed(columnWidth), spacing: gridSpacing)
            ]
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(data.cards) { card in
                    if case .dish(let dish) = card {
                        DishCard(dish: dish) {
                            if isPopupEnabled {
                                selectedDish = dish
                            }
                        }
                        .frame(width: columnWidth, height: columnWidth / cardAspectRatio)
                    }
                }
            }
            .frame(width: availableWidth)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: dishGridContentHeight)
    }
    
    private var dishGridContentHeight: CGFloat {
        let dishCount = data.cards.filter { if case .dish = $0 { return true }; return false }.count
        let rowCount = (dishCount + 1) / 2
        guard rowCount > 0 else { return 0 }
        let estimatedColumnWidth: CGFloat = 160
        let rowHeight = estimatedColumnWidth / cardAspectRatio
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * gridSpacing
    }
    
    // MARK: - Feature List Layout
    @ViewBuilder
    private var featureListContent: some View {
        let features = data.cards.compactMap { card -> PointFeature? in
            if case .feature(let feature) = card { return feature }
            return nil
        }
        
        if !features.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    ContentPoiItemView(feature: feature)
                    
                    if index < features.count - 1 {
                        Divider()
                            .background(Color("onBkgTextColor30").opacity(0.3))
                    }
                }
            }
        }
    }
}

/// Card with image background and dish name overlay; tappable to show popup.
struct DishCard: View {
    let dish: Dish
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    cardBackground
                    gradientOverlay
                    textOverlay(cardWidth: geometry.size.width)
                }
            }
            .aspectRatio(cardAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(Color("onBkgTextColor30").opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    @ViewBuilder
    private var cardBackground: some View {
        Group {
            if let imageURL = dish.imageURL {
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
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 36))
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
                            .font(.system(size: 36))
                            .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
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

    private func textOverlay(cardWidth: CGFloat) -> some View {
        let horizontalPadding = Spacing.current.spaceXs * 2
        let maxTextWidth = max(0, cardWidth - horizontalPadding)
        return VStack(alignment: .leading, spacing: 2) {
            Text(dish.localName)
                .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article1.baseSize))
                .foregroundColor(.white)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.5)
            if dish.globalName != dish.localName {
                Text(dish.globalName)
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: maxTextWidth, alignment: .leading)
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.space2xs)
        .clipped()
    }
}

/// Popup presented when a regional dish card is tapped.
struct DishPopupView: View {
    let dish: Dish
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                    if let imageURL = dish.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color("onBkgTextColor30").opacity(0.1))
                                    .frame(height: 220)
                                    .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxHeight: 220)
                                    .clipped()
                            case .failure:
                                Rectangle()
                                    .fill(Color("onBkgTextColor30").opacity(0.1))
                                    .frame(height: 220)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(Color("onBkgTextColor30").opacity(0.5))
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                    }

                    Text(dish.localName)
                        .bodyText(size: .article2)
                        .foregroundColor(Color("onBkgTextColor20"))
                    if dish.globalName != dish.localName {
                        Text(dish.globalName)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor30"))
                    }
                    Text(dish.description)
                        .bodyParagraph(color: Color("onBkgTextColor30"))
                }
                .padding(Spacing.current.spaceS)
            }
            .navigationTitle(dish.localName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}


/// Builds a minimal LocationDict from CLLocation and optional display strings (for previews and tests).
func makeLocationDict(location: CLLocation, placeName: String?, countryName: String?) -> LocationDict {
    var coordDict: [String: JSONValue] = [
        "lat": .double(location.coordinate.latitude),
        "lng": .double(location.coordinate.longitude),
    ]
    if location.verticalAccuracy > 0 { coordDict["alt"] = .double(location.altitude) }
    let locationDict: LocationDict = [
        "coordinate": .dictionary(coordDict),
        "place_name": .string(placeName ?? ""),
        "country_name": .string(countryName ?? ""),
        "timezone": .string(TimeZone.current.identifier),
        "timestamp": .double(location.timestamp.timeIntervalSince1970),
    ]
    return locationDict
}


// MARK: - Catalogue Manager
/// Manages catalogue sections with dynamic types, allowing selective updates and action-based handling
@MainActor
class CatalogueManager: ObservableObject {
    @Published private var sections: [String: CatalogueSection] = [:]
    @Published private(set) var sectionOrder: [String] = []  // Order from server (order of arrival)
    
    /// Current location data for header display (separate from catalogue sections)
    @Published private(set) var locationDetailData: LocationDetailData?
    
    /// Returns sections in display order (server-controlled via arrival order)
    var orderedSections: [CatalogueSection] {
        sectionOrder.compactMap { sections[$0] }
    }
    
    /// Set location data for header display.
    /// The location's `dataSource` property determines whether it's from device GPS or lookup.
    func setLocationData(_ locationData: LocationDetailData) {
        self.locationDetailData = locationData
    }
    
    /// Handle catalogue update with action
    /// Upsert catalogue content by key.
    ///
    /// - If the section already exists: merge incoming keyed items into the existing content dictionary.
    ///   Existing keys are replaced; new keys are inserted.
    /// - If the section does not exist: create it with the given content.
    ///
    /// - Parameters:
    ///   - sectionType: The section type string (e.g., "overview", "cuisine", "architecture")
    ///   - displayTitle: The display title for the tab
    ///   - content: The content data (dictionary of keyed items, each optionally carrying `_metadata`)
    func handleCatalogue(
        sectionType: String,
        displayTitle: String,
        content: JSONValue
    ) {
        guard case .dictionary(let contentDict) = content else {
            // Non-dictionary content: replace wholesale
            replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, content: content)
            return
        }

        if var existing = sections[sectionType] {
            // Upsert: merge items by key into existing section content
            guard case .dictionary(var existingDict) = existing.content else {
                replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, content: content)
                return
            }
            for (key, value) in contentDict {
                existingDict[key] = value  // insert or replace by key
            }
            existing.content = .dictionary(existingDict)
            sections[sectionType] = existing
        } else {
            // New section
            replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, content: content)
        }
    }
    
    /// Replace: Set section content from scratch.
    private func replaceCatalogue(sectionType: String, displayTitle: String, content: JSONValue) {
        let section = CatalogueSection(
            sectionType: sectionType,
            displayTitle: displayTitle,
            content: content
        )
        sections[sectionType] = section
        if !sectionOrder.contains(sectionType) {
            sectionOrder.append(sectionType)
        }
    }
    
    /// Remove catalogue by type
    func removeCatalogue(sectionType: String) {
        sections.removeValue(forKey: sectionType)
        sectionOrder.removeAll { $0 == sectionType }
    }
    
    /// Check if catalogue exists for a type
    func hasCatalogue(sectionType: String) -> Bool {
        sections[sectionType] != nil
    }
    
    /// Get catalogue for a specific type
    func getCatalogue(sectionType: String) -> CatalogueSection? {
        sections[sectionType]
    }
    
    /// Remove catalogue items whose `_metadata.geo_scope` no longer applies to the new location.
    ///
    /// Compares the current `locationDetailData` (old) with `newLocation` to find the highest
    /// geographic level where the two locations diverge. All catalogue items scoped at or more
    /// specific than that divergence point are pruned, while shared higher-level content is kept.
    ///
    /// **Example — Shenzhen → Shanghai (same country, different admin area):**
    /// - `country` keys match → country-scoped items (e.g. "Chinese cuisine") are kept.
    /// - `adminarea` keys differ → adminarea/locality/sublocality items (e.g. "Cantonese cuisine") are removed.
    ///
    /// Call this **before** `setLocationData(_:)` and SSE stream processing so that the old
    /// location reference is still available for comparison.
    func pruneStaleItems(forNewLocation newLocation: LocationDetailData) {
        guard let oldLocation = locationDetailData else {
            // No previous location context — clear everything for a clean slate
            clearAll()
            return
        }

        let oldKeyMap = Dictionary(
            uniqueKeysWithValues: StorageKey.applicableLevels(from: oldLocation).map { ($0.level, $0.key) }
        )
        let newKeyMap = Dictionary(
            uniqueKeysWithValues: StorageKey.applicableLevels(from: newLocation).map { ($0.level, $0.key) }
        )

        // Walk from most general to most specific. Once a level diverges,
        // that level and every more-specific level is considered stale.
        var staleLevels = Set<GeoLevel>()
        for level in GeoLevel.allCases {
            if !staleLevels.isEmpty || oldKeyMap[level] != newKeyMap[level] {
                staleLevels.insert(level)
            }
        }

        guard !staleLevels.isEmpty else { return }  // Identical location — nothing to prune

        // Collect section types to remove (sections that become empty after pruning)
        var sectionsToRemove: [String] = []

        for (sectionType, section) in sections {
            guard case .dictionary(var contentDict) = section.content else { continue }
            var modified = false

            for (key, value) in contentDict {
                if key.hasPrefix("_") { continue }  // Preserve root-level metadata keys

                let itemLevel: GeoLevel? = {
                    guard case .dictionary(let itemDict) = value,
                          case .dictionary(let meta) = itemDict["_metadata"],
                          let scopeStr = meta["geo_scope"]?.stringValue else { return nil }
                    return GeoLevel(identifier: scopeStr)
                }()

                // Remove if the item's scope is stale, or if it has no scope (conservative —
                // unscoped items may be location-specific and cannot be verified).
                if itemLevel == nil || staleLevels.contains(itemLevel!) {
                    contentDict.removeValue(forKey: key)
                    modified = true
                }
            }

            if modified {
                // Filter out root-level metadata to check if real content remains
                let hasRealContent = contentDict.contains { !$0.key.hasPrefix("_") }
                if !hasRealContent {
                    sectionsToRemove.append(sectionType)
                } else {
                    var updated = section
                    updated.content = .dictionary(contentDict)
                    sections[sectionType] = updated
                }
            }
        }

        for sectionType in sectionsToRemove {
            removeCatalogue(sectionType: sectionType)
        }
    }

    /// Clear all catalogue
    func clearAll() {
        sections.removeAll()
        sectionOrder.removeAll()
    }
    
    // MARK: - Persistence
    
    /// Optional persistence backend. Set via `setPersistence(_:)` during app initialization.
    private var persistence: (any CataloguePersisting)?
    
    /// Inject the persistence backend. Called once during app setup.
    func setPersistence(_ persistence: any CataloguePersisting) {
        self.persistence = persistence
    }
    
    /// Persist the current in-memory catalogue state for a given location.
    /// Called after SSE stream processing completes for a location event.
    func persistCurrentState(for location: LocationDetailData) {
        guard let persistence = persistence else { return }
        let currentSections = orderedSections.map { section in
            CachedSection(
                sectionType: section.sectionType,
                displayTitle: section.displayTitle,
                content: section.content
            )
        }
        guard !currentSections.isEmpty else { return }
        let order = sectionOrder
        Task {
            do {
                try await persistence.persist(sections: currentSections, sectionOrder: order, location: location)
            } catch {
                #if DEBUG
                print("⚠️ CatalogueManager: Failed to persist catalogue: \(error)")
                #endif
            }
        }
    }
    
    /// Restore cached catalogue sections for a known location.
    /// Called on app launch when EventManager has a last-known location.
    /// Only restores into empty sections (does not overwrite live SSE data).
    func restoreFromCache(for location: LocationDetailData) async {
        guard let persistence = persistence else { return }
        guard sections.isEmpty else { return }
        
        do {
            let cached = try await persistence.restore(for: location)
            for section in cached where !hasCatalogue(sectionType: section.sectionType) {
                handleCatalogue(
                    sectionType: section.sectionType,
                    displayTitle: section.displayTitle,
                    content: section.content
                )
            }
            // Restore the location for header display
            if locationDetailData == nil {
                setLocationData(location)
            }
        } catch {
            #if DEBUG
            print("⚠️ CatalogueManager: Failed to restore catalogue for location: \(error)")
            #endif
        }
    }
    
    /// Restore the last active catalogue context (no location needed).
    /// Fallback for app launch when no location is available yet.
    func restoreFromCache() async {
        guard let persistence = persistence else { return }
        guard sections.isEmpty else { return }
        
        do {
            guard let result = try await persistence.restoreLastContext() else { return }
            for section in result.sections where !hasCatalogue(sectionType: section.sectionType) {
                handleCatalogue(
                    sectionType: section.sectionType,
                    displayTitle: section.displayTitle,
                    content: section.content
                )
            }
            // Also restore the location summary for header display
            let restoredLocation = result.snapshot.locationSummary.toLocationDetailData()
            if locationDetailData == nil {
                self.locationDetailData = restoredLocation
            }
        } catch {
            #if DEBUG
            print("⚠️ CatalogueManager: Failed to restore last catalogue context: \(error)")
            #endif
        }
    }
}

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
                DishCardGrid(cards: cards, config: cardConfig)
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
    
    var body: some View {
        Markdown(markdown)
            .markdownTextStyle(\.text) {
                ForegroundColor(Color("onBkgTextColor30"))
            }
    }
}

// MARK: - Dish Card Grid (render_type: "dish")
/// Renders dish cards with strict key contract: local_name, global_name, description, img_url
struct DishCardGrid: View {
    let cards: [JSONValue]
    let config: JSONValue?
    @State private var selectedDish: Dish?
    @Environment(\.isPopupEnabled) private var isPopupEnabled
    
    private var aspectRatio: CGFloat {
        config?["aspectRatio"]?.doubleValue.map { CGFloat($0) } ?? 0.85
    }
    
    private var columnCount: Int {
        config?["inColsofCount"]?.doubleValue.map { Int($0) } ?? 2
    }
    
    private let gridSpacing = Spacing.current.spaceS
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width)
            let columnWidth = (availableWidth - gridSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            let columns = Array(repeating: GridItem(.fixed(columnWidth), spacing: gridSpacing), count: columnCount)
            
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(parsedDishes) { dish in
                    DishCard(dish: dish) {
                        if isPopupEnabled {
                            selectedDish = dish
                        }
                    }
                    .frame(width: columnWidth, height: columnWidth / aspectRatio)
                }
            }
            .frame(width: availableWidth)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: gridContentHeight)
        .sheet(item: $selectedDish) { dish in
            DishPopupView(dish: dish) {
                selectedDish = nil
            }
        }
    }
    
    private var parsedDishes: [Dish] {
        cards.compactMap { card -> Dish? in
            guard case .dictionary(let dict) = card else { return nil }
            guard let localName = dict["local_name"]?.stringValue,
                  let globalName = dict["global_name"]?.stringValue,
                  let description = dict["description"]?.stringValue else {
                return nil
            }
            let imageURL = dict["img_url"]?.stringValue.flatMap { URL(string: $0) }
            return Dish(localName: localName, globalName: globalName, description: description, imageURL: imageURL)
        }
    }
    
    private var gridContentHeight: CGFloat {
        let dishCount = parsedDishes.count
        let rowCount = (dishCount + columnCount - 1) / columnCount
        guard rowCount > 0 else { return 0 }
        let estimatedColumnWidth: CGFloat = 160
        let rowHeight = estimatedColumnWidth / aspectRatio
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * gridSpacing
    }
}

// MARK: - Feature Card List (render_type: "feature")
/// Renders feature cards with strict GeoJSON key contract
struct FeatureCardList: View {
    let cards: [JSONValue]
    let config: JSONValue?
    
    var body: some View {
        let features = parsedFeatures
        
        if !features.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    ContentPoiItemView(feature: feature)
                    
                    if index < features.count - 1 {
                        Divider()
                            .background(Color("onBkgTextColor30").opacity(0.3))
                    }
                }
            }
        }
    }
    
    private var parsedFeatures: [PointFeature] {
        cards.compactMap { card -> PointFeature? in
            guard case .dictionary(let dict) = card else { return nil }
            return PointFeature(from: dict)
        }
    }
}

// MARK: - Dynamic Card Grid (no render_type)
/// Renders cards dynamically using layout config and flexible key conventions
/// Config options:
/// - `inColsofCount`: Number of columns (default: 2)
/// - `colGap`: Horizontal gap between columns (default: Spacing.current.spaceS)
/// - `rowGap`: Vertical gap between rows (default: Spacing.current.spaceS)
/// - `aspectRatio`: Card width/height ratio (default: 0.85, meaning height > width)
struct DynamicCardGrid: View {
    let cards: [JSONValue]
    let config: JSONValue?
    
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
                    GenericCard(data: cards[index])
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

// MARK: - Generic Card
/// A generic card view that uses flexible key conventions
/// Fills available space - parent determines dimensions
struct GenericCard: View {
    let data: JSONValue
    
    private let cardCornerRadius: CGFloat = 12
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardBackground
            gradientOverlay
            textOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
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
                Text(primary)
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article1.baseSize))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.5)
            }
            if let secondary = secondaryText {
                Text(secondary)
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.space2xs)
    }
}

// MARK: - Overview View
struct OverviewView: View {
    let markdown: String
    
    var body: some View {
        // Use MarkdownUI with default theme for now
        // Custom font styling can be applied via view modifiers if needed
        Markdown(markdown)
            .padding(.vertical, Spacing.current.spaceXs)
    }
}

// MARK: - Location Detail View
// MARK: - Content POI Item View
struct ContentPoiItemView: View {
    let feature: PointFeature
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
            // Image at the top if available
            if let imageURL = feature.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        // Placeholder while loading
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.1))
                            .frame(height: 200)
                            .overlay(
                                ProgressView()
                                    .tint(Color("onBkgTextColor30"))
                            )
                            .cornerRadius(Spacing.current.spaceXs)
                    case .success(let image):
                        ZStack {
                            // Base image
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: 200)
                                .clipped()
                            
                            // Gradient overlay for brand consistency
                            // Creates a subtle blend that makes images look cohesive
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color("AppBkgColor").opacity(0.0),  // Transparent at top
                                    Color("AppBkgColor").opacity(0.3), // Slight blend in middle
                                    Color("AppBkgColor").opacity(0.5)  // More blend at bottom
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .blendMode(.overlay)  // Blend mode for natural color mixing
                        }
                        .cornerRadius(Spacing.current.spaceXs)
                        .overlay(
                            // Subtle border for definition
                            RoundedRectangle(cornerRadius: Spacing.current.spaceXs)
                                .stroke(Color("onBkgTextColor30").opacity(0.1), lineWidth: 1)
                        )
                    case .failure:
                        // Error state - show placeholder
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.1))
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(Color("onBkgTextColor30").opacity(0.5))
                            )
                            .cornerRadius(Spacing.current.spaceXs)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            if let title = feature.title {
                DisplayText(title, scale: .article2, color: Color("onBkgTextColor20"))
            }
            
            if let description = feature.description {
                Text(description)
                    .bodyParagraph(color: Color("onBkgTextColor30"))
            }
            
            if let coordinate = feature.clCoordinate {
                Text("📍 \(coordinate.latitude, specifier: "%.6f"), \(coordinate.longitude, specifier: "%.6f")")
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor30"))
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
}

// MARK: - Content POI List View
struct ContentPoiListView: View {
    let features: [PointFeature]
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            DisplayText("Points of Interest", scale: .article2, color: Color("onBkgTextColor20"))
            
            // Use index as id so duplicate coordinates (same poi_ lat_lon) don't cause ForEach warnings
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                ContentPoiItemView(feature: feature)
                
                // Show divider if not the last item
                if index < features.count - 1 {
                    Divider()
                        .background(Color("onBkgTextColor30").opacity(0.3))
                }
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
}

// MARK: - Heritage View (Architecture Section)

// MARK: - PointFeature Description Extension
extension PointFeature {
    /// Extract description with priority: short_description > wikipedia.extract
    var description: String? {
        guard let properties = properties else { return nil }
        
        // First, try short_description
        if let shortDescriptionValue = properties["short_description"],
           let shortDescription = shortDescriptionValue.stringValue,
           !shortDescription.isEmpty {
            return shortDescription
        }
        
        // Fall back to wikipedia.extract
        if let wikipediaValue = properties["wikipedia"],
           let wikipedia = wikipediaValue.dictionaryValue,
           let extractValue = wikipedia["extract"],
           let extract = extractValue.stringValue,
           !extract.isEmpty {
            return extract
        }
        
        return nil
    }
}

// MARK: - POI Extraction Helper
/// Helper function to extract POI data from GeoJSON features
func extractPOIs(from geoJSON: GeoJSON) -> [PointFeature] {
    return geoJSON.features.compactMap { feature -> PointFeature? in
        PointFeature(from: feature)
    }
}

// MARK: - Previews
#if DEBUG
#Preview("Overview View") {
    ScrollView {
        OverviewView(markdown: """
        # Welcome to Ancient Rome
        
        This journey takes you through the **heart of the Roman Empire**, exploring iconic landmarks and hidden gems.
        
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
        """)
        .padding()
    }
    .background(Color("AppBkgColor"))
}


#Preview("POI Item View") {
    ScrollView {
        if let feature = createMockPointFeature() {
            ContentPoiItemView(feature: feature)
                .padding()
        }
    }
    .background(Color("AppBkgColor"))
}

#Preview("POI List View") {
    ScrollView {
        let features = [
            createMockPointFeature(name: "The Colosseum", description: "An elliptical amphitheatre in the centre of the city of Rome, Italy."),
            createMockPointFeature(name: "The Roman Forum", description: "A rectangular forum surrounded by the ruins of several important ancient government buildings."),
            createMockPointFeature(name: "The Pantheon", description: "A former Roman temple and, since AD 609, a Catholic church in Rome, Italy.")
        ].compactMap { $0 }
        
        ContentPoiListView(features: features)
            .padding()
    }
    .background(Color("AppBkgColor"))
}

// Helper function to create mock PointFeature for previews
private func createMockPointFeature(name: String = "The Colosseum", description: String = "An elliptical amphitheatre in the centre of the city of Rome, Italy.") -> PointFeature? {
    let feature: [String: JSONValue] = [
        "type": .string("Feature"),
        "geometry": .dictionary([
            "type": .string("Point"),
            "coordinates": .array([.double(12.4964), .double(41.9028)])
        ]),
        "properties": .dictionary([
            "names": .dictionary([
                "device_lang": .string(name)
            ]),
            "short_description": .string(description)
        ])
    ]
    return PointFeature(from: feature)
}
#endif
