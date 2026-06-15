import SwiftUI
import CoreLocation
import core

func currentDeviceLanguageCode() -> String {
    return Locale.current.language.languageCode?.identifier ?? "en"
}

func countryLanguageCode(countryCode: String?) -> String? {
    guard let countryCode,
          countryCode.count == 2 else {
        return nil
    }
    let normalizedCountryCode = countryCode.uppercased()
    for localeIdentifier in Locale.availableIdentifiers {
        let locale = Locale(identifier: localeIdentifier)
        guard locale.region?.identifier.uppercased() == normalizedCountryCode else {
            continue
        }
        if let languageCode = locale.language.languageCode?.identifier,
           !languageCode.isEmpty {
            return languageCode
        }
    }
    return nil
}

private let nonLoadableImageHosts: Set<String> = [
    "photos.app.goo.gl",
    "photos.google.com",
]

private func isLoadableImageURL(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return !nonLoadableImageHosts.contains(host)
}

/// Rewrites Wikimedia `/thumb/…/{width}px-Name` URLs to the requested width;
/// passes non-wiki URLs through unchanged.
func wikiThumbnail(_ url: URL, width: Int) -> URL {
    let str = url.absoluteString
    guard str.contains("upload.wikimedia.org"),
          str.contains("/thumb/"),
          let range = str.range(of: #"/\d+px-[^/]+$"#, options: .regularExpression) else {
        return url
    }
    let filename = str[range].split(separator: "-", maxSplits: 1).dropFirst().joined(separator: "-")
    let replacement = "/\(width)px-\(filename)"
    return URL(string: str.replacingCharacters(in: range, with: replacement)) ?? url
}

func parseImageURLs(from value: JSONValue?) -> [URL] {
    guard let value else {
        return []
    }
    if case .array(let imageValues) = value {
        return imageValues.compactMap { imageValue in
            if let imageString = imageValue.stringValue,
               let imageURL = URL(string: imageString),
               isLoadableImageURL(imageURL) {
                return imageURL
            }
            #if DEBUG
            if imageValue.dictionaryValue != nil {
                print("⚠️ parseImageURLs received non-canonical image reference object; backend should return URL strings")
            }
            #endif
            return nil
        }
    }
    if let imageString = value.stringValue,
       let imageURL = URL(string: imageString),
       isLoadableImageURL(imageURL) {
        return [imageURL]
    }
    #if DEBUG
    if value.dictionaryValue != nil {
        print("⚠️ parseImageURLs received non-canonical single image reference object; backend should return URL strings")
    }
    #endif
    return []
}

struct JourneyRouteLeg {
    let waypointStart: Int
    let waypointEnd: Int
    let distanceKm: Double?
    let durationMins: Double?
}

struct JourneyRouteMetadata {
    let routeGeoJSON: RouteFeature?
    let legs: [JourneyRouteLeg]
    let totalDistanceKm: Double?
    let totalDurationMins: Double?
}

func resolvedPlaceName(from properties: [String: JSONValue]) -> String? {
    let names = properties["names"]?.dictionaryValue
    let deviceLanguageCode = currentDeviceLanguageCode().lowercased()
    let baseDeviceLanguageCode = deviceLanguageCode.split(separator: "-").first.map(String.init) ?? deviceLanguageCode
    if let names {
        if let matchedDeviceName = names["lang:\(deviceLanguageCode)"]?.stringValue,
           !matchedDeviceName.isEmpty {
            return matchedDeviceName
        }
        if let matchedBaseDeviceName = names["lang:\(baseDeviceLanguageCode)"]?.stringValue,
           !matchedBaseDeviceName.isEmpty {
            return matchedBaseDeviceName
        }
        if let englishName = names["lang:en"]?.stringValue,
           !englishName.isEmpty {
            return englishName
        }
        for (nameKey, nameValue) in names where nameKey.hasPrefix("lang:") {
            if let fallbackName = nameValue.stringValue, !fallbackName.isEmpty {
                return fallbackName
            }
        }
    }
    return properties["place_name"]?.stringValue
}

func resolvedLocalName(from properties: [String: JSONValue], placeName: String?) -> String? {
    guard let names = properties["names"]?.dictionaryValue else {
        return properties["local_name"]?.stringValue
    }

    // Fast path: backend pre-resolved lang:local
    if let localName = names["lang:local"]?.stringValue, !localName.isEmpty {
        if let placeName, placeName == localName {
            return nil
        }
        return localName
    }

    // Fallback: resolve from country_code when lang:local is absent
    let countryCode = properties["country_code"]?.stringValue
    guard let localLanguageCode = countryLanguageCode(countryCode: countryCode)?.lowercased() else {
        return properties["local_name"]?.stringValue
    }
    let localName = names["lang:\(localLanguageCode)"]?.stringValue
    guard let localName, !localName.isEmpty else {
        return properties["local_name"]?.stringValue
    }
    if let placeName, placeName == localName {
        return nil
    }
    return localName
}

/// A journey card item representing a guided tour or route
struct Journey: Identifiable {
    let journeyId: String?
    let kicker: String
    let title: String
    let subhead: String
    let intro: String
    let duration: Int
    let distance: Int
    let places: [JSONValue]
    let imageURLs: [URL]
    let routeMetadata: JourneyRouteMetadata?
    let audioDeliveryMode: AudioDeliveryMode
    var featureImageURL: URL? { imageURLs.first }

    var id: String { journeyId ?? "\(title)|\(kicker)" }

    var isLocalKokoroDelivery: Bool {
        audioDeliveryMode == .localKokoro
    }

    var isDownloaded: Bool {
        guard let journeyId else { return false }
        let downloadedJourneyIds = Set(
            Storage.loadFromUserDefaults(
                forKey: "journey_manifest.downloaded_journeys",
                as: [String].self
            ) ?? []
        )
        return downloadedJourneyIds.contains(journeyId)
    }

    /// Formatted duration for display (e.g., "1h 30m" or "45m")
    var formattedDuration: String {
        if duration >= 60 {
            let hours = duration / 60
            let minutes = duration % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(duration)m"
    }

    /// Formatted distance for display (e.g., "2.5 km" or "800 m")
    var formattedDistance: String {
        if distance >= 1000 {
            let km = Double(distance) / 1000.0
            return String(format: "%.1f km", km)
        }
        return "\(distance) m"
    }

    /// Coordinate of the first place, extracted from GeoJSON Feature Point geometry.
    var firstPlaceCoordinate: CLLocationCoordinate2D? {
        guard let firstStop = places.first,
              case .dictionary(let feature) = firstStop,
              case .dictionary(let geometry) = feature["geometry"],
              case .array(let coords) = geometry["coordinates"],
              coords.count >= 2,
              let longitude = coords[0].doubleValue,
              let latitude = coords[1].doubleValue,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Name of the first place for map label.
    var firstPlaceName: String? {
        guard let firstStop = places.first,
              case .dictionary(let feature) = firstStop,
              case .dictionary(let props) = feature["properties"] else {
            return nil
        }
        return resolvedPlaceName(from: props)
    }
}

// MARK: - Journey Card Content (render_type: "journey")
/// Renders journey cards in a vertical list layout.
/// Manages navigation state and parses JSONValue into Journey models.
/// Tapping a card opens a full-screen detail view (not a sheet or popup).
struct JourneyCardContent: View {
    let cards: [JSONValue]
    let config: JSONValue?
    @State private var selectedJourney: Journey?
    @Environment(\.isPopupEnabled) private var isPopupEnabled

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            ForEach(cards.indices, id: \.self) { index in
                journeyCardView(from: cards[index])
            }
        }
        .fullScreenCover(item: $selectedJourney) { journey in
            JourneyCoverView(journey: journey) {
                selectedJourney = nil
            }
        }
    }

    @ViewBuilder
    private func journeyCardView(from data: JSONValue) -> some View {
        if let journey = parseJourney(from: data) {
            JourneyCard(journey: journey, config: config) {
                if isPopupEnabled {
                    selectedJourney = journey
                }
            }
        }
    }

    private func parseJourney(from data: JSONValue) -> Journey? {
        guard case .dictionary(let dict) = data else { return nil }
        let journeyId = dict["journey_id"]?.stringValue
            ?? dict["journeyId"]?.stringValue
        guard let kicker = dict["kicker"]?.stringValue,
              let title = dict["title"]?.stringValue,
              let subhead = dict["subhead"]?.stringValue,
              let intro = dict["intro"]?.stringValue else {
            return nil
        }
        let metadataDict = dict["metadata"]?.dictionaryValue
        let places: [JSONValue] = {
            if let placesValue = dict["places"], case .array(let placesArray) = placesValue {
                return placesArray
            }
            return []
        }()
        var imageURLs: [URL] = []
        imageURLs.append(contentsOf: parseImageURLs(from: dict["feature_img"]))
        imageURLs.append(contentsOf: parseImageURLs(from: dict["img_urls"]))
        for place in places {
            guard case .dictionary(let feature) = place,
                  case .dictionary(let props) = feature["properties"] else {
                continue
            }
            imageURLs.append(contentsOf: parseImageURLs(from: props["img_urls"]))
            imageURLs.append(contentsOf: parseImageURLs(from: props["feature_img"]))
        }
        imageURLs = Array(NSOrderedSet(array: imageURLs).compactMap { $0 as? URL })
        let routeMetadata: JourneyRouteMetadata? = {
            guard let metadata = metadataDict else {
                return nil
            }
            let legs: [JourneyRouteLeg] = {
                guard let legValues = metadata["legs"]?.arrayValue else {
                    return []
                }
                return legValues.compactMap { legValue in
                    guard let legDict = legValue.dictionaryValue else {
                        return nil
                    }
                    let waypointStart = legDict["waypoint_start"]?.doubleValue.map { Int($0) } ?? 0
                    let waypointEnd = legDict["waypoint_end"]?.doubleValue.map { Int($0) } ?? 0
                    let durationMins = legDict["duration_min"]?.doubleValue
                    return JourneyRouteLeg(
                        waypointStart: waypointStart,
                        waypointEnd: waypointEnd,
                        distanceKm: legDict["distance_km"]?.doubleValue,
                        durationMins: durationMins
                    )
                }
            }()
            let routeGeoJSON = RouteFeature(from: metadata["route"])
            let totalDurationMins = metadata["total_duration_min"]?.doubleValue
            return JourneyRouteMetadata(
                routeGeoJSON: routeGeoJSON,
                legs: legs,
                totalDistanceKm: metadata["total_distance_km"]?.doubleValue,
                totalDurationMins: totalDurationMins
            )
        }()
        let duration = metadataDict?["total_duration_min"]?.doubleValue.map { Int($0) } ?? 0
        let distance = metadataDict?["total_distance_km"]?.doubleValue.map { Int($0 * 1000.0) } ?? 0
        let audioDeliveryMode = AudioDeliveryMode(
            rawManifestValue: dict["audio_delivery_mode"]?.stringValue
        )

        return Journey(
            journeyId: journeyId,
            kicker: kicker,
            title: title,
            subhead: subhead,
            intro: intro,
            duration: duration,
            distance: distance,
            places: places,
            imageURLs: imageURLs,
            routeMetadata: routeMetadata,
            audioDeliveryMode: audioDeliveryMode
        )
    }
}

// MARK: - Journey Card
struct JourneyCard: View {
    let journey: Journey
    let config: JSONValue?
    let onTap: () -> Void
    @State private var hasLoadedBackgroundImage = false

    /// Corner radius from config, falling back to journey-specific default
    private var cornerRadius: CGFloat {
        config?["cornerRadius"]?.doubleValue.map { CGFloat($0) } ?? CardConstants.cornerRadius
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                // Background: feature image or filled color
                cardBackground

                // Gradient overlay for text legibility when image is present
                if hasLoadedBackgroundImage {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.15),
                            Color.black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                // Text content - aligned to bottom
                VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                    if journey.isDownloaded {
                        Text("Downloaded")
                            .font(.custom(FontFamily.sansSemibold, size: TypographyScale.articleMinus2.baseSize))
                            .foregroundColor(hasImage ? .white : Color("AccentColor"))
                            .padding(.horizontal, Spacing.current.space2xs)
                            .padding(.vertical, Spacing.current.space3xs)
                            .background(
                                Capsule()
                                    .fill(hasImage ? Color.black.opacity(0.2) : Color("AccentColor").opacity(0.1))
                            )
                    }

                    // Kicker — same styling as TopicHeaderView overline
                    DisplayText(
                        journey.kicker.uppercased(),
                        scale: .articleMinus2,
                        color: hasImage ? .white.opacity(0.85) : Color.textSecondary,
                        lineHeightMultiple: 1.0,
                        fontFamily: FontFamily.sansRegular,
                        tracking: 0.2
                    )

                    // Title — SerifDisplay
                    DisplayText(
                        journey.title,
                        scale: .article2,
                        color: hasImage ? .white : Color.textPrimary,
                        lineHeightMultiple: 1.1
                    )

                    // Subhead — SerifRegular (matches TopicHeaderView subhead)
                    DisplayText(
                        journey.subhead,
                        scale: .articleMinus1,
                        color: hasImage ? .white.opacity(0.9) : Color.textSecondary,
                        lineHeightMultiple: 1.0,
                        fontFamily: FontFamily.sansRegular
                    )

                    // Metadata row
                    HStack(spacing: Spacing.current.spaceS) {
                        if journey.duration > 0 {
                            Label(journey.formattedDuration, systemImage: "clock")
                        }
                        if journey.distance > 0 {
                            Label(journey.formattedDistance, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        if !journey.places.isEmpty {
                            Label("\(journey.places.count) places", systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(hasImage ? .white.opacity(0.7) : Color("onBkgTextColor30").opacity(0.8))
                    .padding(.top, Spacing.current.space3xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.current.spaceS)
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color("onBkgTextColor30").opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Whether the card has a feature image (affects text colors)
    private var hasImage: Bool { hasLoadedBackgroundImage }

    @ViewBuilder
    private var cardBackground: some View {
        if !journey.imageURLs.isEmpty {
            FallbackAsyncImage(urls: journey.imageURLs) { loadState in
                switch loadState {
                case .loaded:
                    hasLoadedBackgroundImage = true
                case .loading, .failedAll:
                    break
                }
            }
        } else {
            Rectangle()
                .fill(Color("onBkgTextColor30").opacity(0.06))
        }
    }
}

// MARK: - Fallback Async Image
/// Tries image URLs in order; advances to the next URL on load failure.
private enum FallbackAsyncImageLoadState {
    case loading
    case loaded
    case failedAll
}

private struct FallbackAsyncImage: View {
    let urls: [URL]
    let onLoadStateChange: (FallbackAsyncImageLoadState) -> Void
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

private let sampleJourneyCards: [JSONValue] = [
    .dictionary([
        "journey_id": .string("journey-preview-1"),
        "version_number": .int(4),
        "distance_m": .double(113.57),
        "kicker": .string("Walking Tour"),
        "title": .string("An Unorthodox History of Istanbul"),
        "subhead": .string("From Byzantine splendor to Ottoman grandeur"),
        "intro": .string("Walk the ancient streets where empires rose and fell. This journey takes you through Istanbul's most storied neighborhoods, revealing layers of history hidden beneath the modern city. From the monumental Hagia Sophia to the bustling Grand Bazaar, every step tells a story of conquest, culture, and resilience."),
        "duration": .int(90),
        "distance": .int(4500),
        "feature_img": .string("https://upload.wikimedia.org/wikipedia/commons/thumb/2/22/Hagia_Sophia_Mars_2013.jpg/960px-Hagia_Sophia_Mars_2013.jpg"),
        "img_urls": .array([
            .string("https://upload.wikimedia.org/wikipedia/commons/thumb/2/22/Hagia_Sophia_Mars_2013.jpg/960px-Hagia_Sophia_Mars_2013.jpg"),
            .string("https://upload.wikimedia.org/wikipedia/commons/thumb/1/12/Exterior_of_Sultan_Ahmed_I_Mosque_in_Istanbul%2C_Turkey_002.jpg/960px-Exterior_of_Sultan_Ahmed_I_Mosque_in_Istanbul%2C_Turkey_002.jpg"),
            .string("https://photos.app.goo.gl/wmTQWVkAqZ71cbu67")
        ]),
        "places": .array([
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9801), .double(41.0086)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary([
                        "lang:en": .string("Hagia Sophia"),
                        "lang:local": .string("Ayasofya")
                    ]),
                    "description": .dictionary([
                        "lang:en": .string("A former Greek Orthodox patriarchal basilica, later an imperial mosque, and now a museum.")
                    ]),
                    "img_urls": .array([
                        .string("https://upload.wikimedia.org/wikipedia/commons/thumb/2/22/Hagia_Sophia_Mars_2013.jpg/960px-Hagia_Sophia_Mars_2013.jpg")
                    ])
                ])
            ]),
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9768), .double(41.0054)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary([
                        "lang:en": .string("Blue Mosque"),
                        "lang:local": .string("Sultanahmet Camii")
                    ]),
                    "description": .dictionary([
                        "lang:en": .string("An Ottoman-era historical imperial mosque known for its blue Iznik tiles.")
                    ]),
                    "img_urls": .array([])
                ])
            ]),
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9680), .double(41.0107)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary([
                        "lang:en": .string("Grand Bazaar"),
                        "lang:local": .string("Kapalicarsi")
                    ]),
                    "description": .dictionary([
                        "lang:en": .string("One of the largest and oldest covered markets in the world with over 4,000 shops.")
                    ]),
                    "img_urls": .array([
                        .string("https://upload.wikimedia.org/wikipedia/commons/thumb/1/12/Exterior_of_Sultan_Ahmed_I_Mosque_in_Istanbul%2C_Turkey_002.jpg/960px-Exterior_of_Sultan_Ahmed_I_Mosque_in_Istanbul%2C_Turkey_002.jpg")
                    ])
                ])
            ])
        ])
    ]),
    .dictionary([
        "journey_id": .string("journey-preview-2"),
        "version_number": .int(2),
        "distance_m": .double(850.0),
        "kicker": .string("Cultural Heritage"),
        "title": .string("Street Art & Modern Culture"),
        "subhead": .string("Discover the creative pulse of the city"),
        "intro": .string("Explore the vibrant street art scene and contemporary cultural spaces that define Istanbul's modern identity. From hidden galleries to open-air murals, this journey showcases the city's thriving creative community."),
        "duration": .int(60),
        "distance": .int(2800),
        "places": .array([
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9920), .double(41.0255)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary(["lang:en": .string("Karakoy Street Art District")]),
                    "description": .dictionary(["lang:en": .string("A neighbourhood alive with murals and independent galleries.")]),
                    "img_urls": .array([])
                ])
            ]),
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9777), .double(41.0262)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary(["lang:en": .string("Istanbul Modern")]),
                    "description": .dictionary(["lang:en": .string("Turkey's first museum of modern and contemporary art.")]),
                    "img_urls": .array([])
                ])
            ])
        ])
    ]),
    .dictionary([
        "journey_id": .string("journey-preview-3"),
        "version_number": .int(1),
        "distance_m": .double(1320.0),
        "kicker": .string("Culinary Trail"),
        "title": .string("Flavours of the Bosphorus"),
        "subhead": .string("A tasting journey through waterfront kitchens"),
        "intro": .string("Sample the city's most beloved dishes as you trace the shoreline from Eminönü to Ortaköy. Each stop pairs a signature bite with the story behind it — from the iconic balık ekmek to Ottoman-era confections that have survived centuries."),
        "duration": .int(120),
        "distance": .int(6200),
        "feature_img": .string("https://upload.wikimedia.org/wikipedia/commons/5/5e/Istanbul_Grand_Bazaar.jpg"),
        "places": .array([
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9671), .double(41.0162)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary(["lang:en": .string("Eminonu Fish Market")]),
                    "description": .dictionary(["lang:en": .string("Famous for its floating fish-bread boats along the Bosphorus.")]),
                    "img_urls": .array([])
                ])
            ])
        ])
    ]),
    .dictionary([
        "journey_id": .string("journey-preview-4"),
        "version_number": .int(1),
        "distance_m": .double(1640.0),
        "kicker": .string("Architecture"),
        "title": .string("Domes, Minarets & Hidden Courtyards"),
        "subhead": .string("A skyline story told in stone and light"),
        "intro": .string("Trace the evolution of Istanbul's sacred architecture from early Byzantine basilicas to the masterworks of Sinan. Venture beyond the famous silhouettes into lesser-known mosques and courtyards where artisans still restore centuries-old tile work by hand."),
        "duration": .int(75),
        "distance": .int(3100),
        "feature_img": .string("https://upload.wikimedia.org/wikipedia/commons/b/b0/Sultan_Ahmed_Mosque_Istanbul_Turkey_retouched.jpg"),
        "places": .array([
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9425), .double(41.0312)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary([
                        "lang:en": .string("Chora Church"),
                        "lang:local": .string("Kariye Camii")
                    ]),
                    "description": .dictionary(["lang:en": .string("Home to some of the finest Byzantine mosaics and frescoes in the world.")]),
                    "img_urls": .array([
                        .string("https://upload.wikimedia.org/wikipedia/commons/f/f3/Topkap%C4%B1_-_01.jpg")
                    ])
                ])
            ])
        ])
    ]),
    .dictionary([
        "journey_id": .string("journey-preview-5"),
        "version_number": .int(1),
        "distance_m": .double(2100.0),
        "kicker": .string("Night Walk"),
        "title": .string("After Dark: Rooftops & Raki"),
        "subhead": .string("Experience the city when the lights come on"),
        "intro": .string("As the sun dips behind the minarets, a different Istanbul awakens. This evening route winds through lantern-lit alleys to rooftop terraces with panoramic views, ending at a meyhane where locals gather for raki, meze, and conversation."),
        "duration": .int(105),
        "distance": .int(3800),
        "places": .array([
            .dictionary([
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(28.9722), .double(41.0256)])
                ]),
                "properties": .dictionary([
                    "names": .dictionary([
                        "lang:en": .string("Galata Bridge at Sunset"),
                        "lang:local": .string("Galata Koprusu")
                    ]),
                    "description": .dictionary(["lang:en": .string("Watch the sun set over the Golden Horn from the iconic double-deck bridge.")]),
                    "img_urls": .array([])
                ])
            ])
        ])
    ])
]

#Preview("Journey Card - With Image") {
    JourneyCardContent(cards: [sampleJourneyCards[0]], config: nil)
        .padding()
        .background(Color("AppBkgColor"))
}

#Preview("Journey Card - No Image") {
    JourneyCardContent(cards: [sampleJourneyCards[1]], config: nil)
        .padding()
        .background(Color("AppBkgColor"))
}

#Preview("Journey Cards - Multiple") {
    ScrollView {
        JourneyCardContent(cards: sampleJourneyCards, config: nil)
            .padding()
    }
    .background(Color("AppBkgColor"))
}
#endif
