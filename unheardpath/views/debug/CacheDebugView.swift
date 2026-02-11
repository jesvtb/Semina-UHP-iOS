import SwiftUI
import core

#if DEBUG
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
#endif
