# LiveActivity Lock Screen Display Checklist

This checklist helps diagnose why LiveActivities aren't appearing on the lock screen.

## ✅ Critical Requirements (MUST HAVE)

### 1. Widget Extension Entitlements ⚠️ **CRITICAL - FIXED**
- [x] **`widgetExtension.entitlements`** must contain:
  ```xml
  <key>com.apple.developer.activitykit</key>
  <true/>
  ```
  **Status:** ✅ **FIXED** - Added ActivityKit entitlement

### 2. Main App Info.plist ✅
- [x] **`unheardpath/Info.plist`** contains:
  ```xml
  <key>NSSupportsLiveActivities</key>
  <true/>
  ```
  **Status:** ✅ Already configured

### 3. ActivityConfiguration Setup ✅
- [x] **`widget/widgetLiveActivity.swift`** has proper `ActivityConfiguration`:
  ```swift
  ActivityConfiguration(for: widgetAttributes.self) { context in
      // Lock screen/banner UI goes here
      VStack {
          Text("Hello \(context.state.emoji)")
      }
      .activityBackgroundTint(Color.cyan)
  }
  ```
  **Status:** ✅ Already configured correctly

### 4. Physical Device ✅
- [ ] **Testing on physical device** (not simulator)
  - LiveActivities don't work on simulator for actual testing
  - Requires iPhone X or later (iOS 16.1+)
  - For Dynamic Island: iPhone 14 Pro or later

### 5. Device Settings ⚠️ **CHECK THIS**
- [ ] **Settings > Face ID & Passcode** (or Touch ID & Passcode)
  - Scroll down to find **"Allow Access When Locked"** section
  - Ensure **"Live Activities"** toggle is **ON**
  - This is a device-level setting that can block LiveActivities

- [ ] **Settings > [Your App Name]**
  - Check if there are any app-specific LiveActivity permissions
  - Some iOS versions have per-app LiveActivity controls

### 6. Code Signing & Provisioning
- [ ] **Widget Extension Target:**
  - Signing & Capabilities > Team: `ZMR9YNSJN2`
  - Code Signing Entitlements: `widgetExtension.entitlements`
  - Automatic Signing enabled

- [ ] **Main App Target:**
  - Signing & Capabilities > Team: `ZMR9YNSJN2`
  - Automatic Signing enabled

- [ ] **After adding entitlement:**
  1. Clean Build Folder: **Product** > **Clean Build Folder** (⇧⌘K)
  2. Delete app from device
  3. Rebuild and reinstall
  4. Xcode will regenerate provisioning profile with ActivityKit entitlement

### 7. Activity Authorization Check
- [ ] **Verify in code** that LiveActivities are enabled:
  ```swift
  let info = ActivityAuthorizationInfo()
  if !info.areActivitiesEnabled {
      print("❌ LiveActivities are disabled on this device")
  }
  ```
  - Check console logs when starting activity
  - If disabled, user needs to enable in Settings

### 8. Activity Request Implementation
- [ ] **Activity is being started correctly:**
  ```swift
  let attributes = widgetAttributes(name: "Test Activity")
  let contentState = widgetAttributes.ContentState(emoji: "😀")
  let content = ActivityContent(state: contentState, staleDate: nil)
  
  do {
      let activity = try Activity<widgetAttributes>.request(
          attributes: attributes,
          content: content
      )
      print("✅ Activity started: \(activity.id)")
  } catch {
      print("❌ Error: \(error)")
  }
  ```
  - Check console for errors
  - Verify activity ID is created

## 🔍 Debugging Steps

### Step 1: Check Console Logs
When you start a LiveActivity, look for:
- ✅ `"✅ LiveActivity started: [activity-id]"`
- ❌ Any error messages about entitlements
- ❌ Any error messages about authorization

### Step 2: Verify Activity State
```swift
print("Activity state: \(activity.activityState)")
print("Activity ID: \(activity.id)")
```
- Should show `.active` state
- Should have a valid ID

### Step 3: Check Device Settings
1. Go to **Settings > Face ID & Passcode**
2. Scroll to **"Allow Access When Locked"**
3. Ensure **"Live Activities"** is **ON**

### Step 4: Test on Lock Screen
1. Start the LiveActivity from your app
2. Lock the device
3. Wake the device (but don't unlock)
4. Check if LiveActivity appears below the time

### Step 5: Check Activity Lifecycle
- Activity should remain active even when app is backgrounded
- Activity should persist after app is terminated
- Activity should update when you call `activity.update()`

## 🚨 Common Issues & Solutions

### Issue: "LiveActivities are not enabled"
**Solution:**
- Check device Settings > Face ID & Passcode > Live Activities (must be ON)
- Check `ActivityAuthorizationInfo().areActivitiesEnabled` in code

### Issue: "Provisioning profile doesn't include ActivityKit entitlement"
**Solution:**
1. Ensure `widgetExtension.entitlements` has ActivityKit entitlement ✅ (FIXED)
2. Clean build folder
3. Delete app from device
4. Rebuild - Xcode will regenerate profile

### Issue: Activity starts but doesn't appear on lock screen
**Possible causes:**
1. **Device settings:** Live Activities disabled in Settings
2. **Activity dismissed too quickly:** Check if activity is ending immediately
3. **UI too small/invisible:** Check ActivityConfiguration UI is visible
4. **Device locked before activity starts:** Try locking device after starting activity

### Issue: Activity appears but disappears immediately
**Possible causes:**
1. Activity is being ended too quickly
2. Activity state is invalid
3. ActivityConfiguration has rendering errors

## ✅ Verification Checklist

After fixing the entitlements file, verify:

- [ ] Widget extension entitlements file has `com.apple.developer.activitykit = true` ✅
- [ ] Main app Info.plist has `NSSupportsLiveActivities = true` ✅
- [ ] ActivityConfiguration is properly configured ✅
- [ ] Testing on physical device (not simulator)
- [ ] Device Settings > Face ID & Passcode > Live Activities is ON
- [ ] Code signing is correct for both targets
- [ ] App is rebuilt after adding entitlement
- [ ] Console shows activity started successfully
- [ ] Activity appears on lock screen when device is locked

## Next Steps

1. **Clean and rebuild:**
   - Product > Clean Build Folder (⇧⌘K)
   - Delete app from device
   - Rebuild and reinstall

2. **Test the activity:**
   - Use the test button in Profile tab
   - Check console logs
   - Lock device and check lock screen

3. **If still not working:**
   - Check device Settings > Face ID & Passcode > Live Activities
   - Verify `ActivityAuthorizationInfo().areActivitiesEnabled` returns `true`
   - Check console for any error messages
