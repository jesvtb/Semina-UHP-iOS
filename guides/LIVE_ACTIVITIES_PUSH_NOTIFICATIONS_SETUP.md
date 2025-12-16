# Live Activities & Push Notifications Setup Prerequisites

Complete checklist for enabling Live Activities and Push Notifications in the unheardpath iOS app.

## Prerequisites Checklist

### Part 1: Apple Developer Portal Configuration

#### 1.1 App ID Configuration
- [ ] Log in to [Apple Developer Portal](https://developer.apple.com/account/)
- [ ] Navigate to **Certificates, Identifiers & Profiles** > **Identifiers**
- [ ] Select your App ID: `com.semina.unheardpath`
- [ ] **Enable Push Notifications:**
  - [ ] Check "Push Notifications" in Capabilities section
  - [ ] Click "Configure" (if needed)
  - [ ] Click "Save" to apply changes
- [ ] **ActivityKit (Live Activities):**
  - [ ] ⚠️ **CRITICAL:** ActivityKit does **NOT** appear as a capability anywhere:
    - ❌ **NOT** in Apple Developer Portal capabilities list
    - ❌ **NOT** in Xcode's "+ Capability" button list
  - [ ] ActivityKit is enabled **ONLY** through:
    - ✅ **Entitlements file:** `com.apple.developer.activitykit` = `true`
    - ✅ **Info.plist:** `NSSupportsLiveActivities` = `true`
  - [ ] **No action needed in Developer Portal** - just configure in Xcode project files

#### 1.2 App Group Configuration (Optional - if sharing data with widget extension)

> **⚠️ IMPORTANT: When do you need App Groups?**
> - **You NEED App Groups if:** You want to share data (like images, files, or UserDefaults) between your main app and widget extension
> - **You DON'T need App Groups if:** You're only using Live Activities that update via push notifications (ActivityKit handles this automatically)
> - **For most Live Activities use cases:** App Groups are **NOT required** - you can skip this section
> - **Skip to section 1.3** if you don't need to share data between app and widget

**Step 1: Create App Group in Developer Portal**
- [ ] Log in to [Apple Developer Portal](https://developer.apple.com/account/)
- [ ] Navigate to **Certificates, Identifiers & Profiles** > **Identifiers**
- [ ] Click the **"+"** button (top left) to create a new identifier
- [ ] Select **"App Groups"** (under "Services")
- [ ] Click **"Continue"**
- [ ] **Enter App Group Identifier:**
  - Format: `group.com.semina.unheardpath`
  - Must start with `group.` followed by your reverse domain
- [ ] Enter a **Description:** (e.g., "UnheardPath App Group")
- [ ] Click **"Continue"**, then **"Register"**
- [ ] ✅ App Group is now created

**Step 2: Enable App Groups on Main App ID**
- [ ] Still in **Identifiers**, select your **App ID:** `com.semina.unheardpath`
- [ ] Scroll to **"Capabilities"** section
- [ ] Check the box for **"App Groups"**
- [ ] Click **"Configure"** button next to App Groups
- [ ] In the modal, check the box for your App Group: `group.com.semina.unheardpath`
- [ ] Click **"Continue"**, then **"Save"**
- [ ] ✅ Main app now has App Groups enabled

**Step 3: Enable App Groups on Widget Extension App ID (if exists)**
- [ ] In **Identifiers**, check if you have a separate App ID for your widget extension
- [ ] If yes, select the widget extension App ID (e.g., `com.semina.unheardpath.widget`)
- [ ] Enable **"App Groups"** capability
- [ ] Click **"Configure"** and select the same App Group: `group.com.semina.unheardpath`
- [ ] Click **"Save"**
- [ ] ⚠️ **Note:** If using Automatic Signing, Xcode may create the widget App ID automatically

#### 1.2.1 Broadcast Capability (Optional - for Broadcast Push Notifications)

**When to Enable Broadcast Capability:**
- [ ] **Enable if:** You need to send **broadcast push notifications** to update Live Activities for multiple users simultaneously
- [ ] **Use cases:**
  - Sports scores that update for all users watching the same game
  - Delivery tracking that updates for multiple recipients
  - Live events that broadcast to all participants
  - Any scenario where you want to update many Live Activities with a single push notification

**When NOT to Enable:**
- ❌ **Don't enable if:** You only send individual push notifications to specific users
- ❌ **Don't enable if:** Each Live Activity update is user-specific and independent
- ❌ **Don't enable if:** You're just starting out - you can add this later if needed

**How to Enable:**
- [ ] In the Push Notifications configuration modal (when you click "Configure")
- [ ] Look for **"Broadcast Capability"** option
- [ ] Check the box if you need broadcast functionality
- [ ] Click "Save" or "Done"

> **Note:** Broadcast Capability is an **optional feature**. You can enable Push Notifications without it. Enable it only if you have a specific use case for broadcasting updates to multiple Live Activities at once.

#### 1.3 Push Notifications Configuration: SSL Certificate vs Authentication Key

When you click "Configure" for Push Notifications, you'll see options for SSL Certificates. Here's what you need to know:

**Option A: APNs Authentication Key (`.p8`) - RECOMMENDED ✅**
- [ ] Navigate to **Certificates, Identifiers & Profiles** > **Keys**
- [ ] Click "+" button to create a new key
- [ ] Name it (e.g., "APNs Key for unheardpath")
- [ ] **Enable "Apple Push Notifications service (APNs)"**
- [ ] Click "Continue", then "Register"
- [ ] **Download the `.p8` file** (⚠️ **ONLY AVAILABLE ONCE** - save it securely!)
- [ ] **Note the Key ID** (10-character string)
- [ ] **Note your Team ID** (found in Membership section)

**Advantages of `.p8` Key:**
- ✅ Works for **both** regular push notifications **and** Live Activities
- ✅ **One key works for all apps** in your developer account
- ✅ Works for **both development and production** environments
- ✅ **Never expires** (no annual renewal needed)
- ✅ **REQUIRED** for Live Activities (SSL certificates don't work)

**Option B: SSL Certificate (`.p12`) - Legacy Method**
- [ ] In the Push Notifications configuration modal, you can click "Create Certificate"
- [ ] You'll need to create **separate certificates** for:
  - [ ] Development SSL Certificate
  - [ ] Production SSL Certificate
- [ ] Each certificate is **app-specific** and **environment-specific**
- [ ] Certificates **expire annually** and need renewal

**When to Use SSL Certificates:**
- ❌ **DO NOT use** if you plan to use Live Activities (they won't work)
- ⚠️ Only use if your backend/push service **doesn't support** `.p8` keys
- ⚠️ Legacy systems that haven't migrated to `.p8` authentication

> **⚠️ CRITICAL DECISION:** 
> - **For Live Activities:** You **MUST** use `.p8` Authentication Key (SSL certificates don't work)
> - **For regular push notifications:** Use `.p8` Authentication Key (recommended) or SSL Certificate (legacy)
> - **Best practice:** Use `.p8` Authentication Key for everything - it's simpler and more flexible

**What to do in the SSL Certificate modal:**
- If you're using `.p8` Authentication Key (recommended): **Click "Done"** without creating SSL certificates
- The SSL certificate option is only needed if you're using the legacy `.p12` method
- You can always create SSL certificates later if needed, but `.p8` is preferred

#### 1.4 Provisioning Profiles
- [ ] Navigate to **Certificates, Identifiers & Profiles** > **Profiles**
- [ ] **For Development:**
  - [ ] Create/update **iOS App Development** profile
  - [ ] Select App ID: `com.semina.unheardpath`
  - [ ] Select your development certificate
  - [ ] Select your devices
  - [ ] Generate and download
- [ ] **For Distribution (App Store/Ad Hoc):**
  - [ ] Create/update **App Store** or **Ad Hoc** profile
  - [ ] Select App ID: `com.semina.unheardpath`
  - [ ] Select your distribution certificate
  - [ ] Generate and download

> **Note:** If using Automatic Signing in Xcode, profiles are managed automatically, but capabilities must be enabled in Developer Portal first.

---

### Part 2: Xcode Project Configuration

#### 2.1 Project Settings
- [ ] Open `unheardpath.xcodeproj` in Xcode
- [ ] Select the **project** in Navigator
- [ ] Select the **`unheardpath` target**
- [ ] Go to **Signing & Capabilities** tab
- [ ] Verify:
  - [ ] **Team:** `ZMR9YNSJN2` (or your team)
  - [ ] **Bundle Identifier:** `com.semina.unheardpath`
  - [ ] **Automatic signing** is enabled (or manual profile is selected)

#### 2.1.1 Add App Groups Capability to Main App (if sharing data)
- [ ] With **`unheardpath` target** selected, go to **Signing & Capabilities** tab
- [ ] Click **"+ Capability"** button
- [ ] Add **"App Groups"** capability
- [ ] In the App Groups section, click the **"+"** button
- [ ] **Select your App Group:** `group.com.semina.unheardpath`
  - ⚠️ **If you don't see it:** Make sure you created it in Developer Portal (see section 1.2) and enabled it on your App ID
  - ⚠️ **If it's not listed:** Xcode may need to refresh. Try:
    1. Close and reopen Xcode
    2. Or go to **Xcode** > **Preferences** > **Accounts** > Select your account > **Download Manual Profiles**
    3. Or wait a few minutes for Apple's servers to sync

#### 2.2 Add Push Notifications Capability
- [ ] In **Signing & Capabilities** tab, click **"+ Capability"**
- [ ] Add **"Push Notifications"**
- [ ] Verify it appears in the capabilities list
- [ ] Xcode should automatically update entitlements file

#### 2.3 Add Background Modes Capability (if needed)
- [ ] In **Signing & Capabilities** tab, click **"+ Capability"**
- [ ] Add **"Background Modes"**
- [ ] Enable:
  - [ ] **Remote notifications** (for push notifications)
  - [ ] **Processing** (if needed for Live Activities updates)

#### 2.4 Verify Entitlements File
- [ ] Open `unheardpath/unheardpath.entitlements`
- [ ] Verify it contains:
  ```xml
  <key>aps-environment</key>
  <string>development</string>  <!-- or "production" for release -->
  ```
- [ ] Verify it contains:
  ```xml
  <key>com.apple.developer.activitykit</key>
  <true/>
  ```

> **⚠️ IMPORTANT:** ActivityKit is **NOT** a capability you can add in Xcode's "+ Capability" button. It's only enabled through the entitlements file and Info.plist.

#### 2.4.1 Fix Provisioning Profile Error (If You See ActivityKit Entitlement Error)
If you see an error: *"Provisioning profile 'iOS Team Provisioning Profile: com.semina.unheardpath' doesn't include the `com.apple.developer.activitykit` entitlement"*

> **⚠️ IMPORTANT:** "iOS Team Provisioning Profile" is an **Xcode-managed profile** created automatically. You **won't see it** in your Apple Developer Portal - this is normal! It's managed by Xcode behind the scenes when using "Automatically manage signing".

**This error is normal** - Xcode needs to regenerate the provisioning profile. Try these steps in order:

1. **Click "Try Again"** in the error dialog
   - Xcode will attempt to regenerate the profile with the ActivityKit entitlement
   - Wait a few seconds for it to process

2. **If "Try Again" doesn't work - Force Profile Regeneration:**
   - In **Signing & Capabilities** tab, find **"Automatically manage signing"**
   - **Uncheck** the box (temporarily disable automatic signing)
   - Wait 2-3 seconds
   - **Check** the box again (re-enable automatic signing)
   - Xcode will create a fresh provisioning profile that includes all entitlements from your entitlements file
   - This usually resolves the issue

3. **If still not working - Refresh Profiles:**
   - Go to **Xcode > Settings** (or **Preferences** on older versions) > **Accounts** tab
   - Select your Apple ID account
   - Select your team: `ZMR9YNSJN2`
   - Click **"Download Manual Profiles"** button
   - Wait for it to complete (may take 30-60 seconds)
   - Go back to **Signing & Capabilities** tab
   - The error should be resolved

4. **Delete Provisioning Profiles Cache (Advanced):**
   - **Quit Xcode completely**
   - Open **Finder**
   - Press **Cmd + Shift + G** (Go to Folder)
   - Navigate to: `~/Library/MobileDevice/Provisioning Profiles/`
   - **Delete all files** in this folder (these are cached profiles)
   - Reopen Xcode
   - Go to **Signing & Capabilities** - Xcode will regenerate fresh profiles
   - This forces Xcode to create completely new profiles with all current entitlements

5. **Clear Derived Data (Advanced):**
   - **Quit Xcode completely**
   - Open **Finder**
   - Press **Cmd + Shift + G** (Go to Folder)
   - Navigate to: `~/Library/Developer/Xcode/DerivedData/`
   - **Delete the entire DerivedData folder** (or just your project's folder if you can identify it)
   - Reopen Xcode
   - Xcode will rebuild all derived data from scratch

6. **Check Apple Developer Account:**
   - Log in to [Apple Developer Portal](https://developer.apple.com/account/)
   - Check if there are any **pending agreements** that need to be accepted
   - Pending agreements can prevent provisioning profile updates
   - Accept any pending agreements if they exist

7. **Manual Signing (Last Resort):**
   - In **Signing & Capabilities**, uncheck **"Automatically manage signing"**
   - You'll need to manually create a provisioning profile in Developer Portal
   - Go to **Certificates, Identifiers & Profiles** > **Profiles**
   - Create a new **iOS App Development** profile for your App ID
   - Download and install it
   - Select it manually in Xcode
   - ⚠️ **Note:** This is more complex and you'll need to manually update profiles when entitlements change

> **Note:** The "iOS Team Provisioning Profile" is automatically created and managed by Xcode. You don't need to create it manually in Developer Portal. When Xcode regenerates it, it should automatically include the `com.apple.developer.activitykit` entitlement from your entitlements file.

#### 2.5 Info.plist Configuration (REQUIRED for Live Activities)
- [ ] Open `unheardpath/Info.plist`
- [ ] **Add Live Activities support (REQUIRED):**
  ```xml
  <key>NSSupportsLiveActivities</key>
  <true/>
  ```
  > **⚠️ IMPORTANT:** This is how ActivityKit/Live Activities is enabled - through Info.plist, NOT through Developer Portal capabilities
- [ ] (Optional) For frequent updates:
  ```xml
  <key>NSSupportsLiveActivitiesFrequentUpdates</key>
  <true/>
  ```

---

### Part 3: Widget Extension (Optional - for Custom Live Activity UI)

#### 3.1 Create Widget Extension Target
- [ ] In Xcode: **File** > **New** > **Target**
- [ ] Select **"Widget Extension"**
- [ ] Configure:
  - [ ] **Product Name:** `unheardpathWidget` (or similar)
  - [ ] **Organization Identifier:** `com.semina`
  - [ ] **Language:** Swift
  - [ ] **Include Live Activity:** ✅ Yes
- [ ] Click **Finish**
- [ ] Activate the scheme if prompted

#### 3.2 Configure Widget Extension
- [ ] Select the **widget extension target**
- [ ] Go to **Signing & Capabilities** tab:
  - [ ] Set **Team:** `ZMR9YNSJN2`
  - [ ] **Bundle Identifier:** `com.semina.unheardpath.widget` (or similar)
  - [ ] Enable **Automatic Signing**
- [ ] **Add App Groups capability** (if sharing data):
  - [ ] Click **"+ Capability"** button
  - [ ] Add **"App Groups"** capability
  - [ ] In the App Groups section, click the **"+"** button
  - [ ] **Select your App Group:** `group.com.semina.unheardpath`
    - ⚠️ **If you don't see it:** Make sure you created it in Developer Portal (see section 1.2) and enabled it on both App IDs
    - ⚠️ **If it's not listed:** Xcode may need to refresh. Try:
      1. Close and reopen Xcode
      2. Or go to **Xcode** > **Preferences** > **Accounts** > Select your account > **Download Manual Profiles**
      3. Or wait a few minutes for Apple's servers to sync

#### 3.3 Widget Extension Entitlements
- [ ] Widget extension should have its own entitlements file
- [ ] Verify it includes:
  ```xml
  <key>com.apple.developer.activitykit</key>
  <true/>
  ```
- [ ] If using App Groups:
  ```xml
  <key>com.apple.security.application-groups</key>
  <array>
      <string>group.com.semina.unheardpath</string>
  </array>
  ```

---

### Part 4: Code Prerequisites

#### 4.1 Minimum iOS Version
- [ ] Verify deployment target:
  - [ ] **Live Activities:** iOS 16.1+
  - [ ] **Push Notifications:** iOS 8+ (but use iOS 13+ for modern APIs)
- [ ] Check in **Build Settings** > **iOS Deployment Target**

#### 4.2 Import Statements
- [ ] For Push Notifications:
  ```swift
  import UserNotifications
  ```
- [ ] For Live Activities:
  ```swift
  import ActivityKit
  ```

#### 4.3 App Delegate / App Lifecycle
- [ ] Set up `UNUserNotificationCenterDelegate` early in app lifecycle
- [ ] Request notification permissions
- [ ] Register for remote notifications
- [ ] Handle device token registration

---

### Part 5: Testing Prerequisites

#### 5.1 Physical Device
- [ ] **Live Activities require a physical device** (iOS 16.1+)
- [ ] **Push Notifications require a physical device** (simulator doesn't receive APNs)
- [ ] Device must be registered in your Apple Developer account

#### 5.2 Development vs Production
- [ ] **Development:**
  - [ ] Use development provisioning profile
  - [ ] `aps-environment` set to `development`
  - [ ] Use sandbox APNs server
- [ ] **Production:**
  - [ ] Use distribution provisioning profile
  - [ ] `aps-environment` set to `production`
  - [ ] Use production APNs server

---

### Part 6: Server/Backend Prerequisites

#### 6.1 APNs Configuration
- [ ] APNs Authentication Key (`.p8` file) downloaded
- [ ] Key ID noted (10 characters)
- [ ] Team ID noted (10 characters)
- [ ] Configure backend to use APNs with:
  - [ ] Key file (`.p8`)
  - [ ] Key ID
  - [ ] Team ID
  - [ ] Bundle ID: `com.semina.unheardpath`

#### 6.2 APNs Endpoints
- [ ] **Development:** `api.sandbox.push.apple.com:443`
- [ ] **Production:** `api.push.apple.com:443`

---

### Part 7: Verification Checklist

#### 7.1 Developer Portal
- [ ] App ID has Push Notifications enabled
- [ ] ⚠️ **ActivityKit does NOT need to be enabled in Developer Portal** (enabled via Info.plist/entitlements)
- [ ] APNs Authentication Key created and downloaded
- [ ] Provisioning profiles updated (or Automatic Signing enabled)

#### 7.2 Xcode
- [ ] Push Notifications capability added
- [ ] Background Modes added (if needed)
- [ ] Entitlements file correct
- [ ] Info.plist has `NSSupportsLiveActivities`
- [ ] Widget Extension created (if using custom UI)
- [ ] All targets have correct signing

#### 7.3 Code
- [ ] Import statements added
- [ ] Notification delegate implemented
- [ ] Permissions requested
- [ ] Device token registration handled

---

## Quick Reference: Key Values to Collect

Before starting, make sure you have:

1. **Team ID:** `ZMR9YNSJN2` (from your project)
2. **Bundle ID:** `com.semina.unheardpath`
3. **APNs Key ID:** (10 characters, from Developer Portal)
4. **APNs Key file:** `.p8` file (download once - save securely!)
5. **App Group ID:** `group.com.semina.unheardpath` (if using)

---

## Important Notes

1. **Live Activities require iOS 16.1+** and a physical device
2. **APNs Authentication Key (`.p8`) is REQUIRED** for Live Activities (not `.p12`)
3. **ActivityKit is NOT a capability:**
   - ❌ Does NOT appear in Apple Developer Portal capabilities
   - ❌ Does NOT appear in Xcode's "+ Capability" button
   - ✅ Enabled ONLY through entitlements file and Info.plist
4. **Provisioning Profile Issues:**
   - If you see "provisioning profile doesn't include ActivityKit entitlement" error, Xcode needs to regenerate the profile
   - See section 2.4.1 for detailed troubleshooting steps
   - This is a common issue and usually resolves after profile regeneration
5. **Test on physical device** - simulators don't support APNs or Live Activities
6. **SSL Certificates vs Authentication Keys:**
   - Use `.p8` Authentication Key for everything (recommended)
   - SSL Certificates (`.p12`) are legacy and don't work with Live Activities
   - You can click "Done" in the SSL Certificate modal if using `.p8` keys
7. **Broadcast Capability:** Only enable if you need to update multiple Live Activities with one push notification

---

## Troubleshooting

### Common Issues

**Issue:** "Push Notifications capability not available"
- **Solution:** Enable Push Notifications in Apple Developer Portal first, then add capability in Xcode

**Issue:** "ActivityKit not available" or "Provisioning profile doesn't include ActivityKit entitlement"
- **Solution:** 
  - Ensure iOS deployment target is 16.1+
  - Verify `NSSupportsLiveActivities` is set to `YES` in Info.plist
  - Verify `com.apple.developer.activitykit` entitlement is in entitlements file
  - **ActivityKit is NOT a capability** - it doesn't appear in Developer Portal or Xcode capability list
  - **For provisioning profile errors:** See section 2.4.1 for step-by-step fix
  - Xcode needs to regenerate the provisioning profile to include the entitlement

**Issue:** "APNs authentication failed"
- **Solution:** Verify `.p8` key file, Key ID, and Team ID are correct. Ensure key has APNs enabled.

**Issue:** "Live Activity not updating"
- **Solution:** Check that `NSSupportsLiveActivities` is in Info.plist, and ActivityKit entitlement is enabled

---

## Next Steps

After completing all prerequisites:

1. Implement `NotificationManager` for push notification handling
2. Implement `ActivityManager` for Live Activities management
3. Set up notification delegate in app lifecycle
4. Configure backend to send push notifications
5. Test on physical device

See the file structure guide for organizing the implementation code.


