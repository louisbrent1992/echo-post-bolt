# YouTube Data API v3 Setup Guide - Complete Fix for 401 Error

## Problem Resolution
You're getting a 401 error because YouTube Data API v3 is not properly configured or the OAuth 2.0 credentials are not being passed correctly. This guide provides a complete solution.

## Step 1: Enable YouTube Data API v3 in Your Firebase Project

1. **Go to Google Cloud Console**: https://console.cloud.google.com/
2. **Select Your Firebase Project**: `echopost-f0b99` (Project ID: 794380832661)
3. **Navigate to APIs & Services > Library**
4. **Search for "YouTube Data API v3"**
5. **Click on "YouTube Data API v3"**
6. **Click "ENABLE"**
7. **Wait 5-10 minutes for the API to be fully enabled**

## Step 2: Configure OAuth Consent Screen

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
   - `https://www.googleapis.com/auth/youtube.force-ssl`
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

## Step 4: Create Environment Configuration

Create a `.env.local` file in your project root with:

```env
# OpenAI API (Required for voice transcription)
OPENAI_API_KEY=your_openai_api_key_here

# YouTube API Key (for read-only operations and quota management)
YOUTUBE_API_KEY=your_youtube_api_key_here

# Twitter Authentication
TWITTER_CLIENT_ID=your_twitter_client_id_here
TWITTER_CLIENT_SECRET=your_twitter_client_secret_here
TWITTER_REDIRECT_URI=echopost://twitter-callback

# TikTok Authentication
TIKTOK_CLIENT_KEY=your_tiktok_client_key_here
TIKTOK_CLIENT_SECRET=your_tiktok_client_secret_here
```

## Step 5: Get YouTube API Key (Optional but Recommended)

1. **Go to APIs & Services > Credentials**
2. **Click "CREATE CREDENTIALS" > "API Key"**
3. **Copy the API key**
4. **Add it to your `.env.local` file as `YOUTUBE_API_KEY`**

## Step 6: Test the Integration

### Clear App Data and Re-authenticate

1. **Clear app cache/data** to force fresh authentication
2. **Uninstall and reinstall the app** if needed
3. **Sign out of Google** in your device settings
4. **Sign back in** with your Google account

### Test YouTube Authentication

1. **Open the app**
2. **Tap the YouTube icon** in the platform selection
3. **Complete the OAuth flow**
4. **Verify authentication state updates**
5. **Check Firestore for stored tokens**

### Test Video Upload

1. **Create a new post with a video**
2. **Select YouTube as the platform**
3. **Attempt to upload**
4. **Check the debug logs** for detailed information

## Step 7: Debug Common Issues

### 401 Authentication Error

**Symptoms**: "The request had invalid authentication credentials"

**Solutions**:
1. **Re-authenticate with YouTube**: Sign out and sign back in
2. **Check OAuth consent screen**: Ensure YouTube scopes are added
3. **Verify API is enabled**: YouTube Data API v3 must be enabled
4. **Check token expiration**: YouTube tokens expire in 1 hour

### 403 Forbidden Error

**Symptoms**: "Access denied" or "API not enabled"

**Solutions**:
1. **Enable YouTube Data API v3** in Google Cloud Console
2. **Check OAuth consent screen** configuration
3. **Verify API quotas** haven't been exceeded
4. **Wait 5-10 minutes** after enabling the API

### File Not Found Error

**Symptoms**: "Video file does not exist"

**Solutions**:
1. **Check file path** is correct and accessible
2. **Verify file permissions** on the device
3. **Ensure file exists** before upload attempt
4. **Use absolute file paths** when possible

## Step 8: Monitor API Usage

1. **Go to Google Cloud Console > APIs & Services > Dashboard**
2. **Click on "YouTube Data API v3"**
3. **Monitor quota usage** and requests
4. **Set up alerts** for quota limits

## Step 9: Production Considerations

### Quota Management
- **Daily quota**: 10,000 units per day (default)
- **Upload quota**: 1,600 uploads per day
- **Monitor usage** and request quota increases if needed

### Security Best Practices
- **Never commit `.env.local`** to version control
- **Use different API keys** for development and production
- **Implement proper error handling** for authentication failures
- **Monitor for suspicious activity**

## Troubleshooting Checklist

- [ ] YouTube Data API v3 enabled in Firebase project
- [ ] OAuth consent screen configured with YouTube scopes
- [ ] OAuth 2.0 client IDs properly configured
- [ ] Environment variables set in `.env.local`
- [ ] App cache cleared and re-authenticated
- [ ] Video file exists and is accessible
- [ ] API quotas not exceeded
- [ ] Debug logs show successful authentication
- [ ] Firestore contains valid YouTube tokens

## Code Changes Made

The following improvements have been implemented:

1. **Enhanced YouTubeAuthService**:
   - Improved token management with validation
   - Better error handling for 401/403 errors
   - Consistent token retrieval methods
   - Added `youtube.force-ssl` scope

2. **Enhanced YouTubeUploadService**:
   - Better file validation and error handling
   - Improved logging for debugging
   - Enhanced error messages with specific solutions
   - Better metadata handling for uploads

3. **Enhanced SocialPostService**:
   - Improved YouTube posting flow
   - Better error handling and user feedback
   - Enhanced logging for debugging
   - Proper Firestore updates with video URLs

## Testing the Fix

After implementing these changes:

1. **Build the app**: `flutter build apk --debug`
2. **Install on device**: `flutter install`
3. **Test YouTube authentication**: Should work without 401 errors
4. **Test video upload**: Should successfully upload to YouTube
5. **Check debug logs**: Should show detailed progress information

## Support

If you continue to experience issues:

1. **Check the debug logs** for specific error messages
2. **Verify all setup steps** in this guide
3. **Test with a simple video file** first
4. **Contact support** with specific error codes and messages 