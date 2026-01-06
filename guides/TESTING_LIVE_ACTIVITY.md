# Testing LiveActivity Guide

This guide explains how to test the existing LiveActivity implementation in the widget extension.

## Prerequisites

1. **Physical Device Required**: LiveActivities only work on physical iOS devices (iPhone 14 Pro or later for Dynamic Island, iPhone X or later for Lock Screen)
2. **iOS 16.1+**: LiveActivities require iOS 16.1 or later
3. **Configuration**: Ensure `NSSupportsLiveActivities` is set to `true` in `Info.plist` (already configured ✅)

## Testing Methods

### Method 1: Xcode Preview (Recommended for UI Development)

The LiveActivity already has preview support built-in. To use it:

1. Open `widget/widgetLiveActivity.swift` in Xcode
2. Look for the `#Preview` block at the bottom (lines 75-80)
3. Click the **"Resume"** button in the preview pane
4. You can see different states:
   - Lock Screen/Banner view
   - Dynamic Island expanded view
   - Compact view
   - Minimal view

**Preview Features:**
- See different emoji states (😀 and 🤩)
- Test UI layout without running on device
- Fast iteration for UI changes

**Limitations:**
- Preview doesn't show real-time updates
- No actual activity lifecycle testing
- No Dynamic Island animations

**⚠️ Common Preview Error: "Failed to install 'unheardpath.app'"**

If you see this error, it means Xcode cannot install the host app on your device/simulator. Here's how to fix it:

**Solution 1: Use iOS Simulator (Easiest)**
1. Select an **iOS Simulator** as the preview destination (not a physical device)
2. Go to **Product** > **Destination** > Select a simulator (e.g., "iPhone 15 Pro")
3. Try the preview again

**Solution 2: Build Main App First**
1. Select the **unheardpath** scheme (not widgetExtension)
2. Build and run the main app once on your device/simulator: **Product** > **Run** (⌘R)
3. This ensures the app is properly signed and installed
4. Then switch back to preview the widget

**Solution 3: Fix Code Signing**
1. Select the **unheardpath** target in Xcode
2. Go to **Signing & Capabilities** tab
3. Ensure **"Automatically manage signing"** is checked
4. Select your **Team**: `ZMR9YNSJN2`
5. Build the main app: **Product** > **Build** (⌘B)
6. Try preview again

**Solution 4: Clean Build Folder**
1. **Product** > **Clean Build Folder** (⇧⌘K)
2. Close Xcode
3. Reopen Xcode
4. Build the main app first, then try preview

**Solution 5: Check Device Connection**
- If using a physical device, ensure:
  - Device is unlocked
  - Device trusts your computer (check for "Trust This Computer" prompt)
  - Device has enough storage space
  - Try unplugging and replugging the USB cable

**Solution 6: Fix Widget Extension Entitlements (Common Issue)**
If the `widgetExtension.entitlements` file is empty or missing the ActivityKit entitlement:

1. Open `widgetExtension.entitlements` file
2. Ensure it contains:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.developer.activitykit</key>
       <true/>
   </dict>
   </plist>
   ```
3. Clean build folder: **Product** > **Clean Build Folder** (⇧⌘K)
4. Build the main app first, then try preview again

**Solution 7: Verify Build Settings**
1. Select the **widgetExtension** target
2. Go to **Build Settings** tab
3. Verify:
   - **Code Signing Entitlements**: `widgetExtension.entitlements`
   - **Development Team**: `ZMR9YNSJN2`
   - **Code Signing Style**: Automatic
4. Select the **unheardpath** target
5. Verify it has the widget extension as a dependency (should be automatic)

**Solution 8: Manual Build Sequence**
Sometimes Xcode needs a specific build order:
1. Select **unheardpath** scheme
2. **Product** > **Build** (⌘B) - Build main app
3. Select **widgetExtension** scheme  
4. **Product** > **Build** (⌘B) - Build widget extension
5. Switch back to preview and try again

**Why This Happens:**
Widget extension previews require the host app (`unheardpath.app`) to be installed because the widget extension runs as part of the main app. Xcode needs to install the main app first before it can preview the widget extension. Additionally, the widget extension must have proper entitlements (especially `com.apple.developer.activitykit`) for LiveActivities to work.

### Method 2: Test Helper in Main App (Recommended for Full Testing)

Add a test helper to start the LiveActivity from your main app. See the code example below.

**Steps:**
1. Add the test helper code to your app
2. Add a test button in a debug view or settings screen
3. Run on a physical device
4. Tap the button to start the LiveActivity
5. Observe it on Lock Screen and Dynamic Island

### Method 3: Programmatic Testing

You can test LiveActivity programmatically by:

1. **Starting an Activity (iOS 16.2+ API):**
   ```swift
   let attributes = widgetAttributes(name: "Test Activity")
   let contentState = widgetAttributes.ContentState(emoji: "😀")
   let content = ActivityContent(state: contentState, staleDate: nil)
   
   do {
       let activity = try Activity<widgetAttributes>.request(
           attributes: attributes,
           content: content
       )
       print("✅ LiveActivity started: \(activity.id)")
   } catch {
       print("❌ Failed to start LiveActivity: \(error)")
   }
   ```

2. **Updating an Activity (iOS 16.2+ API):**
   ```swift
   Task {
       let updatedState = widgetAttributes.ContentState(emoji: "🤩")
       let content = ActivityContent(state: updatedState, staleDate: nil)
       await activity.update(content)
   }
   ```

3. **Ending an Activity (iOS 16.2+ API):**
   ```swift
   Task {
       let finalState = widgetAttributes.ContentState(emoji: "✅")
       let content = ActivityContent(state: finalState, staleDate: nil)
       await activity.end(content, dismissalPolicy: .immediate)
   }
   ```

## Test Helper Implementation

Add this helper class to test LiveActivity functionality:

```swift
import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class LiveActivityTestHelper: @unchecked Sendable {
    static let shared = LiveActivityTestHelper()
    private var currentActivity: Activity<widgetAttributes>?
    
    private init() {}
    
    /// Starts a test LiveActivity (iOS 16.2+ API)
    func startTestActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("❌ LiveActivities are not enabled")
            return
        }
        
        let attributes = widgetAttributes(name: "Test Activity")
        let contentState = widgetAttributes.ContentState(emoji: "😀")
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        do {
            let activity = try Activity<widgetAttributes>.request(
                attributes: attributes,
                content: content
            )
            currentActivity = activity
            print("✅ LiveActivity started: \(activity.id)")
        } catch {
            print("❌ Failed to start LiveActivity: \(error)")
        }
    }
    
    /// Updates the current LiveActivity with a new emoji (iOS 16.2+ API)
    func updateTestActivity(emoji: String) {
        guard let activity = currentActivity else {
            print("❌ No active LiveActivity to update")
            return
        }
        
        Task {
            let updatedState = widgetAttributes.ContentState(emoji: emoji)
            let content = ActivityContent(state: updatedState, staleDate: nil)
            await activity.update(content)
            print("✅ LiveActivity updated with emoji: \(emoji)")
        }
    }
    
    /// Ends the current LiveActivity (iOS 16.2+ API)
    func endTestActivity() {
        guard let activity = currentActivity else {
            print("❌ No active LiveActivity to end")
            return
        }
        
        Task {
            let finalState = widgetAttributes.ContentState(emoji: "✅")
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            await MainActor.run {
                currentActivity = nil
            }
            print("✅ LiveActivity ended")
        }
    }
    
    /// Checks if LiveActivities are available and enabled
    func checkAvailability() -> (enabled: Bool, available: Bool) {
        let info = ActivityAuthorizationInfo()
        // ActivityKit is available if we can create ActivityAuthorizationInfo
        let isAvailable = true
        return (info.areActivitiesEnabled, isAvailable)
    }
}
```

## Adding a Test Button

To easily test LiveActivity, add a test button to a debug view or settings screen:

```swift
#if DEBUG
struct LiveActivityTestView: View {
    @State private var currentEmoji = "😀"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("LiveActivity Test")
                .font(.title)
            
            if #available(iOS 16.1, *) {
                let availability = LiveActivityTestHelper.shared.checkAvailability()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status:")
                    Text("Available: \(availability.available ? "✅" : "❌")")
                    Text("Enabled: \(availability.enabled ? "✅" : "❌")")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                Button("Start LiveActivity") {
                    LiveActivityTestHelper.shared.startTestActivity()
                }
                .buttonStyle(.borderedProminent)
                
                HStack {
                    TextField("Emoji", text: $currentEmoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    
                    Button("Update") {
                        LiveActivityTestHelper.shared.updateTestActivity(emoji: currentEmoji)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("End LiveActivity") {
                    LiveActivityTestHelper.shared.endTestActivity()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Text("LiveActivities require iOS 16.1+")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}
#endif
```

## Testing Checklist

- [ ] **Preview Test**: Verify UI looks correct in Xcode preview
- [ ] **Device Test**: Test on physical iPhone (14 Pro or later for Dynamic Island)
- [ ] **Start Activity**: Verify activity appears on Lock Screen
- [ ] **Dynamic Island**: Verify activity appears in Dynamic Island (iPhone 14 Pro+)
- [ ] **Update Activity**: Verify updates work correctly
- [ ] **End Activity**: Verify activity dismisses properly
- [ ] **Multiple States**: Test different emoji states
- [ ] **Background**: Test activity behavior when app is in background
- [ ] **App Termination**: Test activity persistence after app closes

## Common Issues

### "LiveActivities are not enabled"
- Check `NSSupportsLiveActivities` is `true` in `Info.plist` ✅ (already configured)
- Check entitlements file has `com.apple.developer.activitykit` = `true`
- Verify you're testing on a physical device (not simulator)

### "ActivityKit is not available"
- Ensure you're on iOS 16.1+
- Check device supports LiveActivities (iPhone X or later)
- Verify provisioning profile includes ActivityKit entitlement

### Activity doesn't appear
- Check device has LiveActivities enabled in Settings > Face ID & Passcode (or Touch ID & Passcode)
- Ensure you're testing on a physical device
- Check console logs for errors

### Dynamic Island not showing
- Requires iPhone 14 Pro or later
- Ensure device has Dynamic Island (not notch)
- Check activity is actually active

## Debug Tips

1. **Check Console Logs**: Look for ActivityKit-related messages
2. **Verify Authorization**: Use `ActivityAuthorizationInfo()` to check status
3. **Test Incrementally**: Start with simple state, then add complexity
4. **Use Preview First**: Validate UI in preview before device testing
5. **Check Activity State**: Monitor `activity.activityState` for lifecycle

## Next Steps

After testing the basic LiveActivity:

1. **Customize Content**: Update `widgetAttributes` and `ContentState` for your use case
2. **Add Real Data**: Connect to your app's data models
3. **Implement Updates**: Add logic to update activity based on app events
4. **Handle Errors**: Add proper error handling for production use
5. **Test Edge Cases**: Test with network issues, app termination, etc.









