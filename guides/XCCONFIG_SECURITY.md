# xcconfig File Security Guide

## Current Status

Your `.gitignore` currently ignores **all** `.xcconfig` files (`*.xcconfig` in `03_apps/iosapp/.gitignore`).

## Security Analysis

### ❌ **NOT Safe to Commit**

**`Config.xcconfig`** - Contains sensitive secrets:
- `SUPABASE_PUBLISHABLE_KEY` - Publishable key (meant to be public, but still sensitive)
- `POSTHOG_API_KEY` - API key (sensitive!)
- `MAPBOX_ACCESS_TOKEN` - Access token (sensitive!)
- `SUPABASE_PROJECT_URL` - Public URL (safe, but part of sensitive file)

**Status**: Already in `.gitignore` ✅ (line 107: `*.xcconfig`)

### ✅ **Safe to Commit**

**`Config.Dev.xcconfig`** - Contains:
- `IS_POSTHOG_TRACKING_ENABLED = NO` - Boolean flag (safe)
- `UHP_GATEWAY_BASE_URL = http://192.168.50.171:1031` - Local dev URL (safe, reveals local setup but not sensitive)

**`Config.Release.xcconfig`** - Contains:
- `IS_POSTHOG_TRACKING_ENABLED = YES` - Boolean flag (safe)
- `UHP_GATEWAY_BASE_URL = https://api.unheardpath.com` - Public production URL (safe)

## Recommended Approach

### Option 1: Commit Debug/Release, Ignore Base Config (Recommended)

Update `.gitignore` to be more specific:

```gitignore
# Configuration files with secrets
Config.plist
Config.xcconfig          # Base config with secrets - DO NOT COMMIT
!Config.Dev.xcconfig   # Safe to commit
!Config.Release.xcconfig # Safe to commit
*.p8
```

**Benefits:**
- Team can see environment-specific settings
- Secrets remain private
- Build configurations are version-controlled
- CI/CD can use the committed configs

### Option 2: Keep All Ignored (Current Setup)

Keep current `.gitignore` that ignores all `.xcconfig` files.

**Benefits:**
- Maximum security (nothing committed)
- Each developer maintains their own configs

**Drawbacks:**
- Team members need to create configs manually
- No version control for environment settings
- CI/CD needs configs provided another way

## Best Practice Recommendation

**Use Option 1** - Commit the environment-specific configs:

1. **Update `.gitignore`**:
   ```gitignore
   # Configuration files with secrets
   Config.plist
   Config.xcconfig          # Base config with secrets
   !Config.Dev.xcconfig   # Allow Dev config
   !Config.Release.xcconfig # Allow Release config
   *.p8
   ```

2. **Create `Config.xcconfig.example`** (commit this):
   ```xcconfig
   // Example configuration - copy to Config.xcconfig and fill in your values
   // DO NOT commit Config.xcconfig (it's in .gitignore)
   
   SUPABASE_PROJECT_URL = https://your-project.supabase.co
   SUPABASE_PUBLISHABLE_KEY = sb_publishable_YOUR_KEY_HERE
   POSTHOG_API_KEY = phc_YOUR_KEY_HERE
   POSTHOG_HOST = https://your-host.com/relay-XXX
   MAPBOX_ACCESS_TOKEN = pk.YOUR_TOKEN_HERE
   ```

3. **Document setup** in README:
   - Copy `Config.xcconfig.example` to `Config.xcconfig`
   - Fill in your values
   - `Config.xcconfig` is gitignored

## Current Files Status

| File | Contains Secrets? | Safe to Commit? | Currently Ignored? |
|------|------------------|----------------|-------------------|
| `Config.xcconfig` | ✅ Yes | ❌ No | ✅ Yes |
| `Config.Dev.xcconfig` | ❌ No | ✅ Yes | ✅ Yes (but shouldn't be) |
| `Config.Release.xcconfig` | ❌ No | ✅ Yes | ✅ Yes (but shouldn't be) |

## Summary

- **Config.xcconfig**: ❌ Never commit (contains API keys/tokens)
- **Config.Dev.xcconfig**: ✅ Safe to commit (no secrets)
- **Config.Release.xcconfig**: ✅ Safe to commit (no secrets)

**Action**: Update `.gitignore` to allow Debug/Release configs while keeping base Config.xcconfig ignored.

