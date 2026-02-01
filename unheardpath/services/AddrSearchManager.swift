import SwiftUI
@preconcurrency import MapKit
import Combine
import CoreLocation
import core

// MARK: - Search Source
enum SearchSource: Sendable {
    case geoapify
    case mapkit
}

// MARK: - Address Search Result
/// Unified result type that can represent both Geoapify and MapKit search results
/// Note: Not Sendable due to MKLocalSearchCompletion, but safe to use on MainActor
enum AddressSearchResult {
    case geoapify(PointFeature, coordinate: CLLocationCoordinate2D, subtitle: String)
    case mapkit(MKLocalSearchCompletion)
    
    /// Title for display (from PointFeature.title for Geoapify, completion.title for MapKit)
    var title: String {
        switch self {
        case .geoapify(let pointFeature, _, let subtitle):
            // Try PointFeature.title first (handles names.device_lang > local_lang > global_lang > title > name)
            if let title = pointFeature.title, !title.isEmpty {
                return title
            }
            
            // Fallback: Try additional Geoapify property names
            guard let properties = pointFeature.properties else {
                // Last resort: Extract city from subtitle
                let parts = subtitle.components(separatedBy: ",")
                if let firstPart = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !firstPart.isEmpty {
                    return firstPart
                }
                return "Unknown"
            }
            
            // Try "formatted" property (Geoapify formatted address)
            if let formattedValue = properties["formatted"],
               let formatted = formattedValue.stringValue,
               !formatted.isEmpty {
                // Use first part of formatted address (before comma) as title
                let parts = formatted.components(separatedBy: ",")
                if let firstPart = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !firstPart.isEmpty {
                    return firstPart
                }
            }
            
            // Try "city" property directly
            if let cityValue = properties["city"],
               let city = cityValue.stringValue,
               !city.isEmpty {
                return city
            }
            
            // Try "name" property (sometimes Geoapify uses this directly)
            if let nameValue = properties["name"],
               let name = nameValue.stringValue,
               !name.isEmpty {
                return name
            }
            
            // Last resort: Extract city from subtitle
            let parts = subtitle.components(separatedBy: ",")
            if let firstPart = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
               !firstPart.isEmpty {
                return firstPart
            }
            return "Unknown"
            
        case .mapkit(let completion):
            return completion.title
        }
    }
    
    /// Subtitle for display (built from PointFeature properties for Geoapify, completion.subtitle for MapKit)
    var subtitle: String {
        switch self {
        case .geoapify(_, _, let subtitle):
            return subtitle
        case .mapkit(let completion):
            return completion.subtitle
        }
    }
    
    /// Coordinate if available directly (Geoapify has it, MapKit requires geocoding)
    var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .geoapify(_, let coordinate, _):
            return coordinate
        case .mapkit:
            return nil
        }
    }
    
    /// Source of the search result
    var source: SearchSource {
        switch self {
        case .geoapify:
            return .geoapify
        case .mapkit:
            return .mapkit
        }
    }
    
    /// Extract MKLocalSearchCompletion for MapKit results
    var mapkitCompletion: MKLocalSearchCompletion? {
        switch self {
        case .mapkit(let completion):
            return completion
        case .geoapify:
            return nil
        }
    }
}

/// Manages address search autocomplete using MKLocalSearchCompleter and GeoapifyGateway
/// Encapsulates the completer and delegate into a single ObservableObject
/// for cleaner SwiftUI integration
@MainActor
class AddressSearchManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [AddressSearchResult] = []
    
    nonisolated(unsafe) private let completer = MKLocalSearchCompleter()
    private let geoapifyGateway = GeoapifyGateway()
    private var currentQuery: String = ""
    
    // EventManager reference (set after initialization)
    weak var eventManager: EventManager?
    
    // Logger for error and debug logging
    private let logger: Logger
    
    init(logger: Logger = AppLifecycleManager.sharedLogger) {
        self.logger = logger
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
        
        // Configure for global search (minimizes location bias)
        // Set a very large region to cover the entire Earth
        let globalCenter = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        completer.region = MKCoordinateRegion(
            center: globalCenter,
            latitudinalMeters: 200_000_000, // ~20,000 km (covers entire Earth)
            longitudinalMeters: 200_000_000
        )
    }
    
    /// Updates the search query fragment and performs parallel searches
    /// - Parameter query: The search query string
    func updateQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            currentQuery = ""
            results = []
            completer.queryFragment = ""
            return
        }
        
        // Update current query
        currentQuery = trimmedQuery
        
        // Update MapKit completer query (triggers delegate callback)
            completer.queryFragment = trimmedQuery
        
        // Run Geoapify search in parallel
        Task {
            await performGeoapifySearch(query: trimmedQuery)
        }
    }
    
    /// Performs Geoapify search and merges results with MapKit results
    /// - Parameter query: The search query string
    private func performGeoapifySearch(query: String) async {
        do {
            logger.debug("Starting Geoapify search for: '\(query)'")
            
            // Call Geoapify API - limit to 3 results (we'll interleave with MapKit, max 6 total)
            let data = try await geoapifyGateway.searchCities(query: query, limit: 3)
            
            // Parse JSON response
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("Geoapify response is not a JSON object", handlerType: "AddrSearchManager")
                return
            }
            
            // Extract features using GeoJSON helper
            let features = try GeoJSON.extractFeatures(from: jsonObject)
            
            logger.debug("Geoapify returned \(features.count) features")
            
            // Convert to PointFeatures and build AddressSearchResult array
            var geoapifyResults: [AddressSearchResult] = []
            for feature in features {
                guard let pointFeature = PointFeature(from: feature),
                      let coordinate = pointFeature.clCoordinate else {
                    logger.warning("Skipping feature - not a valid PointFeature or missing coordinate", handlerType: "AddrSearchManager")
                    continue
                }
                
                // Build subtitle from PointFeature properties
                let subtitle = pointFeature.subtitle
                
                geoapifyResults.append(.geoapify(pointFeature, coordinate: coordinate, subtitle: subtitle))
            }
            
            logger.debug("Geoapify parsed \(geoapifyResults.count) valid results")
            
            // Reverse Geoapify results so most relevant appears at bottom in UI
            // (UI shows last item as most relevant, so we reverse to match)
            let reversedGeoapifyResults = geoapifyResults.reversed()
            
            // Only update results if this query is still current (prevent stale results)
            // Since performGeoapifySearch is called from MainActor context, we need to check on MainActor
            let (isCurrentQuery, mapkitResults) = await MainActor.run {
                let isCurrent = query == self.currentQuery
                let mapkit = self.results.filter { result in
                    if case .mapkit = result {
                        return true
                    }
                    return false
                }
                return (isCurrent, mapkit)
            }
            
            guard isCurrentQuery else {
                let currentQueryValue = await MainActor.run { self.currentQuery }
                logger.warning("Geoapify query '\(query)' is no longer current (current: '\(currentQueryValue)')", handlerType: "AddrSearchManager")
                return
            }
            
            // Interleave results to prioritize best from each category
            await MainActor.run {
                // Double-check query is still current
                if query == self.currentQuery {
                    self.results = self.interleaveResults(Array(reversedGeoapifyResults), mapkitResults)
                    self.logger.debug("Interleaved results: \(geoapifyResults.count) Geoapify + \(mapkitResults.count) MapKit = \(self.results.count) total")
                } else {
                    self.logger.warning("Query changed during merge, skipping update", handlerType: "AddrSearchManager")
                }
            }
            
        } catch {
            logger.error("Geoapify search failed", handlerType: "AddrSearchManager", error: error)
            // On error, keep existing MapKit results only
        }
    }
    
    /// Clears all search results
    func clearResults() {
        results = []
    }
    
    /// Interleaves two arrays, alternating between them to prioritize best results from each category
    /// Limits total results to 6
    /// - Parameters:
    ///   - first: First array of results (e.g., Geoapify)
    ///   - second: Second array of results (e.g., MapKit)
    /// - Returns: Interleaved array with alternating results, capped at 6 total
    private func interleaveResults(_ first: [AddressSearchResult], _ second: [AddressSearchResult]) -> [AddressSearchResult] {
        var interleaved: [AddressSearchResult] = []
        let maxCount = max(first.count, second.count)
        let maxTotalResults = 6
        
        for i in 0..<maxCount {
            // Stop if we've reached the maximum
            if interleaved.count >= maxTotalResults {
                break
            }
            
            // Add from first array if available
            if i < first.count && interleaved.count < maxTotalResults {
                interleaved.append(first[i])
            }
            
            // Stop if we've reached the maximum
            if interleaved.count >= maxTotalResults {
                break
            }
            
            // Add from second array if available
            if i < second.count && interleaved.count < maxTotalResults {
                interleaved.append(second[i])
            }
        }
        
        return interleaved
    }
    
    // MARK: - MKLocalSearchCompleterDelegate
    
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Capture results before entering main actor context
        // MKLocalSearchCompletion is not Sendable, so we use nonisolated(unsafe)
        // Limit to 3 results (we'll interleave with Geoapify, max 6 total)
        nonisolated(unsafe) let capturedCompletions = Array(completer.results.prefix(3).reversed())
        let capturedQuery = completer.queryFragment
        Task { @MainActor in
            // Only update if query matches current query (prevent stale results)
            guard capturedQuery == self.currentQuery else {
                self.logger.warning("MapKit query '\(capturedQuery)' doesn't match current '\(self.currentQuery)', skipping", handlerType: "AddrSearchManager")
                return
            }
            
            // Filter out query-type results (e.g., "Search Nearby") and convert to AddressSearchResult
            let mapkitResults = capturedCompletions
                .filter { completion in
                    // Exclude results with "Search Nearby" subtitle (these are query suggestions, not locations)
                    completion.subtitle.lowercased() != "search nearby"
                }
                .map { completion in
                    AddressSearchResult.mapkit(completion)
                }
            
            self.logger.debug("MapKit returned \(capturedCompletions.count) results, \(mapkitResults.count) after filtering")
            
            // Preserve existing Geoapify results and merge with new MapKit results
            let existingGeoapifyResults = self.results.filter { result in
                if case .geoapify = result {
                    return true
                }
                return false
            }
            
            self.logger.debug("Merging: \(existingGeoapifyResults.count) existing Geoapify + \(mapkitResults.count) new MapKit")
            
            // Interleave results to prioritize best from each category
            self.results = self.interleaveResults(existingGeoapifyResults, mapkitResults)
            
            self.logger.debug("Total results after MapKit merge (interleaved): \(self.results.count)")
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.error("MKLocalSearchCompleter error", handlerType: "AddrSearchManager", error: error)
            // On error, keep Geoapify results but clear MapKit results
            let existingGeoapifyResults = self.results.filter { result in
                if case .geoapify = result {
                    return true
                }
                return false
            }
            self.results = existingGeoapifyResults
        }
    }
}

