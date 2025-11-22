import SwiftUI
import UIKit

// MARK: - Tab Selection
enum TabSelection: Int {
  case journey = 0
  case map = 1
  case chat = 2
  case profile = 3
}

struct SignedInHomeView: View {
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
      }
      .toolbar(isJourneyTabBarHidden ? .hidden : .visible, for: .tabBar)
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
      .tabItem {
        Label("Profile", systemImage: "person.circle")
      }
      .tag(TabSelection.profile)
      .onAppear {
        // Ensure tab bar is visible when switching to other tabs
        isJourneyTabBarHidden = false
      }
    }
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
    appearance.backgroundColor = UIColor.systemBackground
    
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
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - Journey Home View
struct JourneyHomeView: View {
  @Binding var isTabBarHidden: Bool
  @State private var searchText = ""
  @State private var scrollOffset: CGFloat = 0
  @State private var lastScrollOffset: CGFloat = 0
  
  // Placeholder journey data - replace with real data later
  let sampleJourneys = [
    JourneyItem(title: "Istanbul before Islam", description: "Explore the rich history of Istanbul", imageURL: "https://lp-cms-production.imgix.net/2025-02/shutterstock2500020869.jpg?auto=format,compress&q=72&w=1440&h=810&fit=crop"),
    JourneyItem(title: "Ancient Rome", description: "Discover the wonders of the Roman Empire", imageURL: "https://www.cityrometours.com//upload/CONF93/20181108/fascist-architecture-eur-rome-auto-728X430-zoom.jpg"),
    JourneyItem(title: "Medieval Paris", description: "Walk through the streets of historic Paris", imageURL: "https://media.tacdn.com/media/attractions-splice-spp-674x446/10/5c/9a/f7.jpg"),
  ]
  
  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        // Welcome header
        VStack(alignment: .leading, spacing: 8) {
          Text("Your Journeys")
            .font(.largeTitle)
            .fontWeight(.bold)
          
          Text("Explore historical paths and stories")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top)
        
        // Search bar
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
        .padding(.horizontal)
        .padding(.bottom)
      }
      .background(
        GeometryReader { geometry in
          Color.clear
            .preference(
              key: ScrollOffsetPreferenceKey.self,
              value: geometry.frame(in: .named("scroll")).minY
            )
        }
      )
    }
    // .background(Color.appBackground)
    .coordinateSpace(name: "scroll")
    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
      scrollOffset = value
      let isScrollingDown = value < lastScrollOffset
      let threshold: CGFloat = 50
      
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
    .navigationBarTitleDisplayMode(.large)
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
}
