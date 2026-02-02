//
//  AutocompleteManager.swift
//  unheardpath
//
//  Owns Geocoder and autocomplete results ([MapSearchResult]).
//  Used by MainView+Autocomplete and AddrSearch for autocomplete only.
//

import Foundation
import core

@MainActor
final class AutocompleteManager: ObservableObject {
    @Published private(set) var searchResults: [MapSearchResult] = []

    private let geocoder: Geocoder
    private var currentQuery: String = ""
    private var searchTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64 = 150_000_000 // 0.15s
    private let logger: Logger

    init(geoapifyApiKey: String, logger: Logger = AppLifecycleManager.sharedLogger) {
        self.logger = logger
        self.geocoder = Geocoder(geoapifyApiKey: geoapifyApiKey, logger: logger)
    }

    private static let minimumCharactersForSearch = 3

    /// Updates the search query; debounced and runs Geoapify + MKLocalSearch via Geocoder.
    /// Only triggers search when query has at least `minimumCharactersForSearch` characters.
    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            currentQuery = ""
            searchResults = []
            searchTask?.cancel()
            return
        }
        currentQuery = trimmed
        if trimmed.count < Self.minimumCharactersForSearch {
            searchResults = []
            searchTask?.cancel()
            return
        }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        do {
            let results = try await geocoder.search(query: query)
            guard query == currentQuery else { return }
            searchResults = results
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
        searchResults = []
    }
}
