import SwiftUI
import MapboxMaps
import CoreLocation
import core

// Resolve ambiguity between core.JSONValue and MapboxMaps.JSONValue
private typealias JSONValue = core.JSONValue

// MARK: - Journey Route Section
/// Parses GeoJSON stops and displays a Mapbox route map if valid coordinates exist.
struct JourneyRouteSection: View {
    let stops: [core.JSONValue]

    var body: some View {
        let parsedStops = parseStopCoordinates(from: stops)
        if !parsedStops.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                Label("Route", systemImage: "point.bottomleft.filled.forward.to.point.topright.scurvepath")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article1.baseSize))
                    .foregroundColor(Color("onBkgTextColor20"))

                JourneyRouteMap(stops: parsedStops)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.current.space3xs))
            }
        }
    }

    /// Parses GeoJSON Feature Point stops into coordinate models for the map.
    private func parseStopCoordinates(from stops: [JSONValue]) -> [JourneyMapStop] {
        stops.enumerated().compactMap { index, stop in
            guard case .dictionary(let feature) = stop,
                  case .dictionary(let geometry) = feature["geometry"],
                  case .array(let coords) = geometry["coordinates"],
                  coords.count >= 2,
                  let longitude = coords[0].doubleValue,
                  let latitude = coords[1].doubleValue,
                  CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) else {
                return nil
            }
            let placeName: String? = {
                guard case .dictionary(let props) = feature["properties"] else { return nil }
                return resolvedPlaceName(from: props)
            }()
            return JourneyMapStop(
                index: index + 1,
                placeName: placeName ?? "Stop \(index + 1)",
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        }
    }
}

// MARK: - Journey Map Stop
/// A parsed stop with its index, name, and coordinate for map display.
struct JourneyMapStop: Identifiable {
    let index: Int
    let placeName: String
    let coordinate: CLLocationCoordinate2D

    var id: String { "\(index)|\(placeName)" }
}

// MARK: - Journey Route Map
/// Mapbox map view showing all journey stops with numbered annotations.
/// Camera fits all stops with padding.
struct JourneyRouteMap: View {
    let stops: [JourneyMapStop]

    /// Compute a viewport that fits all stop coordinates.
    private var fittingViewport: Viewport {
        guard !stops.isEmpty else {
            return .camera(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), zoom: 2)
        }
        if stops.count == 1, let stop = stops.first {
            return .camera(center: stop.coordinate, zoom: 14)
        }
        let lats = stops.map(\.coordinate.latitude)
        let lons = stops.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let latSpan = lats.max()! - lats.min()!
        let lonSpan = lons.max()! - lons.min()!
        let maxSpan = max(latSpan, lonSpan)
        // Approximate zoom: smaller span → higher zoom
        let zoom: Double
        if maxSpan < 0.005 { zoom = 16 }
        else if maxSpan < 0.01 { zoom = 15 }
        else if maxSpan < 0.02 { zoom = 14 }
        else if maxSpan < 0.05 { zoom = 13 }
        else if maxSpan < 0.1 { zoom = 12 }
        else if maxSpan < 0.3 { zoom = 11 }
        else if maxSpan < 0.5 { zoom = 10 }
        else { zoom = 9 }
        return .camera(center: center, zoom: zoom, bearing: 0, pitch: 0)
    }

    var body: some View {
        MapboxMaps.Map(initialViewport: fittingViewport) {
            ForEvery(stops) { stop in
                MapboxMaps.MapViewAnnotation(coordinate: stop.coordinate) {
                    JourneyStopAnnotation(index: stop.index, placeName: stop.placeName)
                }
                .allowOverlap(true)
            }
        }
        .mapStyle(MapboxMaps.MapStyle(uri: MapboxMaps.StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
    }
}

// MARK: - Journey Stop Annotation
/// Map annotation for a journey stop showing the stop number and place name.
struct JourneyStopAnnotation: View {
    let index: Int
    let placeName: String

    var body: some View {
        VStack(spacing: 2) {
            // Label with stop number and name
            HStack(spacing: Spacing.current.space2xs) {
                Text("\(index)")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color("AccentColor")))

                Text(placeName)
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(Color("onBkgTextColor10"))
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.current.space2xs)
            .padding(.vertical, Spacing.current.space3xs)
            .background(Color("AppBkgColor").cornerRadius(Spacing.current.spaceXs))
            .shadow(radius: Spacing.current.space3xs)

            // Pin arrow
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: Spacing.current.spaceXs))
                .foregroundColor(Color("AppBkgColor"))
                .shadow(radius: Spacing.current.space3xs)
        }
    }
}
