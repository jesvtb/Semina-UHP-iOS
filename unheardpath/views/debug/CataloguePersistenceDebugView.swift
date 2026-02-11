import SwiftUI
import core

#if DEBUG
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
        let fm = FileManager.default
        let contextsDir = Storage.cachesURL.appendingPathComponent("catalogue/contexts")
        let snapshotFile = Storage.cachesURL.appendingPathComponent("catalogue/last_context.json")
        
        if fm.fileExists(atPath: contextsDir.path) {
            try? fm.removeItem(at: contextsDir)
        }
        if fm.fileExists(atPath: snapshotFile.path) {
            try? fm.removeItem(at: snapshotFile)
        }
        
        statusMessage = "Cleared all cache files"
        refresh()
    }
    
    // MARK: - File Loading
    
    private func loadContextFiles() {
        let fm = FileManager.default
        let contextsDir = Storage.cachesURL.appendingPathComponent("catalogue/contexts")
        
        guard fm.fileExists(atPath: contextsDir.path),
              let files = try? fm.contentsOfDirectory(at: contextsDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            contextFiles = []
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        contextFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { fileURL -> ContextFileInfo? in
                let filename = fileURL.lastPathComponent
                let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = resources?.fileSize ?? 0
                let modified = resources?.contentModificationDate
                
                // Try to decode the context for metadata
                var geoKey = filename.replacingOccurrences(of: ".json", with: "")
                var level = "unknown"
                var sectionCount = 0
                var sectionTypes: [String] = []
                
                var rawJSON = "(unable to read file)"
                if let data = try? Data(contentsOf: fileURL) {
                    // Pretty-print the raw JSON
                    if let jsonObject = try? JSONSerialization.jsonObject(with: data),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        rawJSON = prettyString
                    } else {
                        rawJSON = String(data: data, encoding: .utf8) ?? "(binary data)"
                    }
                    
                    if let context = try? decoder.decode(CachedContext.self, from: data) {
                        geoKey = context.geoKey
                        level = context.level.identifier
                        sectionCount = context.sections.count
                        sectionTypes = context.sectionOrder
                    }
                }
                
                return ContextFileInfo(
                    filename: filename,
                    fileSize: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
                    modified: modified.map { dateFormatter.string(from: $0) } ?? "unknown",
                    geoKey: geoKey,
                    level: level,
                    sectionCount: sectionCount,
                    sectionTypes: sectionTypes,
                    rawJSON: rawJSON
                )
            }
    }
    
    private func loadSnapshot() {
        let snapshotFile = Storage.cachesURL.appendingPathComponent("catalogue/last_context.json")
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: snapshotFile.path),
              let data = try? Data(contentsOf: snapshotFile) else {
            lastSnapshot = nil
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let snapshot = try? decoder.decode(CachedCatalogueSnapshot.self, from: data) else {
            lastSnapshot = nil
            return
        }
        
        // Pretty-print the raw snapshot JSON
        let rawJSON: String
        if let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            rawJSON = prettyString
        } else {
            rawJSON = String(data: data, encoding: .utf8) ?? "(binary data)"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        
        let locSummary: String = {
            var parts: [String] = []
            if let locality = snapshot.locationSummary.locality { parts.append(locality) }
            if let admin = snapshot.locationSummary.adminArea { parts.append(admin) }
            if let country = snapshot.locationSummary.countryCode { parts.append(country) }
            if parts.isEmpty {
                return String(format: "%.4f, %.4f", snapshot.locationSummary.latitude, snapshot.locationSummary.longitude)
            }
            return parts.joined(separator: ", ")
        }()
        
        lastSnapshot = SnapshotInfo(
            geoKey: snapshot.geoKey,
            level: snapshot.level.identifier,
            savedAt: dateFormatter.string(from: snapshot.savedAt),
            sectionOrder: snapshot.sectionOrder,
            locationSummary: locSummary,
            rawJSON: rawJSON
        )
    }
    
    // MARK: - Helpers
    
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
#endif
