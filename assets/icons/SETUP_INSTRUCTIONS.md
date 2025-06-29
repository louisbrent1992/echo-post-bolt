# 🚀 Quick Setup Guide for EchoPost Launcher Icons

## Method 1: Use AppIcon.co (Recommended & Fast)

1. **Go to AppIcon.co**: Visit https://appicon.co/
2. **Create your icon**:
   - Upload any image (logo, text design, or simple graphic)
   - Minimum size: 1024x1024 pixels
   - Make sure Android and iOS are checked
3. **Download and extract** the generated icons
4. **Copy the files**:
   - From the downloaded files, find the largest PNG (usually 1024x1024)
   - Save it as `app_icon.png` in this directory
   - Also save it as `app_icon_foreground.png` in this directory

## Method 2: Create a Simple Text-Based Icon

1. **Use any image editor** (even MS Paint or online editors):
   - Create a 1024x1024 pixel image
   - Add your app name "EchoPost" with a nice background color
   - Export as PNG
   - Save as both `app_icon.png` and `app_icon_foreground.png`

## Method 3: Use Flutter's Default Temporarily

If you just want to test the build process, you can temporarily use a simpler configuration:

1. **Comment out the adaptive icon config** in pubspec.yaml
2. **Use this simplified config**:

```yaml
flutter_icons:
  android: true
  ios: true
  image_path: "assets/icons/app_icon.png"
```

## Quick Commands After Adding Icons

Once you have your icon files in place:

```bash
# Clean the project
flutter clean

# Get dependencies
flutter pub get

# Generate the launcher icons
dart run flutter_launcher_icons:main

# Rebuild your app
flutter build apk --debug
```

## Current Required Files

Place these files in `assets/icons/`:

- ✅ `app_icon.png` (1024x1024 main icon)
- ✅ `app_icon_foreground.png` (1024x1024 foreground for Android adaptive icons)

## What Happens Next

After running the icon generation:

1. ✅ Android icons will be created in multiple sizes in `android/app/src/main/res/mipmap-*` folders
2. ✅ iOS icons will be created in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
3. ✅ AndroidManifest.xml will be updated to use `@mipmap/ic_launcher` (instead of the temporary default icon)

## 🎨 Design Tips for EchoPost

Since your app is about voice-driven social media posting:

- Consider using a microphone icon
- Use vibrant colors that represent social media (blues, greens, oranges)
- Keep text readable at small sizes
- Ensure good contrast for visibility

## Free Icon Resources

- **Flaticon**: https://www.flaticon.com/ (free with attribution)
- **Icons8**: https://icons8.com/ (free tier available)
- **Canva**: https://www.canva.com/ (free design tool)
- **Figma**: https://www.figma.com/ (free design tool)

Ready to add your icons? Follow any method above and then run the generation commands!
