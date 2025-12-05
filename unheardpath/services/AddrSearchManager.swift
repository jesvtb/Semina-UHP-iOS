import SwiftUI
import MapKit
import Combine

/// Manages address search autocomplete using MKLocalSearchCompleter
/// Encapsulates the completer and delegate into a single ObservableObject
/// for cleaner SwiftUI integration
@MainActor
class AddressSearchManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    
    nonisolated(unsafe) private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }
    
    /// Updates the search query fragment
    /// - Parameter query: The search query string
    func updateQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            results = []
        } else {
            completer.queryFragment = trimmedQuery
        }
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
    
    // MARK: - MKLocalSearchCompleterDelegate
    
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Capture results before entering main actor context
        // MKLocalSearchCompletion is not Sendable, so we use nonisolated(unsafe)
        nonisolated(unsafe) let capturedResults = Array(completer.results.prefix(5).reversed())
        Task { @MainActor in
            // Reverse order so most relevant appears at bottom
            self.results = capturedResults
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        #if DEBUG
        print("❌ MKLocalSearchCompleter error: \(error.localizedDescription)")
        #endif
        Task { @MainActor in
            self.results = []
        }
    }
}

