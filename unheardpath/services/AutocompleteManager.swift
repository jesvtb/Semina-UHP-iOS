//
//  AutocompleteManager.swift
//  unheardpath
//
//  Owns Geocoder and autocomplete results ([MapSearchResult]).
//  Caches last API response and filters/ranks client-side when query extends cached prefix.
//  Used by MainView+Autocomplete and AddrSearch for autocomplete only.
//

import Foundation
import core

@MainActor
final class AutocompleteManager: ObservableObject {
    @Published private(set) var searchResults: [MapSearchResult] = []

    private let geocoder: Geocoder
    private var currentQuery: String = ""
    private var lastSearchQuery: String = ""
    private var lastSearchResults: [MapSearchResult] = []
    private var searchTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64 = 150_000_000 // 0.15s
    private let logger: Logger

    private static let minimumCharactersForSearch = 3
    private static let displayCap = 6

    init(geoapifyApiKey: String, logger: Logger = AppLifecycleManager.sharedLogger) {
        self.logger = logger
        self.geocoder = Geocoder(geoapifyApiKey: geoapifyApiKey, logger: logger)
    }

    /// Updates the search query; debounced. Uses cache when query matches or extends last search; otherwise calls API.
    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearCacheAndResults()
            searchTask?.cancel()
            return
        }
        currentQuery = trimmed
        if trimmed.count < Self.minimumCharactersForSearch {
            clearCacheAndResults()
            searchTask?.cancel()
            return
        }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await applyUpdateQuery(trimmed: trimmed)
        }
    }

    private func clearCacheAndResults() {
        lastSearchQuery = ""
        lastSearchResults = []
        searchResults = []
    }

    /// Branch: exact match → use cache; extends prefix → filter cache or API if empty; else → API.
    private func applyUpdateQuery(trimmed: String) async {
        if trimmed == lastSearchQuery {
            searchResults = filterRankAndCap(cache: lastSearchResults, query: trimmed)
            return
        }
        if trimmed.hasPrefix(lastSearchQuery), trimmed.count > lastSearchQuery.count, !lastSearchQuery.isEmpty {
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

    private func performSearch(query: String) async {
        do {
            let results = try await geocoder.search(query: query)
            guard query == currentQuery else { return }
            lastSearchQuery = query
            lastSearchResults = results
            searchResults = filterRankAndCap(cache: results, query: query)
        } catch {
            logger.error("Autocomplete search failed", handlerType: "AutocompleteManager", error: error)
            guard query == currentQuery else { return }
            searchResults = []
        }
    }

    func clearSearchResults() {
        searchTask?.cancel()
        searchTask = nil
        currentQuery = ""
        clearCacheAndResults()
    }
}
