//
//  AutocompleteManager.swift
//  unheardpath
//
//  Owns Geocoder, MKLocalSearchCompleter, and autocomplete results ([MapSearchResult]).
//  The completer is a persistent @MainActor instance — delegate results arrive
//  asynchronously and are merged with Geoapify results for progressive display.
//  Caches last merged response and filters/ranks client-side when query extends cached prefix.
//  Used by MainView+Autocomplete and AddrSearch for autocomplete only.
//

import Foundation
import MapKit
import core

@MainActor
final class AutocompleteManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var searchResults: [MapSearchResult] = []

    let geocoder: Geocoder
    private let mkCompleter = MKLocalSearchCompleter()
    private var currentQuery: String = ""
    /// The query that was last sent to the completer; used to discard stale delegate callbacks.
    private var mkCompleterQuery: String = ""
    private var lastSearchQuery: String = ""
    private var lastSearchResults: [MapSearchResult] = []
    /// The query for which Geoapify results have been fetched. Cache is only valid when this matches lastSearchQuery.
    private var lastGeoapifySearchQuery: String = ""
    /// Partial results from each source, kept separately for progressive merging.
    private var lastMapKitResults: [MapSearchResult] = []
    private var lastGeoapifyResults: [MapSearchResult] = []
    private var searchTask: Task<Void, Never>?
    private let geoapifyDebounceNanoseconds: UInt64 = 150_000_000 // 0.15s
    private let logger: Logger

    private static let geoapifyMinimumCharacters = 3
    private static let displayCap = 6
    private static let maxTotalResults = 15

    init(geoapifyApiKey: String, logger: Logger = AppLifecycleManager.sharedLogger) {
        self.logger = logger
        self.geocoder = Geocoder(geoapifyApiKey: geoapifyApiKey, logger: logger)
        super.init()
        mkCompleter.delegate = self
        mkCompleter.resultTypes = [.address, .pointOfInterest]
    }

    /// Updates the search query.
    /// - MKLocalSearchCompleter fires immediately on 1+ chars (it self-debounces internally).
    /// - Geoapify fires after debounce at 3+ chars (geoapifyMinimumCharacters).
    /// Uses cache when query matches or extends last search for the Geoapify side.
    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearCacheAndResults()
            searchTask?.cancel()
            return
        }
        currentQuery = trimmed

        // Fire completer immediately on any non-empty query — it handles its own debouncing
        mkCompleterQuery = trimmed
        mkCompleter.queryFragment = trimmed

        if trimmed.count < Self.geoapifyMinimumCharacters {
            // Below Geoapify threshold: cancel pending Geoapify task and clear its results.
            // Completer results arrive via delegate and display on their own.
            searchTask?.cancel()
            lastGeoapifyResults = []
            return
        }

        // 3+ chars: debounce and run Geoapify (completer already fired above)
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: geoapifyDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await applyUpdateQuery(trimmed: trimmed)
        }
    }

    private func clearCacheAndResults() {
        lastSearchQuery = ""
        lastSearchResults = []
        lastGeoapifySearchQuery = ""
        lastMapKitResults = []
        lastGeoapifyResults = []
        mkCompleterQuery = ""
        searchResults = []
    }

    /// Branch: exact match → use cache; extends prefix → filter cache or API if empty; else → API.
    /// Cache is only valid when Geoapify has resolved for the base query (lastGeoapifySearchQuery).
    private func applyUpdateQuery(trimmed: String) async {
        let isGeoapifyCacheValid = lastGeoapifySearchQuery == lastSearchQuery && !lastSearchQuery.isEmpty

        if trimmed == lastSearchQuery, isGeoapifyCacheValid {
            searchResults = filterRankAndCap(cache: lastSearchResults, query: trimmed)
            return
        }
        if trimmed.hasPrefix(lastSearchQuery), trimmed.count > lastSearchQuery.count, isGeoapifyCacheValid {
            let filtered = lastSearchResults.filter { item in
                item.name.localizedCaseInsensitiveContains(trimmed) || item.address.localizedCaseInsensitiveContains(trimmed)
            }
            if filtered.isEmpty {
                await performSearch(query: trimmed)
                return
            }
            searchResults = filterRankAndCap(cache: filtered, query: trimmed)
            return
        }
        await performSearch(query: trimmed)
    }

    /// Filter: name/address contains query (case-insensitive). Rank: name starts with, name contains, address starts with, address contains. Cap to displayCap.
    private func filterRankAndCap(cache: [MapSearchResult], query: String) -> [MapSearchResult] {
        let lower = query.lowercased()
        let filtered = cache.filter { item in
            item.name.localizedCaseInsensitiveContains(query) || item.address.localizedCaseInsensitiveContains(query)
        }
        let ranked = filtered.sorted { a, b in
            let scoreA = rankScore(name: a.name, address: a.address, queryLower: lower)
            let scoreB = rankScore(name: b.name, address: b.address, queryLower: lower)
            return scoreA < scoreB
        }
        return Array(ranked.prefix(Self.displayCap))
    }

    private func rankScore(name: String, address: String, queryLower: String) -> Int {
        let n = name.lowercased()
        let a = address.lowercased()
        if n.hasPrefix(queryLower) { return 0 }
        if n.contains(queryLower) { return 1 }
        if a.hasPrefix(queryLower) { return 2 }
        if a.contains(queryLower) { return 3 }
        return 4
    }

    /// Fires Geoapify autocomplete and merges with whatever completer results are available.
    /// The completer is already fired from updateQuery on every keystroke; this only handles Geoapify.
    private func performSearch(query: String) async {
        // Reset Geoapify results for the new query.
        // MapKit completer results are managed by the delegate — not reset here so they stay visible.
        lastGeoapifyResults = []
        lastGeoapifySearchQuery = ""

        do {
            let results = try await geocoder.autocompleteGeoapify(query: query)
            guard query == currentQuery, !Task.isCancelled else { return }
            lastGeoapifyResults = results
            lastGeoapifySearchQuery = query
            mergeAndPublish(query: query)
        } catch {
            logger.error("Geoapify autocomplete failed", handlerType: "AutocompleteManager", error: error)
            // MapKit completer results (if any) still display; don't clear them
        }
    }

    /// Merges partial results from both sources, applies filter/rank/cap, and publishes to UI.
    private func mergeAndPublish(query: String) {
        let merged = Geocoder.interleave(maxTotal: Self.maxTotalResults, first: lastGeoapifyResults, second: lastMapKitResults)
        lastSearchQuery = query
        lastSearchResults = merged
        searchResults = filterRankAndCap(cache: merged, query: query)
    }

    func clearSearchResults() {
        searchTask?.cancel()
        searchTask = nil
        currentQuery = ""
        clearCacheAndResults()
    }

    // MARK: - MKLocalSearchCompleterDelegate

    /// Called when the completer has new suggestions. Converts to MapSearchResult and merges with Geoapify.
    /// Marked nonisolated because MKLocalSearchCompleterDelegate methods are non-isolated ObjC protocol requirements.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let capped = Array(completer.results.prefix(8)) // matches completerResultCap
        let results = capped.map { MapSearchResult($0) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.mkCompleterQuery == self.currentQuery, !self.currentQuery.isEmpty else { return }
            self.lastMapKitResults = results
            self.mergeAndPublish(query: self.currentQuery)
        }
    }

    /// Called when the completer fails. Logs the error; Geoapify results still display if available.
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.error("MKLocalSearchCompleter failed", handlerType: "AutocompleteManager", error: error)
        }
    }
}
