import SwiftUI
import CoreLocation
import core

#if DEBUG
/// Debug view for testing SSE catalogue events in InfoSheet
/// Allows simulating different catalogue section types (overview, cuisine, architecture)
struct SSEContentTestView: View {
    @EnvironmentObject var catalogueManager: CatalogueManager
    @EnvironmentObject var sseEventRouter: SSEEventRouter
    
    @State private var selectedCatalogueType: CatalogueSectionType = .overview
    @State private var overviewMarkdown: String = """
# Welcome to Ancient Rome

This is a **test overview** content that demonstrates how markdown is rendered in the InfoSheet.

## Key Features

- Rich markdown support
- Multiple content types
- Dynamic updates

You can test different content types using the buttons below.
"""
    
    @State private var showTestSheet: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Catalogue Type")) {
                    Picker("Catalogue Type", selection: $selectedCatalogueType) {
                        ForEach(CatalogueSectionType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                }
                
                Section(header: Text("Catalogue Data")) {
                    switch selectedCatalogueType {
                    case .overview:
                        TextEditor(text: $overviewMarkdown)
                            .frame(height: 200)
                            .font(.system(.body, design: .monospaced))
                        
                    case .cuisine, .architecture:
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
                                Text(section.type.rawValue.capitalized)
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
        switch section.data {
        case .overview(let markdown):
            return "Markdown: \(markdown.prefix(50))..."
        case .cardSection(let data):
            let cardCount = data.cards.count
            return "Card Section: \(cardCount) cards"
        }
    }
    
    private func simulateCatalogueEvent() {
        Task { @MainActor in
            switch selectedCatalogueType {
            case .overview:
                let data: CatalogueSection.CatalogueSectionData = .overview(markdown: overviewMarkdown)
                sseEventRouter.setCatalogue(type: .overview, data: data)
                
            case .cuisine, .architecture:
                print("⚠️ Card section simulation not yet implemented in test view")
            }
        }
    }
    
    private func clearCatalogue() {
        catalogueManager.clearAll()
    }
    
    private func clearSelectedType() {
        catalogueManager.removeCatalogue(type: selectedCatalogueType)
    }
}

/// Quick test functions for common scenarios
@MainActor
struct SSECatalogueTestHelpers {
    static func testOverview(router: SSEEventRouter, markdown: String = "# Test Overview\n\nThis is a test.") {
        let data: CatalogueSection.CatalogueSectionData = .overview(markdown: markdown)
        router.setCatalogue(type: .overview, data: data)
    }
    
    static func testAllCatalogueTypes(router: SSEEventRouter) async {
        // Test overview
        testOverview(router: router, markdown: """
        # Complete Test

        This tests **all** catalogue section types in sequence.

        ## Overview Section
        This is the overview catalogue.
        """)
    }
}
#endif
