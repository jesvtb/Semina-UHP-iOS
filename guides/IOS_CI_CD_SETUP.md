# iOS CI/CD Setup Guide

Complete guide for setting up and managing iOS app CI/CD for the Unheard Path app using GitHub Actions.

## Overview

This project uses **GitHub Actions** for automated iOS builds and TestFlight deployments. The workflow automatically builds, archives, exports, and uploads the app to TestFlight.

**Workflow File**: `.github/workflows/iosapp.yml`  
**Build Time**: ~20-35 minutes  
**Build Format**: `Major.Minor.Patch` (e.g., `1.0.2`)

## Prerequisites

- ✅ Apple Developer Program membership (active)
- ✅ App registered in App Store Connect
- ✅ App ID: `com.semina.unheardpath` with "Sign in with Apple" capability enabled

## Setup Steps

### Step 1: Create App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/) > **Users and Access** > **Keys**
2. Click **+** to create new API key
3. **Name**: "GitHub Actions CI/CD"
4. **Access Level**: **Admin** ⭐ (Required - has all permissions by default)
5. **Type**: Team Key (preferred) or Individual Key
6. Click **Generate**
7. **Download** the `.p8` file immediately (can only download once!)
8. **Note** the Key ID (shown in dialog)
9. **Note** the Issuer ID (shown at top of Keys page)

### Step 2: Configure GitHub Secrets

Go to GitHub repository > **Settings** > **Secrets and variables** > **Actions** and add:

#### App Store Connect (4 secrets)
- `APP_STORE_CONNECT_API_KEY_ID` - Key ID from Step 1
- `APP_STORE_CONNECT_ISSUER_ID` - Issuer ID from Step 1
- `APP_STORE_CONNECT_API_KEY` - Full contents of `.p8` file (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`)
- `APP_STORE_CONNECT_TEAM_ID` - Team ID (e.g., `ZMR9YNSJN2`)

#### App Configuration (7 secrets)
- `SUPABASE_PROJECT_URL` - Supabase project URL
- `SUPABASE_PUBLISHABLE_KEY` - Supabase publishable key
- `POSTHOG_API_KEY` - PostHog API key
- `POSTHOG_HOST` - PostHog host URL
- `MAPBOX_ACCESS_TOKEN` - Mapbox access token
- `UHP_GATEWAY_HOST_DEBUG` - Debug gateway host
- `UHP_GATEWAY_HOST_RELEASE` - Release gateway host

#### GitHub Access (1 secret)
- `GH_DEV_TOKEN` - GitHub personal access token with repo access (for submodule checkout)

### Step 3: Apple Developer Portal Setup

1. Go to [Apple Developer Portal](https://developer.apple.com/account/) > **Certificates, Identifiers & Profiles** > **Identifiers**
2. Find or create App ID: `com.semina.unheardpath`
3. Enable **Sign in with Apple** capability
4. Click **Save**
5. Wait 2-3 minutes for changes to propagate

**Note**: With Admin API key and automatic signing, Xcode will automatically create/use certificates and profiles. Manual certificate/profile creation is optional.

### Step 4: Self-hosted runner (macOS) – required if using self-hosted

The workflow uses **self-hosted** runners. The "Select Xcode version" step runs `sudo xcode-select -s /Applications/Xcode.app`. If the runner user does not have **passwordless sudo** for that command, `sudo` will wait for a password (there is no TTY in CI), and the step will **hang** (e.g. 8+ minutes) until the job times out.

**Fix:** On the Mac that hosts the runner, allow passwordless sudo for `xcode-select` for the **user the runner runs as** — this is often **not** your login username.

1. **Identify the runner user**  
   The workflow has a step "Show runner user (for sudoers)" that prints the effective user (e.g. `_runner`, `runner`, or your username). **Use that exact user in sudoers.** If you added your login user (e.g. `jessicaluo`) but the runner runs as another user, the NOPASSWD line will not apply and the step will still fail with "sudo: a password is required".

2. **Run the workflow once** (or check a recent run). In the "Show runner user (for sudoers)" step, note the printed user (e.g. `_runner` or `runner`). That is the user that needs the NOPASSWD line.

3. **Edit sudoers** on the runner Mac (log in as an admin and run):  
   ```bash
   sudo visudo
   ```

4. **Add one line** at the end (replace `RUNNER_USER` with the user from step 2, e.g. `_runner`):  
   ```text
   RUNNER_USER ALL=(ALL) NOPASSWD: /usr/bin/xcode-select
   ```  
   Save and exit (`Ctrl+O`, Enter, then `Ctrl+X` if using nano; or `:wq` in vim).

5. **Re-run the workflow.** The workflow invokes `sudo -n /usr/bin/xcode-select -s /Applications/Xcode.app` (full path so sudo matches the sudoers entry). The step should then succeed. To verify on the Mac as that user: `sudo -n /usr/bin/xcode-select -s /Applications/Xcode.app` should run without a password.

**Optional:** Ensure `/Applications/Xcode.app` is the correct path for the Xcode version you want. The workflow uses this path; if you use a versioned path (e.g. `Xcode_26.1.1.app`), update the step in `.github/workflows/iosapp.yml` to match.

### Step 5: Test the Workflow

1. Make a small change to iOS app code
2. Commit and push to `main` or `master` branch
3. Go to GitHub > **Actions** tab
4. Watch the workflow run
5. Verify Archive, Export, and Upload steps complete successfully
6. Check TestFlight in App Store Connect to verify build appears

## How It Works

### Build Process

1. **Checkout**: Repository and submodule checkout
2. **Config Generation**: Creates `Config.xcconfig` from GitHub Secrets
3. **Build Number**: Auto-increments using format `Major.Minor.Patch`
4. **Archive**: Builds and archives with automatic code signing
5. **Export**: Exports IPA file for App Store distribution
6. **Upload**: Uploads IPA to TestFlight using Transporter

### Code Signing

- **Method**: Automatic signing with App Store Connect API key
- **Certificate**: Automatically created/used by Xcode (type: "Apple Distribution")
- **Provisioning Profile**: Automatically created/used by Xcode
- **API Key Requirement**: Admin access level (has all permissions by default)

### Build Number Format

- **Format**: `[Major].[Minor].[Patch]` (e.g., `1.0.2`, `1.0.3`)
- **Major/Minor**: From `MARKETING_VERSION` in Xcode project
- **Patch**: Auto-increments using GitHub run number

**To change marketing version:**
1. Open Xcode project
2. Select **unheardpath** target > **General** tab
3. Update **Version** field (e.g., `1.0` to `0.1.0`)
4. Commit and push - workflow uses new version automatically

### TestFlight Distribution

**Internal Testing** (Immediate):
- Available to internal testers immediately after upload
- No approval required
- Up to 100 internal testers

**External Testing** (Requires Approval):
- Requires **Beta App Review** (24-48 hours)
- Submit in App Store Connect > TestFlight > Your App
- Up to 10,000 external testers

## Troubleshooting

### "Select Xcode version" step hangs or fails with "sudo: a password is required"
**Cause:** On self-hosted macOS runners, `sudo xcode-select` needs passwordless sudo for the **user the runner runs as**. If the user is wrong or the command path doesn't match sudoers, the step hangs (no `-n`) or fails with "a password is required" (with `-n`).

**Solution:**
1. Check **"Show runner user (for sudoers)"** in the workflow log — add a sudoers line for **that** user (e.g. `_runner` or `runner`), not necessarily your login user.
2. The sudoers line must be exactly: `RUNNER_USER ALL=(ALL) NOPASSWD: /usr/bin/xcode-select` (full path).
3. The workflow uses `sudo -n /usr/bin/xcode-select -s /Applications/Xcode.app` so the command path matches. See **Step 4: Self-hosted runner (macOS)** above.

### "Cloud signing permission error"
**Solution**: Verify API key has **Admin** access level (not App Manager or Developer)

### "No signing certificate found"
**Solution**: Ensure API key is **Admin** level. Automatic signing should create certificates automatically.

### "No profiles found"
**Solution**: Ensure API key is **Admin** level. Verify App ID has "Sign in with Apple" capability enabled.

### "Bundle version must be higher"
**Solution**: Build number auto-increments automatically. Verify workflow is using build number increment step.

### "No Builds Available" for External Testers
**Solution**: Submit build for Beta App Review in App Store Connect > TestFlight > Your App > External Testing > Submit for Review

## Master Checklist

### Prerequisites
- [ ] Apple Developer Program membership (active)
- [ ] App registered in App Store Connect
- [ ] App ID: `com.semina.unheardpath` exists
- [ ] "Sign in with Apple" capability enabled on App ID

### Step 1: App Store Connect API Key
- [ ] Go to App Store Connect > Users and Access > Keys
- [ ] Click **+** to create new API key
- [ ] Name: "GitHub Actions CI/CD"
- [ ] **Access Level: Admin** ⭐ (Required)
- [ ] Type: Team Key (preferred) or Individual Key
- [ ] Click Generate
- [ ] Download `.p8` file immediately
- [ ] Note Key ID
- [ ] Note Issuer ID

### Step 2: GitHub Secrets (12 total)
- [ ] `APP_STORE_CONNECT_API_KEY_ID` - Key ID
- [ ] `APP_STORE_CONNECT_ISSUER_ID` - Issuer ID
- [ ] `APP_STORE_CONNECT_API_KEY` - Full `.p8` file content (including BEGIN/END lines)
- [ ] `APP_STORE_CONNECT_TEAM_ID` - Team ID (e.g., `ZMR9YNSJN2`)
- [ ] `SUPABASE_PROJECT_URL` - Supabase project URL
- [ ] `SUPABASE_PUBLISHABLE_KEY` - Supabase publishable key
- [ ] `POSTHOG_API_KEY` - PostHog API key
- [ ] `POSTHOG_HOST` - PostHog host URL
- [ ] `MAPBOX_ACCESS_TOKEN` - Mapbox access token
- [ ] `UHP_GATEWAY_HOST_DEBUG` - Debug gateway host
- [ ] `UHP_GATEWAY_HOST_RELEASE` - Release gateway host
- [ ] `GH_DEV_TOKEN` - GitHub personal access token with repo access

### Step 3: Apple Developer Portal
- [ ] App ID: `com.semina.unheardpath` exists
- [ ] "Sign in with Apple" capability enabled
- [ ] Changes saved and propagated (wait 2-3 minutes)

### Step 4 (self-hosted only): Runner passwordless sudo
- [ ] Runner user has NOPASSWD for `/usr/bin/xcode-select` in sudoers
- [ ] Path `/Applications/Xcode.app` exists on runner (or workflow step updated to your Xcode path)

### Step 5: Workflow Verification
- [ ] Workflow file exists: `.github/workflows/iosapp.yml`
- [ ] Workflow configured for automatic signing
- [ ] Build number auto-increment configured

### Step 6: Test Workflow
- [ ] Make small change to iOS app code
- [ ] Commit and push to `main` or `master` branch
- [ ] Go to GitHub > Actions tab
- [ ] Watch workflow run
- [ ] Archive step completes successfully
- [ ] Export step completes successfully
- [ ] Upload to TestFlight completes successfully
- [ ] Build appears in TestFlight (App Store Connect)

### Verification
- [ ] All 12 GitHub Secrets configured
- [ ] API key has **Admin** access level
- [ ] API key is Team Key (preferred) or Individual Key
- [ ] App ID has "Sign in with Apple" capability
- [ ] Workflow completes without errors
- [ ] Build appears in TestFlight

## Quick Reference

**Workflow**: `.github/workflows/iosapp.yml`  
**Required Secrets**: 12 total (4 App Store Connect + 7 App Config + 1 GitHub)  
**Build Time**: ~20-35 minutes  
**Build Format**: `Major.Minor.Patch` (e.g., `1.0.2`)  
**API Key**: Admin access level required ⭐  
**Code Signing**: Automatic (via API key)

---

**Last Updated**: Based on verified working configuration with Admin API key and automatic signing.
