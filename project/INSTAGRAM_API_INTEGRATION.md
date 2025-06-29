# Instagram API with Instagram Login Integration

This document outlines the implementation of Instagram API with Instagram Login following the official Meta documentation.

## Overview

The Instagram API with Instagram Login allows Instagram professionals (businesses and creators) to use your app to manage their presence on Instagram. This approach is different from the Facebook Login method and provides direct Instagram authentication.

## Key Features

- **Direct Instagram Authentication**: Uses Instagram's own OAuth flow instead of Facebook login
- **Business Login Flow**: Custom login flow for Instagram professional accounts
- **Content Publishing**: Post media directly to Instagram via API
- **Comment Moderation**: Manage and reply to comments
- **Media Insights**: Get insights on media performance
- **Mentions**: Identify media where users are @mentioned
- **Local HTTP Server**: Uses localhost callback for reliable OAuth flow

## Implementation Status

### ✅ Completed

- [x] Instagram authentication method structure (`signInWithInstagramBusiness`)
- [x] Token exchange flow (authorization code → short-lived → long-lived)
- [x] Instagram posting service integration
- [x] Access token validation and expiration checking
- [x] Fallback to manual sharing for consumer accounts
- [x] Error handling for API responses
- [x] Local HTTP server OAuth callback implementation

### 🔄 In Progress

- [ ] Environment variable configuration
- [ ] Instagram app setup in Meta App Dashboard

### ❌ Pending

- [ ] Instagram app credentials setup
- [ ] Testing with real Instagram accounts

## Required Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  http: ^0.13.6
  url_launcher: ^6.2.2
  app_links: ^6.4.0
```

## Environment Variables

Add to `.env.local`:

```env
INSTAGRAM_APP_ID=your_instagram_app_id
INSTAGRAM_APP_SECRET=your_instagram_app_secret
```

## Instagram App Setup

### 1. Create Instagram App

1. Go to [Meta App Dashboard](https://developers.facebook.com/apps/)
2. Create a new app or use existing app
3. Add Instagram product to your app

### 2. Configure Business Login

1. Navigate to **Instagram > API setup with Instagram login**
2. Complete **Set up business login** section
3. Configure OAuth redirect URIs
4. Note your Instagram App ID and App Secret

### 3. Required Permissions

The following scopes are requested during authentication:

- `instagram_business_basic` - Basic account information
- `instagram_business_content_publish` - Publish content to Instagram
- `instagram_business_manage_comments` - Manage comments

### 4. Redirect URI Configuration

**For Local Development:**

```
http://localhost:8585
```

**For Production:**

```
https://your-domain.com/instagram-callback
```

## OAuth Flow Implementation

### Step 1: Authorization with Local HTTP Server

```dart
// Start local callback server
final Stream<String> onCode = await _startInstagramCallbackServer();

// Build authorization URL
final authUrl = Uri.parse('https://www.instagram.com/oauth/authorize').replace(
  queryParameters: {
    'client_id': instagramAppId,
    'redirect_uri': 'http://localhost:8585',
    'response_type': 'code',
    'scope': 'instagram_business_basic,instagram_business_content_publish,instagram_business_manage_comments',
  },
);

// Launch in external browser
await launchUrl(authUrl, mode: LaunchMode.externalApplication);

// Wait for callback
final code = await onCode.first;
```

### Step 2: Token Exchange

```dart
// Exchange authorization code for short-lived token
final response = await http.post(
  Uri.parse('https://api.instagram.com/oauth/access_token'),
  body: {
    'client_id': instagramAppId,
    'client_secret': instagramAppSecret,
    'grant_type': 'authorization_code',
    'redirect_uri': 'http://localhost:8585',
    'code': authCode,
  },
);
```

### Step 3: Long-lived Token

```dart
// Exchange short-lived token for long-lived token
final response = await http.get(
  Uri.parse('https://graph.instagram.com/access_token').replace(
    queryParameters: {
      'grant_type': 'ig_exchange_token',
      'client_secret': instagramAppSecret,
      'access_token': shortLivedToken,
    },
  ),
);
```

## Local HTTP Server Implementation

The app uses a local HTTP server on port 8585 to handle OAuth callbacks:

```dart
Future<Stream<String>> _startInstagramCallbackServer() async {
  final StreamController<String> onCode = StreamController<String>();

  HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8585);

  server.listen((HttpRequest request) async {
    final String? code = request.uri.queryParameters["code"];
    final String? error = request.uri.queryParameters["error"];

    // Send success response to browser
    request.response
      ..statusCode = 200
      ..headers.set("Content-Type", ContentType.html.mimeType)
      ..write("<html><h1>Authorization Complete!</h1></html>");

    await request.response.close();
    await server.close(force: true);

    if (error != null) {
      onCode.addError('Instagram OAuth error: $error');
    } else if (code != null) {
      onCode.add(code);
    }

    await onCode.close();
  });

  return onCode.stream;
}
```

## API Endpoints

### Content Publishing

- **Create Container**: `POST https://graph.instagram.com/v12.0/{user-id}/media`
- **Publish Container**: `POST https://graph.instagram.com/v12.0/{user-id}/media_publish`

### User Information

- **Get User Info**: `GET https://graph.instagram.com/v12.0/me?fields=id,username,account_type`

### Token Management

- **Exchange Token**: `GET https://graph.instagram.com/access_token`
- **Refresh Token**: `GET https://graph.instagram.com/refresh_access_token`

## Token Storage

Instagram tokens are stored in Firestore with the following structure:

```json
{
	"access_token": "long_lived_access_token",
	"instagram_user_id": "instagram_user_id",
	"username": "instagram_username",
	"account_type": "BUSINESS|CREATOR",
	"expires_in": 5183944,
	"token_type": "bearer",
	"platform": "instagram",
	"created_at": "timestamp"
}
```

## Error Handling

### Common Error Codes

- **100**: Permission error - Check app permissions
- **190**: Token expired or invalid - Re-authenticate
- **200**: App requires review - Contact Meta support

### Token Expiration

- Short-lived tokens: 1 hour
- Long-lived tokens: 60 days
- Refresh tokens: 60 days (can be refreshed)

## Fallback Strategy

### Business/Creator Accounts

- Direct API posting via Instagram Graph API
- Full content publishing capabilities
- Comment moderation and insights

### Consumer Accounts

- Manual sharing via SharePlus
- Opens Instagram app for manual posting
- No direct API access

## Testing

### Prerequisites

1. Instagram professional account (Business or Creator)
2. Instagram app configured in Meta App Dashboard
3. Valid OAuth redirect URI (`http://localhost:8585` for development)
4. Environment variables configured

### Development Testing

1. Start the app
2. Navigate to Instagram authentication
3. The app will open Instagram OAuth in external browser
4. Complete authentication in browser
5. Browser will redirect to `http://localhost:8585`
6. Local server captures the authorization code
7. App receives the code and completes token exchange

## Troubleshooting

### "Invalid redirect_uri" Error

1. Ensure `http://localhost:8585` is added to your Instagram app's redirect URIs
2. Check that the redirect URI in your code matches exactly
3. Wait a few minutes for app settings to propagate

### Local Server Issues

1. Ensure port 8585 is not in use by another application
2. Check firewall settings for localhost connections
3. Verify the server starts successfully in debug logs

### Token Exchange Failures

1. Verify Instagram App ID and Secret are correct
2. Check that the redirect URI matches between authorization and token exchange
3. Ensure the authorization code is used within the time limit

## Security Considerations

- Never expose app secret in client-side code
- Use server-side token exchange for long-lived tokens
- Implement proper token refresh logic
- Validate all API responses
- Handle token expiration gracefully

## Next Steps

1. **Configure Instagram app** in Meta App Dashboard
2. **Set up environment variables** with real credentials
3. **Test with real Instagram accounts**
4. **Implement token refresh logic**
5. **Add comprehensive error handling**

## References

- [Instagram API with Instagram Login](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login)
- [Business Login for Instagram](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login)
- [Instagram Platform Overview](https://developers.facebook.com/docs/instagram-platform/overview)
- [Instagram API Reference](https://developers.facebook.com/docs/instagram-api/reference)
