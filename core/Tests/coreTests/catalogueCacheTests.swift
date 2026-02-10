import Testing
import Foundation
import CoreLocation
@testable import core

// MARK: - StorageKey Test Cases

/// Test case for `StorageKey.geoKey(from:level:)` parameterised tests.
///
/// Each case supplies the location fields and the expected geo-key string
/// (or `nil` when the key cannot be derived).
struct GeoKeyTestCase: Sendable, CustomTestStringConvertible {
    let label: String
    let countryCode: String?
    let adminArea: String?
    let locality: String?
    let subLocality: String?
    let level: GeoLevel
    let expectedKey: String?

    var testDescription: String { label }

    // MARK: - Washington D.C. (punctuation in name)

    static let washingtonDCCountry = GeoKeyTestCase(
        label: "Washington D.C. country key",
        countryCode: "US", adminArea: nil, locality: nil, subLocality: nil,
        level: .country, expectedKey: "us"
    )
    static let washingtonDCLocality = GeoKeyTestCase(
        label: "Washington D.C. periods and commas stripped from locality",
        countryCode: "US", adminArea: "District of Columbia", locality: "Washington, D.C.", subLocality: nil,
        level: .locality, expectedKey: "us.district_of_columbia.washington_dc"
    )
    static let washingtonDCSublocality = GeoKeyTestCase(
        label: "Washington D.C. full hierarchy with subLocality",
        countryCode: "US", adminArea: "District of Columbia", locality: "Washington, D.C.", subLocality: "Capitol Hill",
        level: .subLocality, expectedKey: "us.district_of_columbia.washington_dc.capitol_hill"
    )

    // MARK: - Portland disambiguation (same city name, different states)

    static let portlandOregon = GeoKeyTestCase(
        label: "Portland OR locality key",
        countryCode: "US", adminArea: "Oregon", locality: "Portland", subLocality: nil,
        level: .locality, expectedKey: "us.oregon.portland"
    )
    static let portlandMaine = GeoKeyTestCase(
        label: "Portland ME locality key differs from Portland OR",
        countryCode: "US", adminArea: "Maine", locality: "Portland", subLocality: nil,
        level: .locality, expectedKey: "us.maine.portland"
    )

    // MARK: - Córdoba disambiguation (same city name, different countries)

    static let cordobaArgentina = GeoKeyTestCase(
        label: "Córdoba Argentina: diacritics stripped, distinct from Spain",
        countryCode: "AR", adminArea: "Córdoba", locality: "Córdoba", subLocality: nil,
        level: .locality, expectedKey: "ar.cordoba.cordoba"
    )
    static let cordobaSpain = GeoKeyTestCase(
        label: "Córdoba Spain: same name, different country key",
        countryCode: "ES", adminArea: "Andalucía", locality: "Córdoba", subLocality: nil,
        level: .locality, expectedKey: "es.andalucia.cordoba"
    )

    // MARK: - Missing fields

    static let countryKeyMissing = GeoKeyTestCase(
        label: "country key nil when countryCode missing",
        countryCode: nil, adminArea: nil, locality: nil, subLocality: nil,
        level: .country, expectedKey: nil
    )
    static let adminAreaKeyMissingAdmin = GeoKeyTestCase(
        label: "adminArea key nil when adminArea missing",
        countryCode: "US", adminArea: nil, locality: nil, subLocality: nil,
        level: .adminArea, expectedKey: nil
    )
    static let localityKeyMissingLocality = GeoKeyTestCase(
        label: "locality key nil when locality missing",
        countryCode: "US", adminArea: "California", locality: nil, subLocality: nil,
        level: .locality, expectedKey: nil
    )
    static let subLocalityKeyMissingSub = GeoKeyTestCase(
        label: "subLocality key nil when subLocality missing",
        countryCode: "US", adminArea: "California", locality: "San Francisco", subLocality: nil,
        level: .subLocality, expectedKey: nil
    )

    // MARK: - Côte d'Ivoire (apostrophe + diacritics)

    static let coteIvoireCountry = GeoKeyTestCase(
        label: "Côte d'Ivoire country key",
        countryCode: "CI", adminArea: nil, locality: nil, subLocality: nil,
        level: .country, expectedKey: "ci"
    )
    static let coteIvoireLocality = GeoKeyTestCase(
        label: "Côte d'Ivoire locality: apostrophe and diacritics normalized",
        countryCode: "CI", adminArea: "Lagunes", locality: "Abidjan", subLocality: "Plateau",
        level: .subLocality, expectedKey: "ci.lagunes.abidjan.plateau"
    )
    static let coteIvoireAdminWithApostrophe = GeoKeyTestCase(
        label: "admin area with apostrophe: Côte d'Ivoire Vallée du Bandama",
        countryCode: "CI", adminArea: "Vallée du Bandama", locality: "Bouaké", subLocality: nil,
        level: .locality, expectedKey: "ci.vallee_du_bandama.bouake"
    )

    static let allCases: [GeoKeyTestCase] = [
        // Washington D.C.
        .washingtonDCCountry, .washingtonDCLocality, .washingtonDCSublocality,
        // Portland disambiguation
        .portlandOregon, .portlandMaine,
        // Córdoba disambiguation
        .cordobaArgentina, .cordobaSpain,
        // Missing fields
        .countryKeyMissing, .adminAreaKeyMissingAdmin,
        .localityKeyMissingLocality, .subLocalityKeyMissingSub,
        // Côte d'Ivoire
        .coteIvoireCountry, .coteIvoireLocality, .coteIvoireAdminWithApostrophe,
    ]
}

/// Test case for `StorageKey.normalize(_:)` parameterised tests.
///
/// Consolidates basic, diacritic-collision, special-character, non-Latin,
/// and whitespace edge-case normalize tests into a single parameterised suite.
struct NormalizeTestCase: Sendable, CustomTestStringConvertible {
    let label: String
    let input: String
    let expected: String

    var testDescription: String { label }

    // MARK: - Basic

    static let commasRemoved = NormalizeTestCase(
        label: "commas and periods removed", input: "Washington, D.C.", expected: "washington_dc"
    )
    static let leadingTrailingTrimmed = NormalizeTestCase(
        label: "leading/trailing whitespace trimmed", input: "  New York  ", expected: "new_york"
    )

    // MARK: - Diacritic collisions

    static let zurichUmlaut = NormalizeTestCase(
        label: "Zürich umlaut stripped", input: "Zürich", expected: "zurich"
    )
    static let zurichPlain = NormalizeTestCase(
        label: "Zurich plain (collides with Zürich)", input: "Zurich", expected: "zurich"
    )
    static let saoPauloWithDiacritics = NormalizeTestCase(
        label: "São Paulo diacritics stripped", input: "São Paulo", expected: "sao_paulo"
    )
    static let saoPauloWithout = NormalizeTestCase(
        label: "Sao Paulo without diacritics (collides)", input: "Sao Paulo", expected: "sao_paulo"
    )
    static let nurnbergGerman = NormalizeTestCase(
        label: "Nürnberg umlaut stripped", input: "Nürnberg", expected: "nurnberg"
    )
    static let nurembergEnglish = NormalizeTestCase(
        label: "Nuremberg stays distinct from Nürnberg", input: "Nuremberg", expected: "nuremberg"
    )

    // MARK: - Special characters

    static let apostrophe = NormalizeTestCase(
        label: "apostrophe replaced: Côte d'Ivoire", input: "Côte d'Ivoire", expected: "cote_d_ivoire"
    )
    static let hyphenated = NormalizeTestCase(
        label: "hyphen replaced: Stratford-upon-Avon", input: "Stratford-upon-Avon", expected: "stratford_upon_avon"
    )
    static let period = NormalizeTestCase(
        label: "period stripped: St. Louis", input: "St. Louis", expected: "st_louis"
    )
    static let parentheses = NormalizeTestCase(
        label: "parentheses replaced: Freiburg (Breisgau)", input: "Freiburg (Breisgau)", expected: "freiburg_breisgau"
    )

    // MARK: - Non-Latin scripts

    static let cjk = NormalizeTestCase(
        label: "CJK characters preserved", input: "東京都", expected: "東京都"
    )
    static let arabic = NormalizeTestCase(
        label: "Arabic characters preserved", input: "الرياض", expected: "الرياض"
    )
    static let cyrillic = NormalizeTestCase(
        label: "Cyrillic lowercased: Москва", input: "Москва", expected: "москва"
    )

    // MARK: - Whitespace edge cases

    static let multipleSpaces = NormalizeTestCase(
        label: "multiple spaces collapse to single underscore", input: "New   York", expected: "new_york"
    )
    static let tabAndNewline = NormalizeTestCase(
        label: "tab and newline treated as separators", input: "New\tYork\nCity", expected: "new_york_city"
    )
    static let onlyWhitespace = NormalizeTestCase(
        label: "only whitespace → empty", input: "   ", expected: ""
    )
    static let emptyString = NormalizeTestCase(
        label: "empty string → empty", input: "", expected: ""
    )

    static let allCases: [NormalizeTestCase] = [
        .commasRemoved, .leadingTrailingTrimmed,
        .zurichUmlaut, .zurichPlain, .saoPauloWithDiacritics, .saoPauloWithout,
        .nurnbergGerman, .nurembergEnglish,
        .apostrophe, .hyphenated, .period, .parentheses,
        .cjk, .arabic, .cyrillic,
        .multipleSpaces, .tabAndNewline, .onlyWhitespace, .emptyString,
    ]
}

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

    // MARK: - Geo Key Derivation (parameterised)

    @Test("geoKey derivation from location", arguments: GeoKeyTestCase.allCases)
    func geoKeyDerivation(testCase: GeoKeyTestCase) {
        let loc = makeLocation(
            countryCode: testCase.countryCode,
            adminArea: testCase.adminArea,
            locality: testCase.locality,
            subLocality: testCase.subLocality
        )
        let key = StorageKey.geoKey(from: loc, level: testCase.level)
        
        expect(
            key == testCase.expectedKey,
            success: "[\(testCase.label)] \ngeoKey = \(key ?? "nil")",
            failure: "[\(testCase.label)] expected: \n\(testCase.expectedKey ?? "nil"), got \(key ?? "nil")"
        )
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
        #expect(levels.count == 5) // country, adminArea, locality, subLocality, geohash
        #expect(levels[0].level == .country)
        #expect(levels[1].level == .adminArea)
        #expect(levels[2].level == .locality)
        #expect(levels[3].level == .subLocality)
        #expect(levels[4].level == .geohash)
    }

    @Test("applicableLevels skips levels with missing fields")
    func applicableLevelsPartial() {
        let loc = makeLocation(countryCode: "US", adminArea: "California")
        let levels = StorageKey.applicableLevels(from: loc)
        // Should have: country, adminArea, geohash (skips locality/subLocality)
        #expect(levels.count == 3)
        #expect(levels[0].level == .country)
        #expect(levels[1].level == .adminArea)
        #expect(levels[2].level == .geohash)
    }

    // MARK: - Normalization (parameterised)

    @Test("normalize transforms input correctly", arguments: NormalizeTestCase.allCases)
    func normalizeTransform(testCase: NormalizeTestCase) {
        let result = StorageKey.normalize(testCase.input)
        expect(
            result == testCase.expected,
            success: "[\(testCase.label)] normalize(\"\(testCase.input)\") = \"\(result)\"",
            failure: "[\(testCase.label)] expected \"\(testCase.expected)\", got \"\(result)\""
        )
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

    /// Scoped sections (with _metadata.location.geoscope) mimicking the new backend behavior.
    private func makeScopedSections() -> [CachedSection] {
        [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary([
                    "country_overview": .dictionary([
                        "markdown": .string("# Welcome to China"),
                        "_metadata": .dictionary([
                            "location": .dictionary([
                                "geoscope": .string("country"),
                                "context": .dictionary([:])
                            ]),
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
                            "location": .dictionary([
                                "geoscope": .string("country"),
                                "context": .dictionary([:])
                            ]),
                            "interface": .dictionary([
                                "card": .dictionary(["render_type": .string("dish")])
                            ])
                        ])
                    ]),
                    "Huaiyang cuisine": .dictionary([
                        "qid": .string("Q456"),
                        "cards": .array([.dictionary(["local_name": .string("Lion's Head Meatball")])]),
                        "_metadata": .dictionary([
                            "location": .dictionary([
                                "geoscope": .string("locality"),
                                "context": .dictionary([:])
                            ]),
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

    // MARK: - Scoped (_metadata.location.geoscope) Tests

    @Test("Scoped: splits content by _metadata.location.geoscope into separate context files")
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
               case .dictionary(let metaDict) = chineseDict["_metadata"],
               case .dictionary(let locDict) = metaDict["location"] {
                #expect(locDict["geoscope"]?.stringValue == "country")
                #expect(metaDict["interface"] != nil)
            } else {
                Issue.record("Chinese cuisine should retain _metadata with location.geoscope and interface")
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
                            "location": .dictionary([
                                "geoscope": .string("locality"),
                                "context": .dictionary([:])
                            ]),
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
                            "location": .dictionary([
                                "geoscope": .string("country"),
                                "context": .dictionary([:])
                            ]),
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
            if case .dictionary(let metaDict) = countryOverview["_metadata"],
               case .dictionary(let locDict) = metaDict["location"] {
                #expect(locDict["geoscope"]?.stringValue == "country")
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

/// A single test-case value for the `contentHasGeoScope` parameterised suite.
///
/// - `expectGeoscope`: whether `contentHasGeoScope` should return `true`.
/// - `contextMatched`: whether the `_metadata.location.context` dict contains
///   a key for the declared geoscope level whose value is non-nil (i.e. the
///   backend actually filled in the geographic identity for that level).
struct GeoScopeTestCase: Sendable, CustomTestStringConvertible {
    let label: String
    let content: JSONValue
    let expectGeoscope: Bool
    let contextMatched: Bool

    var testDescription: String { label }

    // MARK: - Factory helpers

    /// Item with full geoscope + populated context at the given level.
    static let itemWithCountryContext = GeoScopeTestCase(
        label: "item with geoscope=country and country_code in context",
        content: .dictionary([
            "Chinese cuisine": .dictionary([
                "qid": .string("Q123"),
                "_metadata": .dictionary([
                    "location": .dictionary([
                        "geoscope": .string("country"),
                        "context": .dictionary([
                            "country_code": .string("CN")
                        ])
                    ])
                ])
            ])
        ]),
        expectGeoscope: true,
        contextMatched: true
    )

    /// Item with geoscope but an empty context dict.
    static let itemWithEmptyContext = GeoScopeTestCase(
        label: "item with geoscope=country but empty context",
        content: .dictionary([
            "Chinese cuisine": .dictionary([
                "qid": .string("Q123"),
                "_metadata": .dictionary([
                    "location": .dictionary([
                        "geoscope": .string("country"),
                        "context": .dictionary([:])
                    ])
                ])
            ])
        ]),
        expectGeoscope: true,
        contextMatched: false
    )

    /// Item with geoscope=locality and context that has locality key.
    static let itemWithLocalityContext = GeoScopeTestCase(
        label: "item with geoscope=locality and locality in context",
        content: .dictionary([
            "Huaiyang cuisine": .dictionary([
                "qid": .string("Q456"),
                "_metadata": .dictionary([
                    "location": .dictionary([
                        "geoscope": .string("locality"),
                        "context": .dictionary([
                            "country_code": .string("CN"),
                            "admin_area": .string("Jiangsu"),
                            "locality": .string("Huai'an")
                        ])
                    ])
                ])
            ])
        ]),
        expectGeoscope: true,
        contextMatched: true
    )

    /// Item with geoscope=locality but context only has country_code (missing locality key).
    static let itemWithMismatchedContext = GeoScopeTestCase(
        label: "item with geoscope=locality but context missing locality key",
        content: .dictionary([
            "Some dish": .dictionary([
                "qid": .string("Q789"),
                "_metadata": .dictionary([
                    "location": .dictionary([
                        "geoscope": .string("locality"),
                        "context": .dictionary([
                            "country_code": .string("JP")
                        ])
                    ])
                ])
            ])
        ]),
        expectGeoscope: true,
        contextMatched: false
    )

    /// Plain content with no _metadata at all.
    static let noMetadata = GeoScopeTestCase(
        label: "plain content without _metadata",
        content: .dictionary([
            "markdown": .string("# Hello")
        ]),
        expectGeoscope: false,
        contextMatched: false
    )

    /// _metadata present but missing location.geoscope.
    static let metadataWithoutGeoscope = GeoScopeTestCase(
        label: "_metadata present but no location.geoscope",
        content: .dictionary([
            "item": .dictionary([
                "_metadata": .dictionary([
                    "interface": .dictionary(["markdown": .dictionary([:])])
                ])
            ])
        ]),
        expectGeoscope: false,
        contextMatched: false
    )

    /// Collects all cases for the parameterised test.
    static let allCases: [GeoScopeTestCase] = [
        .itemWithCountryContext,
        .itemWithEmptyContext,
        .itemWithLocalityContext,
        .itemWithMismatchedContext,
        .noMetadata,
        .metadataWithoutGeoscope,
    ]
}

// MARK: - Context-key lookup for contextMatched verification

/// Returns the `_metadata.location.context` key that corresponds to a given
/// geoscope string (e.g. `"country"` → `"country_code"`).
private func contextKeyForGeoscope(_ geoscope: String) -> String? {
    switch geoscope {
    case "country":      return "country_code"
    case "admin_area":    return "admin_area"
    case "locality":     return "locality"
    case "sub_locality":  return "sub_locality"
    default:             return nil
    }
}

/// Extracts the first `_metadata.location.context` dict from the content and
/// checks whether the key corresponding to the declared geoscope level has a
/// non-nil, non-empty string value.
private func evaluateContextMatched(content: JSONValue) -> Bool {
    guard case .dictionary(let dict) = content else { return false }
    for (key, value) in dict {
        if key.hasPrefix("_") { continue }
        guard case .dictionary(let itemDict) = value,
              case .dictionary(let metaDict) = itemDict["_metadata"],
              case .dictionary(let locDict) = metaDict["location"],
              let geoscope = locDict["geoscope"]?.stringValue,
              case .dictionary(let contextDict) = locDict["context"],
              let expectedKey = contextKeyForGeoscope(geoscope),
              case .string(let val) = contextDict[expectedKey],
              !val.isEmpty else {
            continue
        }
        return true
    }
    return false
}

@Suite("CatalogueFileStore geo-scope helpers")
struct GeoScopeHelperTests {

    // MARK: - contentHasGeoScope + contextMatched (parameterised)

    @Test("contentHasGeoScope and contextMatched expectations", arguments: GeoScopeTestCase.allCases)
    func geoScopeDetection(testCase: GeoScopeTestCase) {
        let hasGeoScope = CatalogueFileStore.contentHasGeoScope(testCase.content)
        let isContextMatched = evaluateContextMatched(content: testCase.content)

        expectAll([
            (hasGeoScope == testCase.expectGeoscope,
             "[\(testCase.label)] expectGeoscope: expected \(testCase.expectGeoscope), got \(hasGeoScope)"),
            (isContextMatched == testCase.contextMatched,
             "[\(testCase.label)] contextMatched: expected \(testCase.contextMatched), got \(isContextMatched)"),
        ], success: "[\(testCase.label)] geoscope=\(testCase.expectGeoscope), contextMatched=\(testCase.contextMatched)")
    }

    @Test("extractGeoScopedFragments splits items by _metadata.location.geoscope into multiple levels")
    func extractItemLevel() {
        let content: JSONValue = .dictionary([
            "Chinese cuisine": .dictionary([
                "qid": .string("Q123"),
                "_metadata": .dictionary([
                    "location": .dictionary([
                        "geoscope": .string("country"),
                        "context": .dictionary([:])
                    ]),
                    "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                ])
            ]),
            "Huaiyang cuisine": .dictionary([
                "qid": .string("Q456"),
                "_metadata": .dictionary([
                    "location": .dictionary([
                        "geoscope": .string("locality"),
                        "context": .dictionary([:])
                    ]),
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
                if case .dictionary(let metaDict) = inner["_metadata"],
                   case .dictionary(let locDict) = metaDict["location"] {
                    #expect(locDict["geoscope"]?.stringValue == "country")
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
                "location": .dictionary([
                    "geoscope": .string("country"),
                    "context": .dictionary([:])
                ]),
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
                    "location": .dictionary([
                        "geoscope": .string("country"),
                        "context": .dictionary([:])
                    ])
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

// MARK: - StorageKey Geographic Edge Cases

@Suite("StorageKey geographic edge cases")
struct StorageKeyEdgeCaseTests {

    private func makeLocation(
        countryCode: String? = nil,
        adminArea: String? = nil,
        locality: String? = nil,
        subLocality: String? = nil,
        timezone: String = "UTC",
        lat: Double = 0.0,
        lon: Double = 0.0
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

    // MARK: - Same Name, Different Countries

    @Test("Córdoba Argentina vs Córdoba Spain produce distinct keys at all levels")
    func cordobaArgentinaVsSpain() {
        let cordobaAR = makeLocation(
            countryCode: "AR", adminArea: "Córdoba", locality: "Córdoba",
            lat: -31.4201, lon: -64.1888
        )
        let cordobaES = makeLocation(
            countryCode: "ES", adminArea: "Andalucía", locality: "Córdoba",
            lat: 37.8882, lon: -4.7794
        )

        let countryAR = StorageKey.geoKey(from: cordobaAR, level: .country)
        let countryES = StorageKey.geoKey(from: cordobaES, level: .country)
        let localityAR = StorageKey.geoKey(from: cordobaAR, level: .locality)
        let localityES = StorageKey.geoKey(from: cordobaES, level: .locality)

        expectAll([
            (countryAR == "ar", "AR country key should be 'ar', got '\(countryAR ?? "nil")'"),
            (countryES == "es", "ES country key should be 'es', got '\(countryES ?? "nil")'"),
            (countryAR != countryES, "Country keys must differ between AR and ES"),
            (localityAR == "ar.cordoba.cordoba", "AR locality key should be 'ar.cordoba.cordoba', got '\(localityAR ?? "nil")'"),
            (localityES == "es.andalucia.cordoba", "ES locality key should be 'es.andalucia.cordoba', got '\(localityES ?? "nil")'"),
            (localityAR != localityES, "Locality keys must differ between AR and ES Córdoba"),
        ], success: "Córdoba AR vs ES keys are fully distinct at all levels")
    }

    @Test("Georgia (country GE) vs Georgia (US state) — country code prevents collision")
    func georgiaCountryVsState() {
        let georgiaCountry = makeLocation(
            countryCode: "GE", adminArea: "Tbilisi", locality: "Tbilisi",
            lat: 41.7151, lon: 44.8271
        )
        let georgiaState = makeLocation(
            countryCode: "US", adminArea: "Georgia", locality: "Atlanta",
            lat: 33.7490, lon: -84.3880
        )

        let keyGE = StorageKey.geoKey(from: georgiaCountry, level: .country)
        let keyUS = StorageKey.geoKey(from: georgiaState, level: .country)
        let adminGE = StorageKey.geoKey(from: georgiaCountry, level: .adminArea)
        let adminUS = StorageKey.geoKey(from: georgiaState, level: .adminArea)

        expectAll([
            (keyGE == "ge", "Georgia country key should be 'ge', got '\(keyGE ?? "nil")'"),
            (keyUS == "us", "US country key should be 'us', got '\(keyUS ?? "nil")'"),
            (adminGE == "ge.tbilisi", "GE admin key should be 'ge.tbilisi', got '\(adminGE ?? "nil")'"),
            (adminUS == "us.georgia", "US admin key should be 'us.georgia', got '\(adminUS ?? "nil")'"),
            (adminGE != adminUS, "Admin keys must differ between Georgia (country) and Georgia (state)"),
        ], success: "Georgia country vs US state keys are fully distinct")
    }

    // MARK: - Same Country, Different Admin, Same Locality

    @Test("Portland Oregon vs Portland Maine produce distinct locality keys")
    func portlandOregonVsMaine() {
        let portlandOR = makeLocation(
            countryCode: "US", adminArea: "Oregon", locality: "Portland",
            lat: 45.5152, lon: -122.6784
        )
        let portlandME = makeLocation(
            countryCode: "US", adminArea: "Maine", locality: "Portland",
            lat: 43.6591, lon: -70.2568
        )

        let keyOR = StorageKey.geoKey(from: portlandOR, level: .locality)
        let keyME = StorageKey.geoKey(from: portlandME, level: .locality)
        let countryOR = StorageKey.geoKey(from: portlandOR, level: .country)
        let countryME = StorageKey.geoKey(from: portlandME, level: .country)

        expectAll([
            (keyOR == "us.oregon.portland", "OR locality key should be 'us.oregon.portland', got '\(keyOR ?? "nil")'"),
            (keyME == "us.maine.portland", "ME locality key should be 'us.maine.portland', got '\(keyME ?? "nil")'"),
            (keyOR != keyME, "Locality keys must differ between Oregon and Maine Portland"),
            (countryOR == countryME, "Country keys should be identical for cross-city reuse"),
        ], success: "Portland OR vs ME: distinct locality keys, shared country key")
    }

    @Test("Springfield in 4 US states: unique locality keys, shared country key")
    func springfieldMultipleStates() {
        let states = ["Illinois", "Missouri", "Massachusetts", "Ohio"]
        let coords: [(Double, Double)] = [
            (39.7817, -89.6501), (37.2090, -93.2923),
            (42.1015, -72.5898), (39.9242, -83.8088)
        ]

        var localityKeys = Set<String>()
        var countryKeys = Set<String>()

        for (state, coord) in zip(states, coords) {
            let loc = makeLocation(
                countryCode: "US", adminArea: state, locality: "Springfield",
                lat: coord.0, lon: coord.1
            )
            if let key = StorageKey.geoKey(from: loc, level: .locality) {
                localityKeys.insert(key)
            }
            if let key = StorageKey.geoKey(from: loc, level: .country) {
                countryKeys.insert(key)
            }
        }

        expectAll([
            (localityKeys.count == 4, "Expected 4 unique locality keys, got \(localityKeys.count)"),
            (countryKeys.count == 1, "Expected 1 shared country key, got \(countryKeys.count)"),
            (countryKeys.first == "us", "Country key should be 'us', got '\(countryKeys.first ?? "nil")'"),
        ], success: "4 Springfields: unique locality keys, shared 'us' country key")
    }

    // MARK: - Direct-Administered Municipalities

    @Test("Shanghai — admin area equals locality produces valid but redundant key segments")
    func shanghaiDirectMunicipality() {
        let shanghai = makeLocation(
            countryCode: "CN", adminArea: "Shanghai", locality: "Shanghai",
            lat: 31.2304, lon: 121.4737
        )
        let localityKey = StorageKey.geoKey(from: shanghai, level: .locality)
        let adminKey = StorageKey.geoKey(from: shanghai, level: .adminArea)
        expectAll([
            (localityKey == "cn.shanghai.shanghai", "Locality key should be 'cn.shanghai.shanghai', got '\(localityKey ?? "nil")'"),
            (adminKey == "cn.shanghai", "Admin key should be 'cn.shanghai', got '\(adminKey ?? "nil")'"),
            (adminKey != localityKey, "Admin and locality keys must differ even when names are equal"),
        ], success: "Shanghai: admin == locality produces valid distinct keys")
    }

    @Test("Beijing — admin == locality does not collapse hierarchy levels")
    func beijingDirectMunicipality() {
        let beijing = makeLocation(
            countryCode: "CN", adminArea: "Beijing", locality: "Beijing",
            lat: 39.9042, lon: 116.4074
        )
        let levels = StorageKey.applicableLevels(from: beijing)
        expectAll([
            (levels.count == 4, "Expected 4 levels (country, adminArea, locality, geohash), got \(levels.count)"),
            (levels.map(\.level) == [.country, .adminArea, .locality, .geohash], "Levels should be in order: country, adminArea, locality, geohash"),
        ], success: "Beijing: admin == locality does not collapse hierarchy")
    }

    // MARK: - Geohash Boundary Behavior

    @Test("Antipodal points produce different geohashes")
    func antipodalGeohashes() {
        let northPole = makeLocation(lat: 89.99, lon: 0.0)
        let southPole = makeLocation(lat: -89.99, lon: 0.0)
        let keyN = StorageKey.geoKey(from: northPole, level: .geohash)
        let keyS = StorageKey.geoKey(from: southPole, level: .geohash)
        #expect(keyN != keyS)
    }

    @Test("International date line neighbors: 179.99 vs -179.99 longitude")
    func dateLine() {
        let east = makeLocation(lat: 0.0, lon: 179.99)
        let west = makeLocation(lat: 0.0, lon: -179.99)
        let keyE = StorageKey.geoKey(from: east, level: .geohash)
        let keyW = StorageKey.geoKey(from: west, level: .geohash)
        // These are geographically close but on opposite longitude extremes
        #expect(keyE != keyW, "Date line neighbors should get different geohashes")
    }
}

// MARK: - CatalogueFileStore Cross-Geography Edge Cases

@Suite("CatalogueFileStore cross-geography edge cases")
struct CatalogueFileStoreCrossGeographyTests {

    private func makeIsolatedStore() -> CatalogueFileStore {
        let uniqueDir = "catalogue_edge_\(UUID().uuidString)"
        return CatalogueFileStore(baseSubdirectory: uniqueDir)
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

    // MARK: - Córdoba: Same City Name, Different Countries

    @Test("Córdoba Argentina cache does not bleed into Córdoba Spain")
    func cordobaCacheIsolation() async throws {
        let store = makeIsolatedStore()

        let argSections = [
            CachedSection(
                sectionType: "cuisine",
                displayTitle: "Cuisine",
                content: .dictionary([
                    "Argentine cuisine": .dictionary([
                        "cards": .array([.dictionary(["local_name": .string("Asado")])])
                    ])
                ])
            )
        ]
        let cordobaAR = makeLocation(
            countryCode: "AR", adminArea: "Córdoba", locality: "Córdoba",
            timezone: "America/Argentina/Cordoba", lat: -31.4201, lon: -64.1888
        )
        try await store.persist(sections: argSections, sectionOrder: ["cuisine"], location: cordobaAR)

        let spanishSections = [
            CachedSection(
                sectionType: "cuisine",
                displayTitle: "Cuisine",
                content: .dictionary([
                    "Andalusian cuisine": .dictionary([
                        "cards": .array([.dictionary(["local_name": .string("Salmorejo")])])
                    ])
                ])
            )
        ]
        let cordobaES = makeLocation(
            countryCode: "ES", adminArea: "Andalucía", locality: "Córdoba",
            timezone: "Europe/Madrid", lat: 37.8882, lon: -4.7794
        )
        try await store.persist(sections: spanishSections, sectionOrder: ["cuisine"], location: cordobaES)

        // Restore Argentina — should only see Argentine food
        let restoredAR = try await store.restore(for: cordobaAR)
        let cuisineAR = restoredAR.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisineAR?.content {
            expectAll([
                (dict["Argentine cuisine"] != nil, "Argentine cuisine missing from AR restore"),
                (dict["Andalusian cuisine"] == nil, "Andalusian cuisine leaked into AR restore"),
            ], success: "AR Córdoba cache contains only Argentine cuisine")
        } else {
            Issue.record("AR cuisine should be a dictionary with only Argentine cuisine")
        }

        // Restore Spain — should only see Spanish food
        let restoredES = try await store.restore(for: cordobaES)
        let cuisineES = restoredES.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisineES?.content {
            expectAll([
                (dict["Andalusian cuisine"] != nil, "Andalusian cuisine missing from ES restore"),
                (dict["Argentine cuisine"] == nil, "Argentine cuisine leaked into ES restore"),
            ], success: "ES Córdoba cache contains only Andalusian cuisine")
        } else {
            Issue.record("ES cuisine should be a dictionary with only Andalusian cuisine")
        }
    }

    // MARK: - Portland: Same Locality, Same Country, Different Admin Area

    @Test("Portland Oregon and Portland Maine stay isolated at locality level")
    func portlandCacheIsolation() async throws {
        let store = makeIsolatedStore()

        let oregonSections = [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary(["markdown": .string("# Portland, Oregon — Rose City")])
            )
        ]
        let portlandOR = makeLocation(
            countryCode: "US", adminArea: "Oregon", locality: "Portland",
            timezone: "America/Los_Angeles", lat: 45.5152, lon: -122.6784
        )
        try await store.persist(sections: oregonSections, sectionOrder: ["overview"], location: portlandOR)

        let maineSections = [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary(["markdown": .string("# Portland, Maine — Vacationland")])
            )
        ]
        let portlandME = makeLocation(
            countryCode: "US", adminArea: "Maine", locality: "Portland",
            timezone: "America/New_York", lat: 43.6591, lon: -70.2568
        )
        try await store.persist(sections: maineSections, sectionOrder: ["overview"], location: portlandME)

        // Restore Oregon Portland — should see Rose City (locality-level)
        let restoredOR = try await store.restore(for: portlandOR)
        let overviewOR = restoredOR.first { $0.sectionType == "overview" }
        if case .dictionary(let dict) = overviewOR?.content {
            #expect(dict["markdown"]?.stringValue?.contains("Rose City") == true)
        } else {
            Issue.record("Oregon Portland should have Rose City overview")
        }

        // Restore Maine Portland — should see Vacationland (locality-level)
        let restoredME = try await store.restore(for: portlandME)
        let overviewME = restoredME.first { $0.sectionType == "overview" }
        if case .dictionary(let dict) = overviewME?.content {
            #expect(dict["markdown"]?.stringValue?.contains("Vacationland") == true)
        } else {
            Issue.record("Maine Portland should have Vacationland overview")
        }
    }

    @Test("Portland OR and Portland ME share country-level content via legacy duplicate")
    func portlandSharesCountryLevel() async throws {
        let store = makeIsolatedStore()

        let sections = [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary(["markdown": .string("# USA overview")])
            )
        ]
        let portlandOR = makeLocation(
            countryCode: "US", adminArea: "Oregon", locality: "Portland",
            lat: 45.5152, lon: -122.6784
        )
        try await store.persist(sections: sections, sectionOrder: ["overview"], location: portlandOR)

        // Restore for Maine Portland — should find country-level content
        let portlandME = makeLocation(
            countryCode: "US", adminArea: "Maine", locality: "Portland",
            lat: 43.6591, lon: -70.2568
        )
        let restored = try await store.restore(for: portlandME)
        #expect(!restored.isEmpty, "Legacy duplicate should provide country-level content")
    }

    // MARK: - Scoped Content: Cross-Country Isolation

    @Test("Scoped: country cuisine persisted in Argentina does not appear for Spain restore")
    func scopedCrossContinentIsolation() async throws {
        let store = makeIsolatedStore()

        let combinedSection = CachedSection(
            sectionType: "cuisine",
            displayTitle: "Cuisine",
            content: .dictionary([
                "Argentine cuisine": .dictionary([
                    "qid": .string("Q_AR"),
                    "cards": .array([.dictionary(["local_name": .string("Empanadas")])]),
                    "_metadata": .dictionary([
                        "location": .dictionary([
                            "geoscope": .string("country"),
                            "context": .dictionary([:])
                        ]),
                        "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                    ])
                ]),
                "Cordobese cuisine": .dictionary([
                    "qid": .string("Q_COR_AR"),
                    "cards": .array([.dictionary(["local_name": .string("Locro")])]),
                    "_metadata": .dictionary([
                        "location": .dictionary([
                            "geoscope": .string("locality"),
                            "context": .dictionary([:])
                        ]),
                        "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                    ])
                ])
            ])
        )

        let cordobaAR = makeLocation(
            countryCode: "AR", adminArea: "Córdoba", locality: "Córdoba",
            lat: -31.4201, lon: -64.1888
        )
        try await store.persist(sections: [combinedSection], sectionOrder: ["cuisine"], location: cordobaAR)

        // Restore for Córdoba, Spain — different country, should find nothing
        let cordobaES = makeLocation(
            countryCode: "ES", adminArea: "Andalucía", locality: "Córdoba",
            lat: 37.8882, lon: -4.7794
        )
        let restoredES = try await store.restore(for: cordobaES)
        #expect(restoredES.isEmpty, "Spanish Córdoba must not see Argentine cache data")
    }

    @Test("Scoped: same country different city gets country-scoped items but not locality-scoped")
    func scopedSameCountryDifferentCity() async throws {
        let store = makeIsolatedStore()

        let combinedSection = CachedSection(
            sectionType: "cuisine",
            displayTitle: "Cuisine",
            content: .dictionary([
                "Argentine cuisine": .dictionary([
                    "qid": .string("Q_AR"),
                    "cards": .array([.dictionary(["local_name": .string("Empanadas")])]),
                    "_metadata": .dictionary([
                        "location": .dictionary([
                            "geoscope": .string("country"),
                            "context": .dictionary([:])
                        ]),
                        "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                    ])
                ]),
                "Cordobese cuisine": .dictionary([
                    "qid": .string("Q_COR"),
                    "cards": .array([.dictionary(["local_name": .string("Locro")])]),
                    "_metadata": .dictionary([
                        "location": .dictionary([
                            "geoscope": .string("locality"),
                            "context": .dictionary([:])
                        ]),
                        "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                    ])
                ])
            ])
        )

        let cordobaAR = makeLocation(
            countryCode: "AR", adminArea: "Córdoba", locality: "Córdoba",
            lat: -31.4201, lon: -64.1888
        )
        try await store.persist(sections: [combinedSection], sectionOrder: ["cuisine"], location: cordobaAR)

        // Buenos Aires — same country, different city
        let buenosAires = makeLocation(
            countryCode: "AR", adminArea: "Buenos Aires", locality: "Buenos Aires",
            lat: -34.6037, lon: -58.3816
        )
        let restored = try await store.restore(for: buenosAires)
        let cuisine = restored.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisine?.content {
            expectAll([
                (dict["Argentine cuisine"] != nil, "Country-scoped Argentine cuisine should be available in Buenos Aires"),
                (dict["Cordobese cuisine"] == nil, "Locality-scoped Cordobese cuisine must NOT appear for different city"),
            ], success: "Buenos Aires gets country-scoped items only, no Córdoba locality items")
        } else {
            Issue.record("Should have country-level cuisine available for Buenos Aires")
        }
    }

    // MARK: - Direct-Administered Municipality Cache Behavior

    @Test("Shanghai: admin area == locality caches and restores correctly")
    func shanghaiCacheRoundTrip() async throws {
        let store = makeIsolatedStore()

        let sections = [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary(["markdown": .string("# Shanghai")])
            )
        ]
        let shanghai = makeLocation(
            countryCode: "CN", adminArea: "Shanghai", locality: "Shanghai",
            timezone: "Asia/Shanghai", lat: 31.2304, lon: 121.4737
        )
        try await store.persist(sections: sections, sectionOrder: ["overview"], location: shanghai)

        let restored = try await store.restore(for: shanghai)
        #expect(restored.count == 1)
        let overview = restored.first { $0.sectionType == "overview" }
        if case .dictionary(let dict) = overview?.content {
            #expect(dict["markdown"]?.stringValue?.contains("Shanghai") == true)
        } else {
            Issue.record("Shanghai overview should round-trip")
        }
    }

    @Test("Shanghai cache is NOT locality-matched for Suzhou (different admin + locality)")
    func shanghaiNotReturnedForSuzhou() async throws {
        let store = makeIsolatedStore()

        let sections = [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary(["markdown": .string("# Shanghai overview")])
            )
        ]
        let shanghai = makeLocation(
            countryCode: "CN", adminArea: "Shanghai", locality: "Shanghai",
            lat: 31.2304, lon: 121.4737
        )
        try await store.persist(sections: sections, sectionOrder: ["overview"], location: shanghai)

        // Suzhou is in Jiangsu, not Shanghai admin area
        let suzhou = makeLocation(
            countryCode: "CN", adminArea: "Jiangsu", locality: "Suzhou",
            lat: 31.2990, lon: 120.5853
        )
        let restored = try await store.restore(for: suzhou)
        // Should get country-level duplicate only (legacy mode), not Shanghai's locality data
        let overview = restored.first { $0.sectionType == "overview" }
        expectAll([
            (!restored.isEmpty, "Country-level duplicate should be found for Suzhou"),
            (overview != nil, "Country-level overview should be available for Suzhou"),
        ], success: "Suzhou gets country-level data only, not Shanghai locality data")
    }

    // MARK: - Diacritics and Normalization in Persistence

    @Test("Diacritics in admin area: Córdoba normalizes consistently for cache hit")
    func diacriticsInAdminAreaCacheHit() async throws {
        let store = makeIsolatedStore()

        let sections = [
            CachedSection(
                sectionType: "overview",
                displayTitle: "Overview",
                content: .dictionary(["markdown": .string("# Córdoba Province")])
            )
        ]

        // Persist with diacritics
        let withDiacritics = makeLocation(
            countryCode: "AR", adminArea: "Córdoba", locality: "Córdoba",
            lat: -31.4201, lon: -64.1888
        )
        try await store.persist(sections: sections, sectionOrder: ["overview"], location: withDiacritics)

        // Restore with stripped diacritics (as might come from a different geocoder)
        let withoutDiacritics = makeLocation(
            countryCode: "AR", adminArea: "Cordoba", locality: "Cordoba",
            lat: -31.4201, lon: -64.1888
        )
        let restored = try await store.restore(for: withoutDiacritics)
        #expect(!restored.isEmpty, "Diacritic-stripped name should still produce a cache hit")
    }

    // MARK: - Overwrite Behavior

    @Test("Second persist to the same location overwrites locality file")
    func overwriteSameLocation() async throws {
        let store = makeIsolatedStore()
        let location = makeLocation()

        let v1 = [CachedSection(
            sectionType: "overview",
            displayTitle: "Overview",
            content: .dictionary(["markdown": .string("Version 1")])
        )]
        try await store.persist(sections: v1, sectionOrder: ["overview"], location: location)

        let v2 = [CachedSection(
            sectionType: "overview",
            displayTitle: "Overview",
            content: .dictionary(["markdown": .string("Version 2")])
        )]
        try await store.persist(sections: v2, sectionOrder: ["overview"], location: location)

        let restored = try await store.restore(for: location)
        let overview = restored.first { $0.sectionType == "overview" }
        if case .dictionary(let dict) = overview?.content {
            #expect(dict["markdown"]?.stringValue == "Version 2")
        } else {
            Issue.record("Overwritten content should be Version 2")
        }
    }

    // MARK: - Country-Level Overwrite from Different Cities

    @Test("Persisting for Portland ME overwrites country file previously written by Portland OR")
    func countryLevelOverwriteFromDifferentCity() async throws {
        let store = makeIsolatedStore()

        let orSections = [CachedSection(
            sectionType: "overview",
            displayTitle: "Overview",
            content: .dictionary(["markdown": .string("Written from Oregon")])
        )]
        let portlandOR = makeLocation(
            countryCode: "US", adminArea: "Oregon", locality: "Portland",
            lat: 45.5152, lon: -122.6784
        )
        try await store.persist(sections: orSections, sectionOrder: ["overview"], location: portlandOR)

        let meSections = [CachedSection(
            sectionType: "overview",
            displayTitle: "Overview",
            content: .dictionary(["markdown": .string("Written from Maine")])
        )]
        let portlandME = makeLocation(
            countryCode: "US", adminArea: "Maine", locality: "Portland",
            lat: 43.6591, lon: -70.2568
        )
        try await store.persist(sections: meSections, sectionOrder: ["overview"], location: portlandME)

        // A third city in the US (Chicago) should see the country-level file from Maine
        let chicago = makeLocation(
            countryCode: "US", adminArea: "Illinois", locality: "Chicago",
            lat: 41.8781, lon: -87.6298
        )
        let restored = try await store.restore(for: chicago)
        let overview = restored.first { $0.sectionType == "overview" }
        if case .dictionary(let dict) = overview?.content {
            #expect(dict["markdown"]?.stringValue == "Written from Maine",
                    "Country file should reflect the last city that wrote it")
        } else {
            Issue.record("Chicago should get country-level data")
        }
    }

    // MARK: - Multiple Sections with Mixed Scopes Across Ambiguous Names

    @Test("Scoped: two countries with same-name localities keep scoped items isolated")
    func scopedSameLocalityNameDifferentCountries() async throws {
        let store = makeIsolatedStore()

        // Persist scoped content for Santiago, Chile
        let chileSections = [
            CachedSection(
                sectionType: "cuisine",
                displayTitle: "Cuisine",
                content: .dictionary([
                    "Chilean cuisine": .dictionary([
                        "qid": .string("Q_CL"),
                        "cards": .array([.dictionary(["local_name": .string("Pastel de Choclo")])]),
                        "_metadata": .dictionary([
                            "location": .dictionary([
                                "geoscope": .string("country"),
                                "context": .dictionary([:])
                            ]),
                            "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                        ])
                    ]),
                    "Santiaguino cuisine": .dictionary([
                        "qid": .string("Q_SCL"),
                        "cards": .array([.dictionary(["local_name": .string("Completo")])]),
                        "_metadata": .dictionary([
                            "location": .dictionary([
                                "geoscope": .string("locality"),
                                "context": .dictionary([:])
                            ]),
                            "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                        ])
                    ])
                ])
            )
        ]
        let santiagoChile = makeLocation(
            countryCode: "CL", adminArea: "Santiago Metropolitan", locality: "Santiago",
            lat: -33.4489, lon: -70.6693
        )
        try await store.persist(sections: chileSections, sectionOrder: ["cuisine"], location: santiagoChile)

        // Persist scoped content for Santiago de Compostela, Spain
        let spainSections = [
            CachedSection(
                sectionType: "cuisine",
                displayTitle: "Cuisine",
                content: .dictionary([
                    "Galician cuisine": .dictionary([
                        "qid": .string("Q_GAL"),
                        "cards": .array([.dictionary(["local_name": .string("Pulpo a la Gallega")])]),
                        "_metadata": .dictionary([
                            "location": .dictionary([
                                "geoscope": .string("country"),
                                "context": .dictionary([:])
                            ]),
                            "interface": .dictionary(["card": .dictionary(["render_type": .string("dish")])])
                        ])
                    ])
                ])
            )
        ]
        let santiagoSpain = makeLocation(
            countryCode: "ES", adminArea: "Galicia", locality: "Santiago de Compostela",
            lat: 42.8782, lon: -8.5448
        )
        try await store.persist(sections: spainSections, sectionOrder: ["cuisine"], location: santiagoSpain)

        // Restore Chile — should see Chilean + Santiaguino, NOT Galician
        let restoredCL = try await store.restore(for: santiagoChile)
        let cuisineCL = restoredCL.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisineCL?.content {
            expectAll([
                (dict["Chilean cuisine"] != nil, "Chilean cuisine missing from Chile restore"),
                (dict["Santiaguino cuisine"] != nil, "Santiaguino locality cuisine missing from Chile restore"),
                (dict["Galician cuisine"] == nil, "Galician cuisine leaked into Chile"),
            ], success: "Santiago Chile: has Chilean + Santiaguino, no Galician leakage")
        } else {
            Issue.record("Chile should have its own cuisine sections")
        }

        // Restore Spain — should see Galician, NOT Chilean
        let restoredES = try await store.restore(for: santiagoSpain)
        let cuisineES = restoredES.first { $0.sectionType == "cuisine" }
        if case .dictionary(let dict) = cuisineES?.content {
            expectAll([
                (dict["Galician cuisine"] != nil, "Galician cuisine missing from Spain restore"),
                (dict["Chilean cuisine"] == nil, "Chilean cuisine leaked into Spain"),
                (dict["Santiaguino cuisine"] == nil, "Santiaguino locality-scoped item leaked into Spain"),
            ], success: "Santiago de Compostela: has Galician only, no Chilean leakage")
        } else {
            Issue.record("Spain should have its own cuisine sections")
        }
    }
}
