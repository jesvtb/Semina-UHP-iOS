import SwiftUI


// MARK: - Tab Bar Button Component
struct TabBarButton: View {
  let selectedIcon: String
  let unselectedIcon: String
  let label: String
  let isSelected: Bool
  let action: () -> Void
  
  private var foregroundColor: Color {
    isSelected ? Color("onBkgTextColor10") : Color("onBkgTextColor30")
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

// MARK: - Tab Selector View Component
struct TabsBarView: View {
  @Binding var selectedTab: PreviewTabSelection
  let tabs: [(name: String, selectedIcon: String, unselectedIcon: String)]
  
  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(PreviewTabSelection.allCases.enumerated()), id: \.element) { index, tabCase in
        let tab = tabs[index]
        TabBarButton(
          selectedIcon: tab.selectedIcon,
          unselectedIcon: tab.unselectedIcon,
          label: tab.name,
          isSelected: selectedTab == tabCase,
          action: {
            withAnimation(.easeInOut(duration: 0.2)) {
              selectedTab = tabCase
            }
          }
        )
      }
    }
    .padding(.horizontal, Spacing.current.space2xs)
    .background(Color("AppBkgColor"))
  }
}