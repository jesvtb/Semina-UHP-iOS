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
  @State var showChatPopup = false
  @State private var selectedTab: TabSelection = .journey
  @State private var isJourneyTabBarHidden = false

  var body: some View {
    TabView(selection: $selectedTab) {
      // Journey Tab - Default "Home" tab
      NavigationStack {
        JourneyHomeView(isTabBarHidden: $isJourneyTabBarHidden)
          .environmentObject(apiService)
          .environment(\.selectedTab, $selectedTab)
      }
      .toolbar(isJourneyTabBarHidden ? .hidden : .visible, for: .tabBar)
      .toolbarBackground(.visible, for: .tabBar)
      .toolbarBackground(Color("AppBkgColor"), for: .tabBar)
      .tabItem {
        Label("Journey", systemImage: "house.fill")
      }
      .tag(TabSelection.journey)
      .onAppear {
        // Reset tab bar visibility when switching to this tab
        if selectedTab == .journey {
          isJourneyTabBarHidden = false
        }
      }
      
      // Map Tab
      
      NavigationStack {
        MapboxMapView()
        // MapboxMapView()
        // MapView()
      }
      .toolbarBackground(.visible, for: .tabBar)
      .toolbarBackground(Color("AppBkgColor"), for: .tabBar)
      .tabItem {
        Label("Map", systemImage: "map")
      }
      .tag(TabSelection.map)
      .onAppear {
        // Ensure tab bar is visible when switching to other tabs
        isJourneyTabBarHidden = false
      }
      
      // Chat Tab - Shows popup instead of navigating
      Color.clear
        .tabItem {
          Label("Chat", systemImage: "message")
        }
        .tag(TabSelection.chat)
        .onAppear {
          showChatPopup = true
        }
      
      // Profile Tab
      NavigationStack {
        Form {
          Section {
            TextField("Username", text: $username)
              .textContentType(.username)
              .textInputAutocapitalization(.never)
            TextField("Full name", text: $fullName)
              .textContentType(.name)
            TextField("Website", text: $website)
              .textContentType(.URL)
              .textInputAutocapitalization(.never)
          }

          Section {
            Button("Update profile") {
              updateProfileButtonTapped()
            }
            .bold()

            Button("Test API Call") {
              testAPICall()
            }
            .bold()

            if isLoading {
              ProgressView()
            }
          }
        }
        .navigationTitle("Profile")
        .toolbar(content: {
          ToolbarItem(placement: .topBarLeading){
            Button("Sign out", role: .destructive) {
              Task {
                try? await supabase.auth.signOut()
              }
            }
          }
        })
      }
      .toolbarBackground(.visible, for: .tabBar)
      .toolbarBackground(Color("AppBkgColor"), for: .tabBar)
      .tabItem {
        Label("Profile", systemImage: "person.circle")
      }
      .tag(TabSelection.profile)
      .onAppear {
        // Ensure tab bar is visible when switching to other tabs
        isJourneyTabBarHidden = false
      }
    }
    .toolbarBackground(.visible, for: .tabBar)
    .toolbarBackground(Color("AppBkgColor"), for: .tabBar)
    .onAppear {
      configureTabBarAppearance()
      print("🔵 SignedInHomeView appeared")
    }
    .sheet(isPresented: $showChatPopup) {
      ChatInputView(isPresented: $showChatPopup)
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
  @Environment(\.selectedTab) var selectedTab: Binding<TabSelection>
  @Binding var isTabBarHidden: Bool
  @State private var searchText = ""
  @State private var scrollOffset: CGFloat = 0
  @State private var lastScrollOffset: CGFloat = 0
  @State private var locationText = "Your Journeys"
  @State private var isLoadingLocation = false
  @State private var lastSentLocation: (latitude: Double, longitude: Double)?
  @State private var bottomSheetOffset: CGFloat = 0
  @State private var locationContent: LocationContent?
  
  // Placeholder journey data - replace with real data later
  let sampleJourneys = [
    JourneyItem(title: "Istanbul before Islam", description: "Explore the rich history of Istanbul", imageURL: "https://lp-cms-production.imgix.net/2025-02/shutterstock2500020869.jpg?auto=format,compress&q=72&w=1440&h=810&fit=crop"),
    JourneyItem(title: "Ancient Rome", description: "Discover the wonders of the Roman Empire", imageURL: "https://www.cityrometours.com//upload/CONF93/20181108/fascist-architecture-eur-rome-auto-728X430-zoom.jpg"),
    JourneyItem(title: "Medieval Paris", description: "Walk through the streets of historic Paris", imageURL: "https://media.tacdn.com/media/attractions-splice-spp-674x446/10/5c/9a/f7.jpg"),
  ]
  
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        ScrollView {
          VStack(spacing: 10) {
        // Welcome header
        GeometryReader { headerGeometry in
          ZStack {
            AsyncImage(url: URL(string: "https://lp-cms-production.imgix.net/2025-02/shutterstock2500020869.jpg?auto=format,compress&q=72&w=1440&h=810&fit=crop")) { image in
              image
                .resizable()
                .scaledToFill()
                .frame(width: headerGeometry.size.width, height: headerGeometry.size.height)
                .clipped()
            } placeholder: {
              Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: headerGeometry.size.width, height: headerGeometry.size.height)
            }

            LinearGradient(
              gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
              startPoint: .bottom,
              endPoint: .top
            )
            
            VStack {
              Text(locationText)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            }
            .padding()
          }
        }
        .frame(height: 300)  
        // Search bar

        Button {
          // Switch to map tab programmatically to reuse the same MapboxMapView instance
          selectedTab.wrappedValue = .map
        } label: {
          MapboxMapView()
            .frame(height: 200)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)


        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
          TextField("Search journeys...", text: $searchText)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        
        // Journey cards
        LazyVStack(spacing: 16) {
          ForEach(sampleJourneys) { journey in
            JourneyCard(journey: journey)
          }
        }
        // .padding(.horizontal)
        .padding(.bottom, bottomSheetOffset > 0 ? 400 : 0) // Add padding when bottom sheet is visible
      }
      // .background(Color.appBackground)
      // .ignoresSafeArea(.all, edges: .top)
      
        }
        .background(Color.appBackground)
        .ignoresSafeArea(.all, edges: .top)
        
        // Location Bottom Sheet - positioned at bottom of ZStack
        // Show sheet when location is available OR always show for testing
        if locationManager.currentLocation != nil || true { // TODO: Remove "|| true" after testing
          LocationBottomSheet(
            locationContent: locationContent,
            locationText: locationText,
            offset: $bottomSheetOffset,
            screenHeight: geometry.size.height
          )
          .zIndex(1000) // Ensure it's on top
          .allowsHitTesting(true) // Ensure it can receive touches
          #if DEBUG
          .onAppear {
            print("📍 Bottom sheet condition met - location available")
            print("   Location: \(locationManager.currentLocation?.coordinate.latitude ?? 0), \(locationManager.currentLocation?.coordinate.longitude ?? 0)")
            print("   Location text: \(locationText)")
            print("   Screen height: \(geometry.size.height)")
          }
          #endif
        }
      }
    }
    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
      scrollOffset = value
      let isScrollingDown = value < lastScrollOffset
      let threshold: CGFloat = 100
      
      if isScrollingDown && abs(value - lastScrollOffset) > threshold && value < -threshold {
        withAnimation(.easeInOut(duration: 0.3)) {
          isTabBarHidden = true
        }
      } else if !isScrollingDown || value > -threshold {
        withAnimation(.easeInOut(duration: 0.3)) {
          isTabBarHidden = false
        }
      }
      
      lastScrollOffset = value
    }
    .navigationTitle("Journeys")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: locationManager.currentLocation) { newLocation in
      // Only make API call when location is captured and change is significant
      if newLocation != nil {
        Task {
          await loadLocationIfSignificant()
        }
      }
    }
    .task {
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
  let screenHeight: CGFloat
  
  // Snap points - visible heights
  private let collapsedHeight: CGFloat = 100
  private let partialHeight: CGFloat = 400
  private let fullHeight: CGFloat = 700 // Fixed container height
  
  @State private var dragOffset: CGFloat = 0
  @State private var currentSnapPoint: SnapPoint = .collapsed
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
      
      // Content
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
          
          // Image gallery
          if let content = locationContent, !content.imageURLs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                ForEach(Array(content.imageURLs.enumerated()), id: \.offset) { index, urlString in
                  AsyncImage(url: URL(string: urlString)) { image in
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
                  .frame(width: index == 0 ? 280 : 140, height: 180)
                  .cornerRadius(12)
                  .clipped()
                }
              }
              .padding(.horizontal)
            }
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
            .frame(height: 200)
            .cornerRadius(12)
            .padding(.horizontal)
          }
          
          // Description
          if let description = locationContent?.description {
            Text(description)
              .font(.body)
              .foregroundColor(.secondary)
              .padding(.horizontal)
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
    .frame(height: fullHeight) // Fixed height - always full height
    .background(
      Color(.systemBackground)
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: -5)
    )
    .offset(y: calculatePositionOffset() + dragOffset) // Position based on snap point + drag
    .padding(.bottom, 0) // Ensure it's at the very bottom, above tab bar
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
      currentSnapPoint = .collapsed
      #if DEBUG
      print("📍 Bottom sheet appeared - screenHeight: \(screenHeight)")
      print("   Current snap point: \(currentSnapPoint), height: \(currentSnapPoint.height)")
      #endif
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

// MARK: - Chat Input View
struct ChatInputView: View {
  @Binding var isPresented: Bool
  @State private var messageText = ""
  @FocusState private var isTextFieldFocused: Bool
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Chat messages area (placeholder for now)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            Text("Chat messages will appear here")
              .foregroundColor(.secondary)
              .padding()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        
        // Message input area
        Divider()
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
      .navigationTitle("Chat")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            isPresented = false
          }
        }
      }
      .onAppear {
        // Auto-focus the text field when popup appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          isTextFieldFocused = true
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
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
