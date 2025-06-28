# Firebase Setup Guide for Android

## Steps to Configure Firebase:

1. **Create a Firebase Project:**

   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Click "Create a project" or select an existing project
   - Follow the setup wizard

2. **Add Android App to Firebase:**

   - In Firebase Console, click "Add app" and select Android
   - Enter your Android package name: `com.example.echopost`
   - Download the `google-services.json` file
   - Place the `google-services.json` file in: `android/app/`

3. **Update values.xml:**
   Open `android/app/src/main/res/values/values.xml` and replace the placeholder values with your actual Firebase configuration values from `google-services.json`:

   - `YOUR_FIREBASE_PROJECT_ID` → Your Firebase project ID
   - `YOUR_FIREBASE_APP_ID` → Your Android app ID (e.g., 1:123456789:android:abcdef)
   - `YOUR_FIREBASE_API_KEY` → Your Firebase API key
   - `YOUR_FIREBASE_SENDER_ID` → Your GCM/FCM sender ID

## Steps to Configure Facebook SDK:

1. **Create a Facebook App:**

   - Go to [Facebook Developers](https://developers.facebook.com/)
   - Create a new app or use an existing one
   - Add Android platform to your app

2. **Update strings.xml:**
   Open `android/app/src/main/res/values/strings.xml` and replace:

   - `YOUR_FACEBOOK_APP_ID` → Your Facebook App ID (numeric)
   - `YOUR_FACEBOOK_CLIENT_TOKEN` → Your Facebook Client Token

3. **Generate Key Hash:**
   For development, run:
   ```bash
   keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore | openssl sha1 -binary | openssl base64
   ```
   Add this hash to your Facebook app settings.

## Alternative: Using google-services.json

If you have a `google-services.json` file from Firebase:

1. Place it in `android/app/`
2. Remove the manual values from `values.xml` (the plugin will read from google-services.json)

## Troubleshooting:

- If you see "Failed to load FirebaseOptions from resource", ensure either:
  - `google-services.json` is present in `android/app/`, OR
  - All values in `values.xml` are properly configured
- For Facebook errors, ensure you've added your development key hash to Facebook app settings
