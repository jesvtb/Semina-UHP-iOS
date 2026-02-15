import SwiftUI
import SafariServices
import core
import MapboxMaps
import CoreLocation

// Resolve ambiguity between core.JSONValue and MapboxMaps.JSONValue
private typealias JSONValue = core.JSONValue

// MARK: - Event Card Defaults
/// Event-specific layout defaults, used when server config doesn't specify values.
private enum EventCardDefaults {
    static let aspectRatio: CGFloat = 0.85
}

/// A cultural event card item
struct CulturalEvent: Identifiable {
    let eventName: String
    let eventDescription: String
    let startDatetime: String
    let endDatetime: String
    let eventVenue: String
    let eventLocality: String
    let sourceURL: String
    let involvesLocalArtists: Bool
    let showcaseLocalHeritage: Bool
    let imageURL: URL?

    var id: String { "\(eventName)|\(startDatetime)" }

    /// Formatted date range for display (e.g. "Jan 22 – Feb 15")
    var formattedDateRange: String? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        // Fallback: try without time component
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        guard let startDate = isoFormatter.date(from: startDatetime) ?? fallbackFormatter.date(from: startDatetime),
              let endDate = isoFormatter.date(from: endDatetime) ?? fallbackFormatter.date(from: endDatetime) else {
            return nil
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"

        let startStr = displayFormatter.string(from: startDate)
        let endStr = displayFormatter.string(from: endDate)

        if startStr == endStr {
            return startStr
        }
        return "\(startStr) – \(endStr)"
    }
}

// MARK: - Event Card Content (render_type: "event")
/// Renders event cards in a horizontal scroll layout with `EventCard` as the card view.
/// Manages event popup state and parses JSONValue into CulturalEvent models.
struct EventCardContent: View {
    let cards: [core.JSONValue]
    let config: core.JSONValue?
    @State private var selectedEvent: CulturalEvent?
    @Environment(\.isPopupEnabled) private var isPopupEnabled
    @EnvironmentObject var catalogueManager: CatalogueManager

    /// Card aspect ratio from config, falling back to event-specific default
    private var cardAspectRatio: CGFloat {
        config?["aspectRatio"]?.doubleValue.map { CGFloat($0) } ?? EventCardDefaults.aspectRatio
    }

    /// Fixed card width for horizontal scroll
    private let horizontalCardWidth: CGFloat = 200

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Spacing.current.spaceS) {
                ForEach(cards.indices, id: \.self) { index in
                    eventCardView(from: cards[index])
                        .frame(width: horizontalCardWidth, height: horizontalCardWidth / cardAspectRatio)
                }
            }
            .padding(.horizontal, Spacing.current.spaceXs)
        }
        .frame(height: horizontalCardWidth / cardAspectRatio)
        .sheet(item: $selectedEvent) { event in
            EventPopupView(
                event: event,
                countryCode: catalogueManager.locationDetailData?.countryCode
            ) {
                selectedEvent = nil
            }
        }
    }

    @ViewBuilder
    private func eventCardView(from data: JSONValue) -> some View {
        if let event = parseEvent(from: data) {
            EventCard(event: event, config: config) {
                if isPopupEnabled {
                    selectedEvent = event
                }
            }
        }
    }

    private func parseEvent(from data: JSONValue) -> CulturalEvent? {
        guard case .dictionary(let dict) = data else { return nil }
        guard let eventName = dict["event_name"]?.stringValue,
              let eventDescription = dict["event_description"]?.stringValue,
              let startDatetime = dict["start_datetime"]?.stringValue,
              let endDatetime = dict["end_datetime"]?.stringValue,
              let eventVenue = dict["event_venue"]?.stringValue,
              let eventLocality = dict["event_locality"]?.stringValue,
              let sourceURL = dict["source_url"]?.stringValue else {
            return nil
        }
        let involvesLocalArtists = dict["involves_local_artists"]?.boolValue ?? false
        let showcaseLocalHeritage = dict["showcase_local_heritage"]?.boolValue ?? false
        let imageURL = dict["img_url"]?.stringValue.flatMap { URL(string: $0) }
        return CulturalEvent(
            eventName: eventName,
            eventDescription: eventDescription,
            startDatetime: startDatetime,
            endDatetime: endDatetime,
            eventVenue: eventVenue,
            eventLocality: eventLocality,
            sourceURL: sourceURL,
            involvesLocalArtists: involvesLocalArtists,
            showcaseLocalHeritage: showcaseLocalHeritage,
            imageURL: imageURL
        )
    }
}

struct EventCard: View {
    let event: CulturalEvent
    let config: core.JSONValue?
    let onTap: () -> Void

    /// Corner radius from config, falling back to event-specific default
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
        Group {
            if let imageURL = event.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
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
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                            .overlay(
                                Image(systemName: "theatermasks")
                                    .font(.system(size: 36))
                                    .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                    }
                }
            } else {
                Rectangle()
                    .fill(Color("onBkgTextColor30").opacity(0.15))
                    .overlay(
                        Image(systemName: "theatermasks")
                            .font(.system(size: 36))
                            .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
                    )
            }
        }
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
            DisplayText(
                event.eventName,
                scale: .article0,
                color: .white,
                lineHeightMultiple: 1.0,
                fontFamily: FontFamily.sansSemibold
            )
            DisplayText(
                event.eventVenue,
                scale: .articleMinus1,
                color: .white.opacity(0.9),
                lineHeightMultiple: 1.0,
                fontFamily: FontFamily.sansRegular
            )
            DisplayText(
                event.eventLocality,
                scale: .articleMinus1,
                color: .white.opacity(0.9),
                lineHeightMultiple: 1.0,
                fontFamily: FontFamily.sansRegular
            )
            if let dateRange = event.formattedDateRange {
                DisplayText(
                    dateRange,
                    scale: .articleMinus2,
                    color: .white.opacity(0.7),
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

/// Lightweight Mapbox map preview for showing a single venue location.
/// Uses the app's custom Mapbox style for visual consistency with the main map.
private struct VenueMapPreview: View {
    let coordinate: CLLocationCoordinate2D
    let venueName: String

    var body: some View {
        MapboxMaps.Map(initialViewport: .camera(
            center: coordinate,
            zoom: 14,
            bearing: 0,
            pitch: 0
        )) {
            MapboxMaps.MapViewAnnotation(coordinate: coordinate) {
                VStack(spacing: 2) {
                    Text(venueName)
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

/// Popup presented when an event card is tapped.
/// Geocodes the event venue using Geoapify forward search and shows the result on a map.
struct EventPopupView: View {
    let event: CulturalEvent
    let countryCode: String?
    let onDismiss: () -> Void
    @State private var showWebPage = false
    @State private var venueCoordinate: CLLocationCoordinate2D?
    @State private var isGeocoding = false
    @Environment(\.geocoder) private var geocoder

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                    if let imageURL = event.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color("onBkgTextColor30").opacity(0.1))
                                    .frame(height: 220)
                                    .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxHeight: 220)
                                    .clipped()
                            case .failure:
                                Rectangle()
                                    .fill(Color("onBkgTextColor30").opacity(0.1))
                                    .frame(height: 220)
                                    .overlay(
                                        Image(systemName: "theatermasks")
                                            .foregroundColor(Color("onBkgTextColor30").opacity(0.5))
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text(event.eventName)
                        .bodyText(size: .article2)
                        .foregroundColor(Color("onBkgTextColor20"))

                    HStack(spacing: Spacing.current.spaceXs) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(Color("onBkgTextColor30"))
                            .font(.system(size: TypographyScale.articleMinus1.baseSize))
                        Text(event.eventVenue)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor30"))
                    }

                    if let dateRange = event.formattedDateRange {
                        HStack(spacing: Spacing.current.spaceXs) {
                            Image(systemName: "calendar")
                                .foregroundColor(Color("onBkgTextColor30"))
                                .font(.system(size: TypographyScale.articleMinus1.baseSize))
                            Text(dateRange)
                                .bodyText(size: .articleMinus1)
                                .foregroundColor(Color("onBkgTextColor30"))
                        }
                    }

                    // Map showing geocoded venue location
                    if let coordinate = venueCoordinate {
                        VenueMapPreview(coordinate: coordinate, venueName: event.eventVenue)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if isGeocoding {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("onBkgTextColor30").opacity(0.1))
                            .frame(height: 200)
                            .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                    }

                    Text(event.eventDescription)
                        .bodyParagraph(color: Color("onBkgTextColor30"))

                    if let sourceURL = URL(string: event.sourceURL) {
                        Button(action: {
                            showWebPage = true
                        }) {
                            HStack(spacing: Spacing.current.space2xs) {
                                Image(systemName: "safari")
                                    .font(.system(size: TypographyScale.articleMinus1.baseSize))
                                Text("View Source")
                                    .bodyText(size: .articleMinus1)
                            }
                            .foregroundColor(Color("AccentColor"))
                        }
                        .sheet(isPresented: $showWebPage) {
                            SafariView(url: sourceURL)
                        }
                    }
                }
                .padding(Spacing.current.spaceS)
            }
            .navigationTitle(event.eventName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .task {
                await geocodeVenue()
            }
        }
    }

    /// Geocodes the event venue using Geoapify forward search with the catalogue's country code filter.
    private func geocodeVenue() async {
        isGeocoding = true
        defer { isGeocoding = false }
        do {
            let coordinate = try await geocoder.geocodeForward(
                text: event.eventVenue,
                countryCode: countryCode
            )
            if let coordinate = coordinate {
                venueCoordinate = coordinate
            }
        } catch {
            // Geocoding failed silently — map section won't appear
        }
    }
}

// MARK: - Previews
#if DEBUG

private let sampleEventCards: [JSONValue] = [
    .dictionary([
        "event_name": .string("The Earth Laughs in Flowers"),
        "event_description": .string("Singapore artist Dawn Ng presents 12 huge paintings by freezing pigment, earth, and sand into ice blocks then shattering them onto wooden canvases."),
        "start_datetime": .string("2026-01-22T09:00:00"),
        "end_datetime": .string("2026-02-15T22:00:00"),
        "event_venue": .string("Singapore Repertory Theatre"),
        "event_locality": .string("Singapore"),
        "source_url": .string("https://www.ubs.com/global/en/our-firm/art/2026/art-sg-and-singapore-art-week.html"),
        "involves_local_artists": .bool(true),
        "showcase_local_heritage": .bool(false),
        "img_url": .string("https://www.ubs.com/global/en/our-firm/art/2026/art-sg-and-singapore-art-week/_jcr_content/root/pagehead/opengraphimage.coreimg.jpg/807908940/art-sg-2025.jpg")
    ]),
    .dictionary([
        "event_name": .string("Isang Dipang Langit: Fragments of Memory, Fields of Now"),
        "event_description": .string("Huge installations, sculptural works, performances, films, and paintings turn the warehouse into an open field where personal and collective memory shape the now."),
        "start_datetime": .string("2026-01-22T09:00:00"),
        "end_datetime": .string("2026-01-31T22:00:00"),
        "event_venue": .string("Singapore"),
        "source_url": .string("https://www.fzine.com/culture/singapore-art-week-2026-what-to-see"),
        "involves_local_artists": .bool(false),
        "showcase_local_heritage": .bool(false),
        "img_url": .string("https://cassette.sphdigital.com.sg/image/fzine/3e82040190c38636df6c362a023748a01977b17bae447dd74246dada74975c8a")
    ]),
    .dictionary([
        "event_name": .string("Preview of Art Fair Philippines 2026"),
        "event_description": .string("Features Archivo 1984, Leon Gallery, Gajah Gallery, Art Agenda, Silverlens."),
        "start_datetime": .string("2026-02-05T09:00:00"),
        "end_datetime": .string("2026-02-05T22:00:00"),
        "event_venue": .string("Philippines"),
        "source_url": .string("https://www.artandmarket.net/art-fair/2026/02/05/preview-of-art-fair-philippines-2026"),
        "involves_local_artists": .bool(false),
        "showcase_local_heritage": .bool(false),
        "img_url": .string("http://static1.squarespace.com/static/67c1754c89592f0c27fddb0b/67c179f651cd0b7dcef56192/69699ef9eef49d0c34f0af3d/1768552573844/Torlap+Larpjaroensook+-+Cosmos+of+Nostalgia+LR.jpg?format=1500w")
    ]),
    .dictionary([
        "event_name": .string("Keiko Moriuchi: Motif"),
        "event_description": .string("Japanese artist Keiko Moriuchi showcases her Lu: The Never-Ending Thread, experimenting with gold leaf, cosmic symbols, and geometric patterns."),
        "start_datetime": .string("2026-01-17T09:00:00"),
        "end_datetime": .string("2026-02-28T22:00:00"),
        "event_venue": .string("Art Again gallery"),
        "source_url": .string("https://www.fzine.com/culture/singapore-art-week-2026-what-to-see"),
        "involves_local_artists": .bool(false),
        "showcase_local_heritage": .bool(false),
        "img_url": .string("https://cassette.sphdigital.com.sg/image/fzine/3e82040190c38636df6c362a023748a01977b17bae447dd74246dada74975c8a")
    ]),
    .dictionary([
        "event_name": .string("I SAW IT - Algorithmic Prophecy"),
        "event_description": .string("A shifting light and print installation where architecture morphs with movement, turning form into illusion and perception into experience."),
        "start_datetime": .string("2026-01-23T09:00:00"),
        "end_datetime": .string("2026-01-31T22:00:00"),
        "event_venue": .string("FLOCK at Kampong Java, Singapore"),
        "source_url": .string("https://www.artweek.sg/event-detail/I-SAW-IT-Algorithmic-Prophecy"),
        "involves_local_artists": .bool(true),
        "showcase_local_heritage": .bool(true),
        "img_url": .string("https://www.artweek.sg/images/sawlibraries/og-image/saw_og_image.png")
    ]),
    .dictionary([
        "event_name": .string("Visions of the Future"),
        "event_description": .string("A film event imagining alternative futures through myth, ritual, and storytelling, featuring works by various artists."),
        "start_datetime": .string("2026-01-05T09:00:00"),
        "end_datetime": .string("2026-02-08T22:00:00"),
        "event_venue": .string("ArtScience Cinema, Level 4"),
        "source_url": .string("https://www.artweek.sg/event-detail/Visions-of-the-Future"),
        "involves_local_artists": .bool(false),
        "showcase_local_heritage": .bool(false),
        "img_url": .string("https://www.artweek.sg/images/sawlibraries/og-image/saw_og_image.png")
    ])
]

#Preview("Event Card") {
    EventCard(
        event: CulturalEvent(
            eventName: "The Earth Laughs in Flowers",
            eventDescription: "Singapore artist Dawn Ng presents 12 huge paintings.",
            startDatetime: "2026-01-22T09:00:00",
            endDatetime: "2026-02-15T22:00:00",
            eventVenue: "Singapore Repertory Theatre",
            eventLocality: "Singapore",
            sourceURL: "https://example.com",
            involvesLocalArtists: true,
            showcaseLocalHeritage: false,
            imageURL: URL(string: "https://www.ubs.com/global/en/our-firm/art/2026/art-sg-and-singapore-art-week/_jcr_content/root/pagehead/opengraphimage.coreimg.jpg/807908940/art-sg-2025.jpg")
        ),
        config: nil
    ) {
        print("Tapped")
    }
    .frame(width: 180, height: 220)
    .padding()
    .background(Color("AppBkgColor"))
}

#Preview("Event Card Content") {
    ScrollView {
        EventCardContent(cards: sampleEventCards, config: nil)
            .padding()
    }
    .background(Color("AppBkgColor"))
    .environmentObject(CatalogueManager())
}

#Preview("Event Cards - Landscape") {
    ScrollView {
        EventCardContent(
            cards: sampleEventCards,
            config: .dictionary([
                "aspectRatio": .double(2.5)
            ])
        )
        .padding()
    }
    .background(Color("AppBkgColor"))
    .environmentObject(CatalogueManager())
}
#endif
