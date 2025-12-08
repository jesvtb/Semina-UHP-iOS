import SwiftUI
@preconcurrency import MapKit
import Combine
import CoreLocation

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
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
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
            #if DEBUG
            print("🔍 Starting Geoapify search for: '\(query)'")
            #endif
            
            // Call Geoapify API - limit to 3 results (we'll interleave with MapKit, max 6 total)
            let data = try await geoapifyGateway.searchCities(query: query, limit: 3)
            
            // Parse JSON response
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("⚠️ Geoapify response is not a JSON object")
                #endif
                return
            }
            
            // Extract features using GeoJSON helper
            let features = try GeoJSON.extractFeatures(from: jsonObject)
            
            #if DEBUG
            print("📦 Geoapify returned \(features.count) features")
            #endif
            
            // Convert to PointFeatures and build AddressSearchResult array
            var geoapifyResults: [AddressSearchResult] = []
            for feature in features {
                guard let pointFeature = PointFeature(from: feature),
                      let coordinate = pointFeature.coordinate else {
                    #if DEBUG
                    print("⚠️ Skipping feature - not a valid PointFeature or missing coordinate")
                    #endif
                    continue
                }
                
                // Build subtitle from PointFeature properties
                let subtitle = buildSubtitle(from: pointFeature)
                
                geoapifyResults.append(.geoapify(pointFeature, coordinate: coordinate, subtitle: subtitle))
            }
            
            #if DEBUG
            print("✅ Geoapify parsed \(geoapifyResults.count) valid results")
            #endif
            
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
                #if DEBUG
                let currentQueryValue = await MainActor.run { self.currentQuery }
                print("⚠️ Geoapify query '\(query)' is no longer current (current: '\(currentQueryValue)')")
                #endif
                return
            }
            
            // Interleave results to prioritize best from each category
            await MainActor.run {
                // Double-check query is still current
                if query == self.currentQuery {
                    self.results = self.interleaveResults(Array(reversedGeoapifyResults), mapkitResults)
                    #if DEBUG
                    print("✅ Interleaved results: \(geoapifyResults.count) Geoapify + \(mapkitResults.count) MapKit = \(self.results.count) total")
                    #endif
                } else {
                    #if DEBUG
                    print("⚠️ Query changed during merge, skipping update")
                    #endif
                }
            }
            
        } catch {
            #if DEBUG
            print("❌ Geoapify search failed: \(error.localizedDescription)")
            #endif
            // On error, keep existing MapKit results only
        }
    }
    
    /// Builds subtitle string from PointFeature properties (city, state, country)
    /// - Parameter pointFeature: The PointFeature to extract properties from
    /// - Returns: Formatted subtitle string (e.g., "City, State, Country")
    private func buildSubtitle(from pointFeature: PointFeature) -> String {
        guard let properties = pointFeature.properties else {
            return ""
        }
        
        var components: [String] = []
        
        // Extract city
        if let cityValue = properties["city"],
           let city = cityValue.stringValue,
           !city.isEmpty {
            components.append(city)
        }
        
        // Extract state/region (try both "state" and "region" keys)
        if let stateValue = properties["state"] ?? properties["region"],
           let state = stateValue.stringValue,
           !state.isEmpty {
            components.append(state)
        }
        
        // Extract country
        if let countryValue = properties["country"],
           let country = countryValue.stringValue,
           !country.isEmpty {
            components.append(country)
        }
        
        return components.joined(separator: ", ")
    }
    
    /// Configures the search region to prioritize results near a location
    /// - Parameters:
    ///   - center: The center coordinate for the search region
    ///   - meters: The radius in meters (applied to both latitudinal and longitudinal)
    func configureRegionSearch(center: CLLocationCoordinate2D, meters: Double) {
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
    }
    
    /// Configures the search region for global search (minimizes location bias)
    func configureGlobalSearch() {
        let globalCenter = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        completer.region = MKCoordinateRegion(
            center: globalCenter,
            latitudinalMeters: 200_000_000, // ~20,000 km (covers entire Earth)
            longitudinalMeters: 200_000_000
        )
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
                #if DEBUG
                print("⚠️ MapKit query '\(capturedQuery)' doesn't match current '\(self.currentQuery)', skipping")
                #endif
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
            
            #if DEBUG
            print("📦 MapKit returned \(capturedCompletions.count) results, \(mapkitResults.count) after filtering")
            #endif
            
            // Preserve existing Geoapify results and merge with new MapKit results
            let existingGeoapifyResults = self.results.filter { result in
                if case .geoapify = result {
                    return true
                }
                return false
            }
            
            #if DEBUG
            print("🔄 Merging: \(existingGeoapifyResults.count) existing Geoapify + \(mapkitResults.count) new MapKit")
            #endif
            
            // Interleave results to prioritize best from each category
            self.results = self.interleaveResults(existingGeoapifyResults, mapkitResults)
            
            #if DEBUG
            print("✅ Total results after MapKit merge (interleaved): \(self.results.count)")
            #endif
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        #if DEBUG
        print("❌ MKLocalSearchCompleter error: \(error.localizedDescription)")
        #endif
        Task { @MainActor in
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

