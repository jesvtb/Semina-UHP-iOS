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
    @State private var overviewMarkdown: String = """
# Welcome to Ancient Rome
        \
This journey takes you through the **heart of the Roman Empire**, exploring iconic landmarks and hidden gems. Consequat penatibus at ridiculus inceptos auctor sit vehicula rhoncus vestibulum, enim quam quis ornare ullamcorper molestie fames. Netus augue purus aenean mus rhoncus ornare montes sapien urna mattis primis odio nullam convallis varius dictum dignissim, etiam inceptos neque aliquet pharetra mauris felis sed magnis congue lorem libero erat condimentum ante nec

![Rome Colosseum](https://upload.wikimedia.org/wikipedia/commons/thumb/d/de/Colosseo_2020.jpg/1280px-Colosseo_2020.jpg)

## What You'll Discover

- The Colosseum: An architectural marvel
- The Forum: The center of Roman public life
- [The Pantheon](https://en.wikipedia.org/wiki/Pantheon,_Rome): A temple to all gods

## Getting Started

Begin your journey at the Colosseum and follow the path through history.

```swift
let journey = Journey(name: "Ancient Rome")
journey.start()
```

Enjoy your exploration!
"""
    
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
                        TextEditor(text: $overviewMarkdown)
                            .frame(height: 200)
                            .font(.system(.body, design: .monospaced))
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
        // Check for markdown content
        if let markdownContent = section.content["markdown"]?.stringValue {
            return "Markdown: \(markdownContent.prefix(50))..."
        }
        
        // Check for cards content
        if let cardsValue = section.content["cards"], case .array(let cards) = cardsValue {
            return "Card Section: \(cards.count) cards"
        }
        
        // Generic content description
        return "Section Type: \(section.sectionType)"
    }
    
    private func simulateCatalogueEvent() {
        let sectionType = selectedSectionType == "custom" ? customSectionType : selectedSectionType
        
        if sectionType == "overview" {
            // Build keyed content with _metadata per item
            let content: JSONValue = .dictionary([
                "test_overview": .dictionary([
                    "markdown": .string(overviewMarkdown),
                    "_metadata": .dictionary([
                        "location": .dictionary([
                            "geoscope": .string("country"),
                            "context": .dictionary([:])
                        ]),
                        "interface": .dictionary(["markdown": .dictionary([:])])
                    ])
                ])
            ])
            
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
    static func testOverview(manager: CatalogueManager, markdown: String = "# Test Overview\n\nThis is a test.") {
        let content: JSONValue = .dictionary([
            "country_overview": .dictionary([
                "markdown": .string(markdown),
                "_metadata": .dictionary([
                    "location": .dictionary([
                        "geoscope": .string("country"),
                        "context": .dictionary([:])
                    ]),
                    "interface": .dictionary(["markdown": .dictionary([:])])
                ])
            ])
        ])
        
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
        // Test overview
        testOverview(manager: manager, markdown: """
        # Complete Test

        This tests **all** catalogue section types in sequence.

        ## Overview Section
        This is the overview catalogue.
        """)
        
        // Test tour (journey cards)
        testTour(manager: manager)
    }
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
        "stops": .array([
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
        "stops": .array([
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
        "stops": .array([
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
        "stops": .array([
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
        "stops": .array([
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
