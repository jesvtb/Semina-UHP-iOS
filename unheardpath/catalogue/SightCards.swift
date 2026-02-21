import SwiftUI
import SafariServices
import CoreLocation
import MapboxMaps
import core

private typealias JSONValue = core.JSONValue

// MARK: - Sight Card Defaults

private enum SightCardDefaults {
    static let aspectRatio: CGFloat = 0.85
}

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

    private var effectiveConfig: JSONValue {
        var dict: [String: JSONValue] = [
            "aspectRatio": .double(SightCardDefaults.aspectRatio),
            "cornerRadius": .double(CardConstants.cornerRadius)
        ]
        if case .dictionary(let serverDict) = config {
            for (key, value) in serverDict {
                dict[key] = value
            }
        }
        return .dictionary(dict)
    }

    var body: some View {
        DynamicCardGrid(cards: cards, config: effectiveConfig) { cardData in
            sightCardView(from: cardData)
        }
        .sheet(item: $selectedSight) { sight in
            SightPopupView(sight: sight) {
                selectedSight = nil
            }
        }
    }

    @ViewBuilder
    private func sightCardView(from data: JSONValue) -> some View {
        if let sight = parseSight(from: data) {
            SightCard(sight: sight, config: config) {
                if isPopupEnabled {
                    selectedSight = sight
                }
            }
        }
    }

    private func parseSight(from data: JSONValue) -> Sight? {
        guard case .dictionary(let dict) = data,
              case .dictionary(let props) = dict["properties"] else { return nil }
        guard let name = resolvedPlaceName(from: props) else { return nil }
        let localName = resolvedLocalName(from: props, placeName: name)
        let description = props["description"]?.stringValue
        let imageURLs = parseImageURLs(from: props["img_urls"])
        let categories: [String] = {
            if case .array(let arr) = props["wikidata_instance_of"] {
                return arr.compactMap { $0.stringValue }
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

// MARK: - Sight Card

struct SightCard: View {
    let sight: Sight
    let config: core.JSONValue?
    let onTap: () -> Void

    private var cornerRadius: CGFloat {
        config?["cornerRadius"]?.doubleValue.map { CGFloat($0) } ?? CardConstants.cornerRadius
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    cardBackground
                    gradientOverlay
                    textOverlay(cardWidth: geometry.size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color("onBkgTextColor30").opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if !sight.imageURLs.isEmpty {
            SightFallbackAsyncImage(urls: sight.imageURLs) { _ in }
        } else {
            placeholderBackground
        }
    }

    private var placeholderBackground: some View {
        Rectangle()
            .fill(Color("onBkgTextColor30").opacity(0.15))
            .overlay(
                Image(systemName: "mappin.circle")
                    .font(.system(size: 36))
                    .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity(0.1),
                Color.black.opacity(0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func textOverlay(cardWidth: CGFloat) -> some View {
        let horizontalPadding = Spacing.current.spaceXs * 2
        let maxTextWidth = max(0, cardWidth - horizontalPadding)
        return VStack(alignment: .leading, spacing: 2) {
            if let category = sight.categories.first {
                DisplayText(
                    category.capitalized,
                    scale: .articleMinus2,
                    color: .white.opacity(0.7),
                    lineHeightMultiple: 1.0,
                    fontFamily: FontFamily.sansRegular
                )
            }
            DisplayText(
                sight.name,
                scale: .article1,
                color: .white,
                lineHeightMultiple: 1.0,
                fontFamily: FontFamily.sansSemibold
            )
            if let localName = sight.localName {
                DisplayText(
                    localName,
                    scale: .articleMinus1,
                    color: .white.opacity(0.9),
                    lineHeightMultiple: 1.0,
                    fontFamily: FontFamily.sansRegular
                )
            }
        }
        .frame(width: maxTextWidth, alignment: .leading)
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.spaceXs)
        .clipped()
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
                    if !sight.imageURLs.isEmpty {
                        SightFallbackAsyncImage(urls: sight.imageURLs) { _ in }
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        HStack(spacing: Spacing.current.space2xs) {
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

// MARK: - Fallback Async Image

private enum SightFallbackAsyncImageLoadState {
    case loading
    case loaded
    case failedAll
}

private struct SightFallbackAsyncImage: View {
    let urls: [URL]
    let onLoadStateChange: (SightFallbackAsyncImageLoadState) -> Void
    @State private var urlIndex: Int = 0
    @State private var hasLoadedCurrentURL = false
    @State private var hasFailedCurrentURL = false

    private let loadTimeoutNanos: UInt64 = 2_000_000_000

    private func moveToNextURLOrFailAll() {
        if urlIndex + 1 < urls.count {
            urlIndex += 1
            hasLoadedCurrentURL = false
            hasFailedCurrentURL = false
        } else {
            onLoadStateChange(.failedAll)
        }
    }

    var body: some View {
        if urlIndex < urls.count {
            AsyncImage(url: urls[urlIndex]) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color("onBkgTextColor30").opacity(0.06))
                        .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                        .onAppear {
                            onLoadStateChange(.loading)
                        }
                case .success(let image):
                    GeometryReader { geo in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .onAppear {
                        hasLoadedCurrentURL = true
                        onLoadStateChange(.loaded)
                    }
                case .failure:
                    Rectangle()
                        .fill(Color("onBkgTextColor30").opacity(0.06))
                        .onAppear {
                            hasFailedCurrentURL = true
                            moveToNextURLOrFailAll()
                        }
                @unknown default:
                    Rectangle()
                        .fill(Color("onBkgTextColor30").opacity(0.06))
                }
            }
            .task(id: urlIndex) {
                guard urlIndex < urls.count else { return }
                hasLoadedCurrentURL = false
                hasFailedCurrentURL = false
                try? await Task.sleep(nanoseconds: loadTimeoutNanos)
                guard !Task.isCancelled else { return }
                if !hasLoadedCurrentURL && !hasFailedCurrentURL {
                    moveToNextURLOrFailAll()
                }
            }
        } else {
            Rectangle()
                .fill(Color("onBkgTextColor30").opacity(0.06))
        }
    }
}

// MARK: - Previews
#if DEBUG

private func sampleSightFeature(
    name: String,
    localName: String? = nil,
    description: String? = nil,
    imageURL: String? = nil,
    categories: [String] = [],
    longitude: Double = 0,
    latitude: Double = 0
) -> JSONValue {
    var names: [String: JSONValue] = ["lang:en": .string(name)]
    if let localName { names["lang:es"] = .string(localName) }
    var props: [String: JSONValue] = ["names": .dictionary(names)]
    if let description { props["description"] = .string(description) }
    if let imageURL { props["img_urls"] = .array([.string(imageURL)]) }
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
        name: "Mosque-Cathedral of Cordoba",
        localName: "Mezquita-Catedral de Córdoba",
        description: "Cathedral (former mosque) in Cordoba, Spain",
        imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/Mezquita_de_C%C3%B3rdoba_desde_el_aire_%28C%C3%B3rdoba%2C_Espa%C3%B1a%29.jpg/800px-Mezquita_de_C%C3%B3rdoba_desde_el_aire_%28C%C3%B3rdoba%2C_Espa%C3%B1a%29.jpg",
        categories: ["cathedral", "congregational mosque"],
        longitude: -4.7794, latitude: 37.8789
    ),
    sampleSightFeature(
        name: "Roman Bridge of Cordoba",
        localName: "Puente Romano",
        description: "Ancient Roman bridge spanning the Guadalquivir River",
        imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/Puente_romano2_Cordoba.jpg/800px-Puente_romano2_Cordoba.jpg",
        categories: ["bridge"],
        longitude: -4.7781, latitude: 37.8764
    ),
    sampleSightFeature(
        name: "Alcazar of the Christian Monarchs",
        localName: "Alcázar de los Reyes Cristianos",
        description: "Medieval palace and fortress in Cordoba",
        imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7c/Alc%C3%A1zar_de_los_Reyes_Cristianos_-_Aerial_photograph.jpg/800px-Alc%C3%A1zar_de_los_Reyes_Cristianos_-_Aerial_photograph.jpg",
        categories: ["castle", "palace"],
        longitude: -4.7826, latitude: 37.8773
    ),
    sampleSightFeature(
        name: "Calahorra Tower",
        localName: "Torre de la Calahorra",
        description: "Fortified gate in the form of a tower",
        categories: ["tower"],
        longitude: -4.7759, latitude: 37.8755
    ),
    sampleSightFeature(
        name: "Medina Azahara",
        localName: "Medina Azahara",
        description: "Ruins of a vast Moorish medieval palatial city",
        imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4c/Medina_Azahara_%28C%C3%B3rdoba%2C_Espa%C3%B1a%29_01.jpg/800px-Medina_Azahara_%28C%C3%B3rdoba%2C_Espa%C3%B1a%29_01.jpg",
        categories: ["archaeological site", "palace"],
        longitude: -4.8666, latitude: 37.8853
    ),
    sampleSightFeature(
        name: "Synagogue of Cordoba",
        localName: "Sinagoga de Córdoba",
        description: "Medieval synagogue built in Mudéjar style",
        categories: ["synagogue"],
        longitude: -4.7839, latitude: 37.8793
    )
]

#Preview("Sight Card Content") {
    ScrollView {
        SightCardContent(cards: sampleSightCards, config: nil)
            .padding()
    }
    .background(Color("AppBkgColor"))
}

#Preview("Sight Card - With Image") {
    SightCard(
        sight: Sight(
            name: "Mosque-Cathedral of Cordoba",
            localName: "Mezquita-Catedral de Córdoba",
            description: "Cathedral (former mosque) in Cordoba, Spain",
            imageURLs: [URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/Mezquita_de_C%C3%B3rdoba_desde_el_aire_%28C%C3%B3rdoba%2C_Espa%C3%B1a%29.jpg/800px-Mezquita_de_C%C3%B3rdoba_desde_el_aire_%28C%C3%B3rdoba%2C_Espa%C3%B1a%29.jpg")!],
            categories: ["cathedral", "congregational mosque"],
            coordinate: CLLocationCoordinate2D(latitude: 37.8789, longitude: -4.7794)
        ),
        config: nil
    ) {
        print("Tapped")
    }
    .frame(width: 180, height: 220)
    .padding()
    .background(Color("AppBkgColor"))
}

#Preview("Sight Card - No Image") {
    SightCard(
        sight: Sight(
            name: "Calahorra Tower",
            localName: "Torre de la Calahorra",
            description: "Fortified gate in the form of a tower",
            imageURLs: [],
            categories: ["tower"],
            coordinate: CLLocationCoordinate2D(latitude: 37.8755, longitude: -4.7759)
        ),
        config: nil
    ) {
        print("Tapped")
    }
    .frame(width: 180, height: 220)
    .padding()
    .background(Color("AppBkgColor"))
}
#endif
