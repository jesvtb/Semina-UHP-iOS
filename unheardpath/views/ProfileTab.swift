import SwiftUI
import ActivityKit

// MARK: - LiveActivity Attributes (must match widget extension)
// This type must be identical to widgetAttributes in widget/widgetLiveActivity.swift
// for LiveActivities to work properly
public struct widgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var emoji: String
        
        public init(emoji: String) {
            self.emoji = emoji
        }
    }
    
    public var name: String
    
    public init(name: String) {
        self.name = name
    }
}

// MARK: - Profile Tab View
struct ProfileTabView: View {
    let onLogout: () -> Void
    @FocusState.Binding var isTextFieldFocused: Bool
    
    #if DEBUG
    @State private var currentEmoji = "😀"
    @State private var activityStatus: String = ""
    #endif
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile content placeholder
                Text("Profile")
                    .font(.title)
                    .foregroundColor(Color("onBkgTextColor20"))
                    .padding(.top)
                
                #if DEBUG
                if #available(iOS 16.1, *) {
                    liveActivityTestSection
                }
                #endif
                
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
    
    #if DEBUG
    @available(iOS 16.1, *)
    private var liveActivityTestSection: some View {
        VStack(spacing: 16) {
            Text("LiveActivity Test")
                .font(.headline)
                .foregroundColor(Color("onBkgTextColor20"))
            
            let availability = LiveActivityTestHelper.shared.checkAvailability()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Status:")
                    .font(.subheadline)
                    .foregroundColor(Color("onBkgTextColor20"))
                Text("Available: \(availability.available ? "✅" : "❌")")
                    .font(.caption)
                    .foregroundColor(Color("onBkgTextColor20"))
                Text("Enabled: \(availability.enabled ? "✅" : "❌")")
                    .font(.caption)
                    .foregroundColor(Color("onBkgTextColor20"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color("buttonBkgColor90").opacity(0.3))
            .cornerRadius(8)
            
            if !activityStatus.isEmpty {
                Text(activityStatus)
                    .font(.caption)
                    .foregroundColor(activityStatus.contains("✅") ? .green : .red)
                    .padding(.horizontal)
            }
            
            // Show push token if available
            if let pushToken = LiveActivityTestHelper.shared.getCurrentPushToken() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Push Token:")
                        .font(.caption)
                        .foregroundColor(Color("onBkgTextColor20"))
                    Text(pushToken)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color("onBkgTextColor20"))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color("buttonBkgColor90").opacity(0.3))
                .cornerRadius(8)
            }
            
            Button(action: {
                LiveActivityTestHelper.shared.startTestActivity()
                activityStatus = "✅ LiveActivity started"
            }) {
                HStack {
                    Spacer()
                    Text("Start LiveActivity")
                        .bodyText()
                        .foregroundColor(Color("AppBkgColor"))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color("buttonBkgColor90"))
                .cornerRadius(2)
            }
            
            HStack(spacing: 12) {
                TextField("Emoji", text: $currentEmoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                
                Button(action: {
                    LiveActivityTestHelper.shared.updateTestActivity(emoji: currentEmoji)
                    activityStatus = "✅ LiveActivity updated with: \(currentEmoji)"
                }) {
                    Text("Update")
                        .bodyText()
                        .foregroundColor(Color("AppBkgColor"))
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(Color("buttonBkgColor90"))
                        .cornerRadius(2)
                }
            }
            
            Button(action: {
                LiveActivityTestHelper.shared.endTestActivity()
                activityStatus = "✅ LiveActivity ended"
            }) {
                HStack {
                    Spacer()
                    Text("End LiveActivity")
                        .bodyText()
                        .foregroundColor(.red)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color("buttonBkgColor90").opacity(0.5))
                .cornerRadius(2)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color("AppBkgColor"))
    }
    #endif
}

// MARK: - LiveActivity Test Helper
@available(iOS 16.1, *)
@MainActor
final class LiveActivityTestHelper: @unchecked Sendable {
    static let shared = LiveActivityTestHelper()
    private var currentActivity: Activity<widgetAttributes>?
    private var pushTokenTask: Task<Void, Never>?
    private var currentPushToken: String?
    
    private init() {}
    
    /// Starts a test LiveActivity with push token support for remote updates
    func startTestActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("❌ LiveActivities are not enabled")
            return
        }
        
        let attributes = widgetAttributes(name: "Test Activity")
        let contentState = widgetAttributes.ContentState(emoji: "😀")
        
        do {
            // Request LiveActivity with push token to enable remote updates via APNs
            // Reference: https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushType:)
            let activity = try Activity<widgetAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: nil),
                pushType: .token  // Request push token for remote updates
            )
            currentActivity = activity
            print("✅ LiveActivity started: \(activity.id)")
            
            // Listen for push token updates and send to backend
            startListeningForPushToken(activity: activity)
        } catch {
            print("❌ Failed to start LiveActivity: \(error)")
        }
    }
    
    /// Listens for push token updates and sends them to the backend
    /// Reference: https://developer.apple.com/documentation/activitykit/activity/pushtokenupdates
    private func startListeningForPushToken(activity: Activity<widgetAttributes>) {
        // Cancel any existing push token task
        pushTokenTask?.cancel()
        
        pushTokenTask = Task {
            // Listen for push token updates
            // The token may be received immediately or later, so we use an async sequence
            // Reference: https://developer.apple.com/documentation/activitykit/activity/pushtokenupdates
            for await pushToken in activity.pushTokenUpdates {
                // Check if task was cancelled
                if Task.isCancelled {
                    break
                }
                
                // Convert Data to hex string format
                let pushTokenString = pushToken.map { String(format: "%02x", $0) }.joined()
                
                // Only send if token has changed
                guard pushTokenString != currentPushToken else {
                    continue
                }
                
                currentPushToken = pushTokenString
                print("📱 Received ActivityPushToken: \(pushTokenString)")
                
                // Send push token to backend server
                await sendPushTokenToBackend(pushToken: pushTokenString, activityId: activity.id)
            }
        }
    }
    
    /// Sends the ActivityPushToken to the backend server
    /// The backend will use this token to send push notifications for LiveActivity updates
    private func sendPushTokenToBackend(pushToken: String, activityId: String) async {
        print("📤 Sending push token to backend:")
        print("   Activity ID: \(activityId)")
        print("   Push Token: \(pushToken)")
        
        do {
            let uhpGateway = UHPGateway()
            let jsonDict: [String: JSONValue] = [
                "push_token": .string(pushToken),
                "activity_id": .string(activityId)
            ]
            _ = try await uhpGateway.request(
                endpoint: "/v1/live-activities/register-token",
                method: "POST",
                jsonDict: jsonDict
            )
            print("✅ Push token sent to backend successfully")
        } catch {
            print("❌ Failed to send push token to backend: \(error)")
        }
    }
    
    /// Updates the current LiveActivity with a new emoji via push notification
    func updateTestActivity(emoji: String) {
        guard currentActivity != nil else {
            print("❌ No active LiveActivity to update")
            return
        }
        
        guard let pushToken = currentPushToken else {
            print("❌ No push token available. LiveActivity may not have received push token yet.")
            return
        }
        
        Task {
            await updateLiveActivityViaPush(pushToken: pushToken, emoji: emoji)
        }
    }
    
    /// Sends a push notification to update the Live Activity via backend
    private func updateLiveActivityViaPush(pushToken: String, emoji: String) async {
        print("📤 Sending Live Activity update via push notification:")
        print("   Push Token: \(pushToken)")
        print("   Emoji: \(emoji)")
        
        do {
            let uhpGateway = UHPGateway()
            let jsonDict: [String: JSONValue] = [
                "push_token": .string(pushToken),
                "content_state": .dictionary([
                    "emoji": .string(emoji)
                ]),
                "use_production": .bool(false)  // Use sandbox for development
            ]
            _ = try await uhpGateway.request(
                endpoint: "/v1/live-activities/update",
                method: "POST",
                jsonDict: jsonDict
            )
            print("✅ Live Activity update sent via push notification successfully")
            print("   The Live Activity should update automatically when the push notification arrives")
        } catch {
            print("❌ Failed to send Live Activity update via push notification: \(error)")
        }
    }
    
    /// Ends the current LiveActivity
    func endTestActivity() {
        guard let activity = currentActivity else {
            print("❌ No active LiveActivity to end")
            return
        }
        
        // Cancel push token listening task
        pushTokenTask?.cancel()
        pushTokenTask = nil
        
        Task {
            let finalState = widgetAttributes.ContentState(emoji: "✅")
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            await MainActor.run {
                currentActivity = nil
                currentPushToken = nil
            }
            print("✅ LiveActivity ended")
        }
    }
    
    /// Checks if LiveActivities are available and enabled
    func checkAvailability() -> (enabled: Bool, available: Bool) {
        let info = ActivityAuthorizationInfo()
        // ActivityKit is available if we can create ActivityAuthorizationInfo
        let isAvailable = true // ActivityKit framework is linked, so it's available
        return (info.areActivitiesEnabled, isAvailable)
    }
    
    /// Gets the current push token if available
    func getCurrentPushToken() -> String? {
        return currentPushToken
    }
}

