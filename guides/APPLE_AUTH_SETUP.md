# Apple Sign-In Setup Guide for iOS App

Quick reference guide for setting up Apple authentication with Supabase on iOS.

## Overview

1. **Apple Developer Portal**: Create App ID, Service ID, and Key ID
2. **Supabase Dashboard**: Configure Apple provider
3. **Xcode Project**: Enable Sign in with Apple capability
4. **Code**: Already implemented ✅

---

## Why Two Identifiers?

- **App ID** (`com.semina.unheardpath`): For native iOS Sign in with Apple
- **Service ID** (`com.semina.unheardpath.web`): For Supabase backend to verify tokens

Both are required.

---

## Step 1: Apple Developer Portal

### 1.1 Enable Sign in with Apple on App ID (REQUIRED FIRST)

**⚠️ CRITICAL**: Do this BEFORE creating Service ID.

1. [Apple Developer Portal](https://developer.apple.com/account/) > **Certificates, Identifiers & Profiles** > **Identifiers**
2. Find or create App ID: `com.semina.unheardpath`
3. Check **Sign in with Apple** capability
4. Click **Save**
5. Wait 2-3 minutes for changes to propagate

### 1.2 Create Service ID

1. **Identifiers** > Click **+** > **Services IDs** > **Continue**
2. Fill in:
   - **Description**: Unheard Path Web (for Supabase)
   - **Identifier**: Value for `APPLE_SUPABASE_UHP_SERVICE_ID` (e.g., `com.semina.unheardpath.supabase`)
3. Click **Continue** > **Register**
4. **Save** the Service ID to your `.env` file as `APPLE_SUPABASE_UHP_SERVICE_ID`

### 1.3 Configure Service ID

1. Click on the Service ID you created
2. Check **Sign in with Apple** > Click **Configure**
3. Configure:
   - **Primary App ID**: Select `com.semina.unheardpath` (should be available now)
   - **Domains and Subdomains**: `mrrssxdxblwhdsejdlxp.supabase.co`
   - **Return URLs**: `https://mrrssxdxblwhdsejdlxp.supabase.co/auth/v1/callback`
4. Click **Next** > **Save** > **Continue** > **Save**

### 1.4 Create Key ID

1. **Certificates, Identifiers & Profiles** > **Keys** > Click **+**
2. Fill in:
   - **Key Name**: Unheard Path Apple Auth Key
   - Check **Sign in with Apple**
3. Click **Continue** > **Register**
4. **⚠️ CRITICAL**: Download the `.p8` file (only chance to download)
5. **Note the Key ID** and save to your `.env` file as `APPLE_SUPABASE_UHP_AUTH_KEY_ID` (e.g., `GP8NFX44F7`)
6. Click **Done**

### 1.5 Generate OAuth Secret Key

Use the provided shell script:

```bash
cd /Users/jessicaluo/FileServer/2_BUSINESS/21_JessPro/04_Project/Semina/03_apps/iosapp
./generate_apple_secret.sh
```

Enter when prompted:
- **Team ID**: Found in Apple Developer account (top right, e.g., `ZMR9YNSJN2`)
- **Key ID**: Value from `APPLE_SUPABASE_UHP_AUTH_KEY_ID` in your `.env`
- **Service ID**: Value from `APPLE_SUPABASE_UHP_SERVICE_ID` in your `.env`
- **Path to .p8 file**: Full path to downloaded key file

**Save the generated secret** to your `.env` file as `APPLE_SUPABASE_UHP_OATH_SECRET_KEY` and paste it into Supabase in Step 2.

**⚠️ Important**: Secret expires every 6 months. Set a reminder to regenerate.

---

## Step 2: Supabase Dashboard

1. [Supabase Dashboard](https://app.supabase.com/) > Your project
2. **Authentication** > **Providers** > **Apple**
3. Configure:
   - **Enable Sign in with Apple**: Toggle **ON**
   - **Client IDs**: **IMPORTANT** - For native iOS apps, you must include BOTH:
     - Service ID: Value from `APPLE_SUPABASE_UHP_SERVICE_ID` in your `.env` (e.g., `com.semina.unheardpath.supabase`)
     - App ID (Bundle Identifier): `com.semina.unheardpath`
     - Format: `com.semina.unheardpath.supabase,com.semina.unheardpath` (comma-separated)
     - **Why?** Native iOS Sign in with Apple uses the App ID as the audience in the ID token, while web OAuth uses the Service ID. Supabase needs both to accept tokens from both sources.
   - **Secret Key**: Value from `APPLE_SUPABASE_UHP_OATH_SECRET_KEY` in your `.env`
   - **Callback URL**: Should auto-populate (verify it matches Apple Developer Portal)
4. Click **Save**

---

## Step 3: Xcode Configuration

### 3.1 Enable Sign in with Apple Capability

**⚠️ IMPORTANT**: Must enable on App ID first (Step 1.1). If capability doesn't appear, complete Step 1.1 and wait a few minutes.

1. Xcode > Select project > **unheardpath** target > **Signing & Capabilities** tab
2. Click **+ Capability**
3. Search for "Sign in with Apple" and add it

**If it doesn't appear**:
- Verify App ID has Sign in with Apple enabled (Step 1.1)
- **Xcode** > **Preferences** > **Accounts** > Select Apple ID > **Download Manual Profiles**
- Restart Xcode and try again

---

## Step 4: Code (Already Done ✅)

- `AuthView.swift`: Apple Sign-In button with nonce support and full name capture
- Native `SignInWithAppleButton` implementation
- Handles first-sign-in name capture and saves to user metadata

---

## Testing

1. **Build and run on a REAL iOS device** (doesn't work in simulator)
2. Tap "Sign in with Apple"
3. Apple sign-in sheet appears → Authenticate → App authenticates with Supabase

---

## Troubleshooting

**Error 1000**: 
- Verify capability is enabled in Xcode
- Verify App ID has Sign in with Apple enabled in Apple Developer Portal
- Test on real device (not simulator)

**Secret key expired**: Regenerate using `generate_apple_secret.sh`, update `APPLE_SUPABASE_UHP_OATH_SECRET_KEY` in `.env`, and update in Supabase

**Capability doesn't appear**: Complete Step 1.1 first, wait a few minutes, download profiles in Xcode

---

## Checklist

- [ ] App ID created with Sign in with Apple enabled
- [ ] Service ID created and `APPLE_SUPABASE_UHP_SERVICE_ID` saved to `.env`
- [ ] Key ID created, `.p8` file downloaded, and `APPLE_SUPABASE_UHP_AUTH_KEY_ID` saved to `.env`
- [ ] OAuth secret generated using shell script and `APPLE_SUPABASE_UHP_OATH_SECRET_KEY` saved to `.env`
- [ ] Supabase Apple provider enabled
- [ ] Service ID and Secret Key added to Supabase (from `.env` values)
- [ ] Sign in with Apple capability added in Xcode
- [ ] Tested on real iOS device
- [ ] Calendar reminder set for secret renewal (5.5 months)

---

## Important Notes

- **Secret expires every 6 months** - must regenerate
- **Test on real device** - simulator doesn't support Sign in with Apple
- **App Store requirement**: If you offer other third-party sign-in, Apple Sign-In is required
- **Full name**: Only provided on first sign-in - code captures and saves it automatically

---

## Environment Variables

Add these to your `.env` file:

```bash
# Apple OAuth
APPLE_SUPABASE_UHP_SERVICE_ID="com.semina.unheardpath.supabase"
APPLE_SUPABASE_UHP_AUTH_KEY_ID="your-key-id-here"
APPLE_SUPABASE_UHP_OATH_SECRET_KEY="your-jwt-token-here"
```

**Note**: `APPLE_SUPABASE_UHP_OATH_SECRET_KEY` expires every 6 months and must be regenerated.

---

## Resources

- [Supabase Apple Auth Docs](https://supabase.com/docs/guides/auth/social-login/auth-apple?queryGroups=environment&environment=client&queryGroups=platform&platform=swift)
- [Apple Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)
