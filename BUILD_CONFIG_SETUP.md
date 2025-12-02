# Build Configuration Setup Guide

This guide explains how to set up environment-specific configurations for Debug (local dev) and Release (TestFlight/Production) builds.

## Overview

We use Xcode Build Configurations with `.xcconfig` files to manage different settings:
- **Debug**: Local development (PostHog disabled, local API)
- **Release**: Production/TestFlight (PostHog enabled, production API)

## Files Created

1. `Config.Debug.xcconfig` - Debug/development settings
2. `Config.Release.xcconfig` - Release/production settings
3. `Config.xcconfig` - Base configuration (shared secrets)

## Setup Steps in Xcode

### 1. Add Config Files to Xcode Project

1. Open Xcode
2. Right-click on the project root in the navigator
3. Select "Add Files to 'unheardpath'..."
4. Select both `Config.Debug.xcconfig` and `Config.Release.xcconfig`
5. Ensure "Copy items if needed" is **unchecked** (files are already in the right place)
6. Click "Add"

### 2. Configure Build Settings

1. Select the project in the navigator
2. Select the **unheardpath** target
3. Go to **Build Settings** tab
4. Search for "Configuration File" or "baseConfigurationReference"
5. For **Debug** configuration:
   - Set "Configuration File" to `Config.Debug.xcconfig`
6. For **Release** configuration:
   - Set "Configuration File" to `Config.Release.xcconfig`

### 3. Add Info.plist Injection Keys

In the **Build Settings** for the **unheardpath** target, add these to both Debug and Release:

1. Search for "Info.plist" or find "INFOPLIST_KEY_*" entries
2. Add these new entries:
   - `INFOPLIST_KEY_IsPosthogTracking` = `$(IS_POSTHOG_TRACKING_ENABLED)`
   - `INFOPLIST_KEY_UHPGatewayBaseURL` = `$(UHP_GATEWAY_BASE_URL)`

**Note**: The values use `$(VARIABLE_NAME)` syntax to reference the variables from `.xcconfig` files.

### 4. Remove Hardcoded Values from Info.plist

Remove these keys from `Info.plist` (they'll be injected via build settings):
- `IsPosthogTracking`
- `UHPGatewayBaseURL`

## How It Works

1. **Debug builds** use `Config.Debug.xcconfig`:
   - `IS_POSTHOG_TRACKING_ENABLED = NO`
   - `UHP_GATEWAY_BASE_URL = http://192.168.50.171:1031`

2. **Release builds** use `Config.Release.xcconfig`:
   - `IS_POSTHOG_TRACKING_ENABLED = YES`
   - `UHP_GATEWAY_BASE_URL = https://api.unheardpath.com`

3. Build settings inject these into `Info.plist` at build time via `INFOPLIST_KEY_*`

4. Code reads from `Info.plist` at runtime

## Benefits

✅ No manual Info.plist modification during CI/CD  
✅ Configuration managed in version-controlled `.xcconfig` files  
✅ Clear separation between Debug and Release settings  
✅ Type-safe configuration (Xcode validates at build time)  
✅ Easy to add new environments (staging, etc.)

## Verification

After setup, verify:
1. Build in Debug mode → Check `IsPosthogTracking` should be `false` in Info.plist
2. Build in Release mode → Check `IsPosthogTracking` should be `true` in Info.plist
3. CI/CD builds use Release configuration automatically

