# Custom Launcher Icons for EchoPost

## Required Icon Files

To generate custom launcher icons, you need to provide these image files:

### 1. `app_icon.png` (Main Icon)

- **Size**: 1024x1024 pixels minimum (recommended)
- **Format**: PNG with transparency support
- **Usage**: Main app icon used for iOS and fallback for Android
- **Design**: Should work well on both light and dark backgrounds

### 2. `app_icon_foreground.png` (Android Adaptive Icon Foreground)

- **Size**: 1024x1024 pixels
- **Format**: PNG with transparency
- **Usage**: Foreground layer for Android adaptive icons
- **Design**: Should be centered with transparent background, as the outer 25% may be clipped

## How to Add Your Icons

1. **Create your icon images** (1024x1024 pixels each)
2. **Save them in this directory** (`assets/icons/`) with the exact names:
   - `app_icon.png`
   - `app_icon_foreground.png`
3. **Run the generation commands**:
   ```bash
   flutter pub get
   dart run flutter_launcher_icons:main
   ```
4. **Rebuild your app** to see the new icons

## Design Tips

- **Keep it simple**: Icons should be recognizable at small sizes
- **Use high contrast**: Ensure your icon stands out on various backgrounds
- **Test on devices**: Check how your icon looks on actual Android and iOS devices
- **Consider adaptive icons**: Android adaptive icons can be shaped differently on different devices

## Online Icon Generators

If you need help creating icons, you can use:

- [App Icon Generator](https://appicon.co/)
- [Icon Kitchen](https://icon.kitchen/)
- [Flutter Icon Generator](https://flutter-icon-generator.github.io/)

## Current Configuration

The launcher icons are configured in `pubspec.yaml`:

- Android adaptive icons with white background
- iOS icons enabled
- Minimum Android SDK: 21 (Android 5.0+)
