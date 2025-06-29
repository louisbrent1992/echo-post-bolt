# YouTube Data API v3 Setup Guide - Unified Project Approach

## Problem Resolution
You're getting a 403 error because YouTube Data API v3 is not enabled in your Firebase project (794380832661). The solution is to enable YouTube Data API v3 in your existing Firebase project rather than creating separate projects.

## Step 1: Enable YouTube Data API v3 in Your Existing Firebase Project

1. **Go to Google Cloud Console**: https://console.cloud.google.com/
2. **Select Your Firebase Project**: `echopost-f0b99` (Project ID: 794380832661)
3. **Navigate to APIs & Services > Library**
4. **Search for "YouTube Data API v3"**
5. **Click on "YouTube Data API v3"**
6. **Click "ENABLE"**

## Step 2: Configure OAuth Consent Screen (If Not Already Done)

1. **Go to APIs & Services > OAuth consent screen**
2. **Select "External" user type** (unless you have Google Workspace)
3. **Fill in required fields**:
   - App name: `EchoPost`
   - User support email: Your email
   - Developer contact email: Your email
4. **Add scopes** (click "ADD OR REMOVE SCOPES"):
   - `https://www.googleapis.com/auth/youtube`
   - `https://www.googleapis.com/auth/youtube.upload`
   - `https://www.googleapis.com/auth/youtube.readonly`
5. **Add test users** (during development phase)
6. **Save and Continue**

## Step 3: Verify Your OAuth 2.0 Client IDs

Your existing OAuth client should work for YouTube. Verify in **APIs & Services > Credentials**:

1. **Web Application Client** (if you have one):
   - Should include YouTube scopes
   - Authorized redirect URIs should include your app's scheme

2. **Android Application Client**:
   - Package name: `com.example.echopost`
   - SHA-1 certificate fingerprint should be configured

3. **iOS Application Client**:
   - Bundle ID: `com.example.echopost`

## Step 4: Update Your Environment Variables

Your current setup should work. Verify these are set in your `.env.local`:

```env
# Firebase/Google Configuration
GOOGLE_WEB_CLIENT_ID=794380832661-62e0bds0d8rq1ne4fuq10jlht0brr7g8.apps.googleusercontent.com

# YouTube API Key (for read-only operations)
YOUTUBE_API_KEY=your_youtube_api_key_here
```

## Step 5: Test the Integration

Your existing `YouTubeAuthService` should now work without modifications. The key lines that will now succeed:

```dart
// This will now work because YouTube Data API v3 is enabled
final response = await http.get(
  Uri.parse('https://www.googleapis.com/youtube/v3/channels').replace(
    queryParameters: {
      'part': 'id,snippet,statistics',
      'mine': 'true',
    },
  ),
  headers: {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  },
);
```

## Benefits of Unified Project Approach

1. **Simplified Management**: One project to manage all APIs
2. **Shared Quotas**: More efficient quota utilization across services
3. **Consistent Billing**: All API costs in one place
4. **Google's Recommendation**: This is the preferred architecture
5. **Single OAuth Consent**: Users only consent to your app once

## Testing Checklist

- [ ] YouTube Data API v3 enabled in Firebase project
- [ ] OAuth consent screen configured with YouTube scopes
- [ ] App tested with YouTube authentication
- [ ] Channel information retrieval working
- [ ] Video upload capability verified

## Troubleshooting

If you still encounter issues after enabling the API:

1. **Clear app cache/data** to force fresh authentication
2. **Revoke existing tokens** in Google Account settings
3. **Wait 5-10 minutes** for API enablement to propagate
4. **Check quotas** in Google Cloud Console to ensure you haven't hit limits

## Alternative: Separate Projects (Not Recommended)

If you absolutely need separate projects (not recommended):

1. Create new Google Cloud project for YouTube only
2. Configure separate OAuth credentials
3. Modify `YouTubeAuthService` to use different `serverClientId`
4. Manage two sets of credentials and consent flows

This approach adds complexity without significant benefits and goes against Google's best practices. 