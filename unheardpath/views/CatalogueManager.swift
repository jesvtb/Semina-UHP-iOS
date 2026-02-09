import SwiftUI
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
    /// Called on app launch and after pruning when switching locations.
    /// Uses key-level upsert via `handleCatalogue` so cached keys fill gaps
    /// without overwriting fresher in-memory content.
    func restoreFromCache(for location: LocationDetailData) async {
        guard let persistence = persistence else { return }
        
        do {
            let cached = try await persistence.restore(for: location)
            for section in cached {
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
