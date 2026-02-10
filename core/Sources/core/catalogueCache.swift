//
//  catalogueCache.swift
//  core
//
//  Protocol-based catalogue persistence layer with file-based MVP implementation.
//  Stores catalogue sections at geographic levels for cross-city content reuse.
//

import Foundation
import CoreLocation

// MARK: - Storage Models (Codable)

/// Lightweight location summary for cache key derivation. Stored alongside cached contexts.
public struct CachedLocationSummary: Codable, Sendable {
    public let countryCode: String?
    public let adminArea: String?
    public let locality: String?
    public let subLocality: String?
    public let timezone: String?
    public let latitude: Double
    public let longitude: Double

    public init(from location: LocationDetailData) {
        self.countryCode = location.countryCode
        self.adminArea = location.adminArea
        self.locality = location.locality
        self.subLocality = location.subLocality
        self.timezone = location.timezone
        self.latitude = location.location.coordinate.latitude
        self.longitude = location.location.coordinate.longitude
    }

    /// Direct memberwise initializer for construction without a `LocationDetailData`.
    public init(
        countryCode: String?,
        adminArea: String?,
        locality: String?,
        subLocality: String?,
        timezone: String?,
        latitude: Double,
        longitude: Double
    ) {
        self.countryCode = countryCode
        self.adminArea = adminArea
        self.locality = locality
        self.subLocality = subLocality
        self.timezone = timezone
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Reconstruct a `LocationDetailData` for key derivation (not full geocoding).
    public func toLocationDetailData() -> LocationDetailData {
        LocationDetailData(
            location: CLLocation(latitude: latitude, longitude: longitude),
            countryCode: countryCode,
            timezone: timezone,
            adminArea: adminArea,
            locality: locality,
            subLocality: subLocality
        )
    }

    /// Creates a copy with geographic identity fields overridden by backend-provided
    /// ``_metadata.location.context`` values.
    ///
    /// Backend context keys use the Python model's snake_case naming:
    /// `country_code`, `admin_area`, `locality`, `sub_locality`.
    /// Fields absent from the context dict retain their device-derived values.
    /// Non-geographic fields (timezone, coordinates) are always preserved.
    public func overriding(withBackendContext context: [String: String]) -> CachedLocationSummary {
        CachedLocationSummary(
            countryCode: context["country_code"] ?? self.countryCode,
            adminArea: context["admin_area"] ?? self.adminArea,
            locality: context["locality"] ?? self.locality,
            subLocality: context["sub_locality"] ?? self.subLocality,
            timezone: self.timezone,
            latitude: self.latitude,
            longitude: self.longitude
        )
    }
}

/// Codable mirror of CatalogueSection for persistence.
/// Stores the same fields but as pure Codable types (JSONValue is already Codable).
public struct CachedSection: Codable, Sendable {
    public let sectionType: String
    public let displayTitle: String
    public let content: JSONValue

    public init(sectionType: String, displayTitle: String, content: JSONValue) {
        self.sectionType = sectionType
        self.displayTitle = displayTitle
        self.content = content
    }
}

/// A geo-level snapshot containing all catalogue sections cached for that geographic context.
public struct CachedContext: Codable, Sendable {
    public let geoKey: String
    public let level: GeoLevel
    public let locationSummary: CachedLocationSummary
    public let sections: [CachedSection]
    /// Order of section types as received from the server.
    public let sectionOrder: [String]
    public let createdAt: Date
    public var lastAccessedAt: Date

    public init(
        geoKey: String,
        level: GeoLevel,
        locationSummary: CachedLocationSummary,
        sections: [CachedSection],
        sectionOrder: [String],
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.geoKey = geoKey
        self.level = level
        self.locationSummary = locationSummary
        self.sections = sections
        self.sectionOrder = sectionOrder
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
}

/// Snapshot of the last active catalogue state, used for fast relaunch restoration.
public struct CachedCatalogueSnapshot: Codable, Sendable {
    public let geoKey: String
    public let level: GeoLevel
    public let locationSummary: CachedLocationSummary
    /// Section order for display.
    public let sectionOrder: [String]
    public let savedAt: Date

    public init(geoKey: String, level: GeoLevel, locationSummary: CachedLocationSummary, sectionOrder: [String], savedAt: Date = Date()) {
        self.geoKey = geoKey
        self.level = level
        self.locationSummary = locationSummary
        self.sectionOrder = sectionOrder
        self.savedAt = savedAt
    }
}

// MARK: - CataloguePersisting Protocol

/// Abstraction for catalogue persistence backends.
///
/// MVP uses file-based JSON storage (`CatalogueFileStore`).
/// Future implementations can use SQLite or other backends by conforming to this protocol.
public protocol CataloguePersisting: Sendable {
    /// Save sections for a given location. Internally determines which geo-levels to write.
    func persist(sections: [CachedSection], sectionOrder: [String], location: LocationDetailData) async throws

    /// Restore sections for a location by merging applicable geo-levels (country -> locality).
    /// Returns sections in display order, with more specific levels overriding less specific ones.
    func restore(for location: LocationDetailData) async throws -> [CachedSection]

    /// Restore whatever was last active (for app relaunch with no location yet).
    func restoreLastContext() async throws -> (sections: [CachedSection], snapshot: CachedCatalogueSnapshot)?

    /// Remove expired context files.
    func clearExpired() async throws
}

// MARK: - CatalogueFileStore

/// File-based catalogue persistence using the Caches directory.
///
/// Storage layout:
/// ```
/// Caches/catalogue/
///   contexts/
///     us.json                              # country-level
///     us.california.san_francisco.json     # locality-level
///   last_context.json                      # pointer to last active context
/// ```
public final class CatalogueFileStore: CataloguePersisting, @unchecked Sendable {

    private let subdirectory: String
    private let snapshotFilename = "last_context.json"
    private let snapshotSubdirectory: String

    /// Maximum age for cached contexts before they are considered expired.
    private let maxContextAge: TimeInterval

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - maxContextAgeDays: Number of days before a context file expires (default: 14).
    ///   - baseSubdirectory: Root subdirectory under Caches for all catalogue files (default: "catalogue").
    ///     Override in tests for isolation.
    public init(maxContextAgeDays: Int = 14, baseSubdirectory: String = "catalogue") {
        self.maxContextAge = TimeInterval(maxContextAgeDays * 24 * 3600)
        self.subdirectory = "\(baseSubdirectory)/contexts"
        self.snapshotSubdirectory = baseSubdirectory

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - CataloguePersisting

    public func persist(sections: [CachedSection], sectionOrder: [String], location: LocationDetailData) async throws {
        guard !sections.isEmpty else { return }

        let locationSummary = CachedLocationSummary(from: location)
        let levels = StorageKey.applicableLevels(from: location)

        // Use named levels only (excluding geohash for MVP).
        let namedLevels = levels.filter { $0.level != .geohash }
        guard let mostSpecific = namedLevels.last else { return }

        // Check if any section carries _metadata.location.geoscope metadata.
        let hasGeoScope = sections.contains { Self.contentHasGeoScope($0.content) }

        // Snapshot defaults from device-derived location; overridden with
        // backend-canonical identity in the geo-scoped path below.
        var snapshotKey = mostSpecific.key
        var snapshotLevel = mostSpecific.level
        var snapshotSummary = locationSummary
        var snapshotUpdated = false

        if hasGeoScope {
            // Scoped persistence: split content items by their _metadata.location.geoscope, write each level separately.
            var levelSections: [GeoLevel: [CachedSection]] = [:]

            for section in sections {
                let fragments = Self.extractGeoScopedFragments(from: section.content, defaultLevel: mostSpecific.level)
                for (level, fragmentContent) in fragments {
                    let partialSection = CachedSection(
                        sectionType: section.sectionType,
                        displayTitle: section.displayTitle,
                        content: fragmentContent
                    )
                    levelSections[level, default: []].append(partialSection)
                }
            }

            // Write a context file for each level that has content.
            // Use backend-provided _metadata.location.context as the source of truth
            // for both the geo key (file name) and the locationSummary, falling back
            // to device-derived values when backend context is unavailable.
            for (level, levelSecs) in levelSections {
                // Extract backend location context from any section's content at this level.
                let backendContext = levelSecs.lazy.compactMap { Self.extractBackendLocationContext(from: $0.content) }.first

                // Derive geo key from backend context (source of truth), falling back to device-derived key.
                let geoKey: String
                if let ctx = backendContext,
                   let backendKey = StorageKey.geoKey(fromBackendContext: ctx, level: level) {
                    geoKey = backendKey
                } else if let deviceKey = namedLevels.first(where: { $0.level == level })?.key {
                    geoKey = deviceKey
                } else {
                    continue
                }

                // Override geographic identity with backend context, preserving device-derived
                // timezone and coordinates.
                let levelSummary = backendContext.map { locationSummary.overriding(withBackendContext: $0) } ?? locationSummary

                let context = CachedContext(
                    geoKey: geoKey,
                    level: level,
                    locationSummary: levelSummary,
                    sections: levelSecs,
                    sectionOrder: sectionOrder
                )
                try writeContext(context)

                // Track the most specific level persisted for the snapshot.
                if !snapshotUpdated || level > snapshotLevel {
                    snapshotKey = geoKey
                    snapshotLevel = level
                    snapshotSummary = levelSummary
                    snapshotUpdated = true
                }
            }
        } else {
            // Legacy (no location.geoscope): duplicate at most-specific + country for cross-city reuse.
            let context = CachedContext(
                geoKey: mostSpecific.key,
                level: mostSpecific.level,
                locationSummary: locationSummary,
                sections: sections,
                sectionOrder: sectionOrder
            )
            try writeContext(context)

            if let countryLevel = namedLevels.first(where: { $0.level == .country }),
               countryLevel.key != mostSpecific.key {
                let countryContext = CachedContext(
                    geoKey: countryLevel.key,
                    level: .country,
                    locationSummary: locationSummary,
                    sections: sections,
                    sectionOrder: sectionOrder
                )
                try writeContext(countryContext)
            }
        }

        // Update last-context snapshot.
        let snapshot = CachedCatalogueSnapshot(
            geoKey: snapshotKey,
            level: snapshotLevel,
            locationSummary: snapshotSummary,
            sectionOrder: sectionOrder
        )
        try writeSnapshot(snapshot)
    }

    public func restore(for location: LocationDetailData) async throws -> [CachedSection] {
        // Use named levels only (excluding geohash) for MVP restoration.
        let levels = StorageKey.applicableLevels(from: location).filter { $0.level != .geohash }
        guard !levels.isEmpty else { return [] }

        // Load contexts from most general to most specific.
        // For sections present at multiple levels, merge content dictionaries
        // (more specific keys override less specific ones).
        var mergedSections: [String: CachedSection] = [:]
        var mergedOrder: [String] = []

        for (_, key) in levels {
            guard let context = try readContext(geoKey: key) else { continue }
            for section in context.sections {
                if let existing = mergedSections[section.sectionType] {
                    // Merge content: specific-level keys override same keys from a more general level.
                    let mergedContent = Self.mergeContent(base: existing.content, override: section.content)
                    mergedSections[section.sectionType] = CachedSection(
                        sectionType: section.sectionType,
                        displayTitle: section.displayTitle,
                        content: mergedContent
                    )
                } else {
                    mergedSections[section.sectionType] = section
                }
            }
            // Use the order from the most specific context that has data.
            if !context.sectionOrder.isEmpty {
                mergedOrder = context.sectionOrder
            }
        }

        guard !mergedSections.isEmpty else { return [] }

        // Return sections in display order, then any extras not in the order list.
        if !mergedOrder.isEmpty {
            var result: [CachedSection] = []
            var seen = Set<String>()
            for sectionType in mergedOrder {
                if let section = mergedSections[sectionType] {
                    result.append(section)
                    seen.insert(sectionType)
                }
            }
            for (sectionType, section) in mergedSections where !seen.contains(sectionType) {
                result.append(section)
            }
            return result
        }

        return Array(mergedSections.values)
    }

    public func restoreLastContext() async throws -> (sections: [CachedSection], snapshot: CachedCatalogueSnapshot)? {
        guard let snapshot = try readSnapshot() else { return nil }

        // Reconstruct full catalogue by merging all applicable levels,
        // not just the single file the snapshot points to.
        let location = snapshot.locationSummary.toLocationDetailData()
        let sections = try await restore(for: location)
        guard !sections.isEmpty else { return nil }

        return (sections, snapshot)
    }

    // MARK: - Geo-Scope Helpers

    /// Whether the content JSONValue contains any `_metadata.location.geoscope` metadata.
    static func contentHasGeoScope(_ content: JSONValue) -> Bool {
        guard case .dictionary(let dict) = content else { return false }

        // Item-level _metadata.location.geoscope
        for (_, value) in dict {
            if case .dictionary(let itemDict) = value,
               case .dictionary(let metaDict) = itemDict["_metadata"],
               case .dictionary(let locDict) = metaDict["location"],
               locDict["geoscope"]?.stringValue != nil {
                return true
            }
        }
        return false
    }

    /// Extracts the ``_metadata.location.context`` dict from the first content item that carries one.
    ///
    /// The backend embeds canonical geographic identity in each catalogue item as
    /// ``_metadata.location.context`` (e.g. `{"country_code": "JP", "admin_area": "Kyoto Prefecture"}`).
    /// This method returns the first such context found, or `nil` if no item carries one.
    static func extractBackendLocationContext(from content: JSONValue) -> [String: String]? {
        guard case .dictionary(let dict) = content else { return nil }
        for (key, value) in dict {
            if key.hasPrefix("_") { continue }
            if case .dictionary(let itemDict) = value,
               case .dictionary(let metaDict) = itemDict["_metadata"],
               case .dictionary(let locDict) = metaDict["location"],
               case .dictionary(let contextDict) = locDict["context"] {
                var result: [String: String] = [:]
                for (k, v) in contextDict {
                    if let str = v.stringValue {
                        result[k] = str
                    }
                }
                if !result.isEmpty { return result }
            }
        }
        return nil
    }

    /// Splits a section's content by `_metadata.location.geoscope`.
    ///
    /// Each keyed item is grouped by the `geoscope` found in its `_metadata.location` dict.
    /// Items without `_metadata.location.geoscope` default to `defaultLevel`.
    ///
    /// The full `_metadata` (including `location` and `interface`) is preserved in the returned
    /// fragments so that UI rendering configuration and location identity survive persistence
    /// and restoration.
    static func extractGeoScopedFragments(
        from content: JSONValue,
        defaultLevel: GeoLevel
    ) -> [(level: GeoLevel, content: JSONValue)] {
        guard case .dictionary(let dict) = content else {
            return [(defaultLevel, content)]
        }

        var fragments: [GeoLevel: [String: JSONValue]] = [:]

        for (key, value) in dict {
            // Skip metadata keys at root level.
            if key.hasPrefix("_") { continue }

            if case .dictionary(let itemDict) = value,
               case .dictionary(let metaDict) = itemDict["_metadata"],
               case .dictionary(let locDict) = metaDict["location"],
               let scopeStr = locDict["geoscope"]?.stringValue,
               let level = GeoLevel(identifier: scopeStr) {
                fragments[level, default: [:]][key] = .dictionary(itemDict)
            } else {
                fragments[defaultLevel, default: [:]][key] = value
            }
        }

        if fragments.isEmpty {
            return [(defaultLevel, content)]
        }

        return fragments.map { (level, items) in (level, JSONValue.dictionary(items)) }
    }

    /// Merge two content `JSONValue`s. Both should be dictionaries.
    /// Keys in `override` take precedence over keys in `base`.
    static func mergeContent(base: JSONValue, override: JSONValue) -> JSONValue {
        guard case .dictionary(var baseDict) = base,
              case .dictionary(let overrideDict) = override else {
            // If not both dicts, override wins entirely.
            return override
        }

        for (key, value) in overrideDict {
            baseDict[key] = value
        }

        return .dictionary(baseDict)
    }

    public func clearExpired() async throws {
        let fm = FileManager.default
        let base = Storage.cachesURL.appendingPathComponent(subdirectory)

        guard fm.fileExists(atPath: base.path),
              let files = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        let now = Date()
        for fileURL in files {
            guard fileURL.pathExtension == "json" else { continue }
            if let attributes = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = attributes.contentModificationDate,
               now.timeIntervalSince(modified) > maxContextAge {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - File I/O Helpers

    private func contextFilename(for geoKey: String) -> String {
        "\(geoKey).json"
    }

    private func writeContext(_ context: CachedContext) throws {
        let data = try encoder.encode(context)
        try Storage.saveToCaches(data: data, filename: contextFilename(for: context.geoKey), subdirectory: subdirectory)
    }

    private func readContext(geoKey: String) throws -> CachedContext? {
        let filename = contextFilename(for: geoKey)
        guard Storage.existsInCaches(filename: filename, subdirectory: subdirectory) else { return nil }

        do {
            let data = try Storage.loadFromCaches(filename: filename, subdirectory: subdirectory)
            var context = try decoder.decode(CachedContext.self, from: data)
            // Update last accessed timestamp
            context.lastAccessedAt = Date()
            // Write back updated timestamp (best effort)
            try? writeContext(context)
            return context
        } catch {
            // Corrupted file -- remove it and return nil
            try? Storage.deleteFromCaches(filename: filename, subdirectory: subdirectory)
            return nil
        }
    }

    private func writeSnapshot(_ snapshot: CachedCatalogueSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try Storage.saveToCaches(data: data, filename: snapshotFilename, subdirectory: snapshotSubdirectory)
    }

    private func readSnapshot() throws -> CachedCatalogueSnapshot? {
        guard Storage.existsInCaches(filename: snapshotFilename, subdirectory: snapshotSubdirectory) else { return nil }

        do {
            let data = try Storage.loadFromCaches(filename: snapshotFilename, subdirectory: snapshotSubdirectory)
            return try decoder.decode(CachedCatalogueSnapshot.self, from: data)
        } catch {
            // Corrupted -- remove and return nil
            try? Storage.deleteFromCaches(filename: snapshotFilename, subdirectory: snapshotSubdirectory)
            return nil
        }
    }
}
