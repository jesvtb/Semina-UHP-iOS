import SwiftUI
import Combine
import core

private typealias JSONValue = core.JSONValue

// MARK: - Journey Cover View (Full Screen)
/// Full-screen cover view presented when a journey card is tapped.
/// Uses `.fullScreenCover` for a separate-view experience (not a sheet or popup).
struct JourneyCoverView: View {
    let journey: Journey
    let onDismiss: () -> Void
    @State private var isBookmarked = false
    @Environment(\.colorScheme) private var colorScheme

    /// All available feature image URLs from the journey and its places.
    private var allImageURLs: [URL] {
        var urls: [URL] = []
        urls.append(contentsOf: journey.imageURLs)
        for stop in journey.places {
            guard case .dictionary(let feature) = stop,
                  case .dictionary(let props) = feature["properties"] else {
                continue
            }
            let stopImageURLs = parseImageURLs(from: props["img_urls"])
            if !stopImageURLs.isEmpty {
                urls.append(contentsOf: stopImageURLs)
                continue
            }
            let legacyStopImageURLs = parseImageURLs(from: props["feature_img"])
            urls.append(contentsOf: legacyStopImageURLs)
        }
        return Array(NSOrderedSet(array: urls).compactMap { $0 as? URL })
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.current.spaceM) {
                    // Hero header with background image slideshow
                    headerSection

                    // Remaining content with horizontal padding
                    Group {
                        JourneyMetadataRow(journey: journey)

                        Divider()
                            .background(Color("onBkgTextColor30").opacity(0.3))

                        // Intro
                        Text(journey.intro)
                            .bodyParagraph(color: Color("onBkgTextColor30"))

                        JourneyActionButtons(journey: journey)

                        JourneyPlaces(places: journey.places)

                        JourneyRouteSection(stops: journey.places)
                    }
                    .padding(.horizontal, Spacing.current.spaceS)
                }
                .padding(.bottom, Spacing.current.spaceS)
            }
            .background(Color("AppBkgColor"))
            .overlay(alignment: .topLeading) {
                BackButton(lightStyle: !allImageURLs.isEmpty) {
                    onDismiss()
                }
                .padding(.leading, Spacing.current.spaceS)
                .padding(.top, geometry.safeAreaInsets.top)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(Color("AppBkgColor"))
    }

    // MARK: - Header Section
    /// Hero section with image slideshow background when images are available, plain text fallback otherwise.
    @ViewBuilder
    private var headerSection: some View {
        if !allImageURLs.isEmpty {
            // Hero with slideshow background
            ZStack(alignment: .bottomLeading) {
                // Background slideshow
                JourneyImageSlideshow(imageURLs: allImageURLs)

                // Gradient overlays — separate treatments for dark vs light appearance
                if colorScheme == .dark {
                    gradientsOnImageOnDark
                } else {
                    gradientsOnImageOnLight
                }

                // Header text + bookmark button
                ZStack(alignment: .bottomTrailing) {
                    VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                        Spacer()

                        DisplayText(
                            journey.kicker.uppercased(),
                            scale: .articleMinus1,
                            color: .white.opacity(0.85),
                            lineHeightMultiple: 1.0,
                            fontFamily: FontFamily.sansRegular,
                            tracking: 0.2
                        )

                        DisplayText(
                            journey.title,
                            scale: .article4,
                            color: .white,
                            lineHeightMultiple: 1.0
                        )

                        DisplayText(
                            journey.subhead,
                            scale: .article1,
                            color: .white.opacity(0.6),
                            lineHeightMultiple: 1.3,
                            fontFamily: FontFamily.serifRegular
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    bookmarkButton(lightStyle: true)
                }
                .padding(Spacing.current.spaceS)
            }
            .frame(height: 400)
            .clipped()
        } else {
            // Plain text header without slideshow
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: Spacing.current.spaceXs) {
                    DisplayText(
                        journey.kicker.uppercased(),
                        scale: .articleMinus1,
                        color: Color.textSecondary,
                        lineHeightMultiple: 1.0,
                        fontFamily: FontFamily.sansRegular,
                        tracking: 0.2
                    )

                    DisplayText(
                        journey.title,
                        scale: .article4,
                        color: Color.textPrimary,
                        lineHeightMultiple: 1.3
                    )

                    DisplayText(
                        journey.subhead,
                        scale: .article1,
                        color: Color.textSecondary,
                        lineHeightMultiple: 1.0,
                        fontFamily: FontFamily.serifRegular
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                bookmarkButton(lightStyle: false)
            }
            .padding(.horizontal, Spacing.current.spaceS)
            .padding(.top, Spacing.current.spaceS)
        }
    }

    // MARK: - Gradient Overlays on Image (Dark)
    /// Radial blur + dark tint + background blend — works well when AppBkgColor is dark.
    @ViewBuilder
    private var gradientsOnImageOnDark: some View {
        // Radial blur fade: sharp at upper-right, blurred toward lower-left
        Rectangle()
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.2),
                        .init(color: .black.opacity(0.5), location: 0.45),
                        .init(color: .black, location: 0.65)
                    ],
                    center: UnitPoint(x: 0.7, y: 0.05),
                    startRadius: 0,
                    endRadius: 600
                )
            )

        // Radial dark tint: clear at top-center, darkens toward bottom
        RadialGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.15), location: 0.3),
                .init(color: .black.opacity(0.4), location: 0.55),
                .init(color: .black.opacity(0.6), location: 0.75)
            ],
            center: UnitPoint(x: 0.7, y: 0.05),
            startRadius: 0,
            endRadius: 600
        )

        // Background color radial fade: bottom becomes fully opaque
        Rectangle()
            .fill(Color("AppBkgColor"))
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.25),
                        .init(color: .black.opacity(0.4), location: 0.5),
                        .init(color: .black.opacity(0.85), location: 0.7),
                        .init(color: .black, location: 0.85)
                    ],
                    center: UnitPoint(x: 0.7, y: 0.05),
                    startRadius: 0,
                    endRadius: 600
                )
            )
    }

    // MARK: - Gradient Overlays on Image (Light)
    /// Linear dark scrim + narrow bottom blend — avoids the white-wash that occurs
    /// when radial dark tint and light AppBkgColor overlap in light appearance.
    @ViewBuilder
    private var gradientsOnImageOnLight: some View {
        // Bottom-weighted dark scrim for white-text legibility
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.03), location: 0.25),
                .init(color: .black.opacity(0.25), location: 0.55),
                .init(color: .black.opacity(0.5), location: 0.75),
                .init(color: .black.opacity(0.65), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        // Narrow bottom band blending into the light page background
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: Color("AppBkgColor").opacity(0), location: 0.0),
                    .init(color: Color("AppBkgColor").opacity(0.5), location: 0.35),
                    .init(color: Color("AppBkgColor"), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 70)
        }
    }

    // MARK: - Bookmark Button
    @ViewBuilder
    private func bookmarkButton(lightStyle: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isBookmarked.toggle()
            }
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: TypographyScale.article2.baseSize))
                .foregroundColor(
                    isBookmarked
                        ? Color("AccentColor")
                        : (lightStyle ? .white.opacity(0.85) : Color("onBkgTextColor20"))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Journey Image Slideshow
/// Cycles through an array of image URLs with a graceful cross-fade transition.
/// Only loads the current and next image to avoid saturating the network.
private struct JourneyImageSlideshow: View {
    let imageURLs: [URL]
    @State private var currentIndex: Int = 0
    @State private var loadedIndices: Set<Int> = []

    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    /// Indices to load: current image and the next one (for seamless cross-fade).
    private var activeIndices: Set<Int> {
        guard !imageURLs.isEmpty else { return [] }
        let next = (currentIndex + 1) % imageURLs.count
        return [currentIndex, next]
    }

    /// Prefer the current image when loaded; otherwise show a loaded active image immediately.
    private var displayIndex: Int {
        guard !imageURLs.isEmpty else { return 0 }
        let next = (currentIndex + 1) % imageURLs.count
        if loadedIndices.contains(currentIndex) {
            return currentIndex
        }
        if loadedIndices.contains(next) {
            return next
        }
        return currentIndex
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(imageURLs.indices, id: \.self) { index in
                    if activeIndices.contains(index) {
                        AsyncImage(url: imageURLs[index]) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                                    .onAppear {
                                        loadedIndices.insert(index)
                                    }
                            default:
                                Color.clear
                            }
                        }
                        .opacity(index == displayIndex ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: displayIndex)
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            guard imageURLs.count > 1 else { return }
            currentIndex = (currentIndex + 1) % imageURLs.count
        }
    }
}

// MARK: - Journey Metadata Row
/// Displays duration, distance, and stop count for a journey.
private struct JourneyMetadataRow: View {
    let journey: Journey

    var body: some View {
        HStack(spacing: Spacing.current.spaceM) {
            if journey.duration > 0 {
                HStack(spacing: Spacing.current.space2xs) {
                    Image(systemName: "clock")
                    Text(journey.formattedDuration)
                }
            }
            if journey.distance > 0 {
                HStack(spacing: Spacing.current.space2xs) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    Text(journey.formattedDistance)
                }
            }
            if !journey.places.isEmpty {
                HStack(spacing: Spacing.current.space2xs) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("\(journey.places.count) places")
                }
            }
        }
        .font(.custom(FontFamily.sansRegular, size: TypographyScale.articleMinus1.baseSize))
        .foregroundColor(Color("onBkgTextColor30"))
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

/// Visualises the radial gradient center and stop rings for debugging.
private struct RadialGradientDebugView: View {
    private let center = UnitPoint(x: 0.7, y: 0.05)
    private let endRadius: CGFloat = 600

    var body: some View {
        ZStack {
            // Color-coded rings matching the 3 overlay layers' stop locations
            RadialGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .green, location: 0.19),
                    .init(color: .green, location: 0.21),      // 0.2  blur starts
                    .init(color: .yellow, location: 0.24),
                    .init(color: .yellow, location: 0.26),      // 0.25 bkg starts
                    .init(color: .orange, location: 0.29),
                    .init(color: .orange, location: 0.31),      // 0.3  tint starts
                    .init(color: .clear.opacity(0.2), location: 0.37),
                    .init(color: .blue, location: 0.44),
                    .init(color: .blue, location: 0.46),        // 0.45 blur mid
                    .init(color: .purple, location: 0.49),
                    .init(color: .purple, location: 0.51),      // 0.5  bkg mid
                    .init(color: .red, location: 0.54),
                    .init(color: .red, location: 0.56),         // 0.55 tint mid
                    .init(color: .clear.opacity(0.2), location: 0.6),
                    .init(color: .cyan, location: 0.64),
                    .init(color: .cyan, location: 0.66),        // 0.65 blur end
                    .init(color: .pink, location: 0.69),
                    .init(color: .pink, location: 0.71),        // 0.7  bkg strong
                    .init(color: .orange, location: 0.74),
                    .init(color: .orange, location: 0.76),      // 0.75 tint end
                    .init(color: .clear.opacity(0.2), location: 0.8),
                    .init(color: .white, location: 0.84),
                    .init(color: .white, location: 0.86),       // 0.85 bkg opaque
                    .init(color: .black, location: 1.0)
                ],
                center: center,
                startRadius: 0,
                endRadius: endRadius
            )

            // Center dot
            GeometryReader { geo in
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .position(
                        x: geo.size.width * center.x,
                        y: geo.size.height * center.y
                    )
            }

            // Legend
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                legendRow(color: .green,  text: "0.20 — blur starts")
                legendRow(color: .yellow, text: "0.25 — bkg starts")
                legendRow(color: .orange, text: "0.30 — tint starts")
                legendRow(color: .blue,   text: "0.45 — blur mid")
                legendRow(color: .purple, text: "0.50 — bkg mid")
                legendRow(color: .red,    text: "0.55 — tint mid")
                legendRow(color: .cyan,   text: "0.65 — blur end")
                legendRow(color: .pink,   text: "0.70 — bkg strong")
                legendRow(color: .white,  text: "0.85 — bkg opaque")
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 350)
        .clipped()
        .background(Color.black)
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2)
        }
    }
}

#Preview("Debug: Radial Gradient Stops") {
    RadialGradientDebugView()
}

#Preview("Journey Cover View") {
    JourneyCoverView(
        journey: Journey(
            kicker: "Walking Tour",
            title: "An Unorthodox History of Istanbul",
            subhead: "From Byzantine splendor to Ottoman grandeur",
            intro: "Walk the ancient streets where empires rose and fell. This journey takes you through Istanbul's most storied neighborhoods, revealing layers of history hidden beneath the modern city. From the monumental Hagia Sophia to the bustling Grand Bazaar, every step tells a story of conquest, culture, and resilience.",
            duration: 90,
            distance: 4500,
            places: [
                sampleStop(placeName: "Hagia Sophia", localName: "Ayasofya", description: "A former Greek Orthodox patriarchal basilica, later an imperial mosque, and now a museum.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg", isMosque: true, longitude: 28.9801, latitude: 41.0086),
                sampleStop(placeName: "Blue Mosque", localName: "Sultanahmet Camii", description: "An Ottoman-era historical imperial mosque known for its blue İznik tiles.", isMosque: true, longitude: 28.9768, latitude: 41.0054),
                sampleStop(placeName: "Grand Bazaar", localName: "Kapalıçarşı", description: "One of the largest and oldest covered markets in the world with over 4,000 shops.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/5/5e/Istanbul_Grand_Bazaar.jpg", longitude: 28.9680, latitude: 41.0107),
                sampleStop(placeName: "Topkapi Palace", localName: "Topkapı Sarayı", description: "The primary residence of the Ottoman sultans for nearly 400 years.", longitude: 28.9834, latitude: 41.0115),
                sampleStop(placeName: "Basilica Cistern", localName: "Yerebatan Sarnıcı", description: "The largest of several hundred ancient cisterns beneath Istanbul.", longitude: 28.9783, latitude: 41.0084)
            ],
            imageURLs: [URL(string: "https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg")!]
        )
    ) {
        print("Dismissed")
    }
}
#endif
