import SwiftUI
import Foundation
import SafariServices

// MARK: - Bookmarked Web Search Result
/// Extended WebSearchResult with bookmark context
struct BookmarkedWebSearchResult: Codable {
    let id: String
    let title: String
    let url: URL
    let published_date: String
    let text: String
    let summary: String?
    let image_url: URL?
    let bookmark_context: String
    
    // Custom encoding/decoding to handle URL strings
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case published_date
        case text
        case summary
        case image_url
        case bookmark_context
    }
    
    init(from result: WebSearchResult, bookmarkContext: String) {
        self.id = result.id
        self.title = result.title
        self.url = result.url
        self.published_date = result.published_date
        self.text = result.text
        self.summary = result.summary
        self.image_url = result.image_url
        self.bookmark_context = bookmarkContext
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        
        let urlString = try container.decode(String.self, forKey: .url)
        guard let decodedURL = URL(string: urlString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Invalid URL string: \(urlString)")
        }
        url = decodedURL
        
        published_date = try container.decode(String.self, forKey: .published_date)
        text = try container.decode(String.self, forKey: .text)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        
        if let imageUrlString = try container.decodeIfPresent(String.self, forKey: .image_url) {
            image_url = URL(string: imageUrlString)
        } else {
            image_url = nil
        }
        
        bookmark_context = try container.decode(String.self, forKey: .bookmark_context)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url.absoluteString, forKey: .url)
        try container.encode(published_date, forKey: .published_date)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(image_url?.absoluteString, forKey: .image_url)
        try container.encode(bookmark_context, forKey: .bookmark_context)
    }
}

// MARK: - Bookmark Manager
/// Manages cached bookmarks for web search results
enum BookmarkManager {
    private static let bookmarksKey = "web_search_bookmarks"
    
    /// Save a bookmark to cache
    static func saveBookmark(_ result: WebSearchResult, bookmarkContext: String) {
        let bookmarkedResult = BookmarkedWebSearchResult(from: result, bookmarkContext: bookmarkContext)
        var bookmarks = loadAllBookmarks()
        
        // Remove existing bookmark with same ID if it exists
        bookmarks.removeAll { $0.id == result.id }
        
        // Add new bookmark
        bookmarks.append(bookmarkedResult)
        
        // Save to UserDefaults - direct encoding to string
        if let jsonData = try? JSONEncoder().encode(bookmarks),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            StorageManager.saveToUserDefaults(jsonString, forKey: bookmarksKey)
        }
    }
    
    /// Remove a bookmark from cache
    static func removeBookmark(resultId: String) {
        var bookmarks = loadAllBookmarks()
        bookmarks.removeAll { $0.id == resultId }
        
        // Save updated list - direct encoding to string
        if let jsonData = try? JSONEncoder().encode(bookmarks),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            StorageManager.saveToUserDefaults(jsonString, forKey: bookmarksKey)
        }
    }
    
    /// Load all bookmarks from cache
    static func loadAllBookmarks() -> [BookmarkedWebSearchResult] {
        guard let jsonString = StorageManager.loadFromUserDefaults(forKey: bookmarksKey, as: String.self),
              let jsonData = jsonString.data(using: .utf8),
              let bookmarks = try? JSONDecoder().decode([BookmarkedWebSearchResult].self, from: jsonData) else {
            return []
        }
        
        return bookmarks
    }
    
    /// Check if a result is bookmarked
    static func isBookmarked(resultId: String) -> Bool {
        let bookmarks = loadAllBookmarks()
        return bookmarks.contains { $0.id == resultId }
    }
    
    /// Get bookmark context for a result
    static func getBookmarkContext(resultId: String) -> String? {
        let bookmarks = loadAllBookmarks()
        return bookmarks.first { $0.id == resultId }?.bookmark_context
    }
}

struct WebSearchResult: Identifiable, Codable {
    let id: String
    let title: String
    let url: URL
    let published_date: String
    let text: String
    let summary: String?
    let image_url: URL?
    
    // Custom decoding to handle URL strings from JSON
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case published_date
        case text
        case summary
        case image_url
    }
    
    // Regular initializer for creating instances directly
    init(id: String, title: String, url: URL, published_date: String, text: String, summary: String?, image_url: URL?) {
        self.id = id
        self.title = title
        self.url = url
        self.published_date = published_date
        self.text = text
        self.summary = summary
        self.image_url = image_url
    }
    
    // Custom decoding to handle URL strings from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        
        // Decode URL from string
        let urlString = try container.decode(String.self, forKey: .url)
        guard let decodedURL = URL(string: urlString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Invalid URL string: \(urlString)")
        }
        url = decodedURL
        
        published_date = try container.decode(String.self, forKey: .published_date)
        text = try container.decode(String.self, forKey: .text)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        
        // Decode optional URL from string
        if let imageUrlString = try container.decodeIfPresent(String.self, forKey: .image_url) {
            image_url = URL(string: imageUrlString)
        } else {
            image_url = nil
        }
    }
    
    /// Parses the ISO 8601 date string and returns a formatted date string according to user's locale and timezone
    var formattedPublishedDate: String? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = isoFormatter.date(from: published_date) else {
            // Fallback: try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            guard let date = isoFormatter.date(from: published_date) else {
                return nil
            }
            return formatDate(date)
        }
        
        return formatDate(date)
    }
    
    /// Formats a Date according to user's locale and timezone
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct WebSearchResultItemLarge: View {
    let result: WebSearchResult
    @State private var isBookmarked: Bool = false
    @State private var showWebPage: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main content button - wraps all image and text info
            Button(action: {
                showWebPage = true
            }) {
                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    // Title
            Text(result.title)
                        .heading(size: .article0)
                        .foregroundColor(Color("onBkgTextColor10"))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, Spacing.current.space2xl) // Space for bookmark button
                    
                    // HStack with date/summary VStack and image
                    HStack(alignment: .top, spacing: Spacing.current.spaceXs) {
                        // VStack containing date and summary
                        VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                            if let formattedDate = result.formattedPublishedDate {
                                Text(formattedDate)
                                    .bodyText(size: .articleMinus1)
                                    .foregroundColor(Color("onBkgTextColor30").opacity(0.7))
                                    .multilineTextAlignment(.leading)
                            }
                            
                            if let summary = result.summary, !summary.isEmpty {
                                Text(summary)
                                    .bodyText(size: .articleMinus1)
                                    .foregroundColor(Color("onBkgTextColor30"))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        
                        // Small square image
                        if let imageUrl = result.image_url {
                            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                                        .frame(width: 60, height: 60)
                case .success(let image):
                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .saturation(0.4)
                                        .brightness(-0.1)
                                        .overlay(
                                            Color("AccentColor").opacity(0.15)
                                                .blendMode(.softLight)
                                        )
                                        .clipped()
                                        .cornerRadius(Spacing.current.space3xs)
                                case .failure:
                                    Image(systemName: "photo")
                                        .foregroundColor(Color("onBkgTextColor20").opacity(0.5))
                                        .frame(width: 60, height: 60)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: 60, height: 60)
                        }
                    }
                }
                
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Bookmark button overlaid at upper right corner
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isBookmarked {
                        // Remove bookmark
                        BookmarkManager.removeBookmark(resultId: result.id)
                        isBookmarked = false
                    } else {
                        // Add bookmark with context (using title as context for now)
                        let context = result.title
                        BookmarkManager.saveBookmark(result, bookmarkContext: context)
                        isBookmarked = true
                    }
                }
            }) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .bodyText(size: .article1)
                    .foregroundColor(isBookmarked ? Color("AccentColor") : Color("onBkgTextColor20"))
            }
            
        }
        .padding(.horizontal, Spacing.current.space3xs)
        .padding(.vertical, Spacing.current.spaceXs)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color("onBkgTextColor20").opacity(0.2)),
            alignment: .bottom
        )
        .sheet(isPresented: $showWebPage) {
            SafariView(url: result.url)
        }
        .onAppear {
            // Check if this result is already bookmarked
            isBookmarked = BookmarkManager.isBookmarked(resultId: result.id)
        }
    }
}

// MARK: - Safari View Wrapper
/// Wraps SFSafariViewController for use in SwiftUI
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

struct WebSearchResultListLarge: View {
    let results: [WebSearchResult]
    @State private var isExpanded: Bool
    let initialExpanded: Bool
    
    init(results: [WebSearchResult], initialExpanded: Bool = false) {
        self.results = results
        self.initialExpanded = initialExpanded
        _isExpanded = State(initialValue: initialExpanded)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Expanded: Show header with collapse button and the full list
                VStack(spacing: 0) {
                    // Header with collapse button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    }) {
                        HStack(spacing: Spacing.current.spaceXs) {
                            Image(systemName: "link")
                                .bodyText(size: .article1)
                                .foregroundColor(Color("onBkgTextColor10"))
                            
                            Text("Hide Searched Results")
                                .bodyText(size: .article0)
                                .foregroundColor(Color("onBkgTextColor10"))
                            
                            Spacer()
                            
                            Image(systemName: "chevron.up")
                                .bodyText(size: .articleMinus1)
                                .foregroundColor(Color("onBkgTextColor20"))
                        }
                        .padding(.horizontal, Spacing.current.spaceXs)
                        .padding(.vertical, Spacing.current.space2xs)
                        .background(Color("AppBkgColor"))
                    }
                    
                    // List content
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { result in
                                WebSearchResultItemLarge(result: result)
                                    .background(Color("AppBkgColor"))
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .background(Color("AppBkgColor"))
                }
            } else {
                // Collapsed: Show banner
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }) {
                    HStack(spacing: Spacing.current.spaceXs) {
                        Image(systemName: "link")
                            .bodyText(size: .article1)
                            .foregroundColor(Color("onBkgTextColor10"))
                        
                        Text("Show Searched Results")
                            .bodyText(size: .article0)
                            .foregroundColor(Color("onBkgTextColor10"))
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor20"))
                    }
                    .padding(.horizontal, Spacing.current.spaceXs)
                    .padding(.vertical, Spacing.current.space2xs)
                    .background(Color("AppBkgColor"))
                }
            }
        }
        .background(Color("AppBkgColor"))
    }
}

// MARK: - Small Variant Components
struct WebSearchResultItemSM: View {
    let result: WebSearchResult
    @State private var showWebPage: Bool = false
    
    var body: some View {
        Button(action: {
            showWebPage = true
        }) {
            HStack(spacing: Spacing.current.space2xs) {
                Image(systemName: "link")
                    .bodyText(size: .articleMinus2)
                    .foregroundColor(Color("onBkgTextColor30"))
                
                Text(result.title)
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor20")).opacity(0.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showWebPage) {
            SafariView(url: result.url)
        }
    }
}

struct WebSearchResultListSM: View {
    let results: [WebSearchResult]
    @State private var isExpanded: Bool
    let initialExpanded: Bool
    
    init(results: [WebSearchResult], initialExpanded: Bool = false) {
        self.results = results
        self.initialExpanded = initialExpanded
        _isExpanded = State(initialValue: initialExpanded)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Expanded: Show header with collapse button and the full list
                VStack(spacing: 0) {
                    // Header with collapse button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    }) {
                        HStack(spacing: Spacing.current.space2xs) {
                            Image(systemName: "link")
                                .bodyText(size: .articleMinus2)
                                .foregroundColor(Color("onBkgTextColor20"))
                            
                            Text("Hide Searched Results")
                                .bodyText(size: .articleMinus1)
                                .foregroundColor(Color("onBkgTextColor10"))
                            
                            
                            Image(systemName: "chevron.up")
                                .bodyText(size: .articleMinus1)
                                .foregroundColor(Color("onBkgTextColor20"))
                            
                            Spacer()
                        }
                        // .padding(.horizontal, Spacing.current.spaceXs)
                        .padding(.vertical, Spacing.current.space2xs)
                        .background(Color("AppBkgColor"))
                    }
                    
                    // List content
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { result in
                                WebSearchResultItemSM(result: result)
                            }
                        }
                    }
                }
            } else {
                // Collapsed: Show banner
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }) {
                    HStack(spacing: Spacing.current.spaceXs) {
                        Image(systemName: "link")
                            .bodyText(size: .articleMinus2)
                            .foregroundColor(Color("onBkgTextColor10"))
                        
                        Text("Show Searched Results")
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor10"))
                        
                        Image(systemName: "chevron.down")
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor20"))

                        Spacer()
                    }
                    .padding(.vertical, Spacing.current.space2xs)
                }
            }
        }
        .background(Color("AppBkgColor"))
    }
}

#if DEBUG
#Preview {
    WebSearchResultItemLarge(result: WebSearchResult(
        id: "1",
        title: "Test Title",
        url: URL(string: "https://www.getyourguide.com/explorer/istanbul-ttd56/weekend-in-istanbul/")!,
        published_date: "2024-10-03T18:49:55.000Z",
        text: "Neque senectus est porttitor auctor etiam lobortis posuere quisque eget accumsan tellus mollis platea vel ultricies consequat, himenaeos lorem aliquet egestas quam ultrices dictum mus suscipit montes efficitur ridiculus dui penatibus. Fermentum orci dapibus interdum ullamcorper montes praesent neque a donec nunc, malesuada enim aliquam in egestas phasellus amet consequat. Eget tempus netus suscipit velit mattis praesent dapibus odio scelerisque maecenas sapien ad auctor senectus, inceptos conubia pulvinar arcu etiam est duis nisl purus sociosqu feugiat cubilia ornare.",
        summary: "Neque senectus est porttitor auctor etiam lobortis posuere quisque eget accumsan tellus mollis platea vel ultricies consequat",
        image_url: URL(string: "https://images.contentstack.io/v3/assets/blt06f605a34f1194ff/blt152b55f334d45a35/6777f3189acec9951bc7b50a/BCC-2023-EXPLORER-Istanbul-Fun-things-to-do-in-Istanbul-HEADER_DESKTOP.jpg?fit=crop&disable=upscale&auto=webp&quality=60&crop=smart&width=1920&height=1080")!))
}

#Preview("Search List (Large)") {
    WebSearchResultListPreview()
}

#Preview("Search List (Small)") {
    WebSearchResultListSMPreview()
}

// MARK: - Preview Helper Component
/// Preview-only component that loads JSON data and displays the list
private struct WebSearchResultListPreview: View {
    @State private var results: [WebSearchResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: Spacing.current.spaceS) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Color("onBkgTextColor20"))
                    Text("Failed to load data")
                        .bodyText(size: .article0)
                        .foregroundColor(Color("onBkgTextColor20"))
                    Text(error)
                        .bodyText(size: .articleMinus1)
                        .foregroundColor(Color("onBkgTextColor20").opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.current.spaceS)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WebSearchResultListLarge(results: results, initialExpanded: true)
            }
        }
        .background(Color("AppBkgColor"))
        .onAppear {
            loadJSONData()
        }
    }
    
    private func loadJSONData() {
        // Try to find the file in the bundle
        // First try with subdirectory
        var url = Bundle.main.url(forResource: "web_search_results", withExtension: "json", subdirectory: "mock")
        
        // If not found, try without subdirectory
        if url == nil {
            url = Bundle.main.url(forResource: "web_search_results", withExtension: "json")
        }
        
        guard let fileURL = url else {
            errorMessage = "Could not find web_search_results.json in bundle"
            isLoading = false
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            
            // Try to decode as array directly
            if let arrayResults = try? decoder.decode([WebSearchResult].self, from: data) {
                results = arrayResults
            } else if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let resultsArray = jsonDict["results"] as? [[String: Any]] {
                // Try to decode from {"results": [...]} format
                let resultsData = try JSONSerialization.data(withJSONObject: resultsArray)
                results = try decoder.decode([WebSearchResult].self, from: resultsData)
            } else {
                errorMessage = "Invalid JSON structure"
            }
            
            isLoading = false
        } catch {
            errorMessage = "Failed to load JSON: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

// MARK: - Preview Helper Component for SM
/// Preview-only component that loads JSON data and displays the SM list
private struct WebSearchResultListSMPreview: View {
    @State private var results: [WebSearchResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: Spacing.current.spaceS) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Color("onBkgTextColor20"))
                    Text("Failed to load data")
                        .bodyText(size: .article0)
                        .foregroundColor(Color("onBkgTextColor20"))
                    Text(error)
                        .bodyText(size: .articleMinus1)
                        .foregroundColor(Color("onBkgTextColor20").opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.current.spaceS)
                }
                .frame(maxWidth: .infinity)
            } else {
                WebSearchResultListSM(results: results, initialExpanded: true)
            }
        }
        .background(Color("AppBkgColor"))
        .onAppear {
            loadJSONData()
        }
    }
    
    private func loadJSONData() {
        // Try to find the file in the bundle
        // First try with subdirectory
        var url = Bundle.main.url(forResource: "web_search_results", withExtension: "json", subdirectory: "mock")
        
        // If not found, try without subdirectory
        if url == nil {
            url = Bundle.main.url(forResource: "web_search_results", withExtension: "json")
        }
        
        guard let fileURL = url else {
            errorMessage = "Could not find web_search_results.json in bundle"
            isLoading = false
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            
            // Try to decode as array directly
            if let arrayResults = try? decoder.decode([WebSearchResult].self, from: data) {
                results = arrayResults
            } else if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let resultsArray = jsonDict["results"] as? [[String: Any]] {
                // Try to decode from {"results": [...]} format
                let resultsData = try JSONSerialization.data(withJSONObject: resultsArray)
                results = try decoder.decode([WebSearchResult].self, from: resultsData)
            } else {
                errorMessage = "Invalid JSON structure"
            }
            
            isLoading = false
        } catch {
            errorMessage = "Failed to load JSON: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
#endif

