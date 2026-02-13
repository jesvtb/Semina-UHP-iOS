import SwiftUI
import CoreLocation
import core

// MARK: - Journey Card Defaults
/// Journey-specific layout defaults, used when server config doesn't specify values.
private enum JourneyCardDefaults {
    /// Matches Spacing space3xs (~4pt)
    static let cornerRadius: CGFloat = 4
}

/// A journey card item representing a guided tour or route
struct Journey: Identifiable {
    let kicker: String
    let title: String
    let subhead: String
    let intro: String
    let duration: Int
    let distance: Int
    let stops: [JSONValue]
    let featureImageURL: URL?

    var id: String { "\(title)|\(kicker)" }

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

    /// Coordinate of the first stop, extracted from GeoJSON Feature Point geometry.
    var firstStopCoordinate: CLLocationCoordinate2D? {
        guard let firstStop = stops.first,
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

    /// Name of the first stop for map label.
    var firstStopName: String? {
        guard let firstStop = stops.first,
              case .dictionary(let feature) = firstStop,
              case .dictionary(let props) = feature["properties"] else {
            return nil
        }
        return props["place_name"]?.stringValue
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
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
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
        guard let kicker = dict["kicker"]?.stringValue,
              let title = dict["title"]?.stringValue,
              let subhead = dict["subhead"]?.stringValue,
              let intro = dict["intro"]?.stringValue else {
            return nil
        }
        let duration = dict["duration"]?.doubleValue.map { Int($0) } ?? 0
        let distance = dict["distance"]?.doubleValue.map { Int($0) } ?? 0
        let stops: [JSONValue] = {
            if let stopsValue = dict["stops"], case .array(let stopsArray) = stopsValue {
                return stopsArray
            }
            return []
        }()
        let featureImageURL = dict["feature_img"]?.stringValue.flatMap { URL(string: $0) }
        return Journey(
            kicker: kicker,
            title: title,
            subhead: subhead,
            intro: intro,
            duration: duration,
            distance: distance,
            stops: stops,
            featureImageURL: featureImageURL
        )
    }
}

// MARK: - Journey Card
struct JourneyCard: View {
    let journey: Journey
    let config: JSONValue?
    let onTap: () -> Void

    /// Corner radius from config, falling back to journey-specific default
    private var cornerRadius: CGFloat {
        config?["cornerRadius"]?.doubleValue.map { CGFloat($0) } ?? JourneyCardDefaults.cornerRadius
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background: feature image or filled color
                cardBackground

                // Gradient overlay for text legibility when image is present
                if journey.featureImageURL != nil {
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

                // Text content
                VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                    Spacer()

                    // Kicker — same styling as SectionHeaderView overline
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
                        lineHeightMultiple: 1.3
                    )

                    // Subhead — SerifRegular (matches SectionHeaderView subhead)
                    DisplayText(
                        journey.subhead,
                        scale: .articleMinus1,
                        color: hasImage ? .white.opacity(0.9) : Color.textSecondary,
                        lineHeightMultiple: 1.0,
                        fontFamily: FontFamily.serifRegular
                    )

                    // Metadata row
                    HStack(spacing: Spacing.current.spaceS) {
                        if journey.duration > 0 {
                            Label(journey.formattedDuration, systemImage: "clock")
                        }
                        if journey.distance > 0 {
                            Label(journey.formattedDistance, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        if !journey.stops.isEmpty {
                            Label("\(journey.stops.count) stops", systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus2.baseSize))
                    .foregroundColor(hasImage ? .white.opacity(0.7) : Color("onBkgTextColor30").opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.current.spaceS)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color("onBkgTextColor30").opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Whether the card has a feature image (affects text colors)
    private var hasImage: Bool { journey.featureImageURL != nil }

    @ViewBuilder
    private var cardBackground: some View {
        if let imageURL = journey.featureImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color("onBkgTextColor30").opacity(0.06))
                        .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                case .success(let image):
                    GeometryReader { geo in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                case .failure:
                    Rectangle()
                        .fill(Color("onBkgTextColor30").opacity(0.06))
                @unknown default:
                    Rectangle()
                        .fill(Color("onBkgTextColor30").opacity(0.06))
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

/// Helper to build a GeoJSON Feature Point stop for previews.
private func sampleStop(
    placeName: String,
    localName: String? = nil,
    description: String? = nil,
    featureImg: String? = nil,
    isMosque: Bool = false,
    longitude: Double = 0,
    latitude: Double = 0
) -> JSONValue {
    var props: [String: JSONValue] = ["place_name": .string(placeName)]
    if let localName { props["local_name"] = .string(localName) }
    if let description { props["description"] = .string(description) }
    if let featureImg { props["feature_img"] = .string(featureImg) }
    if isMosque { props["is_mosque"] = .bool(true) }
    return .dictionary([
        "type": .string("Feature"),
        "geometry": .dictionary([
            "type": .string("Point"),
            "coordinates": .array([.double(longitude), .double(latitude)])
        ]),
        "properties": .dictionary(props)
    ])
}

private let sampleJourneyCards: [JSONValue] = [
    .dictionary([
        "kicker": .string("Walking Tour"),
        "title": .string("An Unorthodox History of Istanbul"),
        "subhead": .string("From Byzantine splendor to Ottoman grandeur"),
        "intro": .string("Walk the ancient streets where empires rose and fell. This journey takes you through Istanbul's most storied neighborhoods, revealing layers of history hidden beneath the modern city. From the monumental Hagia Sophia to the bustling Grand Bazaar, every step tells a story of conquest, culture, and resilience."),
        "duration": .int(90),
        "distance": .int(4500),
        "feature_img": .string("https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg"),
        "stops": .array([
            sampleStop(placeName: "Hagia Sophia", localName: "Ayasofya", description: "A former Greek Orthodox patriarchal basilica, later an imperial mosque, and now a museum.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg", isMosque: true, longitude: 28.9801, latitude: 41.0086),
            sampleStop(placeName: "Blue Mosque", localName: "Sultanahmet Camii", description: "An Ottoman-era historical imperial mosque known for its blue İznik tiles.", isMosque: true, longitude: 28.9768, latitude: 41.0054),
            sampleStop(placeName: "Grand Bazaar", localName: "Kapalıçarşı", description: "One of the largest and oldest covered markets in the world with over 4,000 shops.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/5/5e/Istanbul_Grand_Bazaar.jpg", longitude: 28.9680, latitude: 41.0107),
            sampleStop(placeName: "Topkapi Palace", localName: "Topkapı Sarayı", description: "The primary residence of the Ottoman sultans for nearly 400 years.", featureImg: "https://www.egypttoursplus.com/wp-content/uploads/2025/07/topkapi-palace.jpg", longitude: 28.9834, latitude: 41.0115),
            sampleStop(placeName: "Basilica Cistern", localName: "Yerebatan Sarnıcı", description: "The largest of several hundred ancient cisterns beneath Istanbul.", featureImg: "https://yerebatan.com/wp-content/uploads/2022/12/yerebatan-sergi-ogu5749-min-FX7w-scaled-1.jpg", longitude: 28.9784, latitude: 41.0084)
        ])
    ]),
    .dictionary([
        "kicker": .string("Cultural Heritage"),
        "title": .string("Street Art & Modern Culture"),
        "subhead": .string("Discover the creative pulse of the city"),
        "intro": .string("Explore the vibrant street art scene and contemporary cultural spaces that define Istanbul's modern identity. From hidden galleries to open-air murals, this journey showcases the city's thriving creative community."),
        "duration": .int(60),
        "distance": .int(2800),
        "stops": .array([
            sampleStop(placeName: "Karaköy Street Art District", description: "A neighbourhood alive with murals and independent galleries."),
            sampleStop(placeName: "Istanbul Modern", description: "Turkey's first museum of modern and contemporary art."),
            sampleStop(placeName: "Galata Tower", localName: "Galata Kulesi", description: "A medieval stone tower offering panoramic views of the historic peninsula.")
        ])
    ]),
    .dictionary([
        "kicker": .string("Culinary Trail"),
        "title": .string("Flavours of the Bosphorus"),
        "subhead": .string("A tasting journey through waterfront kitchens"),
        "intro": .string("Sample the city's most beloved dishes as you trace the shoreline from Eminönü to Ortaköy. Each stop pairs a signature bite with the story behind it — from the iconic balık ekmek to Ottoman-era confections that have survived centuries."),
        "duration": .int(120),
        "distance": .int(6200),
        "feature_img": .string("https://upload.wikimedia.org/wikipedia/commons/5/5e/Istanbul_Grand_Bazaar.jpg"),
        "stops": .array([
            sampleStop(placeName: "Eminönü Fish Market", description: "Famous for its floating fish-bread boats along the Bosphorus."),
            sampleStop(placeName: "Spice Bazaar", localName: "Mısır Çarşısı", description: "A centuries-old market bursting with spices, dried fruits, and Turkish delight."),
            sampleStop(placeName: "Karaköy Güllüoğlu", description: "Legendary baklava shop serving Istanbul since 1949."),
            sampleStop(placeName: "Çiya Sofrası", description: "A beloved Kadıköy restaurant celebrating Anatolian regional cuisine."),
            sampleStop(placeName: "Ortaköy Kumpir Stalls", description: "Bosphorus-side stalls serving oversized baked potatoes with lavish toppings."),
            sampleStop(placeName: "Mangerie Bebek", description: "A modern café with Bosphorus views and creative brunch plates.")
        ])
    ]),
    .dictionary([
        "kicker": .string("Architecture"),
        "title": .string("Domes, Minarets & Hidden Courtyards"),
        "subhead": .string("A skyline story told in stone and light"),
        "intro": .string("Trace the evolution of Istanbul's sacred architecture from early Byzantine basilicas to the masterworks of Sinan. Venture beyond the famous silhouettes into lesser-known mosques and courtyards where artisans still restore centuries-old tile work by hand."),
        "duration": .int(75),
        "distance": .int(3100),
        "feature_img": .string("https://upload.wikimedia.org/wikipedia/commons/b/b0/Sultan_Ahmed_Mosque_Istanbul_Turkey_retouched.jpg"),
        "stops": .array([
            sampleStop(placeName: "Chora Church", localName: "Kariye Camii", description: "Home to some of the finest Byzantine mosaics and frescoes in the world.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/f/f3/Topkap%C4%B1_-_01.jpg"),
            sampleStop(placeName: "Süleymaniye Mosque", localName: "Süleymaniye Camii", description: "Sinan's masterpiece crowning the Third Hill — a triumph of Ottoman architecture.", isMosque: true),
            sampleStop(placeName: "Rüstem Pasha Mosque", localName: "Rüstem Paşa Camii", description: "A small gem near the Spice Bazaar adorned with exquisite İznik tiles.", isMosque: true)
        ])
    ]),
    .dictionary([
        "kicker": .string("Night Walk"),
        "title": .string("After Dark: Rooftops & Raki"),
        "subhead": .string("Experience the city when the lights come on"),
        "intro": .string("As the sun dips behind the minarets, a different Istanbul awakens. This evening route winds through lantern-lit alleys to rooftop terraces with panoramic views, ending at a meyhane where locals gather for raki, meze, and conversation."),
        "duration": .int(105),
        "distance": .int(3800),
        "stops": .array([
            sampleStop(placeName: "Galata Bridge at Sunset", localName: "Galata Köprüsü", description: "Watch the sun set over the Golden Horn from the iconic double-deck bridge."),
            sampleStop(placeName: "Büyük Valide Han Rooftop", description: "A hidden rooftop atop a 17th-century caravanserai with sweeping city views."),
            sampleStop(placeName: "Nevizade Street", description: "A lively alley of meyhanes where locals gather for meze and raki."),
            sampleStop(placeName: "Mikla Restaurant Terrace", description: "A rooftop fine-dining terrace overlooking the Bosphorus and old city skyline.")
        ])
    ])
]

#Preview("Journey Card - With Image") {
    JourneyCard(
        journey: Journey(
            kicker: "Walking Tour",
            title: "An Unorthodox History of Istanbul",
            subhead: "From Byzantine splendor to Ottoman grandeur",
            intro: "Walk the ancient streets where empires rose and fell.",
            duration: 90,
            distance: 4500,
            stops: [
                sampleStop(placeName: "Hagia Sophia", localName: "Ayasofya", isMosque: true),
                sampleStop(placeName: "Blue Mosque", isMosque: true),
                sampleStop(placeName: "Grand Bazaar")
            ],
            featureImageURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg")
        ),
        config: nil
    ) {
        print("Tapped")
    }
    .frame(height: 260)
    .padding()
    .background(Color("AppBkgColor"))
}

#Preview("Journey Card - No Image") {
    JourneyCard(
        journey: Journey(
            kicker: "Cultural Heritage",
            title: "Street Art & Modern Culture",
            subhead: "Discover the creative pulse of the city",
            intro: "Explore the vibrant street art scene.",
            duration: 60,
            distance: 2800,
            stops: [
                sampleStop(placeName: "Karaköy Street Art District"),
                sampleStop(placeName: "Istanbul Modern")
            ],
            featureImageURL: nil
        ),
        config: nil
    ) {
        print("Tapped")
    }
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
