import SwiftUI
import CoreLocation
import MapKit
import core

// MARK: - Autocomplete Management
extension MainView {
    /// Updates autocomplete query
    func updateAutocomplete(query: String) {
        autocompleteManager.updateQuery(query)
    }

    /// Builds LocationDetailData from selected MapSearchResult and sets flyToLocation.
    /// For completer results (no coordinates), resolves the completion first via MKLocalSearch.
    @MainActor
    func flyToLocation(result: MapSearchResult) async {
        switch result.completionSource {
        case .mapItem, .geoJSON:
            guard let detail = result.buildLocationDetailData() else { return }
            mapFeaturesManager.flyToLocation = FlyToLocation(locationDetail: detail)
        case .completion(let completion):
            guard let mapItem = await autocompleteManager.geocoder.resolveMapKitCompletion(completion) else { return }
            let loc = CLLocation(latitude: mapItem.placemark.coordinate.latitude,
                                 longitude: mapItem.placemark.coordinate.longitude)
            let detail = LocationDetailData(placemark: mapItem.placemark, location: loc)
            mapFeaturesManager.flyToLocation = FlyToLocation(locationDetail: detail)
        }
        autocompleteManager.clearSearchResults()
        stretchableInputVM.inputLocation = ""
        stretchableInputVM.isStretched = false
    }
}
