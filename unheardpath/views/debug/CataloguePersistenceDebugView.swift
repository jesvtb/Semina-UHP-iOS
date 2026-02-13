import SwiftUI
import core

// MARK: - Catalogue Persistence Debug View

/// Debug view to observe catalogue persistence: cached context files, last snapshot, and manual actions.
struct CataloguePersistenceDebugView: View {
    @EnvironmentObject var catalogueManager: CatalogueManager
    @EnvironmentObject var eventManager: EventManager
    
    @State private var contextFiles: [ContextFileInfo] = []
    @State private var lastSnapshot: SnapshotInfo?
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var expandedFileIDs: Set<UUID> = []
    @State private var isSnapshotExpanded: Bool = false
    
    struct ContextFileInfo: Identifiable {
        let id = UUID()
        let filename: String
        let fileSize: String
        let modified: String
        let geoKey: String
        let level: String
        let sectionCount: Int
        let sectionTypes: [String]
        let rawJSON: String
    }
    
    struct SnapshotInfo {
        let geoKey: String
        let level: String
        let savedAt: String
        let sectionOrder: [String]
        let locationSummary: String
        let rawJSON: String
    }
    
    var body: some View {
        NavigationView {
            List {
                // Current in-memory state
                inMemorySection
                
                // Last context snapshot
                snapshotSection
                
                // Cached context files on disk
                contextFilesSection
                
                // Actions
                actionsSection
                
                // Status
                if let status = statusMessage {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Catalogue Persistence")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { refresh() }
        }
    }
    
    // MARK: - In-Memory Section
    
    private var inMemorySection: some View {
        Section(header: Text("In-Memory Catalogue")) {
            if catalogueManager.orderedSections.isEmpty {
                Text("No sections loaded")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(catalogueManager.orderedSections) { section in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.displayTitle)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(section.sectionType)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(contentSummary(section.content))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let location = catalogueManager.locationDetailData {
                HStack {
                    Text("Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        if let place = location.placeName {
                            Text(place)
                                .font(.caption2)
                        }
                        if let locality = location.locality, let country = location.countryCode {
                            Text("\(locality), \(country)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let source = location.dataSource {
                            Text(source.rawValue)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Snapshot Section
    
    private var snapshotSection: some View {
        Section(header: Text("Last Context Snapshot")) {
            if let snap = lastSnapshot {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Geo Key", value: snap.geoKey)
                                .font(.caption)
                            LabeledContent("Level", value: snap.level)
                                .font(.caption)
                            LabeledContent("Saved At", value: snap.savedAt)
                                .font(.caption)
                            LabeledContent("Location", value: snap.locationSummary)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Section Order")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(snap.sectionOrder.joined(separator: " -> "))
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                        Image(systemName: isSnapshotExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if isSnapshotExpanded {
                        Divider()
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(snap.rawJSON)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSnapshotExpanded.toggle()
                    }
                }
            } else {
                Text("No snapshot saved")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Context Files Section
    
    private var contextFilesSection: some View {
        Section(header: HStack {
            Text("Cached Context Files")
            Spacer()
            Text("\(contextFiles.count) files")
                .font(.caption2)
                .foregroundColor(.secondary)
        }) {
            if contextFiles.isEmpty {
                Text("No cached contexts on disk")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(contextFiles) { file in
                    let isExpanded = expandedFileIDs.contains(file.id)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.filename)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                HStack(spacing: 12) {
                                    Label(file.level, systemImage: "globe")
                                    Label(file.fileSize, systemImage: "doc")
                                    Label("\(file.sectionCount) sections", systemImage: "list.bullet")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                Text(file.sectionTypes.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text("Modified: \(file.modified)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if isExpanded {
                            Divider()
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(file.rawJSON)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedFileIDs.remove(file.id)
                            } else {
                                expandedFileIDs.insert(file.id)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        Section(header: Text("Actions")) {
            Button(action: { refresh() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            
            Button(action: { persistNow() }) {
                Label("Persist Current State", systemImage: "square.and.arrow.down")
            }
            .disabled(catalogueManager.orderedSections.isEmpty || catalogueManager.locationDetailData == nil)
            
            Button(action: { restoreNow() }) {
                Label("Restore from Cache", systemImage: "square.and.arrow.up")
            }
            
            Button(action: { clearAllCacheFiles() }) {
                Label("Clear All Cache Files", systemImage: "trash")
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Actions
    
    private func refresh() {
        isLoading = true
        statusMessage = nil
        loadContextFiles()
        loadSnapshot()
        isLoading = false
    }
    
    private func persistNow() {
        guard let location = catalogueManager.locationDetailData else {
            statusMessage = "No location data available to persist"
            return
        }
        catalogueManager.persistCurrentState(for: location)
        statusMessage = "Persisted \(catalogueManager.orderedSections.count) sections"
        // Refresh after a short delay to let file I/O complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refresh()
        }
    }
    
    private func restoreNow() {
        Task {
            if let lookupLocation = eventManager.latestLookupLocation,
               let locationDetail = LocationDetailData(eventDict: lookupLocation) {
                await catalogueManager.restoreFromCache(for: locationDetail)
                statusMessage = "Restored from cache for lookup location"
            } else if let deviceLocation = eventManager.latestDeviceLocation,
                      let locationDetail = LocationDetailData(eventDict: deviceLocation) {
                await catalogueManager.restoreFromCache(for: locationDetail)
                statusMessage = "Restored from cache for device location"
            } else {
                await catalogueManager.restoreFromCache()
                statusMessage = "Restored from last context snapshot"
            }
            refresh()
        }
    }
    
    private func clearAllCacheFiles() {
        CatalogueFileStore.clearAllFiles()
        statusMessage = "Cleared all cache files"
        refresh()
    }
    
    // MARK: - File Loading
    
    private func loadContextFiles() {
        let fileManager = FileManager.default
        let contextsDirectoryURL = Storage.cachesURL.appendingPathComponent("catalogue/contexts")
        
        guard fileManager.fileExists(atPath: contextsDirectoryURL.path) else {
            contextFiles = []
            return
        }
        
        let dateFormatter = buildDebugDateFormatter()
        let decoder = buildISO8601JSONDecoder()
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: contextsDirectoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            contextFiles = files
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { makeContextFileInfo(from: $0, dateFormatter: dateFormatter, decoder: decoder) }
        } catch {
            contextFiles = []
            statusMessage = "Failed to read context files: \(error.localizedDescription)"
        }
    }
    
    private func loadSnapshot() {
        let snapshotFileURL = Storage.cachesURL.appendingPathComponent("catalogue/last_context.json")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: snapshotFileURL.path) else {
            lastSnapshot = nil
            return
        }
        
        do {
            let snapshotData = try Data(contentsOf: snapshotFileURL)
            let decoder = buildISO8601JSONDecoder()
            let snapshot = try decoder.decode(CachedCatalogueSnapshot.self, from: snapshotData)
            let dateFormatter = buildDebugDateFormatter()
            
            lastSnapshot = SnapshotInfo(
                geoKey: snapshot.geoKey,
                level: snapshot.level.identifier,
                savedAt: dateFormatter.string(from: snapshot.savedAt),
                sectionOrder: snapshot.sectionOrder,
                locationSummary: formatLocationSummary(snapshot.locationSummary),
                rawJSON: buildPrettyJSONString(from: snapshotData)
            )
        } catch {
            lastSnapshot = nil
            statusMessage = "Failed to load snapshot: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helpers
    
    private func buildDebugDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
    
    private func buildISO8601JSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
    private func makeContextFileInfo(
        from fileURL: URL,
        dateFormatter: DateFormatter,
        decoder: JSONDecoder
    ) -> ContextFileInfo? {
        let fileName = fileURL.lastPathComponent
        let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = resourceValues?.fileSize ?? 0
        let modifiedDate = resourceValues?.contentModificationDate
        
        let metadata = parseContextMetadata(from: fileURL, decoder: decoder, fileName: fileName)
        
        return ContextFileInfo(
            filename: fileName,
            fileSize: ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file),
            modified: modifiedDate.map { dateFormatter.string(from: $0) } ?? "unknown",
            geoKey: metadata.geoKey,
            level: metadata.level,
            sectionCount: metadata.sectionCount,
            sectionTypes: metadata.sectionTypes,
            rawJSON: metadata.rawJSON
        )
    }
    
    private func parseContextMetadata(
        from fileURL: URL,
        decoder: JSONDecoder,
        fileName: String
    ) -> (geoKey: String, level: String, sectionCount: Int, sectionTypes: [String], rawJSON: String) {
        let fallbackGeoKey = fileName.replacingOccurrences(of: ".json", with: "")
        
        do {
            let contextData = try Data(contentsOf: fileURL)
            let rawJSON = buildPrettyJSONString(from: contextData)
            
            guard let context = try? decoder.decode(CachedContext.self, from: contextData) else {
                return (fallbackGeoKey, "unknown", 0, [], rawJSON)
            }
            
            return (
                context.geoKey,
                context.level.identifier,
                context.sections.count,
                context.sectionOrder,
                rawJSON
            )
        } catch {
            let fallbackRawJSON = "(unable to read file: \(error.localizedDescription))"
            return (fallbackGeoKey, "unknown", 0, [], fallbackRawJSON)
        }
    }
    
    private func buildPrettyJSONString(from data: Data) -> String {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? "(binary data)"
        }
        return prettyString
    }
    
    private func formatLocationSummary(_ locationSummary: CachedLocationSummary) -> String {
        let locationParts = [locationSummary.locality, locationSummary.adminArea, locationSummary.countryCode]
            .compactMap { $0 }
        
        guard !locationParts.isEmpty else {
            return String(format: "%.4f, %.4f", locationSummary.latitude, locationSummary.longitude)
        }
        
        return locationParts.joined(separator: ", ")
    }
    
    private func contentSummary(_ content: JSONValue) -> String {
        if case .dictionary(let dict) = content {
            if dict["markdown"]?.stringValue != nil {
                return "markdown"
            }
            if case .array(let cards) = dict["cards"] {
                return "\(cards.count) cards"
            }
            // Nested subsections
            let subsections = dict.values.filter { if case .dictionary = $0 { return true }; return false }
            if !subsections.isEmpty {
                return "\(subsections.count) subsections"
            }
        }
        return "content"
    }
}
