import SwiftUI
import CoreLocation
import MapboxMaps
import core

private typealias JSONValue = core.JSONValue

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else { return .zero }
        let height = rows.reduce(CGFloat.zero) { total, row in
            total + row.height
        } + CGFloat(rows.count - 1) * spacing
        return CGSize(width: proposal.width ?? .infinity, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.sizeThatFits(.unspecified)
                item.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [LayoutSubview] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && currentWidth + spacing + size.width > maxWidth {
                rows.append(Row())
                currentWidth = 0
            }
            if !rows[rows.count - 1].items.isEmpty {
                currentWidth += spacing
            }
            rows[rows.count - 1].items.append(subview)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            currentWidth += size.width
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

// MARK: - Sight Constants

private let hiddenCategories: Set<String> = [
    "tourist attraction"
]

// MARK: - Sight Model

struct Sight: Identifiable {
    let name: String
    let localName: String?
    let description: String?
    let imageURLs: [URL]
    let categories: [String]
    let coordinate: CLLocationCoordinate2D?

    var id: String {
        if let coord = coordinate {
            return "sight_\(coord.latitude)_\(coord.longitude)"
        }
        return "sight_\(name)"
    }

    var featureImageURL: URL? { imageURLs.first }
}

// MARK: - Sight Card Content (render_type: "sight")

struct SightCardContent: View {
    let cards: [core.JSONValue]
    let config: core.JSONValue?
    @State private var selectedSight: Sight?
    @Environment(\.isPopupEnabled) private var isPopupEnabled

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                ForEach(cards.indices, id: \.self) { index in
                    sightCardView(from: cards[index])

                    if index < cards.count - 1 {
                        Divider()
                            .background(Color("onBkgTextColor30").opacity(0.3))
                    }
                }
            }
            .sheet(item: $selectedSight) { sight in
                SightPopupView(sight: sight) {
                    selectedSight = nil
                }
            }
        }
    }

    @ViewBuilder
    private func sightCardView(from data: JSONValue) -> some View {
        if let sight = parseSight(from: data) {
            SightCard(sight: sight) {
                if isPopupEnabled {
                    selectedSight = sight
                }
            }
        }
    }

    private func parseSight(from data: JSONValue) -> Sight? {
        guard case .dictionary(let dict) = data,
              case .dictionary(let props) = dict["properties"] else { return nil }
        guard let names = props["names"]?.dictionaryValue,
              let name = sightMainName(from: names) else { return nil }
        let localName = sightLocalName(from: names, mainName: name)
        let description = resolvedLocalizedString(from: props["description"])
        let imageURLs = parseImageURLs(from: props["img_urls"] ?? props["img_url"])
        let categories: [String] = {
            if case .array(let arr) = props["wikidata_instance_of"] {
                return arr.compactMap { $0.stringValue }
                    .filter { !hiddenCategories.contains($0.lowercased()) }
            }
            return []
        }()
        var coordinate: CLLocationCoordinate2D? = nil
        if case .dictionary(let geom) = dict["geometry"],
           case .array(let coords) = geom["coordinates"],
           coords.count >= 2,
           let lng = coords[0].doubleValue,
           let lat = coords[1].doubleValue,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return Sight(
            name: name, localName: localName, description: description,
            imageURLs: imageURLs, categories: categories, coordinate: coordinate
        )
    }
}

// MARK: - Sight Name Resolution

private func deviceLangKeys() -> (full: String, base: String) {
    let full = currentDeviceLanguageCode().lowercased()
    let base = full.split(separator: "-").first.map(String.init) ?? full
    return (full, base)
}

/// Primary display name: device language → English.
private func sightMainName(from names: [String: JSONValue]) -> String? {
    let lang = deviceLangKeys()
    if let name = names["lang:\(lang.full)"]?.stringValue, !name.isEmpty { return name }
    if lang.base != lang.full,
       let name = names["lang:\(lang.base)"]?.stringValue, !name.isEmpty { return name }
    if let name = names["lang:en"]?.stringValue, !name.isEmpty { return name }
    return nil
}

/// Secondary name: prefers a language that is neither device_lang nor English;
/// falls back to any non-device_lang, then English if it differs from the main name.
private func sightLocalName(from names: [String: JSONValue], mainName: String?) -> String? {
    let lang = deviceLangKeys()
    let deviceKeys: Set<String> = ["lang:\(lang.full)", "lang:\(lang.base)"]

    for (key, value) in names where key.hasPrefix("lang:") {
        if deviceKeys.contains(key) || key == "lang:en" { continue }
        if let name = value.stringValue, !name.isEmpty, name != mainName { return name }
    }
    for (key, value) in names where key.hasPrefix("lang:") {
        if deviceKeys.contains(key) { continue }
        if let name = value.stringValue, !name.isEmpty, name != mainName { return name }
    }
    return nil
}

/// Resolves a value that may be a plain string or a `{"lang:en": "...", "lang:ms": "..."}` dict.
private func resolvedLocalizedString(from value: JSONValue?) -> String? {
    guard let value else { return nil }
    if let plain = value.stringValue { return plain }
    guard case .dictionary(let langDict) = value else { return nil }
    let lang = deviceLangKeys()
    if let matched = langDict["lang:\(lang.full)"]?.stringValue, !matched.isEmpty { return matched }
    if lang.base != lang.full,
       let matched = langDict["lang:\(lang.base)"]?.stringValue, !matched.isEmpty { return matched }
    if let english = langDict["lang:en"]?.stringValue, !english.isEmpty { return english }
    for (_, val) in langDict {
        if let fallback = val.stringValue, !fallback.isEmpty { return fallback }
    }
    return nil
}

// MARK: - Sight Card

struct SightCard: View {
    let sight: Sight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                    if !sight.categories.isEmpty {
                        FlowLayout(spacing: Spacing.current.space2xs) {
                            ForEach(sight.categories, id: \.self) { category in
                                Text(category.capitalized)
                                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                                    .foregroundColor(Color("onBkgTextColor30"))
                                    .padding(.horizontal, Spacing.current.spaceXs)
                                    .padding(.vertical, 4)
                                    .background(Color("onBkgTextColor30").opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    DisplayText(
                        sight.name,
                        scale: .article1,
                        color: Color("onBkgTextColor10"),
                        fontFamily: FontFamily.serifRegular
                    )
                    if let localName = sight.localName {
                        DisplayText(
                            localName,
                            scale: .articleMinus1,
                            color: Color("onBkgTextColor50"),
                            fontFamily: FontFamily.sansRegular
                        )
                    }
                }

                if let description = sight.description {
                    Text(description)
                        .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
                        .foregroundColor(Color("onBkgTextColor20").opacity(0.8))
                }

                if let featureImageURL = sight.featureImageURL {
                    AsyncImage(url: featureImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            Color.clear
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                                .overlay {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.current.space3xs))
                        default:
                            Color.clear.frame(height: 0)
                        }
                    }
                    // .padding(.leading, Spacing.current.spaceXl)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.current.space3xs)
        .padding(.bottom, Spacing.current.space2xs)
    }
}

// MARK: - Sight Popup View

struct SightPopupView: View {
    let sight: Sight
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                    if let featureImageURL = sight.featureImageURL {
                        AsyncImage(url: featureImageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 220)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            default:
                                Color.clear.frame(height: 0)
                            }
                        }
                    }

                    Text(sight.name)
                        .bodyText(size: .article2)
                        .foregroundColor(Color("onBkgTextColor20"))

                    if let localName = sight.localName {
                        Text(localName)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor30"))
                    }

                    if !sight.categories.isEmpty {
                        FlowLayout(spacing: Spacing.current.space2xs) {
                            ForEach(sight.categories, id: \.self) { category in
                                Text(category.capitalized)
                                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                                    .foregroundColor(Color("onBkgTextColor30"))
                                    .padding(.horizontal, Spacing.current.spaceXs)
                                    .padding(.vertical, 4)
                                    .background(Color("onBkgTextColor30").opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    if let coordinate = sight.coordinate {
                        SightMapPreview(coordinate: coordinate, sightName: sight.name)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let description = sight.description {
                        Text(description)
                            .bodyParagraph(color: Color("onBkgTextColor30"))
                    }
                }
                .padding(Spacing.current.spaceS)
            }
            .navigationTitle(sight.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Sight Map Preview

private struct SightMapPreview: View {
    let coordinate: CLLocationCoordinate2D
    let sightName: String

    var body: some View {
        MapboxMaps.Map(initialViewport: .camera(
            center: coordinate,
            zoom: 14,
            bearing: 0,
            pitch: 0
        )) {
            MapboxMaps.MapViewAnnotation(coordinate: coordinate) {
                VStack(spacing: 2) {
                    Text(sightName)
                        .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus2.baseSize))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.current.spaceXs)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
            }
            .allowOverlap(true)
        }
        .mapStyle(MapboxMaps.MapStyle(uri: MapboxMaps.StyleURI(rawValue: "mapbox://styles/jessicamingyu/clxyfv0on002q01r1143f2f70")!))
    }
}

// MARK: - Previews
#if DEBUG

private func sampleSightFeature(
    name: String,
    localName: String? = nil,
    localNameLanguage: String = "ms",
    description: String? = nil,
    imageURLs: [String] = [],
    categories: [String] = [],
    longitude: Double = 0,
    latitude: Double = 0
) -> JSONValue {
    var names: [String: JSONValue] = ["lang:en": .string(name)]
    if let localName { names["lang:\(localNameLanguage)"] = .string(localName) }
    var props: [String: JSONValue] = ["names": .dictionary(names)]
    if let description { props["description"] = .dictionary(["lang:en": .string(description)]) }
    if !imageURLs.isEmpty {
        props["img_urls"] = .array(imageURLs.map { .string($0) })
    }
    if !categories.isEmpty {
        props["wikidata_instance_of"] = .array(categories.map { .string($0) })
    }
    return .dictionary([
        "type": .string("Feature"),
        "geometry": .dictionary([
            "type": .string("Point"),
            "coordinates": .array([.double(longitude), .double(latitude)])
        ]),
        "properties": .dictionary(props)
    ])
}

private let sampleSightCards: [JSONValue] = [
    sampleSightFeature(
        name: "Holy Spirit Cathedral, Penang",
        localName: "Katedral Roh Kudus, Pulau Pinang",
        description: "church in Penang, Malaysia",
        imageURLs: ["https://commons.wikimedia.org/wiki/Special:FilePath/Cmglee%20Penang%20Cathedral%20of%20the%20Holy%20Spirit.jpg"],
        categories: ["cathedral"],
        longitude: 100.30206, latitude: 5.39394
    ),
    sampleSightFeature(
        name: "Kek Lok Si",
        localName: "Kuil Kek Lok Si",
        description: "Buddhist temple situated in Air Itam in Penang",
        imageURLs: ["https://commons.wikimedia.org/wiki/Special:FilePath/Kek%20Lok%20Si%201.jpg"],
        categories: ["Buddhist temple", "tourist attraction"],
        longitude: 100.27305556, latitude: 5.39833333
    ),
    sampleSightFeature(
        name: "Tropical Fruit Farm",
        localName: "Taman Buah-Buahan Tropika",
        description: "Tropical Fruit Farm",
        longitude: 100.21939371763, latitude: 5.41583669947849
    ),
    sampleSightFeature(
        name: "Snake Temple",
        localName: "Tokong Ular",
        description: "Chinese temple in George Town, Penang, Malaysia",
        imageURLs: ["https://commons.wikimedia.org/wiki/Special:FilePath/Snake%20Temple,%20Penang.jpg"],
        categories: ["Taoist temple"],
        longitude: 100.285194, latitude: 5.313944
    ),
    sampleSightFeature(
        name: "Menara Pandang",
        description: "Menara Pandang",
        longitude: 100.2219669, latitude: 5.44989399947633
    ),
    sampleSightFeature(
        name: "Church of the Assumption",
        localName: "Gereja Assumption (Pulau Pinang)",
        description: "church in Penang, Malaysia",
        imageURLs: ["https://commons.wikimedia.org/wiki/Special:FilePath/Cathedral%20Of%20The%20Assumption.jpg"],
        categories: ["church building"],
        longitude: 100.337817, latitude: 5.42076183
    ),
    sampleSightFeature(
        name: "Shan Cheng Durian Penang",
        description: "Shan Cheng Durian Penang",
        longitude: 100.2382522, latitude: 5.3475541994829
    )
]

#Preview("Sight Card Content") {
    ScrollView {
        SightCardContent(cards: sampleSightCards, config: nil)
            .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("Sight Card - With Image & Categories") {
    SightCard(
        sight: Sight(
            name: "Kek Lok Si",
            localName: "Kuil Kek Lok Si",
            description: "Buddhist temple situated in Air Itam in Penang",
            imageURLs: [URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/Kek%20Lok%20Si%201.jpg")!],
            categories: ["Buddhist temple", "tourist attraction"],
            coordinate: CLLocationCoordinate2D(latitude: 5.39833333, longitude: 100.27305556)
        )
    ) {
        print("Tapped")
    }
    .padding()
    .background(Color("AppBkgColor"))
}

#Preview("Sight Card - No Image, No Categories") {
    SightCard(
        sight: Sight(
            name: "Tropical Fruit Farm",
            localName: "Taman Buah-Buahan Tropika",
            description: "Tropical Fruit Farm",
            imageURLs: [],
            categories: [],
            coordinate: CLLocationCoordinate2D(latitude: 5.41583669947849, longitude: 100.21939371763)
        )
    ) {
        print("Tapped")
    }
    .padding()
    .background(Color("AppBkgColor"))
}
#endif
