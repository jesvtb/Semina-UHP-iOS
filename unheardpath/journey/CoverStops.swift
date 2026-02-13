import SwiftUI
import core

// Resolve ambiguity between core.JSONValue and MapboxMaps.JSONValue
private typealias JSONValue = core.JSONValue

// MARK: - Journey Stops Section
/// Lists all journey stops with numbered rows and dividers.
struct JourneyStopsSection: View {
    let stops: [core.JSONValue]

    var body: some View {
        if !stops.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                Text("Stops")
                    .font(.custom(FontFamily.sansSemibold, size: TypographyScale.article1.baseSize))
                    .foregroundColor(Color("onBkgTextColor20"))

                ForEach(stops.indices, id: \.self) { index in
                    JourneyStopRow(stop: stops[index], index: index + 1)

                    if index < stops.count - 1 {
                        Divider()
                            .background(Color("onBkgTextColor30").opacity(0.3))
                    }
                }
            }
        }
    }
}

// MARK: - Journey Stop Row
/// A single stop row for a GeoJSON Feature Point.
/// Reads `place_name`, `description`, `local_name`, and `feature_img` from the feature's `properties`.
struct JourneyStopRow: View {
    let stop: core.JSONValue
    let index: Int

    /// The `properties` dict from the GeoJSON feature
    private var properties: [String: JSONValue]? {
        guard case .dictionary(let feature) = stop,
              case .dictionary(let props) = feature["properties"] else {
            return nil
        }
        return props
    }

    private var placeName: String? { properties?["place_name"]?.stringValue }
    private var localName: String? { properties?["local_name"]?.stringValue }
    private var stopDescription: String? { properties?["description"]?.stringValue }
    private var featureImageURL: URL? { properties?["feature_img"]?.stringValue.flatMap { URL(string: $0) } }
    private var isMosque: Bool { properties?["is_mosque"]?.boolValue ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.current.spaceS) {
            // Stop number badge + category icon
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

            // Stop content container
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
                    
                    if let stopDescription {
                        Text(stopDescription)
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
