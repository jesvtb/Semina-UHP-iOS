import SwiftUI
import UIKit

// MARK: - Tab Selection
enum TabSelection: Int {
  case journey = 0
  case map = 1
  case chat = 2
  case profile = 3
}

// MARK: - Environment Key for Tab Selection
private struct SelectedTabKey: EnvironmentKey {
  static let defaultValue: Binding<TabSelection> = .constant(.journey)
}

extension EnvironmentValues {
  var selectedTab: Binding<TabSelection> {
    get { self[SelectedTabKey.self] }
    set { self[SelectedTabKey.self] = newValue }
  }
}

struct MainView: View {
  @EnvironmentObject var apiClient: APIClient

  @EnvironmentObject var uhpGateway: UHPGateway
  @EnvironmentObject var locationManager: LocationManager
  @State var username = ""
  @State var fullName = ""
  @State var website = ""
  @State var userEmail = ""

  @State var isLoading = false
  @State private var selectedTab: TabSelection = .journey
  @State var currentNotification: NotificationData?
  @State var chatMessages: [ChatMessage] = []
  @State private var showChatView = false
  @State var shouldDismissKeyboard = false
  
  // Location-related state
  @State private var isLoadingLocation = false
  @State private var lastSentLocation: (latitude: Double, longitude: Double)?
  @State private var bottomSheetOffset: CGFloat = 0
  @State private var geoJSONData: [String: Any]?
  @State private var geoJSONUpdateTrigger: UUID = UUID()
  @State private var places: Places = []

  var body: some View {
    ZStack(alignment: .bottom) {
      // Full screen map as base
      MapboxMapView(
        geoJSONData: $geoJSONData,
        geoJSONUpdateTrigger: $geoJSONUpdateTrigger,
        targetCameraLocation: .constant(nil)
      )
        .ignoresSafeArea(.all)
      
      // Location Bottom Sheet - positioned at bottom
      if locationManager.currentLocation != nil || true { // TODO: Remove "|| true" after testing
        InfoSheet(
          locationDetails: locationManager.locationDetails,
          offset: $bottomSheetOffset,
          selectedTab: $selectedTab,
          username: username,
          fullName: fullName,
          website: website,
          userEmail: userEmail,
          places: places,
          onPlaceBookmark: bookmarkPlace
        )
        .zIndex(1000) // Ensure it's on top
        .allowsHitTesting(true) // Ensure it can receive touches
        #if DEBUG
        .onAppear {
          print("📍 Bottom sheet condition met - location available")
          if let locationDetails = locationManager.locationDetails {
            print("   Location details: \(locationDetails)")
          } else {
            print("   Location details: nil")
          }
        }
        #endif
      }
      
      // Notification Banner - positioned above bottom sheet (hidden when chat sheet is open)
      if let notification = currentNotification, !showChatView {
        VStack {
          Spacer()
          NotificationBanner(notification: notification) {
            currentNotification = nil
          }
          .padding(.bottom, 720) // Position above bottom sheet (400px partial height + 120px padding)
        }
        .zIndex(1500) // Above bottom sheet but below tab bar
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
      }
      
      // Custom Tab Bar - always visible at absolute bottom
      CustomTabBar(selectedTab: $selectedTab)
        .zIndex(2000) // Above bottom sheet
        .ignoresSafeArea(edges: .bottom) // Keep at absolute bottom
    }
    .onAppear {
      configureTabBarAppearance()
      print("🔵 MainView appeared")
    }
    .onChange(of: locationManager.currentLocation) { newLocation in
      // Only make API call when location is captured and change is significant
      // Skip if this is the initial load (handled by .task)
      if newLocation != nil {
        Task {
          await loadLocationIfSignificant()
        }
      }
    }
    .task { @MainActor in
      // Initial load: If location is already available, call immediately (first time)
      // Otherwise, wait for onChange to trigger when location is captured
      // Use a small delay to avoid race condition with onChange
      try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
      if locationManager.currentLocation != nil {
        await loadLocationIfSignificant()
      }
    }
    .onChange(of: selectedTab) { newTab in
      // Show chat modal when chat tab is selected
      if newTab == .chat {
        showChatView = true
      }
    }
    .onChange(of: showChatView) { isPresented in
      // When modal is dismissed, switch back to journey tab and restore bottom sheet
      if !isPresented && selectedTab == .chat {
        selectedTab = .journey
        // Bottom sheet will automatically fade back in and return to partial via selectedTab onChange
      }
    }
    .sheet(isPresented: $showChatView) {
      // Present chat as separate modal view
      ChatModalView(
        chatMessages: $chatMessages,
        shouldDismissKeyboard: $shouldDismissKeyboard,
        currentNotification: $currentNotification,
        onSendMessage: { messageText in
          await sendChatMessage(messageText)
        }
      )
    }
  }
  
  // MARK: - Tab Bar Styling
  private func configureTabBarAppearance() {
    let appearance = UITabBarAppearance()
    
    // Configure tab bar background
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(Color.appBackground)
    
    // Configure selected tab item
    appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.appPrimary)
    appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
      .foregroundColor: UIColor(Color.appPrimary),
      .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
    ]
    
    // Configure unselected tab item
    appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
    appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
      .foregroundColor: UIColor.secondaryLabel,
      .font: UIFont.systemFont(ofSize: 10, weight: .regular)
    ]
    
    // Apply shadow/border styling
    appearance.shadowColor = UIColor.separator
    appearance.shadowImage = UIImage()
    
    // Apply the appearance
    UITabBar.appearance().standardAppearance = appearance
    if #available(iOS 15.0, *) {
      UITabBar.appearance().scrollEdgeAppearance = appearance
    }
  }


  // MARK: - Chat Message Handling
  private func sendChatMessage(_ messageText: String) async {
    #if DEBUG
    print("🚀 sendChatMessage() called with message: '\(messageText)'")
    #endif
    
    // Validate message is not empty
    let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedMessage.isEmpty else {
      #if DEBUG
      print("⚠️ sendChatMessage: Message is empty after trimming, not sending")
      #endif
      return
    }
    
    // Add user message to chat immediately on main actor
    await MainActor.run {
      chatMessages.append(ChatMessage(text: trimmedMessage, isUser: true, isStreaming: false))
      #if DEBUG
      print("✅ User message added to chat. Total messages: \(chatMessages.count)")
      #endif
    }
    
    // Create assistant message placeholder for streaming
    await MainActor.run {
      chatMessages.append(ChatMessage(text: "", isUser: false, isStreaming: true))
      #if DEBUG
      print("✅ Assistant placeholder added. Total messages: \(chatMessages.count)")
      #endif
    }
    
    do {
      // Prepare request data (use trimmed message)
      var jsonDict: [String: Any] = [
        "message": trimmedMessage
      ]
      
      // Add device date, time, and day of week (separated)
      let now = Date()
      let dateFormatter = DateFormatter()
      dateFormatter.timeZone = TimeZone.current
      
      // Date format: yyyy-MM-dd
      dateFormatter.dateFormat = "yyyy-MM-dd"
      jsonDict["current_date"] = dateFormatter.string(from: now)
      
      // Time format: HH:mm:ss
      dateFormatter.dateFormat = "HH:mm:ss"
      jsonDict["current_time"] = dateFormatter.string(from: now)
      
      // Day of week format: Full day name (Monday, Tuesday, etc.)
      dateFormatter.dateFormat = "EEEE"
      jsonDict["current_weekday"] = dateFormatter.string(from: now)
      
      // Add device language
      let languageCode: String
      if #available(iOS 16.0, *) {
        languageCode = Locale.current.language.languageCode?.identifier ?? "en"
      } else {
        languageCode = Locale.current.languageCode ?? "en"
      }
      jsonDict["device_lang"] = languageCode
      
      // Add location and country from LocationManager's locationDetails
      if let locationDetails = locationManager.locationDetails {
        if let location = locationDetails["location"] as? String {
          jsonDict["current_location"] = location
        }
        // Check both country_name and country fields
        if let countryName = locationDetails["country_name"] as? String {
          jsonDict["current_country"] = countryName
        } else if let country = locationDetails["country"] as? String {
          jsonDict["current_country"] = country
        }
      }
      
      #if DEBUG
      print("💬 Preparing API request:")
      print("   Endpoint: /v1/ask")
      print("   Method: POST")
      print("   Message: '\(trimmedMessage)'")
      print("   JSON Dict: \(jsonDict)")
      #endif
      
      // Use streaming API to receive notifications and content
      #if DEBUG
      print("📡 Calling uhpGateway.stream()...")
      #endif

      let stream = try await uhpGateway.stream(
        endpoint: "/v1/ask",
        jsonDict: jsonDict
      )
      #if DEBUG
      print("✅ Stream received from uhpGateway.stream()")
      #endif
      
      #if DEBUG
      print("✅ Stream created, starting to process events...")
      #endif
      
      var streamingContent = ""
      
      // Process SSE events from stream
      var eventCount = 0
      for try await event in stream {
        eventCount += 1
        #if DEBUG
        print("📨 SSE Event #\(eventCount) received:")
        print("   Event type: \(event.event ?? "nil")")
        print("   Data: \(event.data.prefix(100))...")
        #endif
        
        await handleChatStreamEvent(event: event, streamingContent: &streamingContent)
      }
      
      // Ensure the final assistant message is marked as not streaming
      await MainActor.run {
        if let lastIndex = chatMessages.indices.last,
           !chatMessages[lastIndex].isUser {
          let existingMessage = chatMessages[lastIndex]
          chatMessages[lastIndex] = ChatMessage(
            id: existingMessage.id,
            text: existingMessage.text,
            isUser: existingMessage.isUser,
            isStreaming: false
          )
          #if DEBUG
          print("✅ Stream finished, marked last assistant message as not streaming")
          #endif
        }
      }
      
      #if DEBUG
      print("✅ Stream processing completed. Total events: \(eventCount)")
      #endif
      
    } catch {
      #if DEBUG
      print("❌ Failed to send chat message:")
      print("   Error: \(error)")
      print("   Error type: \(type(of: error))")
      print("   Error localized description: \(error.localizedDescription)")
      if let apiError = error as? APIError {
        print("   API Error message: \(apiError.message)")
        print("   API Error code: \(apiError.code ?? -1)")
      }
      #endif
      
      // Remove the streaming message placeholder on error
      await MainActor.run {
        if let lastIndex = chatMessages.indices.last,
           !chatMessages[lastIndex].isUser,
           chatMessages[lastIndex].text.isEmpty {
          chatMessages.removeLast()
          #if DEBUG
          print("✅ Removed empty streaming message placeholder after error")
          #endif
        }
      }
    }
  }
  
  // MARK: - Location Management
  
  /// Checks if location change is significant (>= 0.001 for either coordinate)
  /// Returns true if change is significant or if this is the first location
  private func isLocationChangeSignificant(
    newLatitude: Double,
    newLongitude: Double
  ) -> Bool {
    // If we haven't sent a location before, always send it
    guard let lastSent = lastSentLocation else {
      return true
    }
    
    // Calculate differences
    let latDifference = abs(newLatitude - lastSent.latitude)
    let lonDifference = abs(newLongitude - lastSent.longitude)
    
    // Only make request if change is >= 0.001 (3rd decimal place) for either coordinate
    let threshold: Double = 0.001
    let isSignificant = latDifference >= threshold || lonDifference >= threshold
    
    #if DEBUG
    if isSignificant {
      print("📍 Significant location change detected:")
      print("   Old: [\(lastSent.latitude), \(lastSent.longitude)]")
      print("   New: [\(newLatitude), \(newLongitude)]")
      print("   Lat diff: \(latDifference), Lon diff: \(lonDifference)")
    } else {
      print("📍 Location change too small, skipping API call:")
      print("   Lat diff: \(latDifference), Lon diff: \(lonDifference) (threshold: \(threshold))")
    }
    #endif
    
    return isSignificant
  }
  
  /// Checks if location change is significant before making API call
  private func loadLocationIfSignificant() async {
    // Prevent concurrent API calls
    guard !isLoadingLocation else {
      #if DEBUG
      print("⏸️ API call already in progress, skipping duplicate request")
      #endif
      return
    }
    
    // Only proceed if location is actually available
    guard let latitude = locationManager.latitude,
          let longitude = locationManager.longitude else {
      #if DEBUG
      print("⚠️ Location not available yet, skipping API call")
      #endif
      return
    }
    
    // Check if location change is significant BEFORE reverse geocoding
    guard isLocationChangeSignificant(newLatitude: latitude, newLongitude: longitude) else {
      #if DEBUG
      print("⏸️ Location change not significant, skipping API call")
      #endif
      return
    }
    
    // Reverse geocode user location and get JSON dict
    #if DEBUG
    print("📍 Calling reverseGeocodeUserLocation() from loadLocationIfSignificant()")
    #endif
    
    let locationDict = await withCheckedContinuation { continuation in
      locationManager.reverseGeocodeUserLocation { dict, error in
        if let error = error {
          #if DEBUG
          print("⚠️ Reverse geocoding error: \(error.localizedDescription), using location only")
          #endif
          // Even if geocoding fails, dict should still have location data
          continuation.resume(returning: dict)
        } else {
          continuation.resume(returning: dict)
        }
      }
    }
    
    guard let locationDict = locationDict else {
      #if DEBUG
      print("❌ Failed to get location dict from reverse geocoding")
      #endif
      return
    }
    
    // Make the API call with the location dict
    await loadLocation(jsonDict: locationDict)
  }
  
  private func loadLocation(jsonDict: [String: Any]) async {
    isLoadingLocation = true
    defer { isLoadingLocation = false }
    
    // Extract user_lat and user_lon from jsonDict (LocationManager uses user_lat/user_lon)
    guard let userLat = jsonDict["user_lat"] as? Double,
          let userLon = jsonDict["user_lon"] as? Double else {
      #if DEBUG
      print("⚠️ Missing user_lat or user_lon in location dict")
      #endif
      return
    }
    
    // Check cache first
    if let cachedGeoJSON = locationManager.reconstructGeoJSONFromCache(userLat: userLat, userLon: userLon) {
      #if DEBUG
      print("✅ Using cached GeoJSON data")
      #endif
      let cachedPlaces = parsePlaces(from: cachedGeoJSON)
      // Update geoJSONData to trigger map update
      await MainActor.run {
        geoJSONData = cachedGeoJSON
        geoJSONUpdateTrigger = UUID()
        places = cachedPlaces
      }
      // Update last sent location
      lastSentLocation = (latitude: userLat, longitude: userLon)
      return
    }
    
    // Cache miss - make API call
    do {
      #if DEBUG
      print("📍 Sending location to API: \(userLat), \(userLon)")
      print("📦 Full location dict: \(jsonDict)")
      #endif
      
      let response = try await uhpGateway.request(
        endpoint: "/v1/signed-in-home",
        method: "POST",
        jsonDict: jsonDict
      )
      
      // Update last sent location after successful API call
      lastSentLocation = (latitude: userLat, longitude: userLon)
      
      // Parse response: extract data field containing GeoJSON FeatureCollection
      // Response format: {result: {event: "map", data: {type: "FeatureCollection", features: [...]}}, status: "success", ...}
      guard let responseDict = response as? [String: Any],
            let result = responseDict["result"] as? [String: Any],
            let event = result["event"] as? String,
            event == "map",
            let data = result["data"] as? [String: Any],
            let features = data["features"] as? [[String: Any]] else {
        #if DEBUG
        if let responseDict = response as? [String: Any] {
          print("⚠️ Invalid response format. Available keys: \(responseDict.keys.joined(separator: ", "))")
          if let result = responseDict["result"] as? [String: Any] {
            print("   Result keys: \(result.keys.joined(separator: ", "))")
          }
        } else {
          print("⚠️ Invalid response format. Response is not a dictionary.")
        }
        #endif
        return
      }
      
      // Process features: extract idx and pageid, save to cache
      var featuresList: [[String: Any]] = []
      for feature in features {
        guard let properties = feature["properties"] as? [String: Any],
              let idx = properties["idx"] as? Int,
              let pageid = properties["pageid"] as? Int else {
          continue
        }
        
        // Add to features list for location cache
        featuresList.append([
          "idx": idx,
          "pageid": pageid
        ])
        
        // Save individual feature to cache
        locationManager.saveCachedFeature(pageid: pageid, feature: feature)
      }
      
      // Save location cache with list of {idx, pageid}
      locationManager.saveCachedLocationData(userLat: userLat, userLon: userLon, features: featuresList)
      
      // Update geoJSONData to trigger map update
      // Format: {event: "map", data: {type: "FeatureCollection", features: [...]}}
      let geoJSONResponse: [String: Any] = [
        "event": event,
        "data": data
      ]
      let parsedPlaces = parsePlaces(from: geoJSONResponse)
      await MainActor.run {
        geoJSONData = geoJSONResponse
        geoJSONUpdateTrigger = UUID()
        places = parsedPlaces
      }
      
      #if DEBUG
      print("✅ GeoJSON data loaded and cached with \(featuresList.count) features")
      #endif
      
      #if DEBUG
      print("✅ GeoJSON data loaded and cached with \(featuresList.count) features")
      #endif
      
    } catch let apiError as APIError {
      #if DEBUG
      print("❌ API Error: \(apiError.message)")
      if let code = apiError.code {
        print("   Status Code: \(code)")
      }
      #endif
    } catch {
      #if DEBUG
      print("❌ Failed to load location: \(error.localizedDescription)")
      print("   Error type: \(type(of: error))")
      #endif
    }
  }
  
  private func parsePlaces(from geoJSON: [String: Any]) -> Places {
    guard
      let data = geoJSON["data"] as? [String: Any],
      let features = data["features"] as? [[String: Any]]
    else {
      return []
    }
    
    let parsedPlaces = features.compactMap { Place(feature: $0) }
    return parsedPlaces.sorted { $0.sortIndex < $1.sortIndex }
  }
  
  private func bookmarkPlace(_ place: Place) {
    #if DEBUG
    print("🔖 Bookmark tapped for \(place.title) (\(place.id))")
    #endif
  }
  
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - Scroll Content Offset Preference Key (for bottom sheet)
struct ScrollContentOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - Chat Scroll Offset Preference Key
struct ChatScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - Notification Model
struct NotificationData {
  let type: String?
  let message: String
  
  init?(from dict: [String: Any]) {
    guard let message = dict["message"] as? String else {
      return nil
    }
    self.type = dict["type"] as? String
    self.message = message
  }
  
  // Convenience initializer for creating mock notifications
  init(type: String? = nil, message: String) {
    self.type = type
    self.message = message
  }
}

// MARK: - Chat Message Model
struct ChatMessage: Identifiable {
  let id: UUID
  let text: String
  let isUser: Bool
  let isStreaming: Bool
  
  init(id: UUID = UUID(), text: String, isUser: Bool, isStreaming: Bool) {
    self.id = id
    self.text = text
    self.isUser = isUser
    self.isStreaming = isStreaming
  }
}

// MARK: - Places Model
typealias Places = [Place]

struct Place: Identifiable, Hashable {
  let id: Int
  let title: String
  let description: String
  let categories: [String]
  let wikiURL: URL?
  let imageURL: URL?
  let latitude: Double?
  let longitude: Double?
  let sortIndex: Int
  
  init?(feature: [String: Any]) {
    guard let properties = feature["properties"] as? [String: Any],
          let pageid = properties["pageid"] as? Int else {
      return nil
    }
    
    self.id = pageid
    self.sortIndex = properties["idx"] as? Int ?? Int.max
    self.title = properties["title"] as? String ?? properties["name"] as? String ?? "Untitled Place"
    
    let extract = properties["short_description"] as? String ??
      properties["extract"] as? String ?? ""
    self.description = extract
    self.categories = properties["categories"] as? [String] ?? []
    
    if let wikiString = properties["wiki_url"] as? String {
      self.wikiURL = URL(string: wikiString)
    } else {
      self.wikiURL = nil
    }
    
    if let imageString = properties["img_url"] as? String {
      self.imageURL = URL(string: imageString)
    } else {
      self.imageURL = nil
    }
    
    if
      let geometry = feature["geometry"] as? [String: Any],
      let coordinates = geometry["coordinates"] as? [Double],
      coordinates.count >= 2
    {
      self.longitude = coordinates[0]
      self.latitude = coordinates[1]
    } else {
      self.latitude = nil
      self.longitude = nil
    }
  }
}



// MARK: - Journey Item Model
struct JourneyItem: Identifiable {
  let id = UUID()
  let title: String
  let description: String
  let imageURL: String?
}

// MARK: - Journey Card Component
struct JourneyCard: View {
  let journey: JourneyItem
  
  var body: some View {
    NavigationLink(destination: JourneyStart()) {
      VStack(alignment: .leading, spacing: 0) {
        // Image
        AsyncImage(url: journey.imageURL != nil ? URL(string: journey.imageURL!) : nil) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          Rectangle()
            .fill(Color(.systemGray4))
            .overlay {
              Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            }
        }
        .frame(height: 200)
        .clipped()
        
        // Content
        VStack(alignment: .leading, spacing: 8) {
          Text(journey.title)
            .font(.title2)
            .fontWeight(.semibold)
          
          Text(journey.description)
            .font(.body)
            .foregroundColor(.secondary)
            .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Color(.systemBackground))
      .cornerRadius(12)
      .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Notification Banner Component
struct NotificationBanner: View {
  let notification: NotificationData
  var onDismiss: (() -> Void)?
  var zIndex: Double = 1500
  
  /// Maps notification type to SF Symbol icon name
  private var iconName: String {
    guard let type = notification.type else {
      return "bell.fill" // Default icon for null type
    }
    
    switch type.lowercased() {
    case "info", "information":
      return "info.circle.fill"
    case "search", "search web":
      return "magnifyingglass"
    case "success", "completed":
      return "checkmark.circle.fill"
    case "warning", "alert":
      return "exclamationmark.triangle.fill"
    case "error", "failure":
      return "xmark.circle.fill"
    case "location", "gps":
      return "location.fill"
    case "journey", "trip":
      return "signpost.right.and.left.fill"
    case "message", "chat":
      return "message.fill"
    case "update", "refresh":
      return "arrow.clockwise.circle.fill"
    default:
      return "bell.fill" // Default icon for unknown types
    }
  }
  
  // The banner content itself
  private var bannerContent: some View {
    HStack(spacing: 12) {
      // Icon placeholder
      Image(systemName: iconName)
        .font(.title3)
        .foregroundColor(.primary)
        .frame(width: 24, height: 24)
      
      // Notification message
      Text(notification.message)
        // .font(.subheadline)
        .bodyText()
        .foregroundColor(Color("onBkgTextColor20"))
        .lineLimit(2)
        .multilineTextAlignment(.leading)
    }
    .padding(.horizontal, 16)  // Inner padding: space between content and background
    .padding(.vertical, 12)     // Inner padding: space between content and background
    .background(
      Color(.systemBackground)
        .opacity(0.95)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
    )
    // .padding(.horizontal)       // Outer padding: margin from screen edges
    // .padding(.bottom, 8)        // Outer padding: margin from bottom
  }
  
  var body: some View {
    // Always positioned from top, independent of other views
    VStack {
      bannerContent
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.top, 8)
      // Spacer()
    }
    // .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    // .ignoresSafeArea(.all) // Position absolutely from screen edges, not relative to other views
    // .zIndex(zIndex)
    // .allowsHitTesting(true) // Allow interaction when notification is visible
    // .id(notification.message) // Force SwiftUI to recognize view updates
    // .animation(.spring(response: 0.3, dampingFraction: 0.8), value: notification.message)
  }
}




// MARK: - Place Row
struct PlaceRow: View {
  let place: Place
  let onBookmark: (Place) -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "location")
          .font(.headline)
          .foregroundColor(.teal)
          .padding(8)
          .background(Color.teal.opacity(0.12))
          .clipShape(Circle())
        
        VStack(alignment: .leading, spacing: 4) {
          Text(place.title)
            .font(.headline)
            .foregroundColor(.primary)
          
          if !place.description.isEmpty {
            Text(place.description)
              .font(.subheadline)
              .foregroundColor(.secondary)
              .lineLimit(3)
          }
          
          if !place.categories.isEmpty {
            Text(place.categories.prefix(2).joined(separator: " • "))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        
        Spacer()
        
        Button(action: { onBookmark(place) }) {
          Image(systemName: "bookmark")
            .font(.title3)
            .foregroundColor(.primary)
            .frame(width: 32, height: 32)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    )
  }
}

// MARK: - Detail Row Component
struct DetailRow: View {
  let icon: String
  let title: String
  let value: String
  
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(.teal)
        .frame(width: 24)
      
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .foregroundColor(.secondary)
        Text(value)
          .font(.body)
          .foregroundColor(.primary)
      }
      
      Spacer()
    }
    .padding(.vertical, 8)
  }
}

// MARK: - Review Card Component
struct ReviewCard: View {
  let author: String
  let rating: Int
  let date: String
  let comment: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(author)
            .font(.headline)
          Text(date)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        
        Spacer()
        
        // Star rating
        HStack(spacing: 2) {
          ForEach(1...5, id: \.self) { index in
            Image(systemName: index <= rating ? "star.fill" : "star")
              .foregroundColor(index <= rating ? .yellow : .gray.opacity(0.3))
              .font(.caption)
          }
        }
      }
      
      Text(comment)
        .font(.body)
        .foregroundColor(.primary)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
}

// MARK: - Corner Radius Extension
extension View {
  func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
    clipShape(RoundedCorner(radius: radius, corners: corners))
  }
}

struct RoundedCorner: Shape {
  var radius: CGFloat = .infinity
  var corners: UIRectCorner = .allCorners

  func path(in rect: CGRect) -> Path {
    let path = UIBezierPath(
      roundedRect: rect,
      byRoundingCorners: corners,
      cornerRadii: CGSize(width: radius, height: radius)
    )
    return Path(path.cgPath)
  }
}

// MARK: - Multi-line Text Input with Return Key Support
struct MultiLineTextField: UIViewRepresentable {
  @Binding var text: String
  var placeholder: String
  var onReturnKeyPress: (String) -> Void
  
  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.font = UIFont.systemFont(ofSize: 16)
    textView.backgroundColor = UIColor.systemGray6
    textView.layer.cornerRadius = 8
    // Reduced padding for smaller initial size
    textView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
    textView.textContainer.lineFragmentPadding = 0
    textView.isScrollEnabled = true
    textView.textContainer.maximumNumberOfLines = 5
    textView.textContainer.lineBreakMode = .byWordWrapping
    textView.returnKeyType = .send
    textView.enablesReturnKeyAutomatically = true
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
    
    // Set initial placeholder
    if text.isEmpty {
      textView.text = placeholder
      textView.textColor = UIColor.placeholderText
    }
    
    return textView
  }
  
  func updateUIView(_ uiView: UITextView, context: Context) {
    // Always update when text is cleared (even if editing) to clear the input after sending
    let currentText = (uiView.text ?? "") == placeholder ? "" : (uiView.text ?? "")
    if currentText != text {
      if text.isEmpty {
        // Force clear text and show placeholder, even if editing
        uiView.text = placeholder
        uiView.textColor = UIColor.placeholderText
        // Reset editing state to allow placeholder to show
        context.coordinator.isEditing = false
      } else if !context.coordinator.isEditing {
        // Only update text if not editing (to avoid interfering with user typing)
        uiView.text = text
        uiView.textColor = UIColor.label
      }
    }
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
  
  class Coordinator: NSObject, UITextViewDelegate {
    var parent: MultiLineTextField
    var isEditing = false
    
    init(_ parent: MultiLineTextField) {
      self.parent = parent
    }
    
    func textViewDidChange(_ textView: UITextView) {
      // Update parent text, excluding placeholder
      let currentText = textView.text ?? ""
      if currentText != parent.placeholder {
        parent.text = currentText
      } else {
        parent.text = ""
      }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
      // Handle return key press
      if text == "\n" {
        let currentText = (textView.text == parent.placeholder) ? "" : (textView.text ?? "")
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
          // Capture the text BEFORE clearing
          let textToSend = trimmedText
          // Clear the text view immediately after capturing
          textView.text = parent.placeholder
          textView.textColor = UIColor.placeholderText
          parent.text = ""
          isEditing = false
          // Pass the captured text to the callback
          parent.onReturnKeyPress(textToSend)
          return false // Prevent newline
        }
        return false // Don't add newline even if empty
      }
      
      // Handle placeholder removal when user starts typing
      let currentText = textView.text ?? ""
      if currentText == parent.placeholder && !text.isEmpty {
        textView.text = ""
        textView.textColor = UIColor.label
      }
      
      return true
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
      isEditing = true
      let currentText = textView.text ?? ""
      if currentText == parent.placeholder {
        textView.text = ""
        textView.textColor = UIColor.label
      }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
      isEditing = false
      let currentText = textView.text ?? ""
      if currentText.isEmpty {
        textView.text = parent.placeholder
        textView.textColor = UIColor.placeholderText
      }
    }
  }
}



#Preview {
  MainView()
    .environmentObject(UHPGateway())
    .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
    .environmentObject(LocationManager())
}
