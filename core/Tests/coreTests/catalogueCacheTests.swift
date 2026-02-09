import Testing
import Foundation
import CoreLocation
@testable import core

// MARK: - StorageKey Tests

@Suite("StorageKey geographic key derivation")
struct StorageKeyTests {

    // MARK: - Helpers

    private func makeLocation(
        countryCode: String? = nil,
        adminArea: String? = nil,
        locality: String? = nil,
        subLocality: String? = nil,
        timezone: String = "America/Los_Angeles",
        lat: Double = 37.7749,
        lon: Double = -122.4194
    ) -> LocationDetailData {
        LocationDetailData(
            location: CLLocation(latitude: lat, longitude: lon),
            countryCode: countryCode,
            timezone: timezone,
            adminArea: adminArea,
            locality: locality,
            subLocality: subLocality
        )
    }

    // MARK: - Country Level

    @Test("Country key is lowercased country code")
    func countryKey() {
        let loc = makeLocation(countryCode: "US")
        let key = StorageKey.geoKey(from: loc, level: .country)
        #expect(key == "us")
    }

    @Test("Country key returns nil when countryCode is missing")
    func countryKeyMissing() {
        let loc = makeLocation()
        let key = StorageKey.geoKey(from: loc, level: .country)
        #expect(key == nil)
    }

    // MARK: - Admin Area Level

    @Test("Adminarea key uses dot delimiter")
    func adminareaKey() {
        let loc = makeLocation(countryCode: "US", adminArea: "California")
        let key = StorageKey.geoKey(from: loc, level: .adminarea)
        #expect(key == "us.california")
    }

    @Test("Adminarea key returns nil when adminArea is missing")
    func adminareaKeyMissing() {
        let loc = makeLocation(countryCode: "US")
        let key = StorageKey.geoKey(from: loc, level: .adminarea)
        #expect(key == nil)
    }

    // MARK: - Locality Level

    @Test("Locality key with spaces becomes underscores within level")
    func localityKeyWithSpaces() {
        let loc = makeLocation(countryCode: "US", adminArea: "California", locality: "San Francisco")
        let key = StorageKey.geoKey(from: loc, level: .locality)
        #expect(key == "us.california.san_francisco")
    }

    @Test("Locality key returns nil when locality is missing")
    func localityKeyMissing() {
        let loc = makeLocation(countryCode: "US", adminArea: "California")
        let key = StorageKey.geoKey(from: loc, level: .locality)
        #expect(key == nil)
    }

    // MARK: - Sublocality Level

    @Test("Sublocality key includes all four levels")
    func sublocalityKey() {
        let loc = makeLocation(countryCode: "US", adminArea: "California", locality: "San Francisco", subLocality: "Mission District")
        let key = StorageKey.geoKey(from: loc, level: .sublocality)
        #expect(key == "us.california.san_francisco.mission_district")
    }

    // MARK: - Geohash Level

    @Test("Geohash key is 5 characters for San Francisco")
    func geohashKey() {
        let loc = makeLocation(lat: 37.7749, lon: -122.4194)
        let key = StorageKey.geoKey(from: loc, level: .geohash)
        #expect(key != nil)
        #expect(key?.count == 5)
    }

    @Test("Nearby coordinates produce the same geohash")
    func geohashClustering() {
        // Two points ~100m apart in SF
        let loc1 = makeLocation(lat: 37.7749, lon: -122.4194)
        let loc2 = makeLocation(lat: 37.7750, lon: -122.4195)
        let key1 = StorageKey.geoKey(from: loc1, level: .geohash)
        let key2 = StorageKey.geoKey(from: loc2, level: .geohash)
        #expect(key1 == key2)
    }

    @Test("Distant coordinates produce different geohashes")
    func geohashDifferentLocations() {
        let sf = makeLocation(lat: 37.7749, lon: -122.4194)
        let ny = makeLocation(lat: 40.7128, lon: -74.0060)
        let keySF = StorageKey.geoKey(from: sf, level: .geohash)
        let keyNY = StorageKey.geoKey(from: ny, level: .geohash)
        #expect(keySF != keyNY)
    }

    // MARK: - Applicable Levels

    @Test("applicableLevels returns all available levels in order")
    func applicableLevelsComplete() {
        let loc = makeLocation(countryCode: "CN", adminArea: "Jiangsu", locality: "Suzhou", subLocality: "Gusu")
        let levels = StorageKey.applicableLevels(from: loc)
        #expect(levels.count == 5) // country, adminarea, locality, sublocality, geohash
        #expect(levels[0].level == .country)
        #expect(levels[1].level == .adminarea)
        #expect(levels[2].level == .locality)
        #expect(levels[3].level == .sublocality)
        #expect(levels[4].level == .geohash)
    }

    @Test("applicableLevels skips levels with missing fields")
    func applicableLevelsPartial() {
        let loc = makeLocation(countryCode: "US", adminArea: "California")
        let levels = StorageKey.applicableLevels(from: loc)
        // Should have: country, adminarea, geohash (skips locality/sublocality)
        #expect(levels.count == 3)
        #expect(levels[0].level == .country)
        #expect(levels[1].level == .adminarea)
        #expect(levels[2].level == .geohash)
    }

    // MARK: - Normalization

    @Test("Diacritics are stripped: São Paulo → sao_paulo")
    func normalizeDiacritics() {
        let loc = makeLocation(countryCode: "BR", adminArea: "São Paulo", locality: "São Paulo")
        let key = StorageKey.geoKey(from: loc, level: .locality)
        #expect(key == "br.sao_paulo.sao_paulo")
    }

    @Test("Commas are removed")
    func normalizeCommas() {
        let result = StorageKey.normalize("Washington, D.C.")
        #expect(result == "washington_d.c.")
    }

    @Test("Leading/trailing whitespace is trimmed")
    func normalizeTrimming() {
        let result = StorageKey.normalize("  New York  ")
        #expect(result == "new_york")
    }
}

// MARK: - Geohash Tests

@Suite("Geohash encoding")
struct GeohashTests {

    @Test("Known geohash for Washington DC")
    func washingtonDC() {
        // Washington DC (38.8977, -77.0365) should start with "dqcjq"
        let hash = Geohash.encode(latitude: 38.8977, longitude: -77.0365, precision: 5)
        #expect(hash.count == 5)
        #expect(hash.hasPrefix("dqcj"))
    }

    @Test("Known geohash for London")
    func london() {
        // London (51.5074, -0.1278) should start with "gcpvj"
        let hash = Geohash.encode(latitude: 51.5074, longitude: -0.1278, precision: 5)
        #expect(hash.count == 5)
        #expect(hash.hasPrefix("gcpv"))
    }

    @Test("Precision parameter controls length")
    func precision() {
        let hash3 = Geohash.encode(latitude: 37.7749, longitude: -122.4194, precision: 3)
        let hash7 = Geohash.encode(latitude: 37.7749, longitude: -122.4194, precision: 7)
        #expect(hash3.count == 3)
        #expect(hash7.count == 7)
        #expect(hash7.hasPrefix(hash3))
    }
}

// MARK: - CachedLocationSummary Tests

@Suite("CachedLocationSummary round-trip")
struct CachedLocationSummaryTests {

    @Test("Round-trip through toLocationDetailData preserves fields")
    func roundTrip() {
        let original = LocationDetailData(
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            countryCode: "US",
            timezone: "America/Los_Angeles",
            adminArea: "California",
            locality: "San Francisco",
            subLocality: "Mission"
        )
        let summary = CachedLocationSummary(from: original)
        let restored = summary.toLocationDetailData()

        #expect(restored.countryCode == "US")
        #expect(restored.adminArea == "California")
        #expect(restored.locality == "San Francisco")
        #expect(restored.subLocality == "Mission")
        #expect(abs(restored.location.coordinate.latitude - 37.7749) < 0.0001)
        #expect(abs(restored.location.coordinate.longitude - (-122.4194)) < 0.0001)
    }

    @Test("CachedLocationSummary is Codable")
    func codable() throws {
        let summary = CachedLocationSummary(from: LocationDetailData(
            location: CLLocation(latitude: 40.7128, longitude: -74.0060),
            countryCode: "US",
            timezone: "America/New_York",
            adminArea: "New York",
            locality: "New York City"
        ))
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(CachedLocationSummary.self, from: data)
        #expect(decoded.countryCode == "US")
        #expect(decoded.locality == "New York City")
    }
}

// MARK: - CatalogueFileStore Tests

@Suite("CatalogueFileStore persistence")
struct CatalogueFileStoreTests {

    /// Each test uses a unique cache subdirectory for filesystem isolation.
    private func makeIsolatedStore() -> CatalogueFileStore {
        let uniqueDir = "catalogue_test_\(UUID().uuidString)"
        return CatalogueFileStore(baseSubdirectory: uniqueDir)
    }

    /// Legacy sections (no _metadata) for backward-compat tests.
    private func makeLegacySections() -> [CachedSection] {
        [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary(["markdown": .string("# Welcome to San Francisco")])
            ),
            CachedSection(
                sectionType: "cuisine",
                displayTitle: "Regional Cuisine",
                content: .dictionary([
                    "California cuisine": .dictionary([
                        "cards": .array([
                            .dictionary([
                                "local_name": .string("Fish Tacos"),
                                "global_name": .string("Fish Tacos"),
                                "description": .string("Fresh fish in a tortilla")
                            ])
                        ])
                    ])
                ])
            )
        ]
    }

    /// Scoped sections (with _metadata.geo_scope) mimicking the new backend behavior.
    private func makeScopedSections() -> [CachedSection] {
        [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary([
                    "country_overview": .dictionary([
                        "markdown": .string("# Welcome to China"),
                        "_metadata": .dictionary([
                            "geo_scope": .string("country"),
                            "interface": .dictionary(["markdown": .dictionary([:])])
                        ])
                    ])
                ])
            ),
            CachedSection(
                sectionType: "cuisine",
                displayTitle: "Cuisine",
                content: .dictionary([
                    "Chinese cuisine": .dictionary([
                        "qid": .string("Q123"),
                        "cards": .array([.dictionary(["local_name": .string("Kung Pao Chicken")])]),
                        "_metadata": .dictionary([
                            "geo_scope": .string("country"),
                            "interface": .dictionary([
                                "card": .dictionary(["render_type": .string("dish")])
                            ])
                        ])
                    ]),
                    "Huaiyang cuisine": .dictionary([
                        "qid": .string("Q456"),
                        "cards": .array([.dictionary(["local_name": .string("Lion's Head Meatball")])]),
                        "_metadata": .dictionary([
                            "geo_scope": .string("locality"),
                            "interface": .dictionary([
                                "card": .dictionary(["render_type": .string("dish")])
                            ])
                        ])
                    ])
                ])
            )
        ]
    }

    private func makeLocation(
        countryCode: String = "US",
        adminArea: String = "California",
        locality: String = "San Francisco",
        timezone: String = "America/Los_Angeles",
        lat: Double = 37.7749,
        lon: Double = -122.4194
    ) -> LocationDetailData {
        LocationDetailData(
            location: CLLocation(latitude: lat, longitude: lon),
            countryCode: countryCode,
            timezone: timezone,
            adminArea: adminArea,
            locality: locality
        )
    }

    // MARK: - Legacy (no _metadata) Tests

    @Test("Legacy: persist and restore sections for the same location")
    func legacyPersistAndRestore() async throws {
        let store = makeIsolatedStore()
        let sections = makeLegacySections()
        let location = makeLocation()

        try await store.persist(sections: sections, sectionOrder: ["overview", "cuisine"], location: location)

        let restored = try await store.restore(for: location)
        #expect(restored.count == 2)
        #expect(restored[0].sectionType == "overview")
        #expect(restored[1].sectionType == "cuisine")
    }

    @Test("Legacy: cross-city reuse via country duplicate")
    func legacyCrossCityReuse() async throws {
        let store = makeIsolatedStore()
        let sections = makeLegacySections()
        let sfLocation = makeLocation(locality: "San Francisco")

        try await store.persist(sections: sections, sectionOrder: ["overview", "cuisine"], location: sfLocation)

        // Los Angeles — same country, different city
        let laLocation = makeLocation(locality: "Los Angeles", lat: 34.0522, lon: -118.2437)
        let restored = try await store.restore(for: laLocation)

        #expect(!restored.isEmpty)
        #expect(restored.count == 2) // From country-level duplicate
    }

    // MARK: - Scoped (_metadata.geo_scope) Tests

    @Test("Scoped: splits content by _metadata.geo_scope into separate context files")
    func scopedPersistSplits() async throws {
        let store = makeIsolatedStore()
        let sections = makeScopedSections()
        let location = makeLocation(countryCode: "CN", adminArea: "Jiangsu", locality: "Yangzhou", lat: 32.39, lon: 119.43)

        try await store.persist(sections: sections, sectionOrder: ["overview", "cuisine"], location: location)

        // Restore for same location — should merge country + locality
        let restored = try await store.restore(for: location)
        #expect(restored.count == 2) // overview + cuisine

        // Overview content should be from country level
        let overview = restored.first { $0.sectionType == "overview" }
        #expect(overview != nil)
        // After persistence, _metadata is stripped, so the keyed item "country_overview" should have markdown
        if case .dictionary(let overviewDict) = overview?.content,
           case .dictionary(let countryOverview) = overviewDict["country_overview"] {
            #expect(countryOverview["markdown"]?.stringValue?.contains("China") == true)
        } else {
            Issue.record("Overview content should contain country_overview key")
        }

        // Cuisine should have both national + regional items merged
        let cuisine = restored.first { $0.sectionType == "cuisine" }
        #expect(cuisine != nil)
        if case .dictionary(let dict) = cuisine?.content {
            #expect(dict["Chinese cuisine"] != nil)   // from country
            #expect(dict["Huaiyang cuisine"] != nil)   // from locality
            // _metadata should be preserved in stored content for UI rendering config
            if case .dictionary(let chineseDict) = dict["Chinese cuisine"],
               case .dictionary(let metaDict) = chineseDict["_metadata"] {
                #expect(metaDict["geo_scope"]?.stringValue == "country")
                #expect(metaDict["interface"] != nil)
            } else {
                Issue.record("Chinese cuisine should retain _metadata with geo_scope and interface")
            }
        } else {
            Issue.record("Cuisine content should be a dictionary")
        }
    }

    @Test("Scoped: cross-city reuse preserves country-scoped items only")
    func scopedCrossCityReuse() async throws {
        let store = makeIsolatedStore()
        let sections = makeScopedSections()
        let yzLocation = makeLocation(countryCode: "CN", adminArea: "Jiangsu", locality: "Yangzhou", lat: 32.39, lon: 119.43)

        try await store.persist(sections: sections, sectionOrder: ["overview", "cuisine"], location: yzLocation)

        // Shanghai — same country, different city
        let shLocation = makeLocation(countryCode: "CN", adminArea: "Shanghai", locality: "Shanghai", lat: 31.23, lon: 121.47)
        let restored = try await store.restore(for: shLocation)

        // Should have overview (country) and cuisine (country only — no Huaiyang)
        #expect(!restored.isEmpty)

        let overview = restored.first { $0.sectionType == "overview" }
        if case .dictionary(let overviewDict) = overview?.content,
           case .dictionary(let countryOverview) = overviewDict["country_overview"] {
            #expect(countryOverview["markdown"]?.stringValue?.contains("China") == true)
        }

        let cuisine = restored.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisine?.content {
            #expect(dict["Chinese cuisine"] != nil)    // country-scoped, survives
            #expect(dict["Huaiyang cuisine"] == nil)   // locality-scoped to Yangzhou, absent
        } else {
            Issue.record("Cuisine content should be a dictionary")
        }
    }

    @Test("Scoped: more-specific level overrides same key from general level")
    func scopedKeyOverride() async throws {
        let store = makeIsolatedStore()
        let location = makeLocation(countryCode: "CN", adminArea: "Jiangsu", locality: "Yangzhou", lat: 32.39, lon: 119.43)

        // First persist: country cuisine + locality cuisine
        let sections1 = makeScopedSections()
        try await store.persist(sections: sections1, sectionOrder: ["overview", "cuisine"], location: location)

        // Second persist: override "Chinese cuisine" at locality level (unlikely but should work)
        let overrideSections = [
            CachedSection(
                sectionType: "cuisine",
                displayTitle: "Cuisine",
                content: .dictionary([
                    "Chinese cuisine": .dictionary([
                        "qid": .string("Q123-updated"),
                        "cards": .array([.dictionary(["local_name": .string("Peking Duck")])]),
                        "_metadata": .dictionary([
                            "geo_scope": .string("locality"),
                            "interface": .dictionary([
                                "card": .dictionary(["render_type": .string("dish")])
                            ])
                        ])
                    ])
                ])
            )
        ]
        try await store.persist(sections: overrideSections, sectionOrder: ["cuisine"], location: location)

        let restored = try await store.restore(for: location)
        let cuisine = restored.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisine?.content,
           case .dictionary(let chineseDict) = dict["Chinese cuisine"],
           case .string(let qid) = chineseDict["qid"] {
            #expect(qid == "Q123-updated") // locality override
        } else {
            Issue.record("Chinese cuisine should be overridden at locality level")
        }
    }

    @Test("Scoped: restoreLastContext merges all applicable levels")
    func scopedRestoreLastContext() async throws {
        let store = makeIsolatedStore()
        let sections = makeScopedSections()
        let location = makeLocation(countryCode: "CN", adminArea: "Jiangsu", locality: "Yangzhou", lat: 32.39, lon: 119.43)

        try await store.persist(sections: sections, sectionOrder: ["overview", "cuisine"], location: location)

        let result = try await store.restoreLastContext()
        #expect(result != nil)
        #expect(result?.snapshot.geoKey.contains("yangzhou") == true)

        // Should have merged content from country + locality
        let cuisine = result?.sections.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisine?.content {
            #expect(dict["Chinese cuisine"] != nil)
            #expect(dict["Huaiyang cuisine"] != nil)
        } else {
            Issue.record("Cuisine content should merge across levels in restoreLastContext")
        }
    }

    @Test("Scoped: _metadata is preserved in stored content on disk")
    func scopedPreservesMetadata() async throws {
        let store = makeIsolatedStore()
        let sections = [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary([
                    "country_overview": .dictionary([
                        "markdown": .string("# Test"),
                        "_metadata": .dictionary([
                            "geo_scope": .string("country"),
                            "interface": .dictionary(["markdown": .dictionary([:])])
                        ])
                    ])
                ])
            )
        ]
        let location = makeLocation(countryCode: "CN", adminArea: "Jiangsu", locality: "Yangzhou", lat: 32.39, lon: 119.43)

        try await store.persist(sections: sections, sectionOrder: ["overview"], location: location)

        let restored = try await store.restore(for: location)
        let overview = restored.first { $0.sectionType == "overview" }
        if case .dictionary(let dict) = overview?.content,
           case .dictionary(let countryOverview) = dict["country_overview"] {
            #expect(countryOverview["markdown"]?.stringValue == "# Test")
            // _metadata should be preserved so UI rendering config survives persistence
            if case .dictionary(let metaDict) = countryOverview["_metadata"] {
                #expect(metaDict["geo_scope"]?.stringValue == "country")
                #expect(metaDict["interface"] != nil)
            } else {
                Issue.record("_metadata should be preserved in persisted content")
            }
        } else {
            Issue.record("Overview content should be a dictionary with _metadata")
        }
    }

    // MARK: - General Tests

    @Test("Empty sections are not persisted")
    func emptySectionsNotPersisted() async throws {
        let store = makeIsolatedStore()
        let location = makeLocation()

        try await store.persist(sections: [], sectionOrder: [], location: location)

        let result = try await store.restoreLastContext()
        #expect(result == nil)
    }

    @Test("Restore returns empty array for unknown location")
    func restoreUnknownLocation() async throws {
        let store = makeIsolatedStore()
        let location = LocationDetailData(
            location: CLLocation(latitude: -33.8688, longitude: 151.2093),
            countryCode: "AU",
            timezone: "Australia/Sydney",
            adminArea: "New South Wales",
            locality: "Sydney"
        )

        let restored = try await store.restore(for: location)
        #expect(restored.isEmpty)
    }

    @Test("CachedSection Codable round-trip preserves JSONValue content")
    func cachedSectionCodable() throws {
        let section = CachedSection(
            sectionType: "cuisine",
            displayTitle: "Regional Cuisine",
            content: .dictionary([
                "cards": .array([
                    .dictionary(["local_name": .string("Ramen"), "description": .string("Noodle soup")])
                ])
            ])
        )

        let data = try JSONEncoder().encode(section)
        let decoded = try JSONDecoder().decode(CachedSection.self, from: data)

        #expect(decoded.sectionType == "cuisine")
        #expect(decoded.displayTitle == "Regional Cuisine")
        if case .dictionary(let dict) = decoded.content,
           case .array(let cards) = dict["cards"],
           case .dictionary(let card) = cards.first,
           case .string(let name) = card["local_name"] {
            #expect(name == "Ramen")
        } else {
            Issue.record("Content structure not preserved after Codable round-trip")
        }
    }
}

// MARK: - Geo-Scope Helper Tests

@Suite("CatalogueFileStore geo-scope helpers")
struct GeoScopeHelperTests {

    @Test("contentHasGeoScope detects _metadata.geo_scope in keyed items")
    func itemLevelGeoScope() {
        let content: JSONValue = .dictionary([
            "Chinese cuisine": .dictionary([
                "qid": .string("Q123"),
                "_metadata": .dictionary([
                    "geo_scope": .string("country")
                ])
            ])
        ])
        #expect(CatalogueFileStore.contentHasGeoScope(content) == true)
    }

    @Test("contentHasGeoScope returns false when no _metadata.geo_scope present")
    func noGeoScope() {
        let content: JSONValue = .dictionary([
            "markdown": .string("# Hello")
        ])
        #expect(CatalogueFileStore.contentHasGeoScope(content) == false)
    }

    @Test("contentHasGeoScope returns false for _metadata without geo_scope")
    func metadataWithoutGeoScope() {
        let content: JSONValue = .dictionary([
            "item": .dictionary([
                "_metadata": .dictionary([
                    "interface": .dictionary(["markdown": .dictionary([:])])
                ])
            ])
        ])
        #expect(CatalogueFileStore.contentHasGeoScope(content) == false)
    }

    @Test("extractGeoScopedFragments splits items by _metadata.geo_scope into multiple levels")
    func extractItemLevel() {
        let content: JSONValue = .dictionary([
            "Chinese cuisine": .dictionary([
                "qid": .string("Q123"),
                "_metadata": .dictionary([
                    "geo_scope": .string("country"),
                    "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                ])
            ]),
            "Huaiyang cuisine": .dictionary([
                "qid": .string("Q456"),
                "_metadata": .dictionary([
                    "geo_scope": .string("locality"),
                    "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                ])
            ])
        ])
        let fragments = CatalogueFileStore.extractGeoScopedFragments(from: content, defaultLevel: .locality)
        #expect(fragments.count == 2)

        let countryFragment = fragments.first { $0.level == .country }
        let localityFragment = fragments.first { $0.level == .locality }
        #expect(countryFragment != nil)
        #expect(localityFragment != nil)

        // Chinese cuisine at country, _metadata preserved
        if case .dictionary(let dict) = countryFragment?.content {
            #expect(dict["Chinese cuisine"] != nil)
            if case .dictionary(let inner) = dict["Chinese cuisine"] {
                #expect(inner["qid"]?.stringValue == "Q123")
                // _metadata should be preserved for UI rendering config
                if case .dictionary(let metaDict) = inner["_metadata"] {
                    #expect(metaDict["geo_scope"]?.stringValue == "country")
                    #expect(metaDict["interface"] != nil)
                } else {
                    Issue.record("_metadata should be preserved in extracted fragments")
                }
            }
        }

        // Huaiyang at locality
        if case .dictionary(let dict) = localityFragment?.content {
            #expect(dict["Huaiyang cuisine"] != nil)
        }
    }

    @Test("extractGeoScopedFragments defaults items without _metadata")
    func extractDefaultLevel() {
        let content: JSONValue = .dictionary([
            "Unscoped item": .dictionary([
                "qid": .string("Q789")
            ])
        ])
        let fragments = CatalogueFileStore.extractGeoScopedFragments(from: content, defaultLevel: .locality)
        #expect(fragments.count == 1)
        #expect(fragments[0].level == .locality)
    }

    @Test("mergeContent combines two dictionaries with override precedence")
    func mergeContentOverride() {
        let base: JSONValue = .dictionary([
            "a": .string("base_a"),
            "b": .string("base_b")
        ])
        let override: JSONValue = .dictionary([
            "b": .string("override_b"),
            "c": .string("override_c")
        ])
        let merged = CatalogueFileStore.mergeContent(base: base, override: override)
        if case .dictionary(let dict) = merged {
            #expect(dict["a"]?.stringValue == "base_a")
            #expect(dict["b"]?.stringValue == "override_b")
            #expect(dict["c"]?.stringValue == "override_c")
        } else {
            Issue.record("Merged result should be a dictionary")
        }
    }

    @Test("mergeContent returns override when types differ")
    func mergeContentTypeMismatch() {
        let base: JSONValue = .string("not a dict")
        let override: JSONValue = .dictionary(["key": .string("value")])
        let merged = CatalogueFileStore.mergeContent(base: base, override: override)
        if case .dictionary(let dict) = merged {
            #expect(dict["key"]?.stringValue == "value")
        } else {
            Issue.record("Override should win when base is not a dict")
        }
    }
}

// MARK: - GeoLevel Identifier Tests

@Suite("GeoLevel identifier init")
struct GeoLevelIdentifierTests {

    @Test("GeoLevel round-trips through identifier")
    func roundTrip() {
        for level in GeoLevel.allCases {
            let restored = GeoLevel(identifier: level.identifier)
            #expect(restored == level)
        }
    }

    @Test("GeoLevel returns nil for unknown identifier")
    func unknownIdentifier() {
        #expect(GeoLevel(identifier: "unknown") == nil)
        #expect(GeoLevel(identifier: "") == nil)
    }
}

// MARK: - JSONValue strippingMetadataKeys Tests

@Suite("JSONValue strippingMetadataKeys")
struct JSONValueMetadataTests {

    @Test("Strips top-level underscore keys from dictionary")
    func stripsTopLevel() {
        let value: JSONValue = .dictionary([
            "markdown": .string("hello"),
            "_metadata": .dictionary([
                "geo_scope": .string("country"),
                "interface": .dictionary(["markdown": .dictionary([:])])
            ]),
            "_internal": .string("debug")
        ])
        let stripped = value.strippingMetadataKeys
        if case .dictionary(let dict) = stripped {
            #expect(dict["markdown"]?.stringValue == "hello")
            #expect(dict["_metadata"] == nil)
            #expect(dict["_internal"] == nil)
        }
    }

    @Test("Strips nested underscore keys recursively")
    func stripsNested() {
        let value: JSONValue = .dictionary([
            "Chinese cuisine": .dictionary([
                "qid": .string("Q123"),
                "_metadata": .dictionary([
                    "geo_scope": .string("country")
                ])
            ])
        ])
        let stripped = value.strippingMetadataKeys
        if case .dictionary(let outer) = stripped,
           case .dictionary(let inner) = outer["Chinese cuisine"] {
            #expect(inner["qid"]?.stringValue == "Q123")
            #expect(inner["_metadata"] == nil)
        }
    }

    @Test("Non-dictionary values pass through unchanged")
    func passesThrough() {
        let str: JSONValue = .string("hello")
        #expect(str.strippingMetadataKeys.stringValue == "hello")

        let num: JSONValue = .int(42)
        if case .int(let n) = num.strippingMetadataKeys {
            #expect(n == 42)
        }
    }
}
