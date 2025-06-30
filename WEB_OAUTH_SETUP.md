# Web OAuth Setup Guide for EchoPost

This guide provides step-by-step instructions for configuring OAuth authentication for social media platforms on the web version of EchoPost.

## Prerequisites

- Flutter web app deployed to a domain with HTTPS (required for OAuth)
- Developer accounts for each social platform
- Firebase project configured for web

## Quick Setup Checklist

- [ ] Update web domain configuration
- [ ] Configure OAuth redirect URIs in each platform
- [ ] Set up environment variables
- [ ] Test OAuth flows

## 1. Web Domain Configuration

### Update `lib/services/auth/web_oauth_config.dart`

Replace the placeholder domain with your actual domain:

```dart
static String get webDomain {
  if (kDebugMode) {
    return 'http://localhost:8080';  // For development
  } else {
    return 'https://YOUR-ACTUAL-DOMAIN.com';  // ⚠️ UPDATE THIS
  }
}
```

**Examples:**

- Firebase Hosting: `https://your-project.web.app`
- Netlify: `https://your-app.netlify.app`
- Vercel: `https://your-app.vercel.app`
- Custom domain: `https://yourdomain.com`

## 2. Platform-Specific OAuth Configuration

### Twitter OAuth 2.0 Setup

1. **Go to Twitter Developer Portal**: https://developer.twitter.com/
2. **Select your app** or create a new one
3. **Navigate to App Settings > Authentication settings**
4. **Enable OAuth 2.0**
5. **Set App permissions** to "Read and Write"
6. **Add OAuth 2.0 redirect URIs**:
   - Development: `http://localhost:8080/auth/twitter/callback`
   - Production: `https://YOUR-DOMAIN.com/auth/twitter/callback`
7. **Set App type** to "Web App" (not Native App for web)
8. **Note your Client ID and Client Secret**

### Facebook/Instagram OAuth Setup

1. **Go to Facebook Developers**: https://developers.facebook.com/
2. **Select your app** or create a new one
3. **Add Facebook Login product**
4. **Add Instagram product**
5. **Configure OAuth redirect URIs**:
   - Development: `http://localhost:8080/auth/facebook/callback`
   - Production: `https://YOUR-DOMAIN.com/auth/facebook/callback`
6. **Add your domain** to "Valid OAuth Redirect URIs"
7. **Note your App ID and App Secret**

### YouTube/Google OAuth Setup

1. **Go to Google Cloud Console**: https://console.cloud.google.com/
2. **Select your project** or create a new one
3. **Enable YouTube Data API v3**
4. **Create OAuth 2.0 credentials**
5. **Configure OAuth consent screen**
6. **Add authorized redirect URIs**:
   - Development: `http://localhost:8080/auth/youtube/callback`
   - Production: `https://YOUR-DOMAIN.com/auth/youtube/callback`
7. **Note your Client ID and Client Secret**

### TikTok OAuth Setup

1. **Go to TikTok for Developers**: https://developers.tiktok.com/
2. **Create a new app** or select existing
3. **Configure app permissions**:
   - User info basic
   - Video upload
4. **Set redirect URI**:
   - Development: `http://localhost:8080/auth/tiktok/callback`
   - Production: `https://YOUR-DOMAIN.com/auth/tiktok/callback`
5. **Note your Client Key and Client Secret**

## 3. Environment Variables

Update your `.env.local` file with web-compatible credentials:

```env
# Twitter OAuth 2.0
TWITTER_CLIENT_ID=your_twitter_client_id
TWITTER_CLIENT_SECRET=your_twitter_client_secret

# TikTok OAuth
TIKTOK_CLIENT_KEY=your_tiktok_client_key
TIKTOK_CLIENT_SECRET=your_tiktok_client_secret

# Facebook/Instagram (uses flutter_facebook_auth package)
# No environment variables needed - configure in app settings

# YouTube (uses google_sign_in package)
# No environment variables needed - configure in Google Cloud Console
```

## 4. Web Build Configuration

### Development Build

```bash
flutter run -d chrome --web-port=8080
```

### Production Build

```bash
flutter build web --release --web-renderer canvaskit
```

## 5. Testing OAuth Flows

### Development Testing

1. **Start development server**:

   ```bash
   flutter run -d chrome --web-port=8080
   ```

2. **Test each platform**:
   - Sign in to EchoPost
   - Click on a social platform icon
   - Complete the OAuth flow
   - Verify authentication success

### Production Testing

1. **Deploy your app** to your hosting service
2. **Test OAuth flows** on the live domain
3. **Verify redirect URIs** are working correctly
4. **Check browser console** for any errors

## 6. Troubleshooting Common Issues

### "OAuth redirect URI mismatch"

**Cause**: Redirect URI in platform settings doesn't match the one used by the app.

**Solution**:

1. Check the exact redirect URI in your platform settings
2. Ensure it matches: `https://YOUR-DOMAIN.com/auth/PLATFORM/callback`
3. Update platform settings if needed

### "Invalid client" or "Client not found"

**Cause**: Client ID/Secret not properly configured.

**Solution**:

1. Verify environment variables are set correctly
2. Check that credentials are for the right platform
3. Ensure credentials are for web (not mobile) apps

### "HTTPS required" error

**Cause**: OAuth requires HTTPS in production.

**Solution**:

1. Deploy to a service that provides HTTPS
2. Use Firebase Hosting, Netlify, or Vercel
3. Configure custom domain with SSL certificate

### "CORS error" or "Cross-origin request blocked"

**Cause**: Browser security blocking OAuth requests.

**Solution**:

1. Ensure redirect URIs are properly configured
2. Check that domain is added to allowed origins
3. Verify OAuth flow is using correct URLs

### "State parameter mismatch"

**Cause**: OAuth state parameter validation failed.

**Solution**:

1. Clear browser cache and cookies
2. Try the OAuth flow again
3. Check for browser extensions interfering

## 7. Security Best Practices

### Environment Variables

- Never commit `.env.local` to version control
- Use different credentials for development and production
- Rotate API keys regularly

### OAuth Configuration

- Use HTTPS for all production URLs
- Implement proper state parameter validation
- Set appropriate token expiration times
- Monitor OAuth usage and quotas

### Domain Security

- Add security headers to your web server
- Implement Content Security Policy (CSP)
- Use secure cookies for session management

## 8. Platform-Specific Notes

### Twitter

- Requires OAuth 2.0 with PKCE for web apps
- App type must be "Web App" (not "Native App")
- Supports both read and write permissions

### Facebook/Instagram

- Uses Facebook Login with Instagram permissions
- Requires business/creator accounts for Instagram
- Supports both personal and business accounts

### YouTube

- Uses Google OAuth 2.0
- Requires YouTube Data API v3
- Supports channel management and uploads

### TikTok

- Requires HTTPS for production redirects
- Supports video upload permissions
- Has rate limiting and quota restrictions

## 9. Monitoring and Debugging

### Enable Debug Logging

Add to your app for detailed OAuth logs:

```dart
if (kDebugMode) {
  print('🌐 Web OAuth: Starting authentication...');
}
```

### Check Browser Console

Look for:

- Network requests to OAuth endpoints
- JavaScript errors
- CORS issues
- Redirect URI mismatches

### Verify Token Storage

Check Firestore for stored tokens:

- Collection: `users/{userId}/tokens/{platform}`
- Verify token expiration times
- Check token scopes and permissions

## 10. Support and Resources

### Documentation Links

- [Twitter OAuth 2.0](https://developer.twitter.com/en/docs/authentication/oauth-2-0)
- [Facebook Login](https://developers.facebook.com/docs/facebook-login/)
- [YouTube Data API](https://developers.google.com/youtube/v3/docs/)
- [TikTok for Developers](https://developers.tiktok.com/)

### EchoPost Resources

- `WEB_DEPLOYMENT.md` - General web deployment guide
- `ENVIRONMENT_SETUP.md` - Environment configuration
- `INSTAGRAM_API_INTEGRATION.md` - Instagram-specific setup

### Getting Help

1. Check browser console for errors
2. Verify all configuration steps
3. Test with a simple OAuth flow first
4. Contact support with specific error messages
