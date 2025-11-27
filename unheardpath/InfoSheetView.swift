import SwiftUI
import UIKit

// MARK: - Location Bottom Sheet Component
struct InfoSheet: View {
  let locationDetails: [String: Any]?
  @Binding var offset: CGFloat
  @Binding var selectedTab: TabSelection
  let username: String
  let fullName: String
  let website: String
  let userEmail: String
  let places: Places
  let onPlaceBookmark: (Place) -> Void
  
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
          journeyContent(locationDetails: locationDetails, places: places)
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
    .padding(.bottom, tabBarHeight) // Account for custom tab bar height
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
  private func journeyContent(locationDetails: [String: Any]?, places: Places) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      // Fixed width constraint to prevent expansion
      Color.clear
        .frame(width: UIScreen.main.bounds.width)
        .frame(height: 0)
      // Header
      VStack(alignment: .leading, spacing: 4) {
        // Parse location string: first item, second item, and country name
        if let locationDetails = locationDetails {
          let locationString = locationDetails["location"] as? String ?? ""
          let countryName = locationDetails["country_name"] as? String ?? ""
          
          let locationParts = locationString.components(separatedBy: ", ")
          let firstItem = locationParts.count > 0 ? locationParts[0].trimmingCharacters(in: .whitespaces) : ""
          let secondItem = locationParts.count > 1 ? locationParts[1].trimmingCharacters(in: .whitespaces) : ""
          
          if !firstItem.isEmpty {
            Text(firstItem)
          }
          if !secondItem.isEmpty {
            Text(secondItem)
          }
          if !countryName.isEmpty {
            Text(countryName)
          }
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
      
      if !places.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Nearby Places")
            .font(.headline)
            .padding(.horizontal)
          
          VStack(spacing: 12) {
            ForEach(places) { place in
              PlaceRow(place: place, onBookmark: onPlaceBookmark)
            }
          }
          .padding(.horizontal)
        }
      }
      
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
      
      // Location details section
      if let locationDetails = locationDetails {
        VStack(alignment: .leading, spacing: 8) {
          Text("Current Location")
            .font(.headline)
            .padding(.horizontal)
          
          // Display location using first and second items from location string and country name
          if let locationString = locationDetails["location"] as? String,
             let countryName = locationDetails["country_name"] as? String {
            let locationParts = locationString.components(separatedBy: ", ")
            let displayParts = Array(locationParts.prefix(2))
            let displayLocation = displayParts.joined(separator: ", ")
            let fullDisplay = "\(displayLocation), \(countryName)"
            
            HStack {
              Image(systemName: "location.fill")
              Text(fullDisplay)
                .font(.subheadline)
                .foregroundColor(.secondary)
              Spacer()
            }
            .padding(.horizontal)
          } else if let countryName = locationDetails["country_name"] as? String {
            // Fallback to just country name if location string not available
            HStack {
              Image(systemName: "location.fill")
              Text(countryName)
                .font(.subheadline)
                .foregroundColor(.secondary)
              Spacer()
            }
            .padding(.horizontal)
          }
        }
        .padding(.top, 8)
      }
      
      // Coordinates section (fallback if locationDetails not available)
      if let locationDetails = locationDetails,
         let latitude = locationDetails["latitude"] as? Double,
         let longitude = locationDetails["longitude"] as? Double {
        VStack(alignment: .leading, spacing: 8) {
          Text("Coordinates")
            .font(.headline)
            .padding(.horizontal)
          
          HStack {
            Image(systemName: "location.fill")
            Text("\(String(format: "%.6f", latitude)), \(String(format: "%.6f", longitude))")
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
