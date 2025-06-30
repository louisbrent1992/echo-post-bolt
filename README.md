# EchoPost

EchoPost is a next-generation, voice-driven social media posting app that empowers users to record a spoken command and instantly publish to their chosen social networks, all without ever leaving the app or manually selecting files.

## Features

- **Voice Command Recording**: Record a spoken command like "Post that sunset photo from yesterday to Instagram and Twitter with #sunset"
- **Natural Language Processing**: Whisper transcribes the audio, ChatGPT converts the transcription into a structured JSON "social action" object
- **Device-side Media Search**: Intelligently finds media on your device based on your voice command
- **Cross-Platform Posting**: Seamlessly post to Facebook, Instagram, Twitter, and TikTok
- **Secure Media Handling**: Treats local device media as immutable "shareable assets" and eliminates any cloud upload of private photos or videos
- **History Tracking**: View and manage your posting history
- **Web & Mobile Support**: Full OAuth integration for both web and mobile platforms

## Setup Instructions

### Quick Start

1. Clone the repository
2. Copy `.env.example` to `.env.local` and fill in your API keys:
   ```
   OPENAI_API_KEY=your_openai_api_key_here
   TWITTER_CLIENT_ID=your_twitter_client_id_here
   TWITTER_CLIENT_SECRET=your_twitter_client_secret_here
   TIKTOK_CLIENT_KEY=your_tiktok_client_key_here
   TIKTOK_CLIENT_SECRET=your_tiktok_client_secret_here
   ```
3. Run `flutter pub get` to install dependencies
4. Run `flutter pub run build_runner build --delete-conflicting-outputs` to generate JSON serialization code

### Platform-Specific Setup

#### Mobile Setup

1. Configure Firebase:
   - Run `flutterfire configure` if not already generated
   - Place `google-services.json` in `android/app/`
   - Place `GoogleService-Info.plist` in `ios/Runner/`
2. Configure social network SDKs:
   - For Facebook login, set up `AndroidManifest.xml` and `Info.plist` per `flutter_facebook_auth` docs
   - For Twitter, add `redirectURI` in Twitter Developer Console and iOS URL scheme
   - For TikTok, ensure your Cloud Function endpoint is live
3. Run the app: `flutter run`

#### Web Setup

1. **Update Web Domain Configuration**:

   - Edit `lib/services/auth/web_oauth_config.dart`
   - Replace placeholder domain with your actual domain
   - Use HTTPS for production

2. **Configure OAuth Redirect URIs**:

   - **Twitter**: Add `https://YOUR-DOMAIN.com/auth/twitter/callback` to Twitter Developer Console
   - **TikTok**: Add `https://YOUR-DOMAIN.com/auth/tiktok/callback` to TikTok for Developers
   - **Facebook/Instagram**: Add domain to Facebook App settings
   - **YouTube**: Add `https://YOUR-DOMAIN.com/auth/youtube/callback` to Google Cloud Console

3. **Build and Deploy**:

   ```bash
   flutter build web --release --web-renderer canvaskit
   ```

4. **Test OAuth Flows**:
   - Deploy to your hosting service
   - Test each platform authentication
   - Check browser console for errors

### Web OAuth Diagnostic

Add the diagnostic widget to your app to check web OAuth configuration:

```dart
import 'package:echo_post/widgets/web_oauth_diagnostic.dart';

// Add to any screen
WebOAuthDiagnostic()
```

## Documentation

- **[Web OAuth Setup Guide](WEB_OAUTH_SETUP.md)** - Detailed web OAuth configuration
- **[Environment Setup](ENVIRONMENT_SETUP.md)** - Complete environment configuration
- **[Web Deployment](WEB_DEPLOYMENT.md)** - Web deployment instructions
- **[Instagram API Integration](INSTAGRAM_API_INTEGRATION.md)** - Instagram-specific setup

## Architecture

EchoPost follows a clean architecture approach with the following components:

- **Models**: Data classes for social actions, media items, and platform-specific data
- **Services**: Authentication, Firestore, media search, and social posting services
- **Screens**: User interface for login, command recording, media selection, post review, and history
- **Widgets**: Reusable UI components like platform toggles and mic button
- **Web OAuth**: Platform-specific OAuth handlers for web integration

## Security

EchoPost prioritizes user privacy and security:

- Media never leaves the user's device except when directly posting to social networks
- No cloud storage of media files
- Firebase Firestore security rules ensure users can only access their own data
- API keys are stored securely in the `.env.local` file (not committed to version control)
- Social network tokens are stored securely in Firestore
- OAuth state parameter validation prevents CSRF attacks
- HTTPS required for all production web OAuth flows

## Troubleshooting

### Web OAuth Issues

If you're experiencing issues with social media login on web:

1. **Check Configuration**: Use the `WebOAuthDiagnostic` widget to identify issues
2. **Verify Redirect URIs**: Ensure exact match between app and platform settings
3. **Check Environment Variables**: Verify all required credentials are set
4. **Browser Console**: Look for CORS errors or OAuth redirect issues
5. **HTTPS Required**: Ensure production domain uses HTTPS

### Common Issues

- **"OAuth redirect URI mismatch"**: Check platform developer console settings
- **"Invalid client"**: Verify environment variables and credentials
- **"HTTPS required"**: Deploy to service that provides HTTPS
- **"State parameter mismatch"**: Clear browser cache and try again

## License

This project is licensed under the MIT License - see the LICENSE file for details.
