import SwiftUI
import core

// Resolve ambiguity between core.JSONValue and MapboxMaps.JSONValue
private typealias JSONValue = core.JSONValue

// MARK: - Journey Places Section
/// Lists all journey places with numbered rows and dividers.
struct JourneyPlaces: View {
    let places: [core.JSONValue]

    var body: some View {
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                Text("Places")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article1.baseSize))
                    .foregroundColor(Color("onBkgTextColor20"))

                ForEach(places.indices, id: \.self) { index in
                    JourneyPlaceRow(place: places[index], index: index + 1)

                    if index < places.count - 1 {
                        Divider()
                            .background(Color("onBkgTextColor30").opacity(0.3))
                    }
                }
            }
        }
    }
}

// MARK: - Journey Place Row
/// A single place row for a GeoJSON Feature Point.
/// Reads localized names and image urls from the feature's `properties`.
struct JourneyPlaceRow: View {
    let place: core.JSONValue
    let index: Int

    /// The `properties` dict from the GeoJSON feature
    private var properties: [String: JSONValue]? {
        guard case .dictionary(let feature) = place,
              case .dictionary(let props) = feature["properties"] else {
            return nil
        }
        return props
    }

    private var placeName: String? {
        guard let properties else {
            return nil
        }
        return resolvedPlaceName(from: properties)
    }
    private var localName: String? {
        guard let properties else {
            return nil
        }
        return resolvedLocalName(from: properties, placeName: placeName)
    }
    private var placeDescription: String? { properties?["description"]?.stringValue }
    private var featureImageURL: URL? {
        guard let properties else {
            return nil
        }
        let placeImageURLs = parseImageURLs(from: properties["img_urls"])
        if let primaryPlaceImageURL = placeImageURLs.first {
            return primaryPlaceImageURL
        }
        return parseImageURLs(from: properties["feature_img"]).first
    }
    private var isMosque: Bool { properties?["is_mosque"]?.boolValue ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.current.spaceS) {
            // Place number badge + category icon
            VStack(spacing: Spacing.current.space2xs) {
                Text("\(index)")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus1.baseSize))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("AccentColor")))
                
                if isMosque {
                    IconFontImage(.mosque, size: TypographyScale.article1.baseSize, color: Color("onBkgTextColor30"))
                }
            }

            // Place content container
            VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                // Text content
                VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                    // Place name + local name grouped tightly
                    VStack(alignment: .leading, spacing: 2) {
                        if let placeName {
                            Text(placeName)
                                .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article1.baseSize))
                                .foregroundColor(Color("onBkgTextColor20"))
                        }
                        if let localName, localName != placeName {
                            Text(localName)
                                .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                                .foregroundColor(Color("onBkgTextColor30"))
                        }
                    }
                    
                    if let placeDescription {
                        Text(placeDescription)
                            .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                            .foregroundColor(Color("onBkgTextColor30").opacity(0.8))
                    }
                }

                // Feature image — only shown on successful load
                if let featureImageURL {
                    AsyncImage(url: featureImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: 160)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.current.space3xs))
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }
        .padding(.vertical, Spacing.current.space2xs)
    }
}
