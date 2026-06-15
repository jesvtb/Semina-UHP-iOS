import SwiftUI
import core

// MARK: - Cache Debug Content View

/// Debug view showing cache statistics, session events, and device/lookup locations
struct CacheDebugContentView: View {
    @EnvironmentObject var eventManager: EventManager
    let onClearCache: () -> Void
    let onDismiss: () -> Void
    
    @State private var isThisSessionEventsExpanded = false
    @State private var isLastDeviceLocationExpanded = false
    @State private var isLastLookupLocationExpanded = false
    
    private var cacheInfo: (entryCount: Int, totalSize: Int, formattedSize: String, breakdown: [(key: String, size: Int, formattedSize: String, value: Any?)]) {
        getCacheInfo()
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                // Cache statistics
                VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                    Text("Cache Statistics")
                        .bodyText(size: .article1)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Cache Entries:")
                        Spacer()
                        Text(verbatim: String(cacheInfo.entryCount))
                            .foregroundColor(Color("onBkgTextColor30"))
                    }
                    .bodyText()
                    
                    HStack {
                        Text("Total Size:")
                        Spacer()
                        Text(cacheInfo.formattedSize)
                            .foregroundColor(Color("onBkgTextColor30"))
                    }
                    .bodyText()
                    
                    if cacheInfo.entryCount > 0 {
                        Divider()
                            .padding(.vertical, Spacing.current.space2xs)
                        
                        // Cache entry breakdown
                        VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                            Text("Cache Breakdown")
                                .bodyText(size: .articleMinus1)
                                .fontWeight(.semibold)
                                .padding(.bottom, Spacing.current.space3xs)
                            
                            ForEach(cacheInfo.breakdown, id: \.key) { item in
                                cacheBreakdownRow(item: item)
                            }
                        }
                    }
                }
                .padding(Spacing.current.spaceS)
                .background(
                    Color("onBkgTextColor30")
                        .opacity(0.1)
                        .cornerRadius(Spacing.current.spaceXs)
                )
                
                // EventManager.thisSession events - expandable
                expandableSection(
                    title: "This Session Events",
                    isExpanded: $isThisSessionEventsExpanded,
                    isEmpty: eventManager.thisSession.isEmpty,
                    emptyMessage: "No events in this session"
                ) {
                    if !eventManager.thisSession.isEmpty {
                        let totalCount = eventManager.thisSession.count
                        ForEach(Array(eventManager.thisSession.reversed().enumerated()), id: \.offset) { index, event in
                            thisSessionEventSection(index: totalCount - index, event: event)
                        }
                    }
                }
                
                // LastDeviceLocation - expandable
                expandableSection(
                    title: "LastDeviceLocation",
                    isExpanded: $isLastDeviceLocationExpanded,
                    isEmpty: eventManager.latestDeviceLocation == nil,
                    emptyMessage: "No device location available"
                ) {
                    if let deviceLocation = eventManager.latestDeviceLocation {
                        locationJsonView(json: deviceLocation)
                    }
                }
                
                // LastLookupLocation - expandable
                expandableSection(
                    title: "LastLookupLocation",
                    isExpanded: $isLastLookupLocationExpanded,
                    isEmpty: eventManager.latestLookupLocation == nil,
                    emptyMessage: "No lookup location available"
                ) {
                    if let lookupLocation = eventManager.latestLookupLocation {
                        locationJsonView(json: lookupLocation)
                    }
                }
                
                // Clear cache button
                Button(action: onClearCache) {
                    HStack {
                        Spacer()
                        Text("Clear Cache")
                            .bodyText()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.current.space2xs)
                    .background(
                        Color.red
                            .cornerRadius(Spacing.current.spaceXs)
                    )
                }
            }
            .padding(Spacing.current.spaceS)
        }
        .navigationTitle("Debug Cache")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    onDismiss()
                }
            }
        }
    }
    
    private func expandableSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        isEmpty: Bool,
        emptyMessage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
            Button(action: {
                withAnimation {
                    isExpanded.wrappedValue.toggle()
                }
            }) {
                HStack {
                    Text(title)
                        .bodyText(size: .article1)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color("onBkgTextColor30"))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded.wrappedValue {
                if isEmpty {
                    Text(emptyMessage)
                        .bodyText(size: .articleMinus1)
                        .foregroundColor(Color("onBkgTextColor30"))
                        .padding(Spacing.current.spaceS)
                } else {
                    content()
                }
            }
        }
        .padding(Spacing.current.spaceS)
        .background(
            Color("onBkgTextColor30")
                .opacity(0.1)
                .cornerRadius(Spacing.current.spaceXs)
        )
    }
    
    private func locationJsonView(json: [String: JSONValue]) -> some View {
        Text(JSONValue.prettyDict(json))
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(Color("onBkgTextColor30"))
            .padding(Spacing.current.space2xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color("onBkgTextColor30")
                    .opacity(0.06)
                    .cornerRadius(Spacing.current.space3xs)
            )
    }
    
    private func cacheBreakdownRow(item: (key: String, size: Int, formattedSize: String, value: Any?)) -> some View {
        HStack {
            Text(item.key)
                .bodyText(size: .articleMinus1)
            Spacer()
            
            // Show simple values inline
            if let value = item.value {
                if let boolValue = value as? Bool {
                    Text(verbatim: boolValue ? "true" : "false")
                        .bodyText(size: .articleMinus1)
                        .foregroundColor(Color("onBkgTextColor30"))
                        .padding(.trailing, Spacing.current.space2xs)
                } else if let stringValue = value as? String, stringValue.count < 50 {
                    Text(stringValue)
                        .bodyText(size: .articleMinus1)
                        .foregroundColor(Color("onBkgTextColor30"))
                        .lineLimit(1)
                        .padding(.trailing, Spacing.current.space2xs)
                }
            }
            
            Text(item.formattedSize)
                .bodyText(size: .articleMinus1)
                .foregroundColor(Color("onBkgTextColor30"))
        }
    }
    
    private func thisSessionEventSection(index: Int, event: UserEvent) -> some View {
        VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
            Text(verbatim: "Event \(index)")
                .bodyText(size: .articleMinus1)
                .fontWeight(.semibold)
                .foregroundColor(Color("onBkgTextColor30"))
            
            // Structured keys (non-evt_data)
            VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                structuredRow(label: "evt_utc", value: event.evt_utc)
                if let tz = event.evt_timezone {
                    structuredRow(label: "evt_timezone", value: tz)
                }
                structuredRow(label: "evt_type", value: event.evt_type)
                if let sid = event.session_id {
                    let sidDisplay = sid.count >= 6 ? String(sid.suffix(6)) : sid
                    structuredRow(label: "session_id", value: sidDisplay)
                }
            }
            
            // evt_data as JSON
            Text("evt_data")
                .bodyText(size: .articleMinus1)
                .fontWeight(.medium)
            Text(JSONValue.prettyDict(event.evt_data))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color("onBkgTextColor30"))
                .padding(Spacing.current.space2xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color("onBkgTextColor30")
                        .opacity(0.06)
                        .cornerRadius(Spacing.current.space3xs)
                )
        }
        .padding(Spacing.current.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color("onBkgTextColor30")
                .opacity(0.08)
                .cornerRadius(Spacing.current.spaceXs)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.current.spaceXs)
                .stroke(Color("onBkgTextColor30").opacity(0.2), lineWidth: 1)
        )
    }
    
    private func structuredRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(verbatim: "\(label):")
                .bodyText(size: .articleMinus1)
                .fontWeight(.medium)
            Text(value)
                .bodyText(size: .articleMinus1)
                .foregroundColor(Color("onBkgTextColor30"))
                .lineLimit(3)
            Spacer(minLength: 0)
        }
    }
    
    private func getCacheInfo() -> (entryCount: Int, totalSize: Int, formattedSize: String, breakdown: [(key: String, size: Int, formattedSize: String, value: Any?)]) {
        let prefixedKeysDict = Storage.allUserDefaultsKeysWithPrefix()
        
        var breakdown: [(key: String, size: Int, formattedSize: String, value: Any?)] = []
        var totalSize = 0
        let prefix = Storage.keyPrefix
        
        for (key, value) in prefixedKeysDict.sorted(by: { $0.key < $1.key }) {
            let valueString = "\(value)"
            let size = valueString.data(using: .utf8)?.count ?? 0
            totalSize += size
            
            let keyWithoutPrefix = prefix.isEmpty ? key : (key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key)
            let formattedSize = formatBytes(size)
            breakdown.append((key: keyWithoutPrefix, size: size, formattedSize: formattedSize, value: value))
        }
        
        return (
            entryCount: prefixedKeysDict.count,
            totalSize: totalSize,
            formattedSize: formatBytes(totalSize),
            breakdown: breakdown
        )
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Journey Storage Debug View

struct JourneyStorageDebugView: View {
    private struct StoredFileInfo: Identifiable {
        let id = UUID()
        let relativePath: String
        let formattedSize: String
        let modifiedAt: String
    }

    @State private var downloadedJourneyIds: [String] = []
    @State private var audioPathMap: [String: String] = [:]
    @State private var materialPathMap: [String: String] = [:]
    @State private var activeJourneySummary: String = "No active session found."
    @State private var journeyFiles: [StoredFileInfo] = []
    @State private var audioFiles: [StoredFileInfo] = []
    @State private var materialFiles: [StoredFileInfo] = []
    @State private var statusMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section("UserDefaults Keys") {
                    labeledValueRow(
                        label: "downloaded_journeys",
                        value: downloadedJourneyIds.isEmpty ? "[]" : downloadedJourneyIds.joined(separator: ", ")
                    )
                    labeledValueRow(
                        label: "audio_path_map entries",
                        value: "\(audioPathMap.count)"
                    )
                    labeledValueRow(
                        label: "material_path_map entries",
                        value: "\(materialPathMap.count)"
                    )
                }

                Section("Active Journey Session") {
                    Text(activeJourneySummary)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color("onBkgTextColor30"))
                        .textSelection(.enabled)
                }

                storageFilesSection(
                    title: "journeys/",
                    files: journeyFiles,
                    emptyMessage: "No journey manifests/files found in Application Support."
                )

                storageFilesSection(
                    title: "audio/",
                    files: audioFiles,
                    emptyMessage: "No audio files found in Application Support."
                )

                storageFilesSection(
                    title: "materials/",
                    files: materialFiles,
                    emptyMessage: "No material files found in Application Support."
                )

                Section("Actions") {
                    Button("Refresh") {
                        refreshJourneyStorage()
                    }
                }

                if let statusMessage {
                    Section("Status") {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Journey Storage")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                refreshJourneyStorage()
            }
        }
    }

    private func storageFilesSection(
        title: String,
        files: [StoredFileInfo],
        emptyMessage: String
    ) -> some View {
        Section("\(title) (\(files.count))") {
            if files.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(files) { fileInfo in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileInfo.relativePath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Text(fileInfo.formattedSize)
                            Text("•")
                            Text(fileInfo.modifiedAt)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func labeledValueRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func refreshJourneyStorage() {
        downloadedJourneyIds = (
            Storage.loadFromUserDefaults(
                forKey: "journey_manifest.downloaded_journeys",
                as: [String].self
            ) ?? []
        ).sorted()

        audioPathMap = Storage.loadFromUserDefaults(
            forKey: "journey_manifest.audio_path_map",
            as: [String: String].self
        ) ?? [:]

        materialPathMap = Storage.loadFromUserDefaults(
            forKey: "journey_manifest.material_path_map",
            as: [String: String].self
        ) ?? [:]

        activeJourneySummary = buildActiveJourneySummary()

        let appSupportURL = Storage.appSupportURL
        journeyFiles = listFiles(
            under: appSupportURL.appendingPathComponent("journeys"),
            baseURL: appSupportURL
        )
        audioFiles = listFiles(
            under: appSupportURL.appendingPathComponent("audio"),
            baseURL: appSupportURL
        )
        materialFiles = listFiles(
            under: appSupportURL.appendingPathComponent("materials"),
            baseURL: appSupportURL
        )

        statusMessage = "Refreshed at \(Date().formatted(date: .abbreviated, time: .standard))"
    }

    private func buildActiveJourneySummary() -> String {
        guard let activeJourneyData = Storage.loadFromUserDefaults(
            forKey: "active_journey.session",
            as: Data.self
        ) else {
            return "No active session found."
        }

        let decoder = JSONDecoder()
        if let decodedJourney = try? decoder.decode(ActiveJourney.self, from: activeJourneyData) {
            let completedCount = decodedJourney.completedStopIndices.count
            let totalCount = decodedJourney.stories.count
            return """
            journey_id: \(decodedJourney.journeyId)
            version: \(decodedJourney.journeyVersion)
            status: \(decodedJourney.status.rawValue)
            current_stop_index: \(decodedJourney.currentStopIndex)
            completed_stops: \(completedCount)/\(totalCount)
            sources: \(decodedJourney.sourceJourneyIds.joined(separator: ", "))
            """
        }

        return "active_journey.session exists but could not be decoded (bytes: \(activeJourneyData.count))."
    }

    private func listFiles(under directoryURL: URL, baseURL: URL) -> [StoredFileInfo] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        var files: [StoredFileInfo] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isDirectory != true else {
                continue
            }
            let fileSizeBytes = values.fileSize ?? 0
            let modifiedDate = values.contentModificationDate
            files.append(
                StoredFileInfo(
                    relativePath: fileURL.path.replacingOccurrences(
                        of: baseURL.path + "/",
                        with: ""
                    ),
                    formattedSize: ByteCountFormatter.string(
                        fromByteCount: Int64(fileSizeBytes),
                        countStyle: .file
                    ),
                    modifiedAt: modifiedDate.map { dateFormatter.string(from: $0) } ?? "unknown"
                )
            )
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }
}
