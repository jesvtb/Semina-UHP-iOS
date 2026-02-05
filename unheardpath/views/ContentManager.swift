import SwiftUI
import MarkdownUI
import CoreLocation
import core

// MARK: - Content View Type
enum ContentViewType: String, CaseIterable, Sendable {
    case overview
    case locationDetail
    case pointsOfInterest
    case countryOverview
    case subdivisionsOverview
    case neighborhoodOverview
    case cultureOverview
    case regionalCuisine

    /// Tab bar title for section tabs (Overview, Location, Cuisine, Points of Interest).
    var sectionTabTitle: String {
        switch self {
        case .overview, .countryOverview, .subdivisionsOverview, .neighborhoodOverview, .cultureOverview:
            return "Overview"
        case .locationDetail:
            return "Location"
        case .regionalCuisine:
            return "Cuisine"
        case .pointsOfInterest:
            return "Points of Interest"
        }
    }
}

// MARK: - Content Type Definition Protocol
/// Protocol that defines all metadata and behavior for a content type
/// Each content type conforms to this protocol, consolidating parsing, view creation, and type information
/// Sendable because all conforming types are value types (structs) with only static methods
protocol ContentTypeDefinition: Sendable {
    static var type: ContentViewType { get }
    
    /// Parse raw data from SSE event into ContentSectionData
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData?
    
    /// Create SwiftUI view from ContentSectionData
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView
}

// MARK: - Content Type Registry
/// Centralized registry for all content types
/// Provides parsing, view creation, and display order management
/// 
/// Concurrency Safety (Swift 6):
/// - All stored properties are `let` (immutable after initialization)
/// - ContentTypeDefinition protocol is Sendable
/// - ContentViewType enum is Sendable
/// - Dictionary key/value types are Sendable
/// - Registry is only written during initialization, then only read
/// 
/// Note: Using @unchecked Sendable because Swift 6 cannot automatically verify
/// that existential metatypes (`any ContentTypeDefinition.Type`) are Sendable,
/// even though the protocol is Sendable. This is safe because:
/// 1. Metatypes themselves are value types (no mutable state)
/// 2. All conforming types are structs (value types) with only static methods
/// 3. The dictionary is immutable after initialization
/// 4. All access is read-only after initialization
final class ContentTypeRegistry: @unchecked Sendable {
    private let definitions: [ContentViewType: any ContentTypeDefinition.Type]
    
    /// Display order defined as ordered array - easy to reorder by moving items!
    let displayOrder: [ContentViewType] = [
        .overview,
        .locationDetail,
        .regionalCuisine,
        .pointsOfInterest
    ]
    
    fileprivate init() {
        var tempDefinitions: [ContentViewType: any ContentTypeDefinition.Type] = [:]
        
        // Register overview and all its variants to use OverviewContentType
        let overviewTypes: [ContentViewType] = [.overview, .countryOverview, .subdivisionsOverview, .neighborhoodOverview, .cultureOverview]
        for type in overviewTypes {
            tempDefinitions[type] = OverviewContentType.self
        }
        
        // Register remaining content types
        tempDefinitions[.locationDetail] = LocationDetailContentType.self
        tempDefinitions[.pointsOfInterest] = PointsOfInterestContentType.self
        tempDefinitions[.regionalCuisine] = RegionalCuisineContentType.self
        
        self.definitions = tempDefinitions
    }
    
    /// Parse content data from raw SSE event data
    /// Must be called from @MainActor context (used by SSEEventProcessor)
    @MainActor
    func parse(type: ContentViewType, dataValue: Any) -> ContentSection.ContentSectionData? {
        definitions[type]?.parse(from: dataValue)
    }
    
    /// Create SwiftUI view for a content section
    /// Can be called from any context (used by SwiftUI view builders)
    func createView(for section: ContentSection) -> AnyView {
        definitions[section.type]?.createView(for: section.data) ?? AnyView(EmptyView())
    }
}

// Global shared instance - safe because ContentTypeRegistry is @unchecked Sendable
// and all properties are immutable after initialization
private let _contentTypeRegistry = ContentTypeRegistry()

extension ContentTypeRegistry {
    /// Access the shared registry instance
    /// 
    /// Swift 6 Concurrency: Using a function instead of a static property
    /// to avoid static property concurrency warnings. The registry is safe for
    /// concurrent access because:
    /// 1. It's @unchecked Sendable (immutable after init)
    /// 2. All stored properties are `let`
    /// 3. Only read operations after initialization
    nonisolated static func shared() -> ContentTypeRegistry {
        _contentTypeRegistry
    }
}

struct RegionalDish: Identifiable {
    let localName: String
    let globalName: String
    let description: String
    let imageURL: URL?

    var id: String { "\(localName)|\(globalName)" }
}

struct RegionalCuisineData {
    let introduction: String
    let dishes: [RegionalDish]
}

private let regionalCuisineCardCornerRadius: CGFloat = 12
private let regionalCuisineCardAspectRatio: CGFloat = 0.85
private let regionalCuisineCardMinHeight: CGFloat = 140

struct RegionalCuisineView: View {
    let data: RegionalCuisineData
    @State private var selectedDish: RegionalDish?

    private let gridSpacing = Spacing.current.spaceS

    var body: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            Text(data.introduction)
                .bodyParagraph(color: Color("onBkgTextColor30"))

            GeometryReader { geometry in
                let availableWidth = max(0, geometry.size.width)
                let columnWidth = (availableWidth - gridSpacing) / 2
                let columns = [
                    GridItem(.fixed(columnWidth), spacing: gridSpacing),
                    GridItem(.fixed(columnWidth), spacing: gridSpacing)
                ]
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(data.dishes) { dish in
                        RegionalDishCard(dish: dish) {
                            selectedDish = dish
                        }
                        .frame(width: columnWidth, height: columnWidth / regionalCuisineCardAspectRatio)
                    }
                }
                .frame(width: availableWidth)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .frame(height: gridContentHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.vertical, Spacing.current.spaceXs)
        .sheet(item: $selectedDish) { dish in
            RegionalDishPopupView(dish: dish) {
                selectedDish = nil
            }
        }
    }

    /// Approximate height so GeometryReader gets a bounded proposal (card height × rows + spacing).
    private var gridContentHeight: CGFloat {
        let rowCount = (data.dishes.count + 1) / 2
        guard rowCount > 0 else { return 0 }
        let estimatedColumnWidth: CGFloat = 160
        let rowHeight = estimatedColumnWidth / regionalCuisineCardAspectRatio
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * gridSpacing
    }
}

/// Card with image background and dish name overlay; tappable to show popup.
struct RegionalDishCard: View {
    let dish: RegionalDish
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
            .aspectRatio(regionalCuisineCardAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: regionalCuisineCardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: regionalCuisineCardCornerRadius)
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
        .clipShape(RoundedRectangle(cornerRadius: regionalCuisineCardCornerRadius))
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
struct RegionalDishPopupView: View {
    let dish: RegionalDish
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
                        .clipShape(RoundedRectangle(cornerRadius: regionalCuisineCardCornerRadius))
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

// MARK: - Content Type Definitions

/// Overview content type definition
/// Handles all overview variants (overview, countryOverview, subdivisionsOverview, etc.)
struct OverviewContentType: ContentTypeDefinition {
    static var type: ContentViewType { .overview }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let markdown = dataValue as? String else {
            return nil
        }
        return .overview(markdown: markdown)
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .overview(let markdown) = data {
            return AnyView(OverviewView(markdown: markdown))
        }
        return AnyView(EmptyView())
    }
}

/// Location detail content type definition
struct LocationDetailContentType: ContentTypeDefinition {
    static var type: ContentViewType { .locationDetail }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let raw = dataValue as? [String: Any] else { return nil }
        
        let location: CLLocation
        let altitude: Double
        
        if let coord = raw["coordinate"] as? [String: Any], let lat = coord["lat"] as? Double, let lng = coord["lng"] as? Double {
            altitude = coord["alt"] as? Double ?? 0
            location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                altitude: altitude,
                horizontalAccuracy: 0,
                verticalAccuracy: altitude != 0 ? 0 : -1,
                timestamp: Date()
            )
        } else if let lat = raw["latitude"] as? Double, let lon = raw["longitude"] as? Double {
            altitude = raw["altitude"] as? Double ?? 0
            location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitude: altitude,
                horizontalAccuracy: 0,
                verticalAccuracy: altitude != 0 ? 0 : -1,
                timestamp: Date()
            )
        } else {
            return nil
        }
        
        let locationDetailData = LocationDetailData(
            location: location,
            placeName: raw["place_name"] as? String,
            subdivisions: raw["subdivisions"] as? String,
            countryName: raw["country_name"] as? String,
            countryCode: raw["country_code"] as? String,
            timezone: (raw["timezone"] as? String) ?? TimeZone.current.identifier,
            adminArea: raw["adminArea"] as? String,
            subAdminArea: raw["subAdminArea"] as? String,
            locality: raw["locality"] as? String,
            subLocality: raw["subLocality"] as? String,
            iso3166_2: raw["iso3166_2"] as? String,
            isOcean: raw["isOcean"] as? String
        )
        
        return .locationDetail(locationDetailData: locationDetailData)
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .locationDetail(let locationData) = data {
            return AnyView(LocationDetailView(location: locationData.location))
        }
        return AnyView(EmptyView())
    }
}

/// Points of interest content type definition
struct PointsOfInterestContentType: ContentTypeDefinition {
    static var type: ContentViewType { .pointsOfInterest }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let featuresDict = dataValue as? [String: Any],
              let featuresArray = featuresDict["features"] as? [[String: Any]] else {
            return nil
        }
        // Convert to JSONValue format
        let features = featuresArray.compactMap { dict -> PointFeature? in
            guard let jsonValue = JSONValue(from: dict) else { return nil }
            guard case .dictionary(let featureDict) = jsonValue else { return nil }
            return PointFeature(from: featureDict)
        }
        return .pointsOfInterest(features: features)
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .pointsOfInterest(let features) = data {
            if features.count == 1, let feature = features.first {
                return AnyView(ContentPoiItemView(feature: feature))
            } else {
                return AnyView(ContentPoiListView(features: features))
            }
        }
        return AnyView(EmptyView())
    }
}

/// Regional cuisine content type definition
struct RegionalCuisineContentType: ContentTypeDefinition {
    static var type: ContentViewType { .regionalCuisine }
    
    static func parse(from dataValue: Any) -> ContentSection.ContentSectionData? {
        guard let regionalCuisineDict = dataValue as? [String: Any],
              let introduction = regionalCuisineDict["introduction"] as? String,
              let dishesDict = regionalCuisineDict["dishes"] as? [[String: Any]] else {
            return nil
        }
        let dishes = dishesDict.compactMap { dict -> RegionalDish? in
            guard let localName = dict["local_name"] as? String,
                  let globalName = dict["global_name"] as? String,
                  let description = dict["description"] as? String else {
                return nil
            }
            let imageURLString = dict["image_url"] as? String
            let imageURL = imageURLString.flatMap { URL(string: $0) }
            return RegionalDish(
                localName: localName,
                globalName: globalName,
                description: description,
                imageURL: imageURL
            )
        }
        return .regionalCuisine(data: RegionalCuisineData(introduction: introduction, dishes: dishes))
    }
    
    static func createView(for data: ContentSection.ContentSectionData) -> AnyView {
        if case .regionalCuisine(let cuisineData) = data {
            return AnyView(RegionalCuisineView(data: cuisineData))
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
        
        return "Journey Content"
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

// MARK: - Content Section
struct ContentSection: Identifiable {
    // Use type as stable ID - each type appears at most once
    // This prevents SwiftUI from recreating views when parent state changes
    var id: String { type.rawValue }
    let type: ContentViewType
    let data: ContentSectionData
    
    enum ContentSectionData {
        case regionalCuisine(data: RegionalCuisineData)
        case overview(markdown: String)
        case locationDetail(locationDetailData: LocationDetailData)
        case pointsOfInterest(features: [PointFeature])
    }
    
    init(type: ContentViewType, data: ContentSectionData) {
        self.type = type
        self.data = data
    }
}

// MARK: - Content Manager
/// Manages content sections by type, allowing selective updates
@MainActor
class ContentManager: ObservableObject {
    @Published private var sections: [ContentViewType: ContentSection] = [:]
    
    /// Tracks whether the current location content is from device location (true) or lookup/search location (false)
    @Published var isContentFromDeviceLocation: Bool = true
    
    /// Returns sections in display order (from ContentTypeRegistry)
    var orderedSections: [ContentSection] {
        ContentTypeRegistry.shared().displayOrder.compactMap { type in
            sections[type]
        }
    }
    
    /// Returns LocationDetailData if available, for header view construction.
    var locationDetailData: LocationDetailData? {
        if let locationSection = sections[.locationDetail],
           case .locationDetail(let data) = locationSection.data {
            return data
        }
        return nil
    }
    
    /// Set or update content by type
    /// - Parameters:
    ///   - type: The content view type to set
    ///   - data: The content section data
    ///   - isFromDeviceLocation: For locationDetail type, indicates if content is from device location (true) or lookup/search (false)
    func setContent(type: ContentViewType, data: ContentSection.ContentSectionData, isFromDeviceLocation: Bool? = nil) {
        sections[type] = ContentSection(type: type, data: data)
        
        // Update location source tracking when locationDetail content is set
        if type == .locationDetail, let isDevice = isFromDeviceLocation {
            isContentFromDeviceLocation = isDevice
        }
    }
    
    /// Remove content by type
    func removeContent(type: ContentViewType) {
        sections.removeValue(forKey: type)
    }
    
    /// Check if content exists for a type
    func hasContent(type: ContentViewType) -> Bool {
        sections[type] != nil
    }
    
    /// Get content for a specific type
    func getContent(type: ContentViewType) -> ContentSection? {
        sections[type]
    }
    
    /// Clear all content
    func clearAll() {
        sections.removeAll()
    }
}

// MARK: - Content View Registry
struct ContentViewRegistry {
    static func view(for section: ContentSection) -> some View {
        ContentTypeRegistry.shared().createView(for: section)
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
struct LocationDetailView: View {
    let location: CLLocation
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
            DisplayText("Location", scale: .article2, color: Color("onBkgTextColor20"))
            
            VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                Text("Latitude: \(location.coordinate.latitude, specifier: "%.6f")")
                    .bodyText()
                    .foregroundColor(Color("onBkgTextColor30"))
                
                Text("Longitude: \(location.coordinate.longitude, specifier: "%.6f")")
                    .bodyText()
                    .foregroundColor(Color("onBkgTextColor30"))
                
                if location.altitude != 0 {
                    Text("Altitude: \(location.altitude, specifier: "%.2f") m")
                        .bodyText()
                        .foregroundColor(Color("onBkgTextColor30"))
                }
            }
        }
        .padding(.vertical, Spacing.current.spaceXs)
    }
}

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

#Preview("Location Detail View") {
    ScrollView {
        LocationDetailView(location: CLLocation(
            latitude: 41.9028,
            longitude: 12.4964
        ))
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
