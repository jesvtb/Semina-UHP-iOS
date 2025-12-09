import SwiftUI

// MARK: - Profile Tab View
struct ProfileTabView: View {
    let onLogout: () -> Void
    @FocusState.Binding var isTextFieldFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile content placeholder
                Text("Profile")
                    .font(.title)
                    .foregroundColor(Color("onBkgTextColor20"))
                    .padding(.top)
                
                // Logout button
                Button(action: onLogout) {
                    HStack {
                        Spacer()
                        Text("Logout")
                            .bodyText()
                            .foregroundColor(Color("AppBkgColor"))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color("buttonBkgColor90"))
                    .cornerRadius(2)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
            }
            .padding(.top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isTextFieldFocused = false
        }
        .background(Color("AppBkgColor"))
    }
}

