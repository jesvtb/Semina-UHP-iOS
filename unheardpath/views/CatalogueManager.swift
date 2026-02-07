import SwiftUI
import MarkdownUI
import CoreLocation
import core

// MARK: - Catalogue Action
/// Actions for catalogue content handling
enum CatalogueAction: String, Sendable {
    case replace  // Default: Replace entire section content
    case edit     // Merge/patch existing content based on config
}

// MARK: - Catalogue Section
/// A catalogue section with dynamic type and raw JSONValue content
struct CatalogueSection: Identifiable, Sendable {
    let id: String              // Unique ID (from server or generated)
    let sectionType: String     // Dynamic: "overview", "cuisine", "architecture", etc.
    let displayTitle: String    // Tab label (from server or derived)
    let config: JSONValue?      // Optional rendering hints
    var content: JSONValue      // Raw content - no predefined shape (var for edit mutations)
    
    init(id: String = UUID().uuidString, sectionType: String, displayTitle: String, config: JSONValue? = nil, content: JSONValue) {
        self.id = id
        self.sectionType = sectionType
        self.displayTitle = displayTitle
        self.config = config
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
func makeLocationDict(location: CLLocation, placeName: String?, subdivisions: String?, countryName: String?) -> LocationDict {
    var coordDict: [String: JSONValue] = [
        "lat": .double(location.coordinate.latitude),
        "lng": .double(location.coordinate.longitude),
    ]
    if location.verticalAccuracy > 0 { coordDict["alt"] = .double(location.altitude) }
    let locationDict: LocationDict = [
        "coordinate": .dictionary(coordDict),
        "place_name": .string(placeName ?? ""),
        "subdivisions": .string(subdivisions ?? ""),
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
    /// - Parameters:
    ///   - sectionType: The section type string (e.g., "overview", "cuisine", "architecture")
    ///   - displayTitle: The display title for the tab
    ///   - action: The action to perform (replace or edit)
    ///   - config: Optional config for rendering and edit operations
    ///   - content: The content data
    func handleCatalogue(
        sectionType: String,
        displayTitle: String,
        action: CatalogueAction,
        config: JSONValue?,
        content: JSONValue
    ) {
        switch action {
        case .replace:
            replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, config: config, content: content)
        case .edit:
            editCatalogue(sectionType: sectionType, config: config, content: content)
        }
    }
    
    /// Replace: Completely replace section content
    private func replaceCatalogue(sectionType: String, displayTitle: String, config: JSONValue?, content: JSONValue) {
        let section = CatalogueSection(
            sectionType: sectionType,
            displayTitle: displayTitle,
            config: config,
            content: content
        )
        sections[sectionType] = section
        if !sectionOrder.contains(sectionType) {
            sectionOrder.append(sectionType)
        }
    }
    
    /// Edit: Merge/patch existing content based on config
    private func editCatalogue(sectionType: String, config: JSONValue?, content: JSONValue) {
        guard var existingSection = sections[sectionType] else {
            // No existing section - treat as replace with derived title
            let displayTitle = sectionType.replacingOccurrences(of: "_", with: " ").capitalized
            replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, config: config, content: content)
            return
        }
        
        // Apply edit operation based on config
        let operation = config?["operation"]?.stringValue ?? "merge"
        let targetPath = config?["target_path"]?.stringValue
        
        switch operation {
        case "append":
            existingSection.content = appendContent(existing: existingSection.content, new: content, path: targetPath)
        case "remove":
            let match = config?["match"]
            existingSection.content = removeContent(existing: existingSection.content, path: targetPath, match: match)
        default: // "merge"
            existingSection.content = mergeContent(existing: existingSection.content, new: content)
        }
        
        // Update config if provided
        if let newConfig = config {
            existingSection = CatalogueSection(
                id: existingSection.id,
                sectionType: existingSection.sectionType,
                displayTitle: existingSection.displayTitle,
                config: newConfig,
                content: existingSection.content
            )
        }
        
        sections[sectionType] = existingSection
    }
    
    // MARK: - Content Manipulation Helpers
    
    /// Deep merge two JSONValue dictionaries
    private func mergeContent(existing: JSONValue, new: JSONValue) -> JSONValue {
        guard case .dictionary(var existingDict) = existing,
              case .dictionary(let newDict) = new else {
            // If not both dictionaries, new content wins
            return new
        }
        
        for (key, newValue) in newDict {
            if let existingValue = existingDict[key] {
                // Recursive merge for nested dictionaries
                existingDict[key] = mergeContent(existing: existingValue, new: newValue)
            } else {
                existingDict[key] = newValue
            }
        }
        
        return .dictionary(existingDict)
    }
    
    /// Append items to an array at the specified path
    private func appendContent(existing: JSONValue, new: JSONValue, path: String?) -> JSONValue {
        guard let path = path else {
            return mergeContent(existing: existing, new: new)
        }
        
        let pathComponents = path.split(separator: ".").map(String.init)
        return modifyAtPath(existing, pathComponents: pathComponents) { existingValue in
            guard case .array(var existingArray) = existingValue else {
                return existingValue
            }
            
            // Get new items from the same path in new content
            if let newArray = getValueAtPath(new, pathComponents: pathComponents),
               case .array(let newItems) = newArray {
                existingArray.append(contentsOf: newItems)
            }
            
            return .array(existingArray)
        }
    }
    
    /// Remove items from an array at the specified path
    private func removeContent(existing: JSONValue, path: String?, match: JSONValue?) -> JSONValue {
        guard let path = path else {
            return existing
        }
        
        let pathComponents = path.split(separator: ".").map(String.init)
        return modifyAtPath(existing, pathComponents: pathComponents) { existingValue in
            guard case .array(var existingArray) = existingValue else {
                return existingValue
            }
            
            // Remove by index if specified
            if let matchDict = match?.dictionaryValue,
               let indexValue = matchDict["index"],
               let indexDouble = indexValue.doubleValue {
                let index = Int(indexDouble)
                if index >= 0 && index < existingArray.count {
                    existingArray.remove(at: index)
                }
            }
            
            return .array(existingArray)
        }
    }
    
    /// Navigate to a path and modify the value
    private func modifyAtPath(_ value: JSONValue, pathComponents: [String], modifier: (JSONValue) -> JSONValue) -> JSONValue {
        guard !pathComponents.isEmpty else {
            return modifier(value)
        }
        
        guard case .dictionary(var dict) = value else {
            return value
        }
        
        let key = pathComponents[0]
        let remainingPath = Array(pathComponents.dropFirst())
        
        if let existingValue = dict[key] {
            dict[key] = modifyAtPath(existingValue, pathComponents: remainingPath, modifier: modifier)
        }
        
        return .dictionary(dict)
    }
    
    /// Get value at a path
    private func getValueAtPath(_ value: JSONValue, pathComponents: [String]) -> JSONValue? {
        guard !pathComponents.isEmpty else {
            return value
        }
        
        guard case .dictionary(let dict) = value,
              let nextValue = dict[pathComponents[0]] else {
            return nil
        }
        
        return getValueAtPath(nextValue, pathComponents: Array(pathComponents.dropFirst()))
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
    
    /// Clear all catalogue
    func clearAll() {
        sections.removeAll()
        sectionOrder.removeAll()
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
/// Represents a single content block with optional markdown and cards
struct ContentBlock: Identifiable {
    let id: String
    let markdown: String?
    let cards: [JSONValue]?
}

// MARK: - Dynamic Section Renderer
/// Renders catalogue sections using config-driven rendering logic
/// Handles both flat content (direct markdown/cards) and nested content (multiple subsections)
struct DynamicSectionRenderer: View {
    let section: CatalogueSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceM) {
            // Extract content blocks and render each one
            ForEach(extractContentBlocks(from: section.content)) { block in
                ContentBlockView(
                    block: block,
                    markdownConfig: section.config?["markdown"],
                    cardConfig: section.config?["card"]
                )
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
    
    /// Extract content blocks from content
    /// - Flat content: single block with direct markdown/cards
    /// - Nested content: multiple blocks, one per subsection
    private func extractContentBlocks(from content: JSONValue) -> [ContentBlock] {
        guard case .dictionary(let dict) = content else { return [] }
        
        // Check if content is flat (has direct markdown or cards keys)
        let hasDirectMarkdown = dict["markdown"]?.stringValue != nil
        let hasDirectCards: Bool = {
            if let cardsValue = dict["cards"], case .array(let cards) = cardsValue, !cards.isEmpty {
                return true
            }
            return false
        }()
        
        if hasDirectMarkdown || hasDirectCards {
            // Flat content - single block
            let markdown = dict["markdown"]?.stringValue
            let cards: [JSONValue]? = {
                if let cardsValue = dict["cards"], case .array(let cards) = cardsValue {
                    return cards
                }
                return nil
            }()
            return [ContentBlock(id: "root", markdown: markdown, cards: cards)]
        }
        
        // Nested content - extract each subsection as a block
        var blocks: [ContentBlock] = []
        for (key, value) in dict {
            // Skip non-dictionary values (metadata like wikidata_qid at root level)
            guard case .dictionary(let subsectionDict) = value else { continue }
            
            let markdown = subsectionDict["markdown"]?.stringValue
            let cards: [JSONValue]? = {
                if let cardsValue = subsectionDict["cards"], case .array(let cards) = cardsValue {
                    return cards
                }
                return nil
            }()
            
            // Only include if subsection has markdown or cards
            if markdown != nil || cards != nil {
                blocks.append(ContentBlock(id: key, markdown: markdown, cards: cards))
            }
        }
        
        return blocks
    }
}

// MARK: - Content Block View
/// Renders a single content block (markdown + cards)
struct ContentBlockView: View {
    let block: ContentBlock
    let markdownConfig: JSONValue?
    let cardConfig: JSONValue?
    
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
