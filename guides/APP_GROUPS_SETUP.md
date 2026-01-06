# App Groups Setup Guide

This guide explains how to set up App Groups to enable data sharing between the main app and widget extension.

## Why App Groups Are Needed

- **Widget extensions run in separate processes** from the main app
- **UserDefaults are isolated** between processes by default
- **App Groups create a shared UserDefaults suite** that both the app and widget can access
- **Required for sharing**: Location data, app state, tracking mode, and any other data between app and widget

## Prerequisites

- Apple Developer account (free or paid)
- Xcode project with both main app and widget extension targets
- Access to [Apple Developer Portal](https://developer.apple.com/account)

---

## Part 1: Create App Group in Apple Developer Portal

### Step 1.1: Navigate to Developer Portal

1. Go to [https://developer.apple.com/account](https://developer.apple.com/account)
2. Sign in with your Apple Developer account
3. Navigate to **Certificates, Identifiers & Profiles**
4. Click **Identifiers** in the left sidebar

### Step 1.2: Create App Group Identifier

1. Click the **+** button (top left) to create a new identifier
2. Select **App Groups** under **Capabilities**
3. Click **Continue**
4. Fill in the details:
   - **Description**: `UnheardPath App Group` (or any descriptive name)
   - **Identifier**: `group.com.semina.unheardpath`
     - ⚠️ **MUST start with `group.`**
     - ⚠️ **MUST match your organization identifier** (`com.semina`)
5. Click **Continue**
6. Review and click **Register**

### Step 1.3: Enable App Groups on Main App ID

1. In **Identifiers**, find and select your main app identifier: `com.semina.unheardpath`
2. Scroll down to **Capabilities**
3. Check the box for **App Groups**
4. Click **Configure** (if needed)
5. Check the box for `group.com.semina.unheardpath`
6. Click **Save**
7. Click **Continue** and then **Save** again

### Step 1.4: Enable App Groups on Widget Extension App ID

1. In **Identifiers**, find and select your widget extension identifier: `com.semina.unheardpath.widget`
   - ⚠️ **If this doesn't exist**, you may need to create it first, or the widget may use the main app's identifier
2. Scroll down to **Capabilities**
3. Check the box for **App Groups**
4. Click **Configure** (if needed)
5. Check the box for `group.com.semina.unheardpath`
6. Click **Save**
7. Click **Continue** and then **Save** again

### Step 1.5: Wait for Sync

- Apple's servers need a few minutes to sync the changes
- You may need to wait 5-10 minutes before the App Group appears in Xcode

---

## Part 2: Enable App Groups in Xcode

### Step 2.1: Add App Groups to Main App Target

1. Open your Xcode project
2. Select the **unheardpath** target (main app) in the project navigator
3. Go to the **Signing & Capabilities** tab
4. Click the **+ Capability** button (top left)
5. Search for and double-click **App Groups**
6. In the **App Groups** section, click the **+** button
7. Select `group.com.semina.unheardpath` from the dropdown
   - ⚠️ **If it doesn't appear**: Wait a few minutes for Apple's servers to sync, or see troubleshooting below
8. Verify that `unheardpath.entitlements` now includes:
   ```xml
   <key>com.apple.security.application-groups</key>
   <array>
       <string>group.com.semina.unheardpath</string>
   </array>
   ```

### Step 2.2: Add App Groups to Widget Extension Target

1. Select the **widgetExtension** target in the project navigator
2. Go to the **Signing & Capabilities** tab
3. Click the **+ Capability** button
4. Search for and double-click **App Groups**
5. In the **App Groups** section, click the **+** button
6. Select `group.com.semina.unheardpath` from the dropdown
7. Verify that `widgetExtension.entitlements` now includes:
   ```xml
   <key>com.apple.security.application-groups</key>
   <array>
       <string>group.com.semina.unheardpath</string>
   </array>
   ```

### Step 2.3: Verify Both Targets Use Same Team

1. Ensure both **unheardpath** and **widgetExtension** targets use the same **Team** in Signing & Capabilities
2. Both should have **Automatic Signing** enabled
3. If signing errors occur, ensure both App IDs have App Groups enabled in Developer Portal

---

## Part 3: Update Code to Use App Group Identifier

### Step 3.1: Update StorageManager.swift

Change the `sharedUserDefaults` property to use the App Group identifier:

**Current code:**
```swift
private static var sharedUserDefaults: UserDefaults {
    return UserDefaults(suiteName: "com.semina.unheardpath") ?? UserDefaults.standard
}
```

**Updated code:**
```swift
private static var sharedUserDefaults: UserDefaults {
    return UserDefaults(suiteName: "group.com.semina.unheardpath") ?? UserDefaults.standard
}
```

### Step 3.2: Update widget.swift

Find all instances of:
```swift
UserDefaults(suiteName: "com.semina.unheardpath")
```

Replace with:
```swift
UserDefaults(suiteName: "group.com.semina.unheardpath")
```

**Locations to update:**
- In `loadLocationTrackingEntry()` method (around line 86)
- In the debug UI section (around line 267)

---

## Part 4: Verify Setup

### Step 4.1: Clean Build

1. In Xcode: **Product** > **Clean Build Folder** (Shift+Cmd+K)
2. This ensures old UserDefaults instances are cleared

### Step 4.2: Rebuild and Run

1. Build and run the app on a device or simulator
2. Grant location permissions when prompted
3. Allow the app to get a location update

### Step 4.3: Add Widget to Home Screen

1. Long-press on the home screen
2. Tap the **+** button (top left)
3. Search for your app's widget
4. Add the widget to the home screen

### Step 4.4: Test Data Sharing

1. **Background the app** (press home button or swipe up)
2. **Wait for widget to update** (may take 30 seconds to several minutes)
3. **Check the widget** - it should now show:
   - ✅ Location coordinates (latitude/longitude)
   - ✅ Last update timestamp
   - ✅ App background state (if implemented)
   - ✅ Tracking mode (if implemented)

### Step 4.5: Verify in Console Logs

Look for these log messages:
- `💾 Saved Latest Device Location to UserDefaults: [lat], [lon]` (from app)
- `📱 Widget: Reading app state...` (from widget)
- `🔄 Widget: getTimeline called at [time]` (from widget)

---

## Troubleshooting

### App Group Not Appearing in Xcode

**Problem**: After creating App Group in Developer Portal, it doesn't appear in Xcode's dropdown.

**Solutions**:
1. **Wait 5-10 minutes** for Apple's servers to sync
2. **Refresh provisioning profiles**:
   - Xcode > **Preferences** > **Accounts**
   - Select your Apple ID
   - Click **Download Manual Profiles**
3. **Restart Xcode**
4. **Verify in Developer Portal** that the App Group was created successfully

### Signing Errors

**Problem**: Build fails with signing/provisioning errors.

**Solutions**:
1. Ensure both targets use the **same Team**
2. Verify both App IDs have **App Groups enabled** in Developer Portal
3. Check that **Automatic Signing** is enabled for both targets
4. Try **Clean Build Folder** and rebuild

### Widget Still Shows "No Location Data"

**Problem**: After setup, widget still can't read location data.

**Solutions**:
1. **Verify entitlements files** contain the App Group:
   - Check `unheardpath.entitlements`
   - Check `widgetExtension.entitlements`
   - Both should have `group.com.semina.unheardpath` listed
2. **Verify code uses correct identifier**:
   - Search for `com.semina.unheardpath` (without `group.` prefix)
   - Should be `group.com.semina.unheardpath` everywhere
3. **Check console logs**:
   - App should show: `💾 Saved Latest Device Location to UserDefaults`
   - Widget should show: `📱 Widget: Reading app state...`
4. **Remove and re-add widget** to home screen
5. **Restart device/simulator**

### Widget Updates Slowly

**Problem**: Widget doesn't update immediately when location changes.

**Note**: This is **expected behavior**. iOS controls widget update frequency:
- Widgets update on a **timeline schedule** (not real-time)
- iOS may throttle updates, especially in background
- Updates can be delayed by several minutes
- This is by design to preserve battery life

**Solutions**:
- Widget will update eventually (within 15-30 minutes typically)
- For development, you can trigger manual refresh in code (see LocationManager.swift)
- In production, users will see updates as iOS schedules them

---

## Summary Checklist

- [ ] Created App Group `group.com.semina.unheardpath` in Developer Portal
- [ ] Enabled App Groups on main app identifier (`com.semina.unheardpath`)
- [ ] Enabled App Groups on widget extension identifier (`com.semina.unheardpath.widget`)
- [ ] Added App Groups capability to `unheardpath` target in Xcode
- [ ] Added App Groups capability to `widgetExtension` target in Xcode
- [ ] Updated `StorageManager.swift` to use `group.com.semina.unheardpath`
- [ ] Updated `widget.swift` to use `group.com.semina.unheardpath`
- [ ] Cleaned build folder and rebuilt project
- [ ] Tested widget shows location data after app saves location
- [ ] Verified both targets use same Team and signing

---

## Additional Resources

- [Apple Documentation: App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple Documentation: Sharing Data with Your App Extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html#//apple_ref/doc/uid/TP40014214-CH21-SW1)
- [WidgetKit Documentation](https://developer.apple.com/documentation/widgetkit)

---

## Support

If you encounter issues not covered in this guide:
1. Check Xcode console logs for error messages
2. Verify all steps were completed in order
3. Ensure both app and widget are signed with the same Team
4. Check that App Group identifier matches exactly (including `group.` prefix)








