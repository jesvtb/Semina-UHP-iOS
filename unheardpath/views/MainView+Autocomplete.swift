import SwiftUI
import CoreLocation
import core

// MARK: - Autocomplete Management
extension TestMainView {
    /// Updates autocomplete query
    func updateAutocomplete(query: String) {
        autocompleteManager.updateQuery(query)
    }

    /// Sets flyToLocation from selected MapSearchResult and clears autocomplete. No reverse geocode.
    @MainActor
    func geocodeAndFlyToLocation(result: MapSearchResult) async {
        guard let coordinate = result.coordinate else {
            return
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let displayName = result.name.isEmpty ? result.address : result.name
        mapFeaturesManager.flyToLocation = FlyToLocation(location: location, name: displayName.isEmpty ? nil : displayName)
        autocompleteManager.clearSearchResults()
        liveUpdateViewModel.inputLocation = ""
        isTextFieldFocused = false
    }
}
