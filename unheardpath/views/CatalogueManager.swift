import SwiftUI
import MarkdownUI
import CoreLocation
import core

// MARK: - Catalogue Section Type
enum CatalogueSectionType: String, CaseIterable, Sendable {
    case overview
    case cuisine
    case architecture

    /// Tab bar title for section tabs.
    var sectionTabTitle: String {
        switch self {
        case .overview:
            return "Overview"
        case .cuisine:
            return "Cuisine"
        case .architecture:
            return "Architecture"
        }
    }
}

// MARK: - Catalogue Type Definition Protocol
/// Protocol that defines all metadata and behavior for a catalogue type
/// Each catalogue type conforms to this protocol, consolidating parsing, view creation, and type information
/// Sendable because all conforming types are value types (structs) with only static methods
protocol CatalogueTypeDefinition: Sendable {
    static var type: CatalogueSectionType { get }
    
    /// Parse raw data from SSE event into CatalogueSectionData
    static func parse(from dataValue: Any) -> CatalogueSection.CatalogueSectionData?
    
    /// Create SwiftUI view from CatalogueSectionData
    static func createView(for data: CatalogueSection.CatalogueSectionData) -> AnyView
}

// MARK: - Catalogue Type Registry
/// Centralized registry for all catalogue types
/// Provides parsing, view creation, and display order management
/// 
/// Concurrency Safety (Swift 6):
/// - All stored properties are `let` (immutable after initialization)
/// - CatalogueTypeDefinition protocol is Sendable
/// - CatalogueSectionType enum is Sendable
/// - Dictionary key/value types are Sendable
/// - Registry is only written during initialization, then only read
/// 
/// Note: Using @unchecked Sendable because Swift 6 cannot automatically verify
/// that existential metatypes (`any CatalogueTypeDefinition.Type`) are Sendable,
/// even though the protocol is Sendable. This is safe because:
/// 1. Metatypes themselves are value types (no mutable state)
/// 2. All conforming types are structs (value types) with only static methods
/// 3. The dictionary is immutable after initialization
/// 4. All access is read-only after initialization
final class CatalogueTypeRegistry: @unchecked Sendable {
    private let definitions: [CatalogueSectionType: any CatalogueTypeDefinition.Type]
    
    /// Display order defined as ordered array - easy to reorder by moving items!
    let displayOrder: [CatalogueSectionType] = [
        .overview,
        .cuisine,
        .architecture
    ]
    
    fileprivate init() {
        var tempDefinitions: [CatalogueSectionType: any CatalogueTypeDefinition.Type] = [:]
        
        tempDefinitions[.overview] = OverviewCatalogueType.self
        tempDefinitions[.cuisine] = CuisineCatalogueType.self
        tempDefinitions[.architecture] = ArchitectureCatalogueType.self
        
        self.definitions = tempDefinitions
    }
    
    /// Parse catalogue data from raw SSE event data
    /// Must be called from @MainActor context (used by SSEEventProcessor)
    @MainActor
    func parse(type: CatalogueSectionType, dataValue: Any) -> CatalogueSection.CatalogueSectionData? {
        definitions[type]?.parse(from: dataValue)
    }
    
    /// Create SwiftUI view for a catalogue section
    /// Can be called from any context (used by SwiftUI view builders)
    func createView(for section: CatalogueSection) -> AnyView {
        definitions[section.type]?.createView(for: section.data) ?? AnyView(EmptyView())
    }
}

// Global shared instance - safe because CatalogueTypeRegistry is @unchecked Sendable
// and all properties are immutable after initialization
private let _catalogueTypeRegistry = CatalogueTypeRegistry()

extension CatalogueTypeRegistry {
    /// Access the shared registry instance
    /// 
    /// Swift 6 Concurrency: Using a function instead of a static property
    /// to avoid static property concurrency warnings. The registry is safe for
    /// concurrent access because:
    /// 1. It's @unchecked Sendable (immutable after init)
    /// 2. All stored properties are `let`
    /// 3. Only read operations after initialization
    nonisolated static func shared() -> CatalogueTypeRegistry {
        _catalogueTypeRegistry
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

/// Generic view for rendering card sections with markdown intro and cards
struct CardSectionView: View {
    let data: CardSectionData
    @State private var selectedDish: Dish?

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
                            selectedDish = dish
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

// MARK: - Catalogue Type Definitions

/// Overview catalogue type definition
/// Parses content with nested markdown sections (territoryToday, localityToday, etc.)
struct OverviewCatalogueType: CatalogueTypeDefinition {
    static var type: CatalogueSectionType { .overview }
    
    static func parse(from dataValue: Any) -> CatalogueSection.CatalogueSectionData? {
        guard let contentDict = dataValue as? [String: Any] else {
            return nil
        }
        
        // Collect markdown from all sections in order
        var markdownParts: [String] = []
        let sectionKeys = ["territoryToday", "territoryHistory", "localityToday", "localityHistory", "neighborhoodToday", "neighborhoodHistory"]
        
        for key in sectionKeys {
            if let section = contentDict[key] as? [String: Any],
               let markdown = section["markdown"] as? String,
               !markdown.isEmpty {
                markdownParts.append(markdown)
            }
        }
        
        guard !markdownParts.isEmpty else {
            return nil
        }
        
        return .overview(markdown: markdownParts.joined(separator: "\n\n"))
    }
    
    static func createView(for data: CatalogueSection.CatalogueSectionData) -> AnyView {
        if case .overview(let markdown) = data {
            return AnyView(OverviewView(markdown: markdown))
        }
        return AnyView(EmptyView())
    }
}

/// Cuisine catalogue type definition
/// Parses content.regionalCuisine with "markdown" and "cards" keys
struct CuisineCatalogueType: CatalogueTypeDefinition {
    static var type: CatalogueSectionType { .cuisine }
    
    static func parse(from dataValue: Any) -> CatalogueSection.CatalogueSectionData? {
        guard let contentDict = dataValue as? [String: Any],
              let cuisineDict = contentDict["regionalCuisine"] as? [String: Any] else {
            return nil
        }
        
        // "markdown" key for intro text
        let markdown = cuisineDict["markdown"] as? String ?? ""
        
        // "cards" key for dish cards
        var cards: [CardItem] = []
        if let cardsArray = cuisineDict["cards"] as? [[String: Any]] {
            cards = cardsArray.compactMap { dict -> CardItem? in
                guard let localName = dict["local_name"] as? String,
                      let globalName = dict["global_name"] as? String,
                      let description = dict["description"] as? String else {
                    return nil
                }
                let imageURLString = dict["image_url"] as? String
                let imageURL = imageURLString.flatMap { URL(string: $0) }
                let dish = Dish(
                    localName: localName,
                    globalName: globalName,
                    description: description,
                    imageURL: imageURL
                )
                return .dish(dish)
            }
        }
        
        return .cardSection(data: CardSectionData(markdown: markdown, cards: cards))
    }
    
    static func createView(for data: CatalogueSection.CatalogueSectionData) -> AnyView {
        if case .cardSection(let sectionData) = data {
            return AnyView(CardSectionView(data: sectionData))
        }
        return AnyView(EmptyView())
    }
}

/// Architecture catalogue type definition
/// Parses content.heritage with "markdown" and "cards" keys
struct ArchitectureCatalogueType: CatalogueTypeDefinition {
    static var type: CatalogueSectionType { .architecture }
    
    static func parse(from dataValue: Any) -> CatalogueSection.CatalogueSectionData? {
        guard let contentDict = dataValue as? [String: Any],
              let heritageDict = contentDict["heritage"] as? [String: Any] else {
            return nil
        }
        
        // "markdown" key for intro text
        let markdown = heritageDict["markdown"] as? String ?? ""
        
        // "cards" key for heritage site cards (GeoJSON features)
        var cards: [CardItem] = []
        if let cardsArray = heritageDict["cards"] as? [[String: Any]] {
            cards = cardsArray.compactMap { dict -> CardItem? in
                guard let jsonValue = JSONValue(from: dict) else { return nil }
                guard case .dictionary(let featureDict) = jsonValue else { return nil }
                guard let feature = PointFeature(from: featureDict) else { return nil }
                return .feature(feature)
            }
        }
        
        return .cardSection(data: CardSectionData(markdown: markdown, cards: cards))
    }
    
    static func createView(for data: CatalogueSection.CatalogueSectionData) -> AnyView {
        if case .cardSection(let sectionData) = data {
            return AnyView(CardSectionView(data: sectionData))
        }
        return AnyView(EmptyView())
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

// MARK: - Location Detail Data Display Extensions
/// Extends core's LocationDetailData with display helper computed properties for UI
extension LocationDetailData {
    /// Parsed subdivisions array (split by comma and trimmed)
    private var subdivisionsParts: [String] {
        subdivisions?
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
    }
    
    /// Computes header text from location metadata (full: placeName, subdivisions, countryName)
    var headerText: String {
        var parts: [String] = []
        if let placeName = placeName, !placeName.isEmpty {
            parts.append(placeName)
        }
        if let subdivisions = subdivisions, !subdivisions.isEmpty {
            parts.append(subdivisions)
        }
        if let countryName = countryName, !countryName.isEmpty {
            parts.append(countryName)
        }
        return parts.isEmpty ? "Journey Content" : parts.joined(separator: ", ")
    }
    
    /// Computes the DisplayText content (smallest regions, up to 2 items)
    /// Used for the main header display in InfoSheet
    var displayText: String {
        // Take first 2 items from subdivisions for DisplayText
        let displayParts = Array(subdivisionsParts.prefix(2))
        
        if !displayParts.isEmpty {
            return displayParts.joined(separator: ", ")
        }
        
        // Fallback: if no subdivisions, use place name if available
        if let placeName = placeName, !placeName.isEmpty {
            return placeName
        }
        
        return "Journey Catalogue"
    }
    
    /// Computes the body text content (remaining subdivisions + country name)
    /// Used for secondary header text in InfoSheet
    var bodyText: String? {
        // Get remaining subdivisions (after first 2)
        let remainingSubdivisions = Array(subdivisionsParts.dropFirst(2))
        
        // Build body text parts
        var bodyParts: [String] = []
        
        // Add remaining subdivisions
        if !remainingSubdivisions.isEmpty {
            bodyParts.append(contentsOf: remainingSubdivisions)
        }
        
        // Add country name if available
        if let countryName = countryName, !countryName.isEmpty {
            bodyParts.append(countryName)
        }
        
        // Return joined body parts if we have any
        return bodyParts.isEmpty ? nil : bodyParts.joined(separator: ", ")
    }
}

// MARK: - Catalogue Section
struct CatalogueSection: Identifiable {
    // Use type as stable ID - each type appears at most once
    // This prevents SwiftUI from recreating views when parent state changes
    var id: String { type.rawValue }
    let type: CatalogueSectionType
    let data: CatalogueSectionData
    
    enum CatalogueSectionData {
        case overview(markdown: String)
        case cardSection(data: CardSectionData)
    }
    
    init(type: CatalogueSectionType, data: CatalogueSectionData) {
        self.type = type
        self.data = data
    }
}

// MARK: - Catalogue Manager
/// Manages catalogue sections by type, allowing selective updates
@MainActor
class CatalogueManager: ObservableObject {
    @Published private var sections: [CatalogueSectionType: CatalogueSection] = [:]
    
    /// Current location data for header display (separate from catalogue sections)
    @Published private(set) var locationDetailData: LocationDetailData?
    
    /// Tracks whether the current location is from device location (true) or lookup/search location (false)
    @Published var isCatalogueFromDeviceLocation: Bool = true
    
    /// Returns sections in display order (from CatalogueTypeRegistry)
    var orderedSections: [CatalogueSection] {
        CatalogueTypeRegistry.shared().displayOrder.compactMap { type in
            sections[type]
        }
    }
    
    /// Set location data for header display
    /// - Parameters:
    ///   - locationData: The location detail data
    ///   - isFromDeviceLocation: Whether location is from device (true) or lookup/search (false)
    func setLocationData(_ locationData: LocationDetailData, isFromDeviceLocation: Bool) {
        self.locationDetailData = locationData
        self.isCatalogueFromDeviceLocation = isFromDeviceLocation
    }
    
    /// Set or update catalogue by type
    /// - Parameters:
    ///   - type: The catalogue view type to set
    ///   - data: The catalogue section data
    func setCatalogue(type: CatalogueSectionType, data: CatalogueSection.CatalogueSectionData) {
        sections[type] = CatalogueSection(type: type, data: data)
    }
    
    /// Remove catalogue by type
    func removeCatalogue(type: CatalogueSectionType) {
        sections.removeValue(forKey: type)
    }
    
    /// Check if catalogue exists for a type
    func hasCatalogue(type: CatalogueSectionType) -> Bool {
        sections[type] != nil
    }
    
    /// Get catalogue for a specific type
    func getCatalogue(type: CatalogueSectionType) -> CatalogueSection? {
        sections[type]
    }
    
    /// Clear all catalogue
    func clearAll() {
        sections.removeAll()
    }
}

// MARK: - Catalogue View Registry
struct CatalogueViewRegistry {
    static func view(for section: CatalogueSection) -> some View {
        CatalogueTypeRegistry.shared().createView(for: section)
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
