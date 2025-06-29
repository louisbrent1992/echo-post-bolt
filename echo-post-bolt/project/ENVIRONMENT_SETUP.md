# Environment Setup Guide for EchoPost

This guide provides step-by-step instructions for setting up all required environment variables and API credentials for EchoPost's social media authentication.

## Required Environment Variables

Create a `.env.local` file in your project root with the following variables:

```env
# OpenAI API (Required for voice transcription)
OPENAI_API_KEY=your_openai_api_key_here

# Facebook/Instagram Authentication
# No environment variables needed - uses flutter_facebook_auth package
# Configure in Facebook Developer Console and app configuration files

# YouTube Authentication
# No environment variables needed - uses google_sign_in package
# Configure in Google Cloud Console and app configuration files

# Twitter Authentication
TWITTER_API_KEY=your_twitter_api_key_here
TWITTER_API_SECRET=your_twitter_api_secret_here

# TikTok Authentication
TIKTOK_CLIENT_KEY=your_tiktok_client_key_here
TIKTOK_CLIENT_SECRET=your_tiktok_client_secret_here
```

## Platform-Specific Setup Instructions

### 1. OpenAI API Setup

1. Go to [OpenAI Platform](https://platform.openai.com/)
2. Create an account or sign in
3. Navigate to API Keys section
4. Create a new API key
5. Copy the key and add it to `.env.local`

### 2. Facebook/Instagram Setup

#### Facebook App Configuration:
1. Go to [Facebook Developers](https://developers.facebook.com/)
2. Create a new app or use existing app
3. Add Facebook Login product
4. Add Instagram product
5. Configure OAuth redirect URIs:
   - Android: `fb{APP_ID}://authorize`
   - iOS: `fb{APP_ID}://authorize`
6. Note your Facebook App ID and Client Token

#### App Configuration Files:

**Android (`android/app/src/main/res/values/strings.xml`):**
```xml
<string name="facebook_app_id">YOUR_FACEBOOK_APP_ID</string>
<string name="facebook_client_token">YOUR_FACEBOOK_CLIENT_TOKEN</string>
```

**iOS (`ios/Runner/Info.plist`):**
```xml
<key>FacebookAppID</key>
<string>YOUR_FACEBOOK_APP_ID</string>
<key>FacebookClientToken</key>
<string>YOUR_FACEBOOK_CLIENT_TOKEN</string>
<key>FacebookDisplayName</key>
<string>EchoPost</string>
```

### 3. YouTube Setup

#### Google Cloud Console:
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable YouTube Data API v3
4. Create OAuth 2.0 credentials
5. Configure OAuth consent screen
6. Add authorized redirect URIs for your app

#### App Configuration:
The `google_sign_in` package will automatically handle the OAuth flow using your app's configuration.

### 4. Twitter Setup

#### Twitter Developer Console:
1. Go to [Twitter Developer Portal](https://developer.twitter.com/)
2. Create a new app or use existing
3. Navigate to App Settings > Authentication settings
4. Enable OAuth 1.0a
5. Set App permissions to "Read and Write"
6. Add callback URL: `echopost://twitter-callback`
7. Note your API Key and API Secret

#### Environment Variables:
```env
TWITTER_API_KEY=your_twitter_api_key_here
TWITTER_API_SECRET=your_twitter_api_secret_here
```

### 5. TikTok Setup

#### TikTok Developer Console:
1. Go to [TikTok for Developers](https://developers.tiktok.com/)
2. Create a new app
3. Configure app permissions:
   - User info basic
   - Video upload
4. Set redirect URI: `echopost://tiktok-callback`
5. Note your Client Key and Client Secret

#### Environment Variables:
```env
TIKTOK_CLIENT_KEY=your_tiktok_client_key_here
TIKTOK_CLIENT_SECRET=your_tiktok_client_secret_here
```

## URL Scheme Configuration

### Android (`android/app/src/main/AndroidManifest.xml`):
```xml
<activity android:name="com.linusu.flutter_web_auth_2.CallbackActivity">
    <intent-filter android:label="flutter_web_auth_2">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="echopost" />
    </intent-filter>
</activity>
```

### iOS (`ios/Runner/Info.plist`):
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.example.echopost</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>echopost</string>
        </array>
    </dict>
</array>
```

## Testing Authentication

After setting up all credentials:

1. **Build the app**: `flutter build apk --debug`
2. **Install on device**: `flutter install`
3. **Test each platform**:
   - Tap the platform icon in the header
   - Complete the OAuth flow
   - Verify authentication state updates
   - Check Firestore for stored tokens

## Troubleshooting

### Common Issues:

1. **"API credentials not found"**: Check `.env.local` file exists and variables are set
2. **"OAuth callback failed"**: Verify URL schemes are configured correctly
3. **"Permission denied"**: Ensure app permissions are configured in developer consoles
4. **"Token expired"**: Re-authenticate with the platform

### Debug Mode:
Enable debug logging by setting `kDebugMode = true` in your app to see detailed authentication flow logs.

## Security Notes

- Never commit `.env.local` to version control
- Use different API keys for development and production
- Regularly rotate API keys and secrets
- Monitor API usage and quotas
- Implement proper error handling for authentication failures 