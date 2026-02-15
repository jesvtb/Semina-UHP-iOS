import SwiftUI
import CoreLocation
import core

/// Debug view for testing SSE catalogue events in InfoSheet
/// Allows simulating different catalogue section types dynamically
struct SSEContentTestView: View {
    @EnvironmentObject var catalogueManager: CatalogueManager
    @EnvironmentObject var sseEventRouter: SSEEventRouter
    
    // Available section types for testing
    private let availableSectionTypes = ["overview", "tour", "cuisine", "architecture", "custom"]
    
    @State private var selectedSectionType: String = "overview"
    @State private var customSectionType: String = ""
    @State private var displayTitle: String = "Overview"
    
    @State private var showTestSheet: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Catalogue Type")) {
                    Picker("Section Type", selection: $selectedSectionType) {
                        ForEach(availableSectionTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .onChange(of: selectedSectionType) { newValue in
                        displayTitle = newValue.replacingOccurrences(of: "_", with: " ").capitalized
                    }
                    
                    if selectedSectionType == "custom" {
                        TextField("Custom Section Type", text: $customSectionType)
                    }
                    
                    TextField("Display Title", text: $displayTitle)
                }
                
                Section(header: Text("Catalogue Data")) {
                    if selectedSectionType == "overview" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Overview section — Multi-topic")
                                .font(.subheadline.weight(.medium))
                            Text("\(sampleOverviewTopics.count) topics (Istanbul): country, admin area, locality. Each with header, markdown with semantic links, and geoscope metadata.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else if selectedSectionType == "tour" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tour section — Journey cards")
                                .font(.subheadline.weight(.medium))
                            Text("\(sampleTourJourneyCards.count) journey cards (Istanbul) with render_type \"journey\". All cards in one topic.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Text("Card section testing requires structured data. Not yet implemented in test view.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button(action: {
                        simulateCatalogueEvent()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Simulate SSE Event")
                        }
                    }
                    
                    Button(action: {
                        clearCatalogue()
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clear All Catalogue")
                        }
                        .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        clearSelectedType()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Clear Selected Type")
                        }
                        .foregroundColor(.orange)
                    }
                }
                
                Section(header: Text("Current Catalogue")) {
                    if catalogueManager.orderedSections.isEmpty {
                        Text("No catalogue loaded")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(catalogueManager.orderedSections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.displayTitle)
                                    .font(.headline)
                                Text(catalogueDescription(for: section))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("SSE Catalogue Tester")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func catalogueDescription(for section: CatalogueSection) -> String {
        // Content is topic-keyed: { "topic_key": { "markdown": ..., "cards": [...], "_metadata": ... } }
        // Iterate through topics to find markdown or cards content
        guard case .dictionary(let topLevelDict) = section.content else {
            return "Section Type: \(section.sectionType)"
        }
        
        for (_, topicValue) in topLevelDict {
            guard case .dictionary(let topicDict) = topicValue else { continue }
            
            // Check for markdown content within topic
            if let markdownContent = topicDict["markdown"]?.stringValue {
                return "Markdown: \(markdownContent.prefix(50))..."
            }
            
            // Check for cards content within topic
            if let cardsValue = topicDict["cards"], case .array(let cards) = cardsValue {
                return "Card Section: \(cards.count) cards"
            }
        }
        
        // Generic content description
        return "Section Type: \(section.sectionType)"
    }
    
    private func simulateCatalogueEvent() {
        let sectionType = selectedSectionType == "custom" ? customSectionType : selectedSectionType
        
        if sectionType == "overview" {
            let content = buildOverviewCatalogueContent()
            catalogueManager.handleCatalogue(
                sectionType: sectionType,
                displayTitle: displayTitle,
                content: content
            )
        } else if sectionType == "tour" {
            let content = buildTourCatalogueContent()
            catalogueManager.handleCatalogue(
                sectionType: sectionType,
                displayTitle: displayTitle,
                content: content
            )
        } else {
            print("Card section simulation not yet implemented in test view")
        }
    }
    
    private func clearCatalogue() {
        catalogueManager.clearAll()
    }
    
    private func clearSelectedType() {
        let sectionType = selectedSectionType == "custom" ? customSectionType : selectedSectionType
        catalogueManager.removeCatalogue(sectionType: sectionType)
    }
}

/// Quick test functions for common scenarios
@MainActor
struct SSECatalogueTestHelpers {
    static func testOverview(manager: CatalogueManager) {
        let content = buildOverviewCatalogueContent()
        manager.handleCatalogue(
            sectionType: "overview",
            displayTitle: "Overview",
            content: content
        )
    }
    
    static func testTour(manager: CatalogueManager) {
        let content = buildTourCatalogueContent()
        manager.handleCatalogue(
            sectionType: "tour",
            displayTitle: "Tour",
            content: content
        )
    }
    
    static func testAllCatalogueTypes(manager: CatalogueManager) async {
        // Test overview (multi-topic Istanbul)
        testOverview(manager: manager)
        
        // Test tour (journey cards)
        testTour(manager: manager)
    }
}

// MARK: - Overview Test Data

/// Sample overview topics for Istanbul, matching the multi-topic structure
/// produced by `GeoCataloguer.build_overviews` → `CatalogueTopic._sse_dict()`.
/// Each topic has: header (overline/headline/subhead), markdown with semantic links,
/// and _metadata (geoscope + location context + interface).
private let sampleOverviewTopics: [(
    topicId: String,
    geoscope: String,
    overline: String,
    headline: String,
    subhead: String,
    markdown: String,
    context: [String: JSONValue]
)] = [
    (
        topicId: "overview_country",
        geoscope: "country",
        overline: "COUNTRY",
        headline: "Turkey",
        subhead: "Where continents collide and civilizations layer",
        markdown: """
        **[Türkiye](place://T%C3%BCrkiye)** straddles two continents, its western edge touching [Europe](landscape://Europe) and its vast [Anatolian plateau](landscape://Anatolian%20Plateau) stretching deep into Asia. This geographic duality has made it a crossroads of empires — Hittite, Greek, Roman, Byzantine, and Ottoman — each leaving indelible marks on the land.

        The country's modern identity was forged in 1923 when Mustafa Kemal Atatürk declared the Republic, pivoting a crumbling empire toward secularism and Western institutions. Yet beneath the surface, older rhythms persist: the call to prayer echoing across [Cappadocia](landscape://Cappadocia)'s fairy chimneys, the clatter of backgammon in a Southeastern [çay bahçesi](cuisine://çay%20bahçesi), the slow pour of [Turkish coffee](dish://Turkish%20coffee) — a UNESCO-listed ritual that doubles as fortune-telling session.

        Turkey's culinary geography is staggering. The [Black Sea coast](landscape://Black%20Sea%20coast) contributes anchovies and hazelnuts, the Southeast brings fiery [kebab](dish://kebab) traditions influenced by [Mesopotamian cuisine](cuisine://Mesopotamian%20cuisine), and the Aegean delivers olive oil–drenched mezes that blur the line with Greek cooking. The result is not one cuisine but many, united by an obsession with fresh bread, strong tea, and generous hospitality.
        """,
        context: ["country_code": .string("TR")]
    ),
    (
        topicId: "overview_admin_area",
        geoscope: "admin_area",
        overline: "REGION",
        headline: "Marmara Region",
        subhead: "The gateway between two worlds",
        markdown: """
        The [Marmara Region](landscape://Marmara%20Region) takes its name from the small, enclosed [Sea of Marmara](landscape://Sea%20of%20Marmara) that sits between the [Bosphorus](landscape://Bosphorus) and the [Dardanelles](landscape://Dardanelles) — two narrow straits that have shaped trade and warfare for millennia. This is Turkey's most densely populated and industrialized region, yet it holds pockets of surprising quiet: the forested hillsides of [Uludağ](landscape://Uluda%C4%9F), the thermal baths of Bursa, and the vineyards along the Thracian wine route.

        Historically, the region was the heartland of the Ottoman state. [Bursa](place://Bursa) served as the first capital before [Edirne](place://Edirne) and then Constantinople. The culinary legacy runs deep — [İskender kebab](dish://%C4%B0skender%20kebab) was born in Bursa, and the region's dairy traditions produce some of Turkey's finest [kaymak](dish://kaymak), a clotted cream served with honey at breakfast.
        """,
        context: ["country_code": .string("TR"), "admin_area": .string("Marmara")]
    ),
    (
        topicId: "overview_locality",
        geoscope: "locality",
        overline: "TOWN & CITY",
        headline: "Istanbul",
        subhead: "Fifteen million stories on two continents",
        markdown: """
        [Istanbul](place://Istanbul) is the only major city in the world that sits on two continents, and that split — European and Asian sides divided by the [Bosphorus](landscape://Bosphorus) — defines daily life more than any guidebook admits. Commuters ferry across the strait each morning, fishermen cast lines from [Galata Bridge](place://Galata%20Bridge) at dawn, and the call to prayer from [Sultanahmet](place://Sultanahmet)'s minarets mingles with the hum of tram wires.

        The food scene is a story of layers. Street vendors sell [simit](dish://simit) — sesame-crusted bread rings — alongside [balık ekmek](dish://bal%C4%B1k%20ekmek), the iconic fish sandwich served dockside at [Eminönü](place://Emin%C3%B6n%C3%BC). In the backstreets of [Karaköy](place://Karak%C3%B6y), a new wave of [meyhane](cuisine://meyhane) culture pairs traditional [meze](cuisine://meze) with natural wines. And no visit is complete without the syrupy crunch of [baklava](dish://baklava) at one of the city's century-old pastry shops.

        Yet Istanbul resists being pinned down. The [Grand Bazaar](place://Grand%20Bazaar) thrums with 4,000 shops selling everything from hand-knotted carpets to counterfeit watches, while across the water, [Kadıköy](place://Kad%C4%B1k%C3%B6y)'s market stalls overflow with Anatolian cheeses, spices, and pickles. It is a city that rewards wandering without a map.
        """,
        context: ["country_code": .string("TR"), "admin_area": .string("Marmara"), "locality": .string("Istanbul")]
    ),
]

/// Builds complete catalogue content for an "overview" section with multiple geoscope topics.
/// Mirrors the SSE dict shape produced by `CatalogueTopic._sse_dict()` / `Catalogue.to_sse_dict()`.
private func buildOverviewCatalogueContent() -> JSONValue {
    var topics: [String: JSONValue] = [:]
    for topic in sampleOverviewTopics {
        topics[topic.topicId] = .dictionary([
            "header": .dictionary([
                "overline": .string(topic.overline),
                "headline": .string(topic.headline),
                "subhead": .string(topic.subhead),
            ]),
            "markdown": .string(topic.markdown),
            "_metadata": .dictionary([
                "location": .dictionary([
                    "geoscope": .string(topic.geoscope),
                    "context": .dictionary(topic.context),
                ]),
                "interface": .dictionary([
                    "markdown": .dictionary([:]),
                ]),
            ]),
        ])
    }
    return .dictionary(topics)
}

// MARK: - Tour Test Data

/// Helper to build a GeoJSON Feature Point stop for tour test data.
/// Mirrors `sampleStop` in JourneyCards.swift previews.
private func tourTestStop(
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

/// Sample journey cards for tour section testing.
/// Uses the same Istanbul data as preview cards in JourneyCards.swift.
private let sampleTourJourneyCards: [JSONValue] = [
    .dictionary([
        "kicker": .string("Walking Tour"),
        "title": .string("An Unorthodox History of Istanbul"),
        "subhead": .string("From Byzantine splendor to Ottoman grandeur"),
        "intro": .string("Walk the ancient streets where empires rose and fell. This journey takes you through Istanbul's most storied neighborhoods, revealing layers of history hidden beneath the modern city. From the monumental Hagia Sophia to the bustling Grand Bazaar, every step tells a story of conquest, culture, and resilience."),
        "duration": .int(90),
        "distance": .int(4500),
        "feature_img": .string("https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg"),
        "places": .array([
            tourTestStop(placeName: "Hagia Sophia", localName: "Ayasofya", description: "A former Greek Orthodox patriarchal basilica, later an imperial mosque, and now a museum.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/2/22/Hagia_Sophia_Mars_2013.jpg", isMosque: true, longitude: 28.9801, latitude: 41.0086),
            tourTestStop(placeName: "Blue Mosque", localName: "Sultanahmet Camii", description: "An Ottoman-era historical imperial mosque known for its blue İznik tiles.", isMosque: true, longitude: 28.9768, latitude: 41.0054),
            tourTestStop(placeName: "Grand Bazaar", localName: "Kapalıçarşı", description: "One of the largest and oldest covered markets in the world with over 4,000 shops.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/5/5e/Istanbul_Grand_Bazaar.jpg", longitude: 28.9680, latitude: 41.0107),
            tourTestStop(placeName: "Topkapi Palace", localName: "Topkapı Sarayı", description: "The primary residence of the Ottoman sultans for nearly 400 years.", featureImg: "https://www.egypttoursplus.com/wp-content/uploads/2025/07/topkapi-palace.jpg", longitude: 28.9834, latitude: 41.0115),
            tourTestStop(placeName: "Basilica Cistern", localName: "Yerebatan Sarnıcı", description: "The largest of several hundred ancient cisterns beneath Istanbul.", featureImg: "https://yerebatan.com/wp-content/uploads/2022/12/yerebatan-sergi-ogu5749-min-FX7w-scaled-1.jpg", longitude: 28.9784, latitude: 41.0084)
        ])
    ]),
    .dictionary([
        "kicker": .string("Cultural Heritage"),
        "title": .string("Street Art & Modern Culture"),
        "subhead": .string("Discover the creative pulse of the city"),
        "intro": .string("Explore the vibrant street art scene and contemporary cultural spaces that define Istanbul's modern identity. From hidden galleries to open-air murals, this journey showcases the city's thriving creative community."),
        "duration": .int(60),
        "distance": .int(2800),
        "places": .array([
            tourTestStop(placeName: "Karaköy Street Art District", description: "A neighbourhood alive with murals and independent galleries."),
            tourTestStop(placeName: "Istanbul Modern", description: "Turkey's first museum of modern and contemporary art."),
            tourTestStop(placeName: "Galata Tower", localName: "Galata Kulesi", description: "A medieval stone tower offering panoramic views of the historic peninsula.")
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
        "places": .array([
            tourTestStop(placeName: "Eminönü Fish Market", description: "Famous for its floating fish-bread boats along the Bosphorus."),
            tourTestStop(placeName: "Spice Bazaar", localName: "Mısır Çarşısı", description: "A centuries-old market bursting with spices, dried fruits, and Turkish delight."),
            tourTestStop(placeName: "Karaköy Güllüoğlu", description: "Legendary baklava shop serving Istanbul since 1949."),
            tourTestStop(placeName: "Çiya Sofrası", description: "A beloved Kadıköy restaurant celebrating Anatolian regional cuisine."),
            tourTestStop(placeName: "Ortaköy Kumpir Stalls", description: "Bosphorus-side stalls serving oversized baked potatoes with lavish toppings."),
            tourTestStop(placeName: "Mangerie Bebek", description: "A modern café with Bosphorus views and creative brunch plates.")
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
        "places": .array([
            tourTestStop(placeName: "Chora Church", localName: "Kariye Camii", description: "Home to some of the finest Byzantine mosaics and frescoes in the world.", featureImg: "https://upload.wikimedia.org/wikipedia/commons/f/f3/Topkap%C4%B1_-_01.jpg"),
            tourTestStop(placeName: "Süleymaniye Mosque", localName: "Süleymaniye Camii", description: "Sinan's masterpiece crowning the Third Hill — a triumph of Ottoman architecture.", isMosque: true),
            tourTestStop(placeName: "Rüstem Pasha Mosque", localName: "Rüstem Paşa Camii", description: "A small gem near the Spice Bazaar adorned with exquisite İznik tiles.", isMosque: true)
        ])
    ]),
    .dictionary([
        "kicker": .string("Night Walk"),
        "title": .string("After Dark: Rooftops & Raki"),
        "subhead": .string("Experience the city when the lights come on"),
        "intro": .string("As the sun dips behind the minarets, a different Istanbul awakens. This evening route winds through lantern-lit alleys to rooftop terraces with panoramic views, ending at a meyhane where locals gather for raki, meze, and conversation."),
        "duration": .int(105),
        "distance": .int(3800),
        "places": .array([
            tourTestStop(placeName: "Galata Bridge at Sunset", localName: "Galata Köprüsü", description: "Watch the sun set over the Golden Horn from the iconic double-deck bridge."),
            tourTestStop(placeName: "Büyük Valide Han Rooftop", description: "A hidden rooftop atop a 17th-century caravanserai with sweeping city views."),
            tourTestStop(placeName: "Nevizade Street", description: "A lively alley of meyhanes where locals gather for meze and raki."),
            tourTestStop(placeName: "Mikla Restaurant Terrace", description: "A rooftop fine-dining terrace overlooking the Bosphorus and old city skyline.")
        ])
    ])
]

/// Builds complete catalogue content for a "tour" section with all journey cards in one topic.
/// The content follows the keyed-topic structure expected by `CatalogueManager.handleCatalogue`.
private func buildTourCatalogueContent() -> JSONValue {
    .dictionary([
        "istanbul_journeys": .dictionary([
            "cards": .array(sampleTourJourneyCards),
            "_metadata": .dictionary([
                "location": .dictionary([
                    "geoscope": .string("locality"),
                    "context": .dictionary([:])
                ]),
                "interface": .dictionary([
                    "card": .dictionary([
                        "render_type": .string("journey")
                    ])
                ])
            ])
        ])
    ])
}
