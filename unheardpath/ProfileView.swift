import SwiftUI

struct ProfileView: View {
  @State var username = ""
  @State var fullName = ""
  @State var website = ""

  @State var isLoading = false

  var body: some View {
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
    .task {
      await getInitialProfile()
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