# EchoPost Web Deployment Guide

This guide covers how to deploy the EchoPost Flutter app to the web platform.

## Prerequisites

- Flutter SDK with web support enabled
- Firebase project configured
- Web hosting service (Firebase Hosting, Netlify, Vercel, etc.)

## Required Configuration Updates

Before deploying to web, you need to update these configuration values:

### 1. Web Domain Configuration

Update `lib/services/auth/web_oauth_config.dart`:

```dart
static String get webDomain {
  if (kDebugMode) {
    return 'http://localhost:8080';  // For development
  } else {
    return 'https://YOUR-ACTUAL-DOMAIN.com';  // ⚠️ UPDATE THIS
  }
}
```

### 2. Firebase Web Configuration

Update `web/firebase-config.js` with your actual Firebase config:

```javascript
const firebaseConfig = {
	apiKey: "your-actual-api-key", // ⚠️ UPDATE THIS
	authDomain: "your-project.firebaseapp.com", // ⚠️ UPDATE THIS
	projectId: "your-project-id", // ⚠️ UPDATE THIS
	storageBucket: "your-project.appspot.com", // ⚠️ UPDATE THIS
	messagingSenderId: "your-sender-id", // ⚠️ UPDATE THIS
	appId: "your-app-id", // ⚠️ UPDATE THIS
	measurementId: "your-measurement-id", // ⚠️ UPDATE THIS (optional)
};
```

### 3. OAuth Redirect URIs

For each social platform, add these redirect URIs to your app settings:

#### Twitter (https://developer.twitter.com/)

- **Development**: `http://localhost:8080/auth/twitter/callback`
- **Production**: `https://YOUR-DOMAIN.com/auth/twitter/callback`

#### TikTok (https://developers.tiktok.com/)

- **Development**: `http://localhost:8080/auth/tiktok/callback`
- **Production**: `https://YOUR-DOMAIN.com/auth/tiktok/callback`

#### Facebook/Instagram (https://developers.facebook.com/)

- **Development**: `http://localhost:8080/auth/facebook/callback`
- **Production**: `https://YOUR-DOMAIN.com/auth/facebook/callback`

#### YouTube/Google (https://console.cloud.google.com/)

- **Development**: `http://localhost:8080/auth/youtube/callback`
- **Production**: `https://YOUR-DOMAIN.com/auth/youtube/callback`

### 4. Environment Variables

Update your `.env.local` file with web-compatible values:

```env
# Firebase Configuration
FIREBASE_API_KEY=your_web_api_key
FIREBASE_AUTH_DOMAIN=your_project.firebaseapp.com
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_STORAGE_BUCKET=your_project.appspot.com
FIREBASE_MESSAGING_SENDER_ID=your_sender_id
FIREBASE_APP_ID=your_web_app_id

# OAuth Configuration (use web redirect URIs for production)
TWITTER_CLIENT_ID=your_twitter_client_id
TWITTER_CLIENT_SECRET=your_twitter_client_secret
TIKTOK_CLIENT_KEY=your_tiktok_client_key
TIKTOK_CLIENT_SECRET=your_tiktok_client_secret
```

## Building for Web

### Development Build

```bash
flutter run -d chrome --web-port=8080
```

### Production Build

```bash
flutter build web --release --web-renderer canvaskit
```

### Optimized Production Build

```bash
flutter build web --release --web-renderer canvaskit --dart-define=FLUTTER_WEB_USE_SKIA=true
```

## Firebase Hosting Deployment

### 1. Install Firebase CLI

```bash
npm install -g firebase-tools
```

### 2. Login to Firebase

```bash
firebase login
```

### 3. Initialize Firebase Hosting

```bash
firebase init hosting
```

### 4. Configure firebase.json

```json
{
	"hosting": {
		"public": "build/web",
		"ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
		"rewrites": [
			{
				"source": "**",
				"destination": "/index.html"
			}
		],
		"headers": [
			{
				"source": "**/*.@(js|css)",
				"headers": [
					{
						"key": "Cache-Control",
						"value": "max-age=31536000"
					}
				]
			}
		]
	}
}
```

### 5. Deploy

```bash
firebase deploy
```

## Netlify Deployment

### 1. Build the app

```bash
flutter build web --release
```

### 2. Create netlify.toml

```toml
[build]
  publish = "build/web"
  command = "flutter build web --release"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
```

### 3. Deploy via Netlify CLI or drag-and-drop

## Vercel Deployment

### 1. Create vercel.json

```json
{
	"buildCommand": "flutter build web --release",
	"outputDirectory": "build/web",
	"rewrites": [
		{
			"source": "/(.*)",
			"destination": "/index.html"
		}
	]
}
```

### 2. Deploy via Vercel CLI or GitHub integration

## Web-Specific Considerations

### 1. Firebase Configuration

- Update `web/firebase-config.js` with your actual Firebase config
- Ensure Firebase project has web app configured

### 2. OAuth Configuration

- Configure OAuth redirect URIs for web domain
- Update social platform app settings for web URLs

### 3. File Upload Limitations

- Web has different file handling than mobile
- Consider using Firebase Storage for web file uploads

### 4. Permissions

- Web permissions differ from mobile
- Implement web-specific permission handling

### 5. Performance Optimization

- Use `--web-renderer canvaskit` for better performance
- Implement lazy loading for large media files
- Optimize images for web delivery

## Platform Differences

### File Access

- **Mobile**: Uses `photo_manager` for gallery access
- **Web**: Uses `file_picker` with blob URLs and in-memory file handling

### Permissions

- **Mobile**: Requires explicit permission requests
- **Web**: Browser handles permissions automatically via user interaction

### Media Handling

- **Mobile**: Direct file system access
- **Web**: Blob URLs and base64 encoding for file handling

### OAuth Flow

- **Mobile**: Custom URL schemes (`echopost://platform-callback`)
- **Web**: HTTPS redirect URIs (`https://domain.com/auth/platform/callback`)

## Troubleshooting

### Common Issues

1. **CORS Errors**: Ensure Firebase project allows your domain
2. **OAuth Redirect Issues**: Update redirect URIs in social platform apps
3. **File Upload Failures**: Check Firebase Storage rules
4. **Performance Issues**: Use production build and optimize assets

### Debug Commands

```bash
# Check web support
flutter doctor

# Clean and rebuild
flutter clean
flutter pub get
flutter build web --release

# Check for web-specific issues
flutter analyze
```

## Security Considerations

1. **API Keys**: Never expose sensitive keys in client-side code
2. **Firebase Rules**: Configure proper security rules
3. **HTTPS**: Always use HTTPS in production
4. **Content Security Policy**: Implement CSP headers

## Monitoring

1. **Firebase Analytics**: Enable for web tracking
2. **Error Reporting**: Set up Firebase Crashlytics
3. **Performance Monitoring**: Use Firebase Performance Monitoring

## Support

For web-specific issues, check:

- [Flutter Web Documentation](https://docs.flutter.dev/web)
- [Firebase Web Setup](https://firebase.google.com/docs/web/setup)
- [Flutter Web FAQ](https://docs.flutter.dev/web/faq)
