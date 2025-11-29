# Google Sign-In Setup Guide for iOS App

Quick reference guide for setting up Google authentication with Supabase on iOS.

## Overview

1. **Google Cloud Console**: Create Web Application OAuth credentials
2. **Supabase Dashboard**: Configure Google provider
3. **Xcode Project**: Add URL scheme
4. **Code**: Already implemented ✅

---

## Step 1: Google Cloud Console

### 1.1 Create OAuth Consent Screen

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. **APIs & Services** > **OAuth consent screen**
3. Choose **External**
4. Fill in app name, support email, developer contact
5. Add scopes: `openid` (add manually), `email`, `profile` (these are added by default)
6. Save and continue through all steps

### 1.2 Setup Branding (Strongly Recommended)

According to [Supabase documentation](https://supabase.com/docs/guides/auth/social-login/auth-google), branding setup is **strongly recommended** to improve user trust and prevent phishing.

**Why it matters**: Without branding, users will see `<project-id>.supabase.co` in the consent screen, which doesn't inspire trust.

1. Go to **Google Auth Platform** > **Branding** section
2. **App logo**: Upload your app logo (square, 120px × 120px, max 1MB, JPG/PNG/BMP)
3. **App domain** (optional but recommended):
   - **Application home page**: Your website URL (e.g., `https://unheardpath.com`)
   - **Application privacy policy link**: Your privacy policy URL
   - **Application terms of service link**: Your terms of service URL
4. **Authorized domains**: Add your domain(s) (e.g., `unheardpath.com`)
   - This is required if you use your domain in the consent screen
   - You can add multiple domains if needed

**Note**: Brand verification may take a few business days, but you can still use OAuth during testing without verification.

### 1.3 Create Web Application OAuth Client

**Important**: Use **Web Application** type (not iOS app) because Supabase handles OAuth on their web backend.

1. **APIs & Services** > **Credentials** > **Create Credentials** > **OAuth client ID**
2. Select **Web application** (⚠️ NOT "iOS app") - Supabase handles OAuth on their web backend
3. Fill in:
   - **Name**: Unheard Path Web (for Supabase)
   - **Authorized JavaScript origins**: Add your application's URL if you have one (optional for iOS-only apps)
   - **Authorized redirect URIs**: `https://mrrssxdxblwhdsejdlxp.supabase.co/auth/v1/callback`
     - Get this URL from Supabase Dashboard > Authentication > Providers > Google
4. Click **Create**
5. **Save** Client ID and Client Secret to your `.env` file:
   - `GOOGLE_SUPABASE_UHP_CLIENT_ID` = Your Client ID
   - `GOOGLE_SUPABASE_UHP_CLIENT_SECRET` = Your Client Secret

---

## Step 2: Supabase Dashboard

1. Go to [Supabase Dashboard](https://app.supabase.com/) > Your project
2. **Authentication** > **Providers** > **Google**
3. Configure:
   - **Enable Sign in with Google**: Toggle **ON**
   - **Client IDs**: Value from `GOOGLE_SUPABASE_UHP_CLIENT_ID` in your `.env`
   - **Client Secret**: Value from `GOOGLE_SUPABASE_UHP_CLIENT_SECRET` in your `.env`
   - **Callback URL**: Should auto-populate (verify it matches Google Console)
4. Click **Save**

---

## Step 3: Xcode URL Scheme

1. Open project in Xcode
2. Select project > **unheardpath** target > **Info** tab
3. Expand **URL Types** > Click **+**
4. Configure:
   - **Identifier**: `unheardpath`
   - **URL Schemes**: `unheardpath`
   - **Role**: Editor
5. Save

**Verify**: Build and run app, then test in Safari: `unheardpath://login-callback` (should open your app)

---

## Step 4: Code (Already Done ✅)

- `AuthView.swift`: Google Sign-In button and handler
- `unheardpathApp.swift`: URL handling for OAuth callbacks
- Redirect URL: `unheardpath://login-callback`

---

## Testing

1. Build and run app
2. Tap "Sign in with Google"
3. Safari opens → Google sign-in → Redirects back to app
4. App should authenticate successfully

---

## Troubleshooting

**"Invalid characters" in Supabase**: Copy Client ID/Secret without extra spaces

**"PKCE flow URL" error**: Clean build folder (`Cmd + Shift + K`) and verify URL scheme in Xcode

**Redirect not working**: Verify URL scheme is `unheardpath` in Xcode Info tab

---

## Checklist

- [ ] OAuth consent screen configured
- [ ] Required scopes added: `openid`, `email`, `profile`
- [ ] **Branding configured** (strongly recommended - logo, app domain, authorized domains)
- [ ] Web Application OAuth client created
- [ ] Authorized redirect URI set to Supabase callback URL
- [ ] `GOOGLE_SUPABASE_UHP_CLIENT_ID` saved to `.env`
- [ ] `GOOGLE_SUPABASE_UHP_CLIENT_SECRET` saved to `.env`
- [ ] Supabase Google provider enabled
- [ ] Client ID and Secret added to Supabase
- [ ] URL scheme `unheardpath` configured in Xcode
- [ ] Tested authentication flow

---

## Environment Variables

Add these to your `.env` file:

```bash
# Google OAuth
GOOGLE_SUPABASE_UHP_CLIENT_ID="your-client-id-here"
GOOGLE_SUPABASE_UHP_CLIENT_SECRET="your-client-secret-here"
```

---

## Notes

- Only **Web Application** OAuth client needed (not iOS app client)
- URL scheme: `unheardpath://login-callback`
- OAuth flow opens Safari, then redirects back to app
- **Branding is strongly recommended** per [Supabase docs](https://supabase.com/docs/guides/auth/social-login/auth-google) to avoid showing `<project-id>.supabase.co` to users
- For testing, branding can be skipped, but users will see the Supabase project ID which may reduce trust
