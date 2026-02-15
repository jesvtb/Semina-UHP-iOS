import SwiftUI
import CoreLocation
import MapKit
import Contacts
import core

// MARK: - LocationRow

struct LocationRow: View {
    let name: String
    let subtitle: String?
    let systemIcon: String?
    let countryCode: String?

    /// Fixed width for the leading icon column so text stays aligned across row types.
    private let iconColumnWidth: CGFloat = 18

    var body: some View {
        HStack(spacing: Spacing.current.spaceXs) {
            if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 14))
                    .foregroundColor(Color("onBkgTextColor30"))
                    .frame(width: iconColumnWidth)
            } else {
                Color.clear
                    .frame(width: iconColumnWidth, height: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                DisplayText(
                    name,
                    scale: .article0,
                    color: Color("onBkgTextColor10"),
                    fontFamily: FontFamily.sansRegular
                )

                if let subtitle, !subtitle.isEmpty {
                    DisplayText(
                        subtitle,
                        scale: .articleMinus1,
                        color: Color("onBkgTextColor50"),
                        fontFamily: FontFamily.sansRegular
                    )
                }
            }

            Spacer()

            if let countryCode,
               let flagImage = CountryFlag.image(for: countryCode) {
                flagImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: Spacing.current.spaceS)
            }
        }
        .padding(.horizontal, Spacing.current.spaceS)
        .padding(.vertical, Spacing.current.space2xs)
    }
}

// MARK: - LocationListMenu

struct LocationListMenu: View {
    let cachedLocations: [LocationDetailData]
    let autocompleteResults: [MapSearchResult]
    let onSelectCached: (LocationDetailData) -> Void
    let onSelectAutocomplete: (MapSearchResult) -> Void

    private var totalItemCount: Int {
        cachedLocations.count + autocompleteResults.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Cached location rows
                    ForEach(
                        Array(cachedLocations.enumerated()),
                        id: \.offset
                    ) { index, location in
                        Button {
                            onSelectCached(location)
                        } label: {
                            LocationRow(
                                name: location.placeName ?? "Unknown place",
                                subtitle: Self.subtitle(for: location),
                                systemIcon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                                countryCode: location.countryCode
                            )
                        }

                        if index < cachedLocations.count - 1 || !autocompleteResults.isEmpty {
                            Divider()
                                .overlay(Color("onBkgTextColor50").opacity(0.3))
                                .padding(.leading, Spacing.current.spaceS)
                        }
                    }

                    // Autocomplete result rows
                    ForEach(
                        Array(autocompleteResults.enumerated()),
                        id: \.offset
                    ) { index, result in
                        Button {
                            onSelectAutocomplete(result)
                        } label: {
                            LocationRow(
                                name: result.name,
                                subtitle: result.address.isEmpty ? nil : result.address,
                                systemIcon: nil,
                                countryCode: nil
                            )
                        }

                        if index < autocompleteResults.count - 1 {
                            Divider()
                                .overlay(Color("onBkgTextColor50").opacity(0.3))
                                .padding(.leading, Spacing.current.spaceS)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.current.space2xs)
            .frame(maxHeight: 400)
        }
        .background(Color("AppBkgColor"))
        
        .cornerRadius(CardConstants.cornerRadius)
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: -4)
    }

    // MARK: - Helpers

    private static func subtitle(for location: LocationDetailData) -> String? {
        if let locality = location.locality {
            let detail = [locality, location.adminArea]
                .compactMap { $0 }
                .filter { !$0.isEmpty && $0 != locality }
            return ([locality] + detail).joined(separator: ", ")
        } else if let adminArea = location.adminArea {
            return adminArea
        }
        return nil
    }
}

// MARK: - Mock Data

#if DEBUG
private func mockCachedLocations() -> [LocationDetailData] {
    let locations: [(name: String, locality: String, adminArea: String, countryCode: String, lat: Double, lon: Double)] = [
        ("Eiffel Tower", "Paris", "Île-de-France", "FR", 48.8584, 2.2945),
        ("Times Square", "New York", "NY", "US", 40.7580, -73.9855),
        ("Tokyo Tower", "Tokyo", "Tokyo", "JP", 35.6586, 139.7454),
        ("Sydney Opera House", "Sydney", "NSW", "AU", -33.8568, 151.2153)
    ]
    
    return locations.map { loc in
        let location = CLLocation(latitude: loc.lat, longitude: loc.lon)
        
        return LocationDetailData(
            location: location,
            placeName: loc.name,
            countryCode: loc.countryCode,
            adminArea: loc.adminArea,
            locality: loc.locality
        )
    }
}

private func mockAutocompleteResults() -> [MapSearchResult] {
    let places: [(name: String, street: String, city: String, state: String, zip: String, lat: Double, lon: Double)] = [
        ("Central Park", "59th to 110th St", "New York", "NY", "10022", 40.7829, -73.9654),
        ("Central Park Zoo", "830 5th Ave", "New York", "NY", "10065", 40.7678, -73.9718),
        ("Metropolitan Museum of Art", "1000 5th Ave", "New York", "NY", "10028", 40.7794, -73.9632),
        ("American Museum of Natural History", "200 Central Park W", "New York", "NY", "10024", 40.7813, -73.9740)
    ]
    
    return places.map { place in
        let coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        let addressDict: [String: Any] = [
            CNPostalAddressStreetKey: place.street,
            CNPostalAddressCityKey: place.city,
            CNPostalAddressStateKey: place.state,
            CNPostalAddressPostalCodeKey: place.zip,
            CNPostalAddressCountryKey: "United States"
        ]
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: addressDict)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = place.name
        return MapSearchResult(mapItem)
    }
}

// MARK: - Previews

#Preview("LocationListMenu - Both Lists") {
    VStack {
        Spacer()
        LocationListMenu(
            cachedLocations: mockCachedLocations(),
            autocompleteResults: mockAutocompleteResults(),
            onSelectCached: { location in
                print("Selected cached: \(location.placeName ?? "Unknown")")
            },
            onSelectAutocomplete: { result in
                print("Selected autocomplete: \(result.name)")
            }
        )
        .padding(.horizontal, Spacing.current.spaceXs)
    }
    .background(Color.gray.opacity(0.1))
}

#Preview("LocationListMenu - Cached Only") {
    VStack {
        Spacer()
        LocationListMenu(
            cachedLocations: mockCachedLocations(),
            autocompleteResults: [],
            onSelectCached: { location in
                print("Selected cached: \(location.placeName ?? "Unknown")")
            },
            onSelectAutocomplete: { result in
                print("Selected autocomplete: \(result.name)")
            }
        )
        .padding(.horizontal, Spacing.current.spaceXs)
    }
    .background(Color.gray.opacity(0.1))
}

#Preview("LocationListMenu - Autocomplete Only") {
    VStack {
        Spacer()
        LocationListMenu(
            cachedLocations: [],
            autocompleteResults: mockAutocompleteResults(),
            onSelectCached: { location in
                print("Selected cached: \(location.placeName ?? "Unknown")")
            },
            onSelectAutocomplete: { result in
                print("Selected autocomplete: \(result.name)")
            }
        )
        .padding(.horizontal, Spacing.current.spaceXs)
    }
    .background(Color.gray.opacity(0.1))
}

#Preview("LocationListMenu - Empty State") {
    VStack {
        Spacer()
        LocationListMenu(
            cachedLocations: [],
            autocompleteResults: [],
            onSelectCached: { location in
                print("Selected cached: \(location.placeName ?? "Unknown")")
            },
            onSelectAutocomplete: { result in
                print("Selected autocomplete: \(result.name)")
            }
        )
        .padding(.horizontal, Spacing.current.spaceXs)
    }
    .background(Color.gray.opacity(0.1))
}
#endif
