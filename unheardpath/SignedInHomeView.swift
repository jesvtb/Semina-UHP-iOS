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

struct SignedInHomeView: View {
  @EnvironmentObject var apiClient: APIClient

  @EnvironmentObject var uhpGateway: UHPGateway
  @State var username = ""
  @State var fullName = ""
  @State var website = ""
  @State var userEmail = ""

  @State var isLoading = false
  @State private var selectedTab: TabSelection = .journey
  @State private var isJourneyTabBarHidden = false
  @State private var currentNotification: NotificationData?
  @State private var chatMessages: [ChatMessage] = []
  @State private var showChatView = false
  @State private var shouldDismissKeyboard = false

  var body: some View {
    ZStack(alignment: .bottom) {
      // Full screen map as base
      MapboxMapView()
        .ignoresSafeArea(.all)
      
      // Bottom Sheet with tab-controlled content (excluding chat)
      JourneyHomeView(
        isTabBarHidden: $isJourneyTabBarHidden,
        selectedTab: $selectedTab,
        currentNotification: $currentNotification,
        chatMessages: $chatMessages,
        username: username,
        fullName: fullName,
        website: website,
        userEmail: userEmail,
        onSendChatMessage: { messageText in
          await sendChatMessage(messageText)
        }
      )
      .environmentObject(uhpGateway)
      
      // Custom Tab Bar - always visible at absolute bottom
      CustomTabBar(selectedTab: $selectedTab)
        .zIndex(2000) // Above bottom sheet
        .ignoresSafeArea(edges: .bottom) // Keep at absolute bottom
    }
    .onAppear {
      configureTabBarAppearance()
      print("🔵 SignedInHomeView appeared")
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
        currentNotification: $currentNotification,
        shouldDismissKeyboard: $shouldDismissKeyboard,
        onSendMessage: { messageText in
          await sendChatMessage(messageText)
        }
      )
      .presentationDetents([.height(300)])
      .presentationDragIndicator(.visible)
      .presentationBackground(.clear)
    }
    .task {
      print("🔵 SignedInHomeView task started")
      await getInitialProfile()
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

  func getInitialProfile() async {
    do {
      let currentUser = try await supabase.auth.session.user
      
      // Get email from session
      self.userEmail = currentUser.email ?? "Not available"

      let profile: Profile =
      try await supabase
        .from("profiles")
        .select()
        .eq("id", value: currentUser.id)
        .single()
        .execute()
        .value

      self.username = profile.username ?? ""
      self.fullName = profile.fullName ?? ""
      self.website = profile.website ?? ""
      print("✅ Profile fetched successfully: \(profile)")

    } catch {
      #if DEBUG
      print("❌ Profile fetch error: \(error)")
      if let errorString = error.localizedDescription as String? {
        if errorString.contains("Access to schema is forbidden") {
          print("⚠️ Schema access error - this might be due to:")
          print("   1. Using new publishable key format - verify it's enabled in Supabase Dashboard")
          print("   2. Row Level Security (RLS) policies blocking access")
          print("   3. Swift SDK compatibility with new key format")
          print("   Reference: https://github.com/orgs/supabase/discussions/29260")
        }
      }
      #endif
      debugPrint(error)
      
      // Still try to get email even if profile fetch fails
      do {
        let currentUser = try await supabase.auth.session.user
        self.userEmail = currentUser.email ?? "Not available"
      } catch {
        self.userEmail = "Not available"
      }
    }
  }

  func updateProfileButtonTapped() {
    Task {
      isLoading = true
      defer { isLoading = false }
      do {
        let currentUser = try await supabase.auth.session.user

        try await supabase
          .from("profiles")
          .update(
            UpdateProfileParams(
              username: username,
              fullName: fullName,
              website: website
            )
          )
          .eq("id", value: currentUser.id)
          .execute()
      } catch {
        #if DEBUG
        print("❌ Profile update error: \(error)")
        if let errorString = error.localizedDescription as String? {
          if errorString.contains("Access to schema is forbidden") {
            print("⚠️ Schema access error - check RLS policies and API key permissions")
          }
        }
        #endif
        debugPrint(error)
      }
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
      let jsonDict: [String: Any] = [
        "message": trimmedMessage
      ]
      
      #if DEBUG
      print("💬 Preparing API request:")
      print("   URL: http://192.168.50.171:1031/v1/ask")
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
        
        // Handle notification events
        if event.event == "notification" {
          #if DEBUG
          print("🔔 Processing notification event")
          #endif
          // Parse the notification data
          guard let dataDict = try event.parseJSONData() else {
            #if DEBUG
            print("⚠️ Failed to parse notification data as JSON")
            #endif
            continue
          }
          
          // Create notification from parsed data
          guard let notification = NotificationData(from: dataDict) else {
            #if DEBUG
            print("⚠️ Failed to create notification from data: \(dataDict)")
            #endif
            continue
          }
          
          // Update notification on main thread
          await MainActor.run {
            #if DEBUG
            print("📬 Notification received: type=\(notification.type ?? "nil"), message=\(notification.message)")
            print("   Setting currentNotification...")
            #endif
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              currentNotification = notification
            }
            
            #if DEBUG
            print("   currentNotification set. Value: \(currentNotification?.message ?? "nil")")
            #endif
            
            // Auto-dismiss after 5 seconds
            Task {
              try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
              await MainActor.run {
                #if DEBUG
                print("   Auto-dismissing notification after 5 seconds")
                #endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                  currentNotification = nil
                }
              }
            }
          }
        }
        // Handle streaming content events
        else if event.event == "content" {
          #if DEBUG
          print("📝 Processing content event")
          #endif
          
          // Parse the content data
          guard let dataDict = try event.parseJSONData() else {
            #if DEBUG
            print("⚠️ Failed to parse content data as JSON")
            #endif
            continue
          }
          
          if let content = dataDict["content"] as? String {
            streamingContent += content
            #if DEBUG
            print("📝 Content chunk received: '\(content)'")
            print("   Total streaming content length: \(streamingContent.count)")
            #endif
            
            // Update the last message (assistant message) with streaming content
            await MainActor.run {
              if let lastIndex = chatMessages.indices.last,
                 !chatMessages[lastIndex].isUser {
                let existingMessage = chatMessages[lastIndex]
                let isStreaming = dataDict["is_streaming"] as? Bool ?? true
                // Preserve the original message ID to maintain SwiftUI identity
                chatMessages[lastIndex] = ChatMessage(
                  id: existingMessage.id,
                  text: streamingContent,
                  isUser: false,
                  isStreaming: isStreaming
                )
                #if DEBUG
                print("✅ Updated assistant message. isStreaming: \(isStreaming)")
                #endif
              }
            }
          }
        }
        // Handle map events - dismiss keyboard and reset modal position
        else if event.event == "map" {
          #if DEBUG
          print("🗺️ Processing map event - dismissing keyboard and resetting modal")
          #endif
          
          // Trigger keyboard dismissal in ChatModalView
          await MainActor.run {
            shouldDismissKeyboard = true
            // Reset the flag after a brief delay to allow the change to be detected
            Task {
              try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
              await MainActor.run {
                shouldDismissKeyboard = false
              }
            }
          }
        } else {
          #if DEBUG
          print("⚠️ Unknown event type: \(event.event ?? "nil")")
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

// MARK: - Chat Message View
struct ChatMessageView: View {
  let message: ChatMessage
  
  var body: some View {
    HStack {
      if message.isUser {
        Spacer()
      }
      
      VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
        Text(message.text)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(message.isUser ? Color.blue : Color(.systemGray5))
          .foregroundColor(message.isUser ? .white : .primary)
          .cornerRadius(16)
        
        if message.isStreaming {
          ProgressView()
            .scaleEffect(0.8)
        }
      }
      
      if !message.isUser {
        Spacer()
      }
    }
  }
}

// MARK: - Journey Home View
struct JourneyHomeView: View {
  @EnvironmentObject var uhpGateway: UHPGateway
  @EnvironmentObject var locationManager: LocationManager
  @Binding var isTabBarHidden: Bool
  @Binding var selectedTab: TabSelection
  @Binding var currentNotification: NotificationData?
  @Binding var chatMessages: [ChatMessage]
  let username: String
  let fullName: String
  let website: String
  let userEmail: String
  var onSendChatMessage: (String) async -> Void
  
  @State private var locationText = "Your Journeys"
  @State private var isLoadingLocation = false
  @State private var lastSentLocation: (latitude: Double, longitude: Double)?
  @State private var bottomSheetOffset: CGFloat = 0
  @State private var locationContent: LocationContent?
  
  var body: some View {
    ZStack(alignment: .bottom) {
      // Location Bottom Sheet - positioned at bottom
      // Show sheet when location is available OR always show for testing
      if locationManager.currentLocation != nil || true { // TODO: Remove "|| true" after testing
        LocationBottomSheet(
          locationContent: locationContent,
          locationText: locationText,
          offset: $bottomSheetOffset,
          selectedTab: $selectedTab,
          chatMessages: $chatMessages,
          username: username,
          fullName: fullName,
          website: website,
          userEmail: userEmail,
          onSendMessage: onSendChatMessage
        )
        .zIndex(1000) // Ensure it's on top
        .allowsHitTesting(true) // Ensure it can receive touches
        #if DEBUG
        .onAppear {
          print("📍 Bottom sheet condition met - location available")
          print("   Location: \(locationManager.currentLocation?.coordinate.latitude ?? 0), \(locationManager.currentLocation?.coordinate.longitude ?? 0)")
          print("   Location text: \(locationText)")
        }
        #endif
      }
      
      // Notification Banner - positioned above bottom sheet
      VStack {
        Spacer()
        if let notification = currentNotification {
          NotificationBanner(notification: notification) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              currentNotification = nil
            }
          }
          .transition(.opacity)
          .padding(.bottom, 420) // Position above bottom sheet (400px partial height + 20px padding)
        }
      }
      .zIndex(1500) // Above bottom sheet but below tab bar
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onChange(of: locationManager.currentLocation) { newLocation in
      // Only make API call when location is captured and change is significant
      if newLocation != nil {
        Task {
          await loadLocationIfSignificant()
        }
      }
    }
    .task { @MainActor in
      // If location is already available, call immediately (first time)
      // Otherwise, wait for onChange to trigger when location is captured
      if locationManager.currentLocation != nil {
        await loadLocationIfSignificant()
      }
    }
  }
  
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
    // Only proceed if location is actually available
    guard let latitude = locationManager.latitude,
          let longitude = locationManager.longitude else {
      #if DEBUG
      print("⚠️ Location not available yet, skipping API call")
      #endif
      return
    }
    
    // Check if location change is significant
    guard isLocationChangeSignificant(newLatitude: latitude, newLongitude: longitude) else {
      return
    }
    
    // Make the API call
    await loadLocation()
  }
  
  private func loadLocation() async {
    // Only proceed if location is actually available
    guard let latitude = locationManager.latitude,
          let longitude = locationManager.longitude else {
      #if DEBUG
      print("⚠️ Location not available yet, skipping API call")
      #endif
      return
    }
    
    isLoadingLocation = true
    defer { isLoadingLocation = false }
    
    do {
      // Prepare request data with location
      // Location is guaranteed to be available at this point
      let jsonDict: [String: Any] = [
        "latitude": latitude,
        "longitude": longitude
      ]
      
      #if DEBUG
      print("📍 Sending location to API: \(latitude), \(longitude)")
      #endif
      
      let response = try await uhpGateway.request(
        endpoint: "/v1/signed-in-home",
        method: "POST",
        jsonDict: jsonDict
      )
      
      // Update last sent location after successful API call
      lastSentLocation = (latitude: latitude, longitude: longitude)
      
      // Extract location from response
      // API returns SuccessResponse with structure: { "result": { "location": "...", ... } }
      if let responseDict = response as? [String: Any] {
        // Try result.location first (expected structure)
        if let result = responseDict["result"] as? [String: Any],
           let location = result["location"] as? String {
          locationText = location
          #if DEBUG
          print("✅ Location loaded from result.location: \(location)")
          #endif
          return
        }
        
        // Fallback: try direct location
        if let location = responseDict["location"] as? String {
          locationText = location
          #if DEBUG
          print("✅ Location loaded from direct location: \(location)")
          #endif
          return
        }
        
        // Fallback: try data.location
        if let data = responseDict["data"] as? [String: Any],
           let location = data["location"] as? String {
          locationText = location
          #if DEBUG
          print("✅ Location loaded from data.location: \(location)")
          #endif
          return
        }
        
        // Try to extract location content for bottom sheet
        if let result = responseDict["result"] as? [String: Any] {
          locationContent = LocationContent(from: result)
        }
        
        #if DEBUG
        print("⚠️ Location not found in response. Available keys: \(responseDict.keys.joined(separator: ", "))")
        #endif
      }
      
    } catch let apiError as APIError {
      #if DEBUG
      print("❌ API Error: \(apiError.message)")
      if let code = apiError.code {
        print("   Status Code: \(code)")
      }
      #endif
      // Keep default "Your Journeys" text on error
    } catch {
      #if DEBUG
      print("❌ Failed to load location: \(error.localizedDescription)")
      print("   Error type: \(type(of: error))")
      #endif
      // Keep default "Your Journeys" text on error
    }
  }
}

// MARK: - Location Content Model
struct LocationContent {
  let title: String
  let subtitle: String?
  let description: String?
  let imageURLs: [String]
  let coordinates: (latitude: Double, longitude: Double)?
  
  init(from dict: [String: Any]) {
    self.title = dict["location"] as? String ?? dict["title"] as? String ?? "Unknown Location"
    self.subtitle = dict["subtitle"] as? String ?? dict["address"] as? String
    self.description = dict["description"] as? String
    
    // Extract image URLs
    var images: [String] = []
    if let imageURL = dict["image_url"] as? String {
      images.append(imageURL)
    }
    if let imageURLs = dict["image_urls"] as? [String] {
      images.append(contentsOf: imageURLs)
    }
    self.imageURLs = images
    
    // Extract coordinates if available
    if let lat = dict["latitude"] as? Double,
       let lon = dict["longitude"] as? Double {
      self.coordinates = (lat, lon)
    } else {
      self.coordinates = nil
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
  
  /// Maps notification type to SF Symbol icon name
  private var iconName: String {
    guard let type = notification.type else {
      return "bell.fill" // Default icon for null type
    }
    
    switch type.lowercased() {
    case "info", "information":
      return "info.circle.fill"
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
  
  var body: some View {
    HStack(spacing: 12) {
      // Icon placeholder
      Image(systemName: iconName)
        .font(.title3)
        .foregroundColor(.primary)
        .frame(width: 24, height: 24)
      
      // Notification message
      Text(notification.message)
        .font(.subheadline)
        .foregroundColor(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
      
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
      Color(.systemBackground)
        .opacity(0.95)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
    )
    .padding(.horizontal)
    .padding(.bottom, 8)
    .contentShape(Rectangle()) // Make entire area tappable
    .onTapGesture {
      onDismiss?()
    }
  }
}

// MARK: - Location Bottom Sheet Component
struct LocationBottomSheet: View {
  let locationContent: LocationContent?
  let locationText: String
  @Binding var offset: CGFloat
  @Binding var selectedTab: TabSelection
  @Binding var chatMessages: [ChatMessage]
  let username: String
  let fullName: String
  let website: String
  let userEmail: String
  var onSendMessage: (String) async -> Void
  
  // Snap points - visible heights
  private let collapsedHeight: CGFloat = 100
  private let partialHeight: CGFloat = 400
  private let fullHeight: CGFloat = 700 // Fixed container height
  
  @State private var dragOffset: CGFloat = 0
  @State private var currentSnapPoint: SnapPoint = .partial
  @State private var scrollViewContentOffset: CGFloat = 0
  @State private var isScrollingContent: Bool = false
  @State private var isChatNearBottom: Bool = true
  @State private var hasScrolledInitially: Bool = false
  
  enum SnapPoint {
    case collapsed
    case partial
    case full
    
    var height: CGFloat {
      switch self {
      case .collapsed: return 100
      case .partial: return 400
      case .full: return 700
      }
    }
  }
  
  /// Calculates the vertical offset to position the container based on snap point
  /// Returns how much to move the container up to show the desired visible height
  private func calculatePositionOffset() -> CGFloat {
    // Container is fixed at fullHeight (700px)
    // We offset it upward to hide the top portion
    // Collapsed (show 100px): offset up by (700 - 100) = 600px
    // Partial (show 400px): offset up by (700 - 400) = 300px
    // Full (show 700px): offset up by (700 - 700) = 0px
    return fullHeight - currentSnapPoint.height
  }
  
  var body: some View {
    VStack(spacing: 0) {
      // Drag handle
      RoundedRectangle(cornerRadius: 3)
        .fill(Color.secondary.opacity(0.3))
        .frame(width: 40, height: 5)
        .padding(.top, 12)
        .padding(.bottom, 8)
      
      // Content based on selected main tab (chat is now in separate modal)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Invisible geometry reader to track scroll position
          GeometryReader { scrollGeometry in
            Color.clear
              .preference(
                key: ScrollContentOffsetKey.self,
                value: scrollGeometry.frame(in: .named("scroll")).minY
              )
          }
          .frame(height: 0)
          
          // Switch content based on selected main tab
          switch selectedTab {
          case .journey:
            journeyContent
          case .map:
            mapContent
          case .profile:
            profileContent
          case .chat:
            // Chat is now in separate modal, show placeholder or empty
            EmptyView()
          }
        }
        .frame(maxWidth: .infinity) // Constrain width to prevent expansion
        .padding(.bottom, 100) // Extra padding for scrolling
      }
      .coordinateSpace(name: "scroll")
      .onPreferenceChange(ScrollContentOffsetKey.self) { offset in
        scrollViewContentOffset = offset
      }
      // When not at full, disable scrolling - drag will expand sheet instead
      .scrollDisabled(currentSnapPoint != .full)
      // When at full and content is at top, detect downward scroll to collapse
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            // Only handle when at full and content is at top
            if currentSnapPoint == .full && value.translation.height > 0 && scrollViewContentOffset >= 0 {
              // Start collapsing
              dragOffset = value.translation.height
            }
          }
          .onEnded { value in
            // Only handle when at full
            if currentSnapPoint == .full {
              // If dragged down significantly and content was at top, collapse to collapsed
              if value.translation.height > 50 && scrollViewContentOffset >= 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                  currentSnapPoint = .collapsed
                  dragOffset = 0
                }
              } else {
                // Reset if drag wasn't significant enough
                dragOffset = 0
              }
            }
          }
      )
    }
    .frame(width: UIScreen.main.bounds.width) // Fixed width to prevent expansion
    .frame(height: fullHeight) // Fixed height - always full height
    .background(
      Color("AppBkgColor")
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: -5)
    )
    .offset(y: calculatePositionOffset() + dragOffset) // Position based on snap point + drag
    .opacity(selectedTab == .chat ? 0 : 1) // Fade out when chat tab is selected
    .padding(.bottom, 49) // Account for custom tab bar height
    // Drag gesture on the drag handle and sheet background
    .gesture(
      DragGesture()
        .onChanged { value in
          // When at full, only allow downward drag (and only if content is at top)
          if currentSnapPoint == .full {
            if value.translation.height <= 0 {
              return // Don't handle upward drags when at full - let content scroll
            }
            // Only handle downward drag if content is at top
            if scrollViewContentOffset >= 0 {
              dragOffset = value.translation.height
            } else {
              return // Content is scrolled, don't collapse
            }
          } else {
            // Not at full - handle all drags
            dragOffset = value.translation.height
          }
        }
        .onEnded { value in
          // When at full and dragged up, don't change state
          if currentSnapPoint == .full && value.translation.height <= 0 {
            dragOffset = 0
            return
          }
          
          // When at full and dragged down, collapse to collapsed if content was at top
          if currentSnapPoint == .full && value.translation.height > 0 {
            if scrollViewContentOffset >= 0 {
              // Content was at top - collapse to collapsed
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentSnapPoint = .collapsed
                dragOffset = 0
              }
            } else {
              // Content was scrolled - just reset
              dragOffset = 0
            }
            return
          }
          
          // Normal drag handling for collapsed/partial states
          let velocity = value.predictedEndTranslation.height
          let currentVisibleHeight = currentSnapPoint.height - dragOffset
          let newSnapPoint = determineSnapPoint(
            currentOffset: currentVisibleHeight,
            velocity: velocity
          )
          
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentSnapPoint = newSnapPoint
            dragOffset = 0
          }
        }
    )
    .onAppear {
      currentSnapPoint = .partial
      #if DEBUG
      print("📍 Bottom sheet appeared")
      print("   Current snap point: \(currentSnapPoint), height: \(currentSnapPoint.height)")
      #endif
    }
    .onChange(of: selectedTab) { newTab in
      // Collapse to collapsed when chat tab is selected, otherwise reset to partial
      if newTab == .chat {
        withAnimation(.easeOut(duration: 0.2)) {
          currentSnapPoint = .collapsed
        }
      } else {
        withAnimation(.easeOut(duration: 0.2)) {
          currentSnapPoint = .partial
        }
      }
    }
  }
  
  // MARK: - Tab Content Views
  
  @ViewBuilder
  private var journeyContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Fixed width constraint to prevent expansion
      Color.clear
        .frame(width: UIScreen.main.bounds.width)
        .frame(height: 0)
      // Header
      VStack(alignment: .leading, spacing: 4) {
        Text(locationContent?.title ?? locationText)
          .font(.title)
          .fontWeight(.bold)
        
        if let subtitle = locationContent?.subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal)
      .frame(maxWidth: .infinity, alignment: .leading) // Constrain width
      
      // Action buttons
      HStack(spacing: 12) {
        Button(action: {}) {
          HStack {
            Image(systemName: "arrow.triangle.turn.up.right")
            Text("Directions")
          }
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(Color.teal)
          .cornerRadius(8)
        }
        
        Button(action: {}) {
          Image(systemName: "bookmark")
            .font(.title3)
            .foregroundColor(.primary)
          .frame(width: 44, height: 44)
          .background(Color(.systemGray6))
          .cornerRadius(8)
        }
        
        Button(action: {}) {
          Image(systemName: "square.and.arrow.up")
            .font(.title3)
            .foregroundColor(.primary)
          .frame(width: 44, height: 44)
          .background(Color(.systemGray6))
          .cornerRadius(8)
        }
      }
      .padding(.horizontal)
      
      // Image gallery - fixed height container to prevent expansion
      Group {
        if let content = locationContent, !content.imageURLs.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(Array(content.imageURLs.enumerated()), id: \.offset) { index, urlString in
              AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .empty:
                  Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: index == 0 ? 280 : 140, height: 180)
                    .overlay {
                      ProgressView()
                    }
                case .success(let image):
                  image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: index == 0 ? 280 : 140, height: 180)
                case .failure:
                  Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: index == 0 ? 280 : 140, height: 180)
                @unknown default:
                  Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: index == 0 ? 280 : 140, height: 180)
                }
              }
              .cornerRadius(12)
              .clipped()
              }
            }
            .padding(.horizontal)
          }
          .frame(height: 180) // Fixed height to prevent expansion
        } else {
          // Default location image
          AsyncImage(url: URL(string: "https://lp-cms-production.imgix.net/2025-02/shutterstock2500020869.jpg?auto=format,compress&q=72&w=1440&h=810&fit=crop")) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            Rectangle()
              .fill(Color(.systemGray4))
              .overlay {
                ProgressView()
              }
          }
          .frame(height: 180) // Match the gallery height
          .cornerRadius(12)
          .padding(.horizontal)
        }
      }
      .frame(maxWidth: .infinity) // Constrain width
      .frame(height: 180) // Fixed height container
      
      // Description
      if let description = locationContent?.description {
        Text(description)
          .font(.body)
          .foregroundColor(.secondary)
          .padding(.horizontal)
          .frame(maxWidth: .infinity, alignment: .leading) // Constrain width
      }
      
      // Additional content placeholder
      VStack(alignment: .leading, spacing: 12) {
        Text("When to visit")
          .font(.headline)
          .padding(.horizontal)
        
        HStack {
          Image(systemName: "calendar")
          Text("Peak Season · Jun - Sept")
          Spacer()
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .padding(.horizontal)
      }
      .padding(.top)
    }
    .frame(maxWidth: .infinity) // Constrain entire content width
  }
  
  @ViewBuilder
  private var mapContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Map Information")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)
      
      // Coordinates section
      if let coordinates = locationContent?.coordinates {
        VStack(alignment: .leading, spacing: 8) {
          Text("Current Location")
            .font(.headline)
            .padding(.horizontal)
          
          HStack {
            Image(systemName: "location.fill")
            Text("\(String(format: "%.6f", coordinates.latitude)), \(String(format: "%.6f", coordinates.longitude))")
              .font(.subheadline)
              .foregroundColor(.secondary)
            Spacer()
          }
          .padding(.horizontal)
        }
        .padding(.top, 8)
      }
      
      // Map controls placeholder
      VStack(alignment: .leading, spacing: 12) {
        Text("Map Controls")
          .font(.headline)
          .padding(.horizontal)
        
        VStack(alignment: .leading, spacing: 8) {
          DetailRow(icon: "map", title: "Map Style", value: "Standard")
          DetailRow(icon: "location.magnifyingglass", title: "Search Nearby", value: "Tap to search")
          DetailRow(icon: "arrow.triangle.2.circlepath", title: "Map Layers", value: "Toggle layers")
        }
        .padding(.horizontal)
      }
      .padding(.top)
    }
  }
  
  @ViewBuilder
  private var chatContent: some View {
    VStack(spacing: 0) {
      // Chat messages area
      ScrollViewReader { proxy in
        ScrollView {
          // Allow scrolling in chat even when bottom sheet isn't at full
          // This ensures chat messages can scroll independently
          VStack(alignment: .leading, spacing: 12) {
            if chatMessages.isEmpty {
              Text("Chat messages will appear here")
                .foregroundColor(.secondary)
                .padding()
                .id("empty-state")
            } else {
              // Show messages in order (oldest to newest, newest at bottom)
              ForEach(chatMessages) { message in
                ChatMessageView(message: message)
                  .id(message.id)
              }
            }
            // Bottom anchor for scrolling
            Color.clear
              .frame(height: 1)
              .id("bottom-anchor")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
          .padding(.bottom, 80) // Extra padding to account for input bar above tab bar
          .background(
            GeometryReader { geometry in
              Color.clear
                .preference(
                  key: ChatScrollOffsetKey.self,
                  value: -geometry.frame(in: .named("chat-scroll")).minY
                )
            }
          )
        }
        .coordinateSpace(name: "chat-scroll")
        .onPreferenceChange(ChatScrollOffsetKey.self) { offset in
          // Check if user is near bottom (within 150 points)
          // Offset is negative when scrolled down, so we check if it's close to 0
          let threshold: CGFloat = 150
          let newIsNearBottom = abs(offset) <= threshold || offset >= 0
          if newIsNearBottom != isChatNearBottom {
            isChatNearBottom = newIsNearBottom
          }
        }
        .onAppear {
          // Scroll to bottom on initial appear
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let lastMessage = chatMessages.last {
              withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
              }
            } else {
              withAnimation {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
              }
            }
          }
        }
        .onChange(of: chatMessages.count) { newCount in
          // Auto-scroll when new messages arrive
          guard newCount > 0 else { return }
          
          // Always scroll on first message, then respect user's scroll position
          let shouldScroll = !hasScrolledInitially || isChatNearBottom
          
          if shouldScroll {
            // Use Task to ensure we're on the main actor and view has updated
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
              if let lastMessage = chatMessages.last {
                withAnimation(.easeOut(duration: 0.3)) {
                  proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
                hasScrolledInitially = true
              } else {
                withAnimation(.easeOut(duration: 0.3)) {
                  proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
                hasScrolledInitially = true
              }
            }
          }
        }
        .onChange(of: chatMessages.last?.text) { _ in
          // Auto-scroll during streaming updates (if user is near bottom)
          guard isChatNearBottom, let lastMessage = chatMessages.last else { return }
          
          // Use Task to ensure we're on the main actor and view has updated
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000) // 0.03 seconds
            withAnimation(.easeOut(duration: 0.2)) {
              proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
          }
        }
        .onChange(of: chatMessages.last?.isStreaming) { _ in
          // When streaming finishes, ensure we're at the bottom
          if isChatNearBottom, let lastMessage = chatMessages.last, !lastMessage.isStreaming {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity)
    }
  }
  
  @ViewBuilder
  private var profileContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Fixed width constraint to prevent expansion
      Color.clear
        .frame(width: UIScreen.main.bounds.width)
        .frame(height: 0)
      
      // Account Actions Section
      VStack(alignment: .leading, spacing: 0) {
        // Section Header
        Text("Account Actions")
          .font(.system(size: 13, weight: .regular))
          .foregroundColor(.secondary)
          .textCase(.uppercase)
          .padding(.horizontal, 16)
          .padding(.top, 16)
          .padding(.bottom, 6)
        
        // Sign Out Button
        Button(action: signOut) {
          HStack(spacing: 12) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
              .foregroundColor(.red)
              .font(.system(size: 17))
            Text("Sign Out")
              .foregroundColor(.red)
              .font(.body)
            Spacer()
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemBackground))
        }
      }
      .background(Color(.systemGroupedBackground))
      .cornerRadius(10)
      .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top)
  }
  
  // MARK: - Sign Out Function
  private func signOut() {
    Task {
      do {
        try await supabase.auth.signOut()
        #if DEBUG
        print("✅ User signed out successfully")
        #endif
      } catch {
        #if DEBUG
        print("❌ Sign out error: \(error.localizedDescription)")
        #endif
      }
    }
  }
  
  private func expandSheet() {
    // Expand to next larger snap point
    switch currentSnapPoint {
    case .collapsed:
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        currentSnapPoint = .partial
      }
    case .partial:
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        currentSnapPoint = .full
      }
    case .full:
      break // Already at full
    }
  }
  
  private func determineSnapPoint(currentOffset: CGFloat, velocity: CGFloat) -> SnapPoint {
    // Determine snap point based on current position and velocity
    let threshold: CGFloat = 50
    
    if abs(velocity) > 500 {
      // Fast swipe - go to next/previous snap point
      if velocity > 0 {
        // Swiping down
        switch currentSnapPoint {
        case .full: return .partial
        case .partial: return .collapsed
        case .collapsed: return .collapsed
        }
      } else {
        // Swiping up
        switch currentSnapPoint {
        case .collapsed: return .partial
        case .partial: return .full
        case .full: return .full
        }
      }
    } else {
      // Slow drag - snap to nearest point
      let distances: [(SnapPoint, CGFloat)] = [
        (.collapsed, abs(currentOffset - collapsedHeight)),
        (.partial, abs(currentOffset - partialHeight)),
        (.full, abs(currentOffset - SnapPoint.full.height))
      ]
      
      let nearest = distances.min(by: { $0.1 < $1.1 })?.0 ?? .collapsed
      
      // Only snap if within threshold
      if abs(currentOffset - nearest.height) < threshold {
        return nearest
      } else {
        return currentSnapPoint
      }
    }
  }
}

// MARK: - Custom Tab Bar Component
struct CustomTabBar: View {
  @Binding var selectedTab: TabSelection
  
  var body: some View {
    HStack(spacing: 0) {
      TabBarButton(
        selectedIcon: "signpost.right.and.left.fill",
        unselectedIcon: "signpost.right.and.left",
        label: "Journey",
        isSelected: selectedTab == .journey,
        action: { selectedTab = .journey }
      )
      
      TabBarButton(
        selectedIcon: "map.fill",
        unselectedIcon: "map",
        label: "Map",
        isSelected: selectedTab == .map,
        action: { selectedTab = .map }
      )
      
      TabBarButton(
        selectedIcon: "questionmark.bubble.fill",
        unselectedIcon: "questionmark.bubble",
        label: "Ask",
        isSelected: selectedTab == .chat,
        action: { selectedTab = .chat }
      )
      
      TabBarButton(
        selectedIcon: "person.fill",
        unselectedIcon: "person",
        label: "You",
        isSelected: selectedTab == .profile,
        action: { selectedTab = .profile }
      )
    }
    .frame(height: 49) // Standard tab bar height
    .background(Color("AppBkgColor"))
    // .overlay(
    //   Rectangle()
    //     .frame(height: 0.5)
    //     .foregroundColor(Color(UIColor.separator)),
    //   alignment: .top
    // )
  }
}

// MARK: - Tab Bar Button Component
struct TabBarButton: View {
  let selectedIcon: String
  let unselectedIcon: String
  let label: String
  let isSelected: Bool
  let action: () -> Void
  
  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: isSelected ? selectedIcon : unselectedIcon)
          .font(.system(size: 22))
          .foregroundColor(isSelected ? Color("onBkgTextColor90") : Color("onBkgTextColor60"))
        
        Text(label)
          .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
          .foregroundColor(isSelected ? Color("onBkgTextColor90") : Color("onBkgTextColor60"))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 49)
    }
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

// MARK: - Chat Input Bar Component
struct ChatInputBar: View {
  @State private var messageText = ""
  @FocusState.Binding var isTextFieldFocused: Bool
  var onSendMessage: (String) -> Void
  
  init(isTextFieldFocused: FocusState<Bool>.Binding, onSendMessage: @escaping (String) -> Void) {
    self._isTextFieldFocused = isTextFieldFocused
    self.onSendMessage = onSendMessage
  }
  
  // Computed property to check if message is empty (trimmed)
  private var isEmpty: Bool {
    messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  
  var body: some View {
    HStack(spacing: 12) {
      MultiLineTextField(
        text: $messageText,
        placeholder: "Ask anything about your journey.",
        onReturnKeyPress: { textToSend in
          // Use the text passed from the text field instead of reading from messageText
          // which may have already been cleared
          sendMessage(with: textToSend)
        }
      )
      .frame(height: 32)
      
      // Show voice button when empty, send button when typing
      if isEmpty {
        Button(action: {
          // TODO: Implement voice mode functionality
          #if DEBUG
          print("🎤 Voice button tapped")
          #endif
        }) {
          Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundColor(.blue)
        }
      } else {
        Button(action: {
          sendMessage()
        }) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
            .foregroundColor(.blue)
        }
      }
    }
    .padding()
    .background(Color(.systemBackground))
  }
  
  private func sendMessage(with text: String? = nil) {
    // Use provided text or fall back to messageText binding
    let textToSend = text ?? messageText
    let trimmedText = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
    
    #if DEBUG
    print("📝 ChatInputBar.sendMessage() called")
    print("   textToSend: '\(textToSend)'")
    print("   trimmedText: '\(trimmedText)'")
    print("   isEmpty: \(trimmedText.isEmpty)")
    #endif
    
    guard !trimmedText.isEmpty else {
      #if DEBUG
      print("⚠️ Message is empty, not sending")
      #endif
      return
    }
    
    // Clear input after capturing the text
    messageText = ""
    
    #if DEBUG
    print("✅ Calling onSendMessage with: '\(trimmedText)'")
    #endif
    
    // Call the callback with the trimmed text
    onSendMessage(trimmedText)
    
    #if DEBUG
    print("✅ onSendMessage callback completed")
    #endif
  }
}

// MARK: - Chat Modal View
struct ChatModalView: View {
  @Binding var chatMessages: [ChatMessage]
  @Binding var currentNotification: NotificationData?
  @Binding var shouldDismissKeyboard: Bool
  var onSendMessage: (String) async -> Void
  @Environment(\.dismiss) private var dismiss
  
  @State private var messageText = ""
  @State private var isChatNearBottom = true
  @State private var hasScrolledInitially = false
  @FocusState private var isTextFieldFocused: Bool
  
  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
          // Chat messages area
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                if chatMessages.isEmpty {
                  Text("Chat messages will appear here")
                    .foregroundColor(.secondary)
                    .padding()
                    .id("empty-state")
                } else {
                  ForEach(chatMessages) { message in
                    ChatMessageView(message: message)
                      .id(message.id)
                  }
                }
                // Bottom anchor for scrolling
                Color.clear
                  .frame(height: 1)
                  .id("bottom-anchor")
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding()
            }
          .onAppear {
            // Scroll to bottom on initial appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
              if let lastMessage = chatMessages.last {
                withAnimation {
                  proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
              } else {
                withAnimation {
                  proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
              }
            }
          }
          .onChange(of: chatMessages.count) { newCount in
            guard newCount > 0 else { return }
            let shouldScroll = !hasScrolledInitially || isChatNearBottom
            
            if shouldScroll {
              Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                if let lastMessage = chatMessages.last {
                  withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                  }
                  hasScrolledInitially = true
                }
              }
            }
          }
          .onChange(of: chatMessages.last?.text) { _ in
            guard isChatNearBottom, let lastMessage = chatMessages.last else { return }
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 30_000_000)
              withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
              }
            }
          }
          .onChange(of: chatMessages.last?.isStreaming) { _ in
            if isChatNearBottom, let lastMessage = chatMessages.last, !lastMessage.isStreaming {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                  proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
              }
            }
            }
          }
          
          // Input bar at bottom - SwiftUI handles keyboard automatically
          ChatInputBar(
            isTextFieldFocused: $isTextFieldFocused,
            onSendMessage: { messageText in
              Task {
                await onSendMessage(messageText)
              }
            }
          )
          .background(Color(.systemBackground))
        }
        .onChange(of: shouldDismissKeyboard) { shouldDismiss in
          if shouldDismiss {
            // Dismiss keyboard
            isTextFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
          }
        }
        
        // Notification Banner - positioned above input bar
        VStack {
          Spacer()
          if let notification = currentNotification {
            NotificationBanner(notification: notification) {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentNotification = nil
              }
            }
            .transition(.opacity)
            .padding(.bottom, 80) // Position above input bar
          }
        }
        .zIndex(1000) // Above chat content but below navigation
      }
      // .navigationTitle("Ask")
      // .navigationBarTitleDisplayMode(.inline)
      .toolbar {
          ToolbarItem(placement: .principal) {
    HStack(spacing: 6) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.headline)
      Text("Ask")
        .font(.headline)
    }
  }

        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

#Preview {
  SignedInHomeView()
    .environmentObject(UHPGateway())
    .environmentObject(AuthManager.preview(isAuthenticated: true, isLoading: false, userID: "c1a4eee7-8fb1-496e-be39-a58d6e8257e7"))
    .environmentObject(LocationManager())
}
