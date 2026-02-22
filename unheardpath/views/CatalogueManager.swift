import SwiftUI
import CoreLocation
import core

// MARK: - Catalogue Section
/// A catalogue section with dynamic type and raw JSONValue content.
/// Content items carry their own `_metadata` (location, interface) per key.
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
    /// Incoming items that carry `_metadata.location.context` are validated against the current
    /// `locationDetailData`. Items whose location context doesn't match are silently dropped to
    /// prevent late-arriving SSE events from polluting the catalogue. Items without location
    /// metadata (legacy / cached) are accepted permissively.
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
        guard case .dictionary(var contentDict) = content else {
            // Non-dictionary content: replace wholesale
            replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, content: content)
            schedulePersistence()
            return
        }

        // Filter out items whose location context doesn't match the current location.
        // Items without location metadata are accepted (backward compatible / permissive).
        if let currentLocation = locationDetailData {
            contentDict = contentDict.filter { (key, value) in
                guard !key.hasPrefix("_") else { return true }  // Keep metadata keys
                guard Self.itemHasLocationContext(value) else { return true }  // No location → accept
                return Self.itemLocationMatchesCurrent(value, location: currentLocation)
            }
            // If all real content was filtered out, skip the upsert entirely.
            guard contentDict.contains(where: { !$0.key.hasPrefix("_") }) else { return }
        }

        let filteredContent = JSONValue.dictionary(contentDict)

        if var existing = sections[sectionType] {
            // Upsert: merge items by key into existing section content
            guard case .dictionary(var existingDict) = existing.content else {
                replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, content: filteredContent)
                schedulePersistence()
                return
            }
            for (key, value) in contentDict {
                existingDict[key] = value  // insert or replace by key
            }
            existing.content = .dictionary(existingDict)
            sections[sectionType] = existing
        } else {
            // New section
            replaceCatalogue(sectionType: sectionType, displayTitle: displayTitle, content: filteredContent)
        }

        schedulePersistence()
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
    
    /// Remove catalogue items whose `_metadata.location.context` does not match the new location.
    ///
    /// Each item self-describes its geographic identity via `_metadata.location.context`.
    /// Items whose context fields don't match the new location are pruned.
    /// Items without `_metadata.location` are conservatively removed (cannot verify).
    ///
    /// **Example — Shenzhen → Shanghai (same country, different admin area):**
    /// - Items with `context: {"country_code": "CN"}` match → kept.
    /// - Items with `context: {"country_code": "CN", "admin_area": "Guangdong"}` don't match → removed.
    ///
    /// No longer requires the old `locationDetailData` — each item carries its own location
    /// identity, so the comparison is directly against the new location.
    func pruneStaleItems(forNewLocation newLocation: LocationDetailData) {
        // Collect section types to remove (sections that become empty after pruning)
        var sectionsToRemove: [String] = []

        for (sectionType, section) in sections {
            guard case .dictionary(var contentDict) = section.content else { continue }
            var modified = false

            for (key, value) in contentDict {
                if key.hasPrefix("_") { continue }  // Preserve root-level metadata keys

                // Remove if location context doesn't match the new location.
                // Items without location metadata are conservatively removed (cannot verify).
                if !Self.itemLocationMatchesCurrent(value, location: newLocation) {
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

    /// Extract GeoJSON feature dicts from the "sights" section's cards.
    /// Used to forward cached sight features to `MapFeaturesManager` after cache restore.
    func extractSightFeatures() -> [[String: JSONValue]] {
        guard let sightsSection = sections["sights"],
              case .dictionary(let contentDict) = sightsSection.content else {
            return []
        }
        var features: [[String: JSONValue]] = []
        for (key, topicValue) in contentDict where !key.hasPrefix("_") {
            if let cards = topicValue["cards"]?.arrayValue {
                for card in cards {
                    if let featureDict = card.dictionaryValue {
                        features.append(featureDict)
                    }
                }
            }
        }
        return features
    }

    // MARK: - Location Context Matching

    /// Check if an item has `_metadata.location.context`.
    private static func itemHasLocationContext(_ item: JSONValue) -> Bool {
        guard case .dictionary(let itemDict) = item,
              case .dictionary(let meta) = itemDict["_metadata"],
              case .dictionary(let loc) = meta["location"],
              case .dictionary(_) = loc["context"] else {
            return false
        }
        return true
    }

    /// Check if an item's `_metadata.location.context` matches the given location.
    ///
    /// Compares each field in the item's context dict against the corresponding
    /// field in the location. A match requires all present context fields to agree
    /// (normalized to handle case and diacritics consistently with cache keys).
    ///
    /// Items without `_metadata.location.context` return `false` (cannot verify).
    static func itemLocationMatchesCurrent(
        _ item: JSONValue,
        location: LocationDetailData
    ) -> Bool {
        guard case .dictionary(let itemDict) = item,
              case .dictionary(let meta) = itemDict["_metadata"],
              case .dictionary(let loc) = meta["location"],
              case .dictionary(let context) = loc["context"] else {
            return false  // No location context → cannot verify
        }

        if let countryCode = context["country_code"]?.stringValue {
            guard let locCountry = location.countryCode else { return false }
            if StorageKey.normalize(countryCode) != StorageKey.normalize(locCountry) {
                return false
            }
        }
        if let adminArea = context["admin_area"]?.stringValue {
            guard let locAdmin = location.adminArea else { return false }
            if StorageKey.normalize(adminArea) != StorageKey.normalize(locAdmin) {
                return false
            }
        }
        if let locality = context["locality"]?.stringValue {
            guard let locLocality = location.locality else { return false }
            if StorageKey.normalize(locality) != StorageKey.normalize(locLocality) {
                return false
            }
        }
        if let subLocality = context["sub_locality"]?.stringValue {
            guard let locSubLocality = location.subLocality else { return false }
            if StorageKey.normalize(subLocality) != StorageKey.normalize(locSubLocality) {
                return false
            }
        }

        return true
    }

    // MARK: - Persistence
    
    /// Optional persistence backend. Set via `setPersistence(_:)` during app initialization.
    private var persistence: (any CataloguePersisting)?
    
    /// Debounce task for batching rapid SSE-delivered sections into a single persist.
    private var persistenceTask: Task<Void, Never>?
    
    /// When true, suppress scheduled persistence (used during cache restoration to avoid re-persisting loaded data).
    private var isPersistenceSuppressed = false
    
    /// Inject the persistence backend. Called once during app setup.
    func setPersistence(_ persistence: any CataloguePersisting) {
        self.persistence = persistence
    }
    
    /// Schedule a debounced persistence write.
    /// Called after each `handleCatalogue` upsert to batch rapid SSE events into a single disk write.
    private func schedulePersistence() {
        guard !isPersistenceSuppressed else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled, let self else { return }
            guard let location = self.locationDetailData else { return }
            self.persistCurrentState(for: location)
        }
    }
    
    /// Persist the current in-memory catalogue state for a given location.
    /// Normally triggered automatically via debounced `schedulePersistence()`.
    /// Can also be called explicitly (e.g., from debug tools).
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
    /// Persists after restore so the last context snapshot reflects the restored location.
    func restoreFromCache(for location: LocationDetailData) async {
        guard let persistence = persistence else { return }
        
        do {
            // Suppress persistence during load to avoid re-persisting the same data.
            isPersistenceSuppressed = true
            defer { isPersistenceSuppressed = false }
            
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
        
        // Persist so last_context snapshot is updated for the restored location.
        persistCurrentState(for: location)
    }
    
    /// Restore the last active catalogue context (no location needed).
    /// Fallback for app launch when no location is available yet.
    func restoreFromCache() async {
        guard let persistence = persistence else { return }
        guard sections.isEmpty else { return }
        
        // Suppress persistence during restoration to avoid re-persisting loaded data.
        isPersistenceSuppressed = true
        defer { isPersistenceSuppressed = false }
        
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
                "lang:en": .string(name)
            ]),
            "short_description": .string(description)
        ])
    ]
    return PointFeature(from: feature)
}
#endif
