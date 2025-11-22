import SwiftUI
import Supabase
import AuthenticationServices
import UIKit
import CryptoKit

struct AuthView: View {
  @State var email = ""
  @State var isLoading = false
  @State var isGoogleLoading = false
  @State var isAppleLoading = false
  @State var result: Result<Void, Error>?
  @State private var currentNonce: String?

  var body: some View {
    Form {
      Section {
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }

      Section {
        Button("Continue with Email") {
          signInButtonTapped()
        }

        Button("Continue with Google") {
          signInWithGoogleButtonTapped()
        }
        .disabled(isGoogleLoading)

        SignInWithAppleButton(
          onRequest: { request in
            // Request scopes for name and email
            request.requestedScopes = [.fullName, .email]
            
            // Generate and set nonce for security (recommended by Supabase docs)
            let nonce = randomNonceString()
            currentNonce = nonce
            request.nonce = sha256(nonce)
          },
          onCompletion: { result in
            handleAppleSignIn(result: result)
          }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .disabled(isAppleLoading)

        if isLoading || isGoogleLoading || isAppleLoading {
          ProgressView()
        }
      }

      if let result {
        Section {
          switch result {
          case .success:
            Text("Check your inbox for the magic link.")
          case .failure(let error):
            Text(error.localizedDescription).foregroundStyle(.red)
          }
        }
      }
      
      Section {
        Text("New users will automatically have an account created.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .onOpenURL(perform: { url in
      Task {
        do {
          #if DEBUG
          print("🔗 Handling callback URL: \(url.absoluteString)")
          #endif
          try await supabase.auth.session(from: url)
          #if DEBUG
          print("✅ Session created successfully")
          #endif
        } catch {
          #if DEBUG
          print("❌ Session callback error: \(error)")
          print("   Error type: \(type(of: error))")
          print("   Error description: \(error.localizedDescription)")
          #endif
          let errorMessage: String
          if let authError = error as? AuthError {
            errorMessage = authError.localizedDescription
          } else {
            errorMessage = "Authentication failed: \(error.localizedDescription)"
          }
          self.result = .failure(NSError(domain: "AuthCallback", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
        }
      }
    })
  }

  func signInButtonTapped() {
    Task {
      isLoading = true
      defer { isLoading = false }

      do {
        // signInWithOTP automatically creates an account if the user doesn't exist
        // Reference: https://supabase.com/docs/guides/auth/auth-email
        let redirectTo = URL(string: "unheardpath://login-callback")!
        try await supabase.auth.signInWithOTP(
            email: email,
            redirectTo: redirectTo
        )
        result = .success(())
      } catch {
        // Provide detailed error information
        let errorMessage: String
        if let authError = error as? AuthError {
          errorMessage = authError.localizedDescription
        } else if let urlError = error as? URLError {
          errorMessage = "Network error: \(urlError.localizedDescription)"
        } else {
          errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
        #if DEBUG
        print("❌ Email OTP Error: \(error)")
        print("   Error type: \(type(of: error))")
        print("   Error description: \(error.localizedDescription)")
        #endif
        result = .failure(NSError(domain: "EmailSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
      }
    }
  }

  func signInWithGoogleButtonTapped() {
    Task {
      isGoogleLoading = true
      defer { isGoogleLoading = false }

      do {
        // Use the full URL with scheme for OAuth redirect
        guard let redirectTo = URL(string: "unheardpath://login-callback") else {
          result = .failure(NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid redirect URL"]))
          return
        }
        
        // Get the OAuth URL and open it in Safari
        // The redirect will come back to our app via the URL scheme
        // signInWithOAuth automatically creates an account if the user doesn't exist
        // Reference: https://supabase.com/docs/guides/auth/social-login/auth-google
        try await supabase.auth.signInWithOAuth(
          provider: .google,
          redirectTo: redirectTo
        )
        
        // The OAuth flow will open Safari automatically
        // When user completes auth, they'll be redirected back to our app
        // New users will have an account created automatically
        result = .success(())
      } catch {
        // Provide more helpful error message
        let errorMessage: String
        if let authError = error as? AuthError {
          errorMessage = authError.localizedDescription
        } else if error.localizedDescription.contains("PKCE") {
          errorMessage = "OAuth configuration error. Make sure the redirect URL 'unheardpath://login-callback' is properly configured. Error: \(error.localizedDescription)"
        } else {
          errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
        }
        result = .failure(NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
      }
    }
  }

  func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
    Task {
      isAppleLoading = true
      defer { isAppleLoading = false }

      switch result {
      case .success(let authorization):
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
          self.result = .failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential"]))
          return
        }

        guard let identityToken = appleIDCredential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8) else {
          self.result = .failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"]))
          return
        }

        do {
          #if DEBUG
          print("🍎 Apple Sign-In: Starting Supabase authentication...")
          print("   ID Token length: \(idTokenString.count)")
          print("   Nonce provided: \(currentNonce != nil ? "Yes" : "No")")
          if let supabaseURL = Bundle.main.infoDictionary?["SupabaseProjectUrl"] as? String {
            print("   Supabase URL: \(supabaseURL)")
          }
          #endif
          
          // Sign in with Supabase using the ID token
          // signInWithIdToken automatically creates an account if the user doesn't exist
          // According to Supabase docs: https://supabase.com/docs/guides/auth/social-login/auth-apple
          // Reference: https://supabase.com/docs/guides/auth/social-login/auth-apple?queryGroups=environment&environment=client&queryGroups=platform&platform=swift
          //
          // IMPORTANT: For native iOS Sign in with Apple, the ID token's audience is the App ID (bundle identifier).
          // In Supabase Dashboard > Authentication > Providers > Apple, the "Client IDs" field must include
          // BOTH the Service ID (e.g., com.semina.unheardpath.supabase) AND the App ID (com.semina.unheardpath).
          // Separate multiple client IDs with commas: "com.semina.unheardpath.supabase,com.semina.unheardpath"
          let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(
              provider: .apple,
              idToken: idTokenString,
              nonce: currentNonce // Include nonce for security verification (optional but recommended)
            )
          )
          
          #if DEBUG
          print("✅ Apple Sign-In: Supabase authentication successful")
          print("   User ID: \(session.user.id)")
          print("   Email: \(session.user.email ?? "not provided")")
          // Verify session is stored
          do {
            let storedSession = try await supabase.auth.session
            print("✅ Session stored successfully - User ID: \(storedSession.user.id)")
            print("Session: \(storedSession.accessToken)")
          } catch {
            print("⚠️ Warning: Session not found after sign-in: \(error.localizedDescription)")
          }
          #endif
          
          // Apple only provides full name on FIRST sign-in (when account is created)
          // Capture and save it if available (per Supabase documentation)
          // Reference: https://supabase.com/docs/guides/auth/social-login/auth-apple
          // Note: Name saving functionality can be added here if needed in the future
          
          self.result = .success(())
        } catch {
          // Provide more helpful error messages with detailed debugging
          #if DEBUG
          print("❌ Apple Sign-In: Supabase authentication failed")
          print("   Error type: \(type(of: error))")
          print("   Error description: \(error.localizedDescription)")
          if let urlError = error as? URLError {
            print("   URLError code: \(urlError.code.rawValue)")
            print("   URLError domain: \(urlError.localizedDescription)")
            print("   URLError userInfo: \(urlError.userInfo)")
          }
          if let authError = error as? AuthError {
            print("   AuthError message: \(authError.localizedDescription)")
          }
          #endif
          
          let errorMessage: String
          if let authError = error as? AuthError {
            errorMessage = authError.localizedDescription
          } else if let urlError = error as? URLError {
            // Handle network/SSL errors specifically
            switch urlError.code {
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid:
              errorMessage = "SSL connection error. Please check your network connection and try again. If the problem persists, verify your Supabase configuration."
              #if DEBUG
              print("   🔒 SSL Error Details:")
              print("      - Code: \(urlError.code.rawValue)")
              print("      - Description: \(urlError.localizedDescription)")
              print("      - UserInfo: \(urlError.userInfo)")
              #endif
            case .notConnectedToInternet:
              errorMessage = "No internet connection. Please check your network settings."
            case .timedOut:
              errorMessage = "Connection timed out. Please try again."
            default:
              errorMessage = "Network error: \(urlError.localizedDescription)"
            }
          } else {
            errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
          }
          self.result = .failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
        }

      case .failure(let error):
        // Handle Apple Sign-In specific errors
        let errorMessage: String
        if let authError = error as? ASAuthorizationError {
          switch authError.code {
          case .canceled:
            errorMessage = "Sign in was canceled"
          case .failed:
            errorMessage = "Sign in failed. Please check that 'Sign in with Apple' capability is enabled in Xcode."
          case .unknown:
            errorMessage = "Unknown error. Error code: \(authError.code.rawValue). Please check that 'Sign in with Apple' capability is enabled and your App ID has Sign in with Apple enabled in Apple Developer Portal."
          default:
            errorMessage = "Sign in error: \(error.localizedDescription)"
          }
        } else {
          errorMessage = error.localizedDescription
        }
        self.result = .failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
      }
    }
  }
  
  // MARK: - Helper Functions for Apple Sign-In
  
  /// Generates a random nonce string for Apple Sign-In security
  private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] =
      Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length
    
    while remainingLength > 0 {
      let randoms: [UInt8] = (0..<16).map { _ in
        var random: UInt8 = 0
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
        if errorCode != errSecSuccess {
          fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        return random
      }
      
      randoms.forEach { random in
        if remainingLength == 0 {
          return
        }
        
        if random < charset.count {
          result.append(charset[Int(random)])
          remainingLength -= 1
        }
      }
    }
    
    return result
  }
  
  /// Hashes the nonce using SHA256 (required by Apple)
  private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    let hashString = hashedData.compactMap {
      String(format: "%02x", $0)
    }.joined()
    
    return hashString
  }
}
