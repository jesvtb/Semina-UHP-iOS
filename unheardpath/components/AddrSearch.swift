import SwiftUI
import MapKit
import Contacts
import core

struct AddrSearchResultItem: View {
    let result: MapSearchResult
    let isMostRelevant: Bool
    let onSelect: (MapSearchResult) -> Void

    var body: some View {
        Button(action: {
            onSelect(result)
        }) {
            HStack(alignment: .top, spacing: Spacing.current.space2xs) {
                Image(systemName: "mappin.circle.fill")
                    .bodyText(size: .article1)
                    .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    HStack(alignment: .top) {
                        Text(result.name)
                            .heading(size: .article0)
                            .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        #if DEBUG
                        Spacer()
                        Text(sourceIndicator)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(sourceColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(sourceColor.opacity(0.2))
                            .cornerRadius(4)
                        #endif
                    }

                    if !result.address.isEmpty {
                        Text(result.address)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(isMostRelevant ? Color("onBkgTextColor20") : Color("onBkgTextColor20").opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.current.space2xs)
            .padding(.vertical, Spacing.current.space2xs)
            .cornerRadius(Spacing.current.spaceS)
        }
    }

    #if DEBUG
    private var sourceIndicator: String {
        result.source == "geojson" ? "GA" : "MK"
    }

    private var sourceColor: Color {
        result.source == "geojson" ? .blue : .orange
    }
    #endif
}

/// Builds the display list: dedupes by (name, address) preferring geojson, then orders so the most relevant (first city if any, else last) is at the bottom.
private func buildDisplayResults(from searchResults: [MapSearchResult]) -> [MapSearchResult] {
    var keyToPreferred: [String: MapSearchResult] = [:]
    for result in searchResults {
        let key = "\(result.name)|\(result.address)"
        if let existing = keyToPreferred[key] {
            if result.source == "geojson", existing.source != "geojson" {
                keyToPreferred[key] = result
            }
        } else {
            keyToPreferred[key] = result
        }
    }
    var keysInOrder: [String] = []
    var seen = Set<String>()
    for result in searchResults {
        let key = "\(result.name)|\(result.address)"
        if !seen.contains(key) {
            seen.insert(key)
            keysInOrder.append(key)
        }
    }
    var ordered = keysInOrder.compactMap { keyToPreferred[$0] }
    if !ordered.isEmpty {
        let mostRelevantIndex = ordered.firstIndex(where: { $0.isCityType }) ?? (ordered.count - 1)
        let mostRelevant = ordered[mostRelevantIndex]
        ordered.remove(at: mostRelevantIndex)
        ordered.append(mostRelevant)
    }
    return ordered
}

// MARK: - Address Search Results List
struct AddrSearchResultsList: View {
    let searchResults: [MapSearchResult]
    @Binding var inputLocation: String
    @FocusState.Binding var isTextFieldFocused: Bool
    let onResultSelected: (MapSearchResult) async -> Void
    let onClearResults: () -> Void

    var body: some View {
        let displayResults = buildDisplayResults(from: searchResults)
        let lastIndex = displayResults.count - 1

        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                ForEach(Array(displayResults.enumerated()), id: \.offset) { index, result in
                    let isMostRelevant = index == lastIndex

                    AddrSearchResultItem(
                        result: result,
                        isMostRelevant: isMostRelevant,
                        onSelect: { selectedResult in
                            inputLocation = selectedResult.name
                            onClearResults()
                            isTextFieldFocused = false
                            Task {
                                await onResultSelected(selectedResult)
                            }
                        }
                    )
                }
            }
            .padding(.top, Spacing.current.spaceXs)
            .padding(.horizontal, Spacing.current.space3xs)
            .background(Color("AppBkgColor"))
        }
    }
}

#if DEBUG
private func mockSearchResults(count: Int = 6) -> [MapSearchResult] {
    let places: [(name: String, street: String, city: String, state: String, zip: String)] = [
        ("Central Park", "59th to 110th St", "New York", "NY", "10022"),
        ("Central Park Zoo", "830 5th Ave", "New York", "NY", "10065"),
        ("Metropolitan Museum of Art", "1000 5th Ave", "New York", "NY", "10028"),
        ("American Museum of Natural History", "200 Central Park W", "New York", "NY", "10024"),
        ("Lincoln Center", "10 Lincoln Center Plaza", "New York", "NY", "10023"),
        ("Columbus Circle", "59th St & 8th Ave", "New York", "NY", "10019")
    ]
    return (0..<min(count, places.count)).map { i in
        let p = places[i]
        let coord = CLLocationCoordinate2D(latitude: 40.78 + Double(i) * 0.01, longitude: -73.97 - Double(i) * 0.01)
        let addressDict: [String: Any] = [
            CNPostalAddressStreetKey: p.street,
            CNPostalAddressCityKey: p.city,
            CNPostalAddressStateKey: p.state,
            CNPostalAddressPostalCodeKey: p.zip,
            CNPostalAddressCountryKey: "United States"
        ]
        let placemark = MKPlacemark(coordinate: coord, addressDictionary: addressDict)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = p.name
        return MapSearchResult(mapItem)
    }
}

private struct AddrSearchResultsListPreviewContainer: View {
    @State private var inputLocation = "Central Park"
    @State private var draftMessage = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            AddrSearchResultsList(
                searchResults: mockSearchResults(count: 6),
                inputLocation: $inputLocation,
                isTextFieldFocused: $isTextFieldFocused,
                onResultSelected: { _ in },
                onClearResults: { }
            )
            InputBar(
                selectedTab: .map,
                draftMessage: $draftMessage,
                inputLocation: $inputLocation,
                isTextFieldFocused: $isTextFieldFocused,
                isAuthenticated: true,
                isLoading: false,
                onSendMessage: { },
                onSwitchToChat: { }
            )
        }
    }
}

private struct AddrSearchResultItemPreview: View {
    let title: String
    let subtitle: String
    let isMostRelevant: Bool

    var body: some View {
        Button(action: {}) {
            HStack(alignment: .top, spacing: Spacing.current.spaceXs) {
                Image(systemName: "mappin.circle.fill")
                    .bodyText(size: .article1)
                    .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                    .padding(.top, 2) // Align icon with first line of text
                
                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    Text(title)
                        .heading(size: .article0)
                        .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(isMostRelevant ? Color("onBkgTextColor20") : Color("onBkgTextColor20").opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, Spacing.current.spaceXs)
            .padding(.vertical, Spacing.current.space2xs)
            .cornerRadius(Spacing.current.spaceS)
        }
    }
}

#Preview("Autocomplete Result Items - Comparison") {
    VStack(alignment: .leading, spacing: Spacing.current.spaceXl) {
        VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
            Text("Most Relevant")
            AddrSearchResultItemPreview(
                title: "Central Park",
                subtitle: "New York, NY, United States",
                isMostRelevant: true
            )
            .background(Color("AppBkgColor"))
        }
        VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
            Text("Less Relevant")
            AddrSearchResultItemPreview(
                title: "Central Park Zoo",
                subtitle: "830 5th Ave, New York, NY 10065, United States",
                isMostRelevant: false
            )
            .background(Color("AppBkgColor"))
        }
    }
}

#Preview("Address Search Results List") {
    AddrSearchResultsListPreviewContainer()
        .background(.white)
}
#endif
