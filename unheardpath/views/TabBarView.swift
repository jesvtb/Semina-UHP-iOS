import SwiftUI

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
    .frame(height: tabBarHeight)
    .background(Color("AppBkgColor"))
  }
}


// MARK: - Tab Bar Button Component
struct TabBarButton: View {
  let selectedIcon: String
  let unselectedIcon: String
  let label: String
  let isSelected: Bool
  let action: () -> Void
  
  private var foregroundColor: Color {
    isSelected ? Color("onBkgTextColor90") : Color("onBkgTextColor60")
  }
  
  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: isSelected ? selectedIcon : unselectedIcon)
          .font(.system(size: 22))
        
        Text(label)
          .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
      }
      .foregroundColor(foregroundColor)
      .frame(maxWidth: .infinity)
      .frame(height: tabBarHeight)
    }
  }
}