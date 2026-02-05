import SwiftUI
import CoreLocation
import core

#if DEBUG
/// Debug view for testing SSE catalogue events in InfoSheet
/// Allows simulating different catalogue section types dynamically
struct SSEContentTestView: View {
    @EnvironmentObject var catalogueManager: CatalogueManager
    @EnvironmentObject var sseEventRouter: SSEEventRouter
    
    // Available section types for testing
    private let availableSectionTypes = ["overview", "cuisine", "architecture", "custom"]
    
    @State private var selectedSectionType: String = "overview"
    @State private var customSectionType: String = ""
    @State private var displayTitle: String = "Overview"
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
            // Build content with markdown config
            let content: JSONValue = .dictionary([
                "markdown": .string(overviewMarkdown)
            ])
            let config: JSONValue = .dictionary([
                "markdown": .dictionary([:])
            ])
            
            catalogueManager.handleCatalogue(
                sectionType: sectionType,
                displayTitle: displayTitle,
                action: .replace,
                config: config,
                content: content
            )
        } else {
            print("⚠️ Card section simulation not yet implemented in test view")
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
            "markdown": .string(markdown)
        ])
        let config: JSONValue = .dictionary([
            "markdown": .dictionary([:])
        ])
        
        manager.handleCatalogue(
            sectionType: "overview",
            displayTitle: "Overview",
            action: .replace,
            config: config,
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
    }
}
#endif
