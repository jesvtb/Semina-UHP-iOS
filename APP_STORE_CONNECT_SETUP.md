# App Store Connect API Setup Guide

This guide walks you through obtaining the App Store Connect API credentials needed for the TestFlight deployment workflow.

## Required Credentials

The workflow needs these 4 values (stored as GitHub Secrets):

1. **APP_STORE_CONNECT_API_KEY_ID** - The Key ID
2. **APP_STORE_CONNECT_ISSUER_ID** - The Issuer ID  
3. **APP_STORE_CONNECT_API_KEY** - The .p8 private key file content
4. **APP_STORE_CONNECT_TEAM_ID** - Your development team ID (optional, defaults to ZMR9YNSJN2)

### Naming Convention Reference

**For local .env file (reference only):**
- `APP_STORE_CONNECT_GITHUB_ACTION_KEY_ID` → Maps to GitHub Secret: `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_GITHUB_ACTION_P8_API_KEY_FILEPATH` → Maps to GitHub Secret: `APP_STORE_CONNECT_API_KEY` (file content, not filepath)

**Note**: The GitHub Secrets must use the exact names shown above for the workflow to work. The .env file names are for local reference/documentation only.

## Step-by-Step Instructions

### Step 1: Access App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Sign in with your Apple Developer account
3. Ensure you have **Admin** or **App Manager** role (required to create API keys)

### Step 2: Navigate to API Keys

1. Click on your name/account in the top right
2. Select **Users and Access** from the dropdown
3. Click on the **Keys** tab
4. You'll see a list of existing API keys (if any)

### Step 3: Create a New API Key

**Important: Team Key vs Individual Key**

- **Team Key** (Recommended for CI/CD): 
  - Created at the organization/team level
  - Not tied to a specific individual user
  - Better for CI/CD because it persists if team members change
  - Access is controlled by the team/organization
  
- **Individual Key**:
  - Tied to your personal Apple Developer account
  - If you leave the team, the key becomes invalid
  - Less ideal for CI/CD

**For GitHub Actions, use a Team Key if available.**

1. Click the **+** (plus) button or **Generate API Key** button
2. Enter a **Key Name** (e.g., "GitHub Actions TestFlight", "CI/CD Key")
3. Select **Access Level**: **App Manager** ⭐ (Required for TestFlight, don't use Admin or Developer)   
4. Click **Generate**

**Note**: If you see an option to choose between "Team Key" and "Individual Key", select **Team Key** for CI/CD purposes.

### Step 4: Download and Save the Private Key

⚠️ **IMPORTANT**: You can only download the .p8 file **once**. Save it immediately!

1. After clicking Generate, a dialog will appear
2. Click **Download API Key** button
3. The file will be named: `AuthKey_[KEY_ID].p8`
   - Example: `AuthKey_ABC123XYZ.p8`
4. **Save this file securely** - you cannot download it again!
5. Note the **Key ID** shown in the dialog (you'll need this)

### Step 5: Get the Issuer ID

1. Still in the **Keys** tab, look at the top of the page
2. You'll see **Issuer ID** displayed (format: UUID like `12345678-1234-1234-1234-123456789012`)
3. Copy this value - you'll need it

### Step 6: Get Your Team ID (Optional)

1. In App Store Connect, go to **Users and Access** → **Membership** tab
2. Look for **Team ID** (format: 10-character alphanumeric like `ZMR9YNSJN2`)
3. Or check in Xcode: **Preferences** → **Accounts** → Select your Apple ID → View Details
4. The Team ID is shown there

**Note**: If you don't set this secret, the workflow defaults to `ZMR9YNSJN2`

### Step 7: Extract the .p8 File Content

You need to get the **contents** of the .p8 file (not the file itself) for the GitHub secret.

1. Open the `.p8` file in a text editor
2. Copy the entire contents (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`)

The content should look like:
```
-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg...
(many lines of base64 encoded text)
...
-----END PRIVATE KEY-----
```

### Step 8: Add Secrets to GitHub

**Note**: GitHub Secrets must use these exact names (they're referenced in the workflow). For local .env file reference, see the naming convention section above.

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** for each value:

#### Secret 1: APP_STORE_CONNECT_API_KEY_ID
- **GitHub Secret Name**: `APP_STORE_CONNECT_API_KEY_ID` (required - exact name)
- **.env Reference**: `APP_STORE_CONNECT_GITHUB_ACTION_KEY_ID`
- **Value**: The Key ID from Step 4 (e.g., `ABC123XYZ`)
- Click **Add secret**

#### Secret 2: APP_STORE_CONNECT_ISSUER_ID
- **GitHub Secret Name**: `APP_STORE_CONNECT_ISSUER_ID` (required - exact name)
- **Value**: The Issuer ID from Step 5 (e.g., `12345678-1234-1234-1234-123456789012`)
- Click **Add secret**

#### Secret 3: APP_STORE_CONNECT_API_KEY
- **GitHub Secret Name**: `APP_STORE_CONNECT_API_KEY` (required - exact name)
- **.env Reference**: `APP_STORE_CONNECT_GITHUB_ACTION_P8_API_KEY_FILEPATH`
- **Value**: The **entire contents** of the .p8 file from Step 7 (including BEGIN/END lines)
- **Important**: Despite the .env name suggesting "filepath", this secret must contain the **file content**, not a filepath
- Click **Add secret**

#### Secret 4: APP_STORE_CONNECT_TEAM_ID (Optional)
- **Name**: `APP_STORE_CONNECT_TEAM_ID`
- **Value**: Your Team ID from Step 6 (e.g., `ZMR9YNSJN2`)
- Click **Add secret**
- **Note**: If you don't add this, the workflow will use the default `ZMR9YNSJN2`

### Step 9: Verify Secrets Are Set

1. In GitHub, go to **Settings** → **Secrets and variables** → **Actions**
2. You should see all 4 secrets listed:
   - ✅ `APP_STORE_CONNECT_API_KEY_ID`
   - ✅ `APP_STORE_CONNECT_ISSUER_ID`
   - ✅ `APP_STORE_CONNECT_API_KEY`
   - ✅ `APP_STORE_CONNECT_TEAM_ID` (optional)

### Step 10: Test the Workflow

1. Push a change to `main` or `master` branch (or trigger manually)
2. Go to **Actions** tab in GitHub
3. Watch the workflow run
4. Check the logs to verify:
   - Archive step completes
   - Export step completes
   - Upload step completes successfully

## Troubleshooting

### "Invalid API Key" Error
- Verify the .p8 file content was copied correctly (including BEGIN/END lines)
- Check for extra spaces or line breaks
- Ensure the Key ID matches the .p8 filename

### "Unauthorized" Error
- Verify the API key has **App Manager** or **Admin** access
- Check that the Issuer ID is correct
- Ensure the Team ID matches your Apple Developer account

### "Key Not Found" Error
- Verify the Key ID is correct
- Check that the API key hasn't been revoked in App Store Connect

### Can't Find Issuer ID
- It's displayed at the top of the **Keys** tab in App Store Connect
- It's the same for all API keys in your account

### Lost the .p8 File
- You **cannot** re-download it
- You'll need to:
  1. Revoke the old key in App Store Connect
  2. Create a new API key
  3. Download and save the new .p8 file
  4. Update the GitHub secrets with the new values

## Security Best Practices

- [ ] **Never commit** the .p8 file to git
- [ ] Store it securely (password manager, encrypted storage)
- [ ] Use **App Manager** access level (not Admin) for CI/CD
- [ ] Rotate keys periodically
- [ ] Revoke unused keys
- [ ] Use GitHub Secrets (not environment variables in code)

## Quick Reference

### GitHub Secrets (Required for Workflow)

| GitHub Secret Name | .env Reference Name | Where to Find | Example Value |
|-------------------|---------------------|---------------|---------------|
| `APP_STORE_CONNECT_API_KEY_ID` | `APP_STORE_CONNECT_GITHUB_ACTION_KEY_ID` | API key dialog after creation | `ABC123XYZ` |
| `APP_STORE_CONNECT_ISSUER_ID` | (no .env equivalent) | Top of Keys tab | `12345678-1234-1234-1234-123456789012` |
| `APP_STORE_CONNECT_API_KEY` | `APP_STORE_CONNECT_GITHUB_ACTION_P8_API_KEY_FILEPATH` | Contents of .p8 file | `-----BEGIN PRIVATE KEY-----...` |
| `APP_STORE_CONNECT_TEAM_ID` | (no .env equivalent) | Membership tab or Xcode | `ZMR9YNSJN2` |

**Important**: 
- GitHub Secrets must use the exact names in the left column (workflow requirement)
- The .env file names are for local reference/documentation only
- The `APP_STORE_CONNECT_API_KEY` secret should contain the **file content** (not filepath), despite the .env name suggesting filepath

## Next Steps

Once all secrets are configured:
1. The workflow will automatically use them when triggered
2. No code changes needed - secrets are injected at runtime
3. Test by pushing to `main`/`master` or using manual workflow dispatch

