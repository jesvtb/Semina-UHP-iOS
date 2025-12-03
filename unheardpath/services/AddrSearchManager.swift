import SwiftUI
import MapKit
import Combine

/// Manages address search autocomplete using MKLocalSearchCompleter
/// Encapsulates the completer and delegate into a single ObservableObject
/// for cleaner SwiftUI integration
class AddressSearchManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    
    private let completer = MKLocalSearchCompleter()
    
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
            DispatchQueue.main.async {
                self.results = []
            }
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
        DispatchQueue.main.async {
            self.results = []
        }
    }
    
    // MARK: - MKLocalSearchCompleterDelegate
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            // Reverse order so most relevant appears at bottom
            self.results = Array(completer.results.prefix(5).reversed())
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        #if DEBUG
        print("❌ MKLocalSearchCompleter error: \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async {
            self.results = []
        }
    }
}

