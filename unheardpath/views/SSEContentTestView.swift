import SwiftUI
import CoreLocation
import core

#if DEBUG
/// Debug view for testing SSE content events in InfoSheet
/// Allows simulating different content types (overview, locationDetail, pointsOfInterest)
struct SSEContentTestView: View {
    @EnvironmentObject var contentManager: ContentManager
    @EnvironmentObject var sseEventRouter: SSEEventRouter
    
    @State private var selectedContentType: ContentViewType = .overview
    @State private var overviewMarkdown: String = """
# Welcome to Ancient Rome

This is a **test overview** content that demonstrates how markdown is rendered in the InfoSheet.

## Key Features

- Rich markdown support
- Multiple content types
- Dynamic updates

You can test different content types using the buttons below.
"""
    
    @State private var locationLatitude: String = "41.9028"
    @State private var locationLongitude: String = "12.4964"
    @State private var locationAltitude: String = "0"
    
    @State private var showTestSheet: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Content Type")) {
                    Picker("Content Type", selection: $selectedContentType) {
                        ForEach(ContentViewType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                }
                
                Section(header: Text("Content Data")) {
                    switch selectedContentType {
                    case .overview, .countryOverview, .subdivisionsOverview, .neighborhoodOverview, .cultureOverview:
                        TextEditor(text: $overviewMarkdown)
                            .frame(height: 200)
                            .font(.system(.body, design: .monospaced))
                        
                    case .locationDetail:
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Latitude:")
                                TextField("41.9028", text: $locationLatitude)
                                    .keyboardType(.decimalPad)
                            }
                            HStack {
                                Text("Longitude:")
                                TextField("12.4964", text: $locationLongitude)
                                    .keyboardType(.decimalPad)
                            }
                            HStack {
                                Text("Altitude:")
                                TextField("0", text: $locationAltitude)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        
                    case .pointsOfInterest:
                        Text("POI testing requires GeoJSON features. Use the 'Test Sample POIs' button below.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                    case .regionalCuisine:
                        Text("Regional cuisine testing requires structured data. Not yet implemented in test view.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button(action: {
                        simulateContentEvent()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Simulate SSE Event")
                        }
                    }
                    
                    if selectedContentType == .pointsOfInterest {
                        Button(action: {
                            simulateSamplePOIs()
                        }) {
                            HStack {
                                Image(systemName: "map.fill")
                                Text("Test Sample POIs")
                            }
                        }
                    }
                    
                    Button(action: {
                        clearContent()
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clear All Content")
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
                
                Section(header: Text("Current Content")) {
                    if contentManager.orderedSections.isEmpty {
                        Text("No content loaded")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(contentManager.orderedSections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.type.rawValue.capitalized)
                                    .font(.headline)
                                Text(contentDescription(for: section))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("SSE Content Tester")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func contentDescription(for section: ContentSection) -> String {
        switch section.data {
        case .overview(let markdown):
            return "Markdown: \(markdown.prefix(50))..."
        case .locationDetail(let locationData):
            return "Location: \(locationData.location.coordinate.latitude), \(locationData.location.coordinate.longitude)"
        case .pointsOfInterest(let features):
            return "POIs: \(features.count) features"
        case .regionalCuisine(let data):
            return "Regional Cuisine: \(data.dishes.count) dishes"
        }
    }
    
    private func simulateContentEvent() {
        Task { @MainActor in
            switch selectedContentType {
            case .overview, .countryOverview, .subdivisionsOverview, .neighborhoodOverview, .cultureOverview:
                let data: ContentSection.ContentSectionData = .overview(markdown: overviewMarkdown)
                await sseEventRouter.onContent(type: selectedContentType, data: data)
                
            case .locationDetail:
                guard let lat = Double(locationLatitude),
                      let lon = Double(locationLongitude) else {
                    print("⚠️ Invalid location coordinates")
                    return
                }
                let altitude = Double(locationAltitude) ?? 0
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: altitude,
                    horizontalAccuracy: 0,
                    verticalAccuracy: 0,
                    timestamp: Date()
                )
                let locationDetailData = LocationDetailData(
                    location: location,
                    placeName: nil,
                    subdivisions: nil,
                    countryName: nil
                )
                let data: ContentSection.ContentSectionData = .locationDetail(data: locationDetailData)
                await sseEventRouter.onContent(type: .locationDetail, data: data)
                
            case .pointsOfInterest:
                // Use sample POIs
                simulateSamplePOIs()
                
            case .regionalCuisine:
                print("⚠️ Regional cuisine simulation not yet implemented in test view")
            }
        }
    }
    
    private func simulateSamplePOIs() {
        Task { @MainActor in
            // Create sample POI features
            let sampleFeatures: [[String: JSONValue]] = [
                [
                    "type": .string("Feature"),
                    "geometry": .dictionary([
                        "type": .string("Point"),
                        "coordinates": .array([.double(12.4964), .double(41.9028)])
                    ]),
                    "properties": .dictionary([
                        "title": .string("Colosseum"),
                        "description": .string("Ancient Roman amphitheater"),
                        "category": .string("landmark")
                    ])
                ],
                [
                    "type": .string("Feature"),
                    "geometry": .dictionary([
                        "type": .string("Point"),
                        "coordinates": .array([.double(12.4833), .double(41.9000)])
                    ]),
                    "properties": .dictionary([
                        "title": .string("Roman Forum"),
                        "description": .string("Ancient Roman public square"),
                        "category": .string("landmark")
                    ])
                ],
                [
                    "type": .string("Feature"),
                    "geometry": .dictionary([
                        "type": .string("Point"),
                        "coordinates": .array([.double(12.4763), .double(41.9022)])
                    ]),
                    "properties": .dictionary([
                        "title": .string("Pantheon"),
                        "description": .string("Ancient Roman temple"),
                        "category": .string("landmark")
                    ])
                ]
            ]
            
            let features = sampleFeatures.compactMap { featureDict -> PointFeature? in
                PointFeature(from: featureDict)
            }
            
            guard !features.isEmpty else {
                print("⚠️ Failed to create sample POI features")
                return
            }
            
            let data: ContentSection.ContentSectionData = .pointsOfInterest(features: features)
            await sseEventRouter.onContent(type: .pointsOfInterest, data: data)
        }
    }
    
    private func clearContent() {
        contentManager.clearAll()
    }
    
    private func clearSelectedType() {
        contentManager.removeContent(type: selectedContentType)
    }
}

/// Quick test functions for common scenarios
@MainActor
struct SSEContentTestHelpers {
    static func testOverview(router: SSEEventRouter, markdown: String = "# Test Overview\n\nThis is a test.") async {
        let data: ContentSection.ContentSectionData = .overview(markdown: markdown)
        await router.onContent(type: .overview, data: data)
    }
    
    static func testLocationDetail(router: SSEEventRouter, lat: Double = 41.9028, lon: Double = 12.4964) async {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            timestamp: Date()
        )
        let locationDetailData = LocationDetailData(
            location: location,
            placeName: "Test Location",
            subdivisions: "Test City, Test State",
            countryName: "Test Country"
        )
        let data: ContentSection.ContentSectionData = .locationDetail(data: locationDetailData)
        await router.onContent(type: .locationDetail, data: data)
    }
    
    static func testAllContentTypes(router: SSEEventRouter) async {
        // Test overview
        await testOverview(router: router, markdown: """
        # Complete Test
        
        This tests **all** content types in sequence.
        
        ## Overview Section
        This is the overview content.
        """)
        
        // Wait a bit
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Test location
        await testLocationDetail(router: router)
        
        // Wait a bit
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Test POIs
        let sampleFeatures: [[String: JSONValue]] = [
            [
                "type": .string("Feature"),
                "geometry": .dictionary([
                    "type": .string("Point"),
                    "coordinates": .array([.double(12.4964), .double(41.9028)])
                ]),
                "properties": .dictionary([
                    "title": .string("Test POI"),
                    "description": .string("A test point of interest")
                ])
            ]
        ]
        
        let features = sampleFeatures.compactMap { PointFeature(from: $0) }
        if !features.isEmpty {
            let data: ContentSection.ContentSectionData = .pointsOfInterest(features: features)
            await router.onContent(type: .pointsOfInterest, data: data)
        }
    }
}
#endif
