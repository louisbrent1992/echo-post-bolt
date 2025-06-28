# EchoPost

EchoPost is a next-generation, voice-driven social media posting app that empowers users to record a spoken command and instantly publish to their chosen social networks, all without ever leaving the app or manually selecting files.

## Features

- **Voice Command Recording**: Record a spoken command like "Post that sunset photo from yesterday to Instagram and Twitter with #sunset"
- **Natural Language Processing**: Whisper transcribes the audio, ChatGPT converts the transcription into a structured JSON "social action" object
- **Device-side Media Search**: Intelligently finds media on your device based on your voice command
- **Cross-Platform Posting**: Seamlessly post to Facebook, Instagram, Twitter, and TikTok
- **Secure Media Handling**: Treats local device media as immutable "shareable assets" and eliminates any cloud upload of private photos or videos
- **History Tracking**: View and manage your posting history

## Setup Instructions

1. Clone the repository
2. Copy `.env.example` to `.env` and fill in your API keys:
   ```
   OPENAI_API_KEY=your_openai_api_key_here
   TWITTER_API_KEY=your_twitter_api_key_here
   TWITTER_API_SECRET=your_twitter_api_secret_here
   TIKTOK_CLIENT_KEY=your_tiktok_client_key_here
   TIKTOK_CLIENT_SECRET=your_tiktok_client_secret_here
   BACKEND_URL=https://your-backend-url.com
   ```
3. Run `flutter pub get` to install dependencies
4. Run `flutter pub run build_runner build --delete-conflicting-outputs` to generate JSON serialization code
5. Configure Firebase:
   - Run `flutterfire configure` if not already generated
   - Place `google-services.json` in `android/app/`
   - Place `GoogleService-Info.plist` in `ios/Runner/`
6. Configure social network SDKs:
   - For Facebook login, set up `AndroidManifest.xml` and `Info.plist` per `flutter_facebook_auth` docs
   - For Twitter, add `redirectURI` in Twitter Developer Console and iOS URL scheme
   - For TikTok, ensure your Cloud Function endpoint is live
7. Run the app: `flutter run`

## Architecture

EchoPost follows a clean architecture approach with the following components:

- **Models**: Data classes for social actions, media items, and platform-specific data
- **Services**: Authentication, Firestore, media search, and social posting services
- **Screens**: User interface for login, command recording, media selection, post review, and history
- **Widgets**: Reusable UI components like platform toggles and mic button

## Security

EchoPost prioritizes user privacy and security:

- Media never leaves the user's device except when directly posting to social networks
- No cloud storage of media files
- Firebase Firestore security rules ensure users can only access their own data
- API keys are stored securely in the `.env` file (not committed to version control)
- Social network tokens are stored securely in Firestore

## License

This project is licensed under the MIT License - see the LICENSE file for details.