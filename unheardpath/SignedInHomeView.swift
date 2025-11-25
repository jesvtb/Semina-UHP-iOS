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
  @EnvironmentObject var apiService: APIService
  
  @State var username = ""
  @State var fullName = ""
  @State var website = ""

  @State var isLoading = false
  @State private var selectedTab: TabSelection = .journey
  @State private var isJourneyTabBarHidden = false

  var body: some View {
    ZStack(alignment: .bottom) {
      // Full screen map as base
      MapboxMapView()
        .ignoresSafeArea(.all)
      
      // Bottom Sheet with tab-controlled content
      JourneyHomeView(
        isTabBarHidden: $isJourneyTabBarHidden,
        selectedTab: $selectedTab
      )
      .environmentObject(apiService)
      
      // Custom Tab Bar
      CustomTabBar(selectedTab: $selectedTab)
        .zIndex(2000) // Above bottom sheet
    }
    .onAppear {
      configureTabBarAppearance()
      print("🔵 SignedInHomeView appeared")
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

  // MARK: - Simple API Call Example
  func testAPICall() {
    Task {
      isLoading = true
      defer { isLoading = false }
      
      do {
        let response = try await apiService.asyncCallAPI(
          url: "https://127.0.0.1:1031/v1/signed_in_home",
          method: "POST",
          includeAuthToken: true
        )
        
        print("✅ API call successful: \(response)")
        
      } catch {
        print("❌ API call failed: \(error.localizedDescription)")
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

// MARK: - Journey Home View
struct JourneyHomeView: View {
  @EnvironmentObject var apiService: APIService
  @EnvironmentObject var locationManager: LocationManager
  @Binding var isTabBarHidden: Bool
  @Binding var selectedTab: TabSelection
  @State private var locationText = "Your Journeys"
  @State private var isLoadingLocation = false
  @State private var lastSentLocation: (latitude: Double, longitude: Double)?
  @State private var bottomSheetOffset: CGFloat = 0
  @State private var locationContent: LocationContent?
  
  var body: some View {
    Group {
      // Location Bottom Sheet - positioned at bottom
      // Show sheet when location is available OR always show for testing
      if locationManager.currentLocation != nil || true { // TODO: Remove "|| true" after testing
        LocationBottomSheet(
          locationContent: locationContent,
          locationText: locationText,
          offset: $bottomSheetOffset,
          selectedTab: $selectedTab
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
      
      let response = try await apiService.asyncCallAPI(
        url: "http://192.168.50.171:1031/v1/signed_in_home",
        method: "POST",
        jsonDict: jsonDict,
        includeAuthToken: true
      )
      
      // Update last sent location after successful API call
      lastSentLocation = (latitude: latitude, longitude: longitude)
      
      #if DEBUG
      print("📦 Full API Response: \(response)")
      #endif
      
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

// MARK: - Location Bottom Sheet Component
struct LocationBottomSheet: View {
  let locationContent: LocationContent?
  let locationText: String
  @Binding var offset: CGFloat
  @Binding var selectedTab: TabSelection
  
  // Snap points - visible heights
  private let collapsedHeight: CGFloat = 100
  private let partialHeight: CGFloat = 400
  private let fullHeight: CGFloat = 700 // Fixed container height
  
  @State private var dragOffset: CGFloat = 0
  @State private var currentSnapPoint: SnapPoint = .partial
  @State private var scrollViewContentOffset: CGFloat = 0
  @State private var isScrollingContent: Bool = false
  
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
      
      // Content based on selected main tab
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
          case .chat:
            chatContent
          case .profile:
            profileContent
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
      // Reset to partial when switching tabs
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        currentSnapPoint = .partial
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
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          // Placeholder messages - replace with actual chat messages later
          Text("Chat messages will appear here")
            .foregroundColor(.secondary)
            .padding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
      
      // Message input area
      Divider()
      ChatInputBar()
    }
  }
  
  @ViewBuilder
  private var profileContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Profile")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)
      
      // Profile information would go here
      // Note: Profile data (username, fullName, website) is in SignedInHomeView
      // You may need to pass it down or use a shared state
      Text("Profile information and settings")
        .font(.body)
        .foregroundColor(.secondary)
        .padding(.horizontal)
    }
    .padding(.top)
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
        icon: "house.fill",
        label: "Journey",
        isSelected: selectedTab == .journey,
        action: { selectedTab = .journey }
      )
      
      TabBarButton(
        icon: "map",
        label: "Map",
        isSelected: selectedTab == .map,
        action: { selectedTab = .map }
      )
      
      TabBarButton(
        icon: "message",
        label: "Chat",
        isSelected: selectedTab == .chat,
        action: { selectedTab = .chat }
      )
      
      TabBarButton(
        icon: "person.circle",
        label: "Profile",
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
  let icon: String
  let label: String
  let isSelected: Bool
  let action: () -> Void
  
  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon)
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

// MARK: - Chat Input Bar Component
struct ChatInputBar: View {
  @State private var messageText = ""
  @FocusState private var isTextFieldFocused: Bool
  
  var body: some View {
    HStack(spacing: 12) {
      TextField("Type a message...", text: $messageText, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...5)
        .focused($isTextFieldFocused)
        .onSubmit {
          sendMessage()
        }
      
      Button(action: sendMessage) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title2)
          .foregroundColor(messageText.isEmpty ? .gray : .blue)
      }
      .disabled(messageText.isEmpty)
    }
    .padding()
    .background(Color(.systemBackground))
  }
  
  private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    
    // TODO: Implement message sending logic
    print("📤 Sending message: \(messageText)")
    
    // Clear input after sending
    messageText = ""
  }
}

#Preview {
  SignedInHomeView()
    .environmentObject(APIService.shared)
}
