import 'package:flutter/foundation.dart';

/// Web-specific OAuth configuration for social platform authentication
class WebOAuthConfig {
  /// Get the current web domain for OAuth redirects
  static String get webDomain {
    if (kDebugMode) {
      // Development: Use localhost with proper port
      return 'http://localhost:8080';
    } else {
      // Production: Use your actual domain
      // TODO: Replace with your actual deployed domain
      return 'https://echopost-app.web.app'; // Default Firebase hosting domain
    }
  }

  /// Get platform-specific redirect URIs for web
  static Map<String, String> get webRedirectUris => {
        'twitter': '$webDomain/auth/twitter/callback',
        'tiktok': '$webDomain/auth/tiktok/callback',
        'facebook': '$webDomain/auth/facebook/callback',
        'instagram': '$webDomain/auth/instagram/callback',
        'youtube': '$webDomain/auth/youtube/callback',
      };

  /// Get the appropriate redirect URI for the current platform
  static String getRedirectUri(String platform) {
    if (kIsWeb) {
      return webRedirectUris[platform.toLowerCase()] ??
          '$webDomain/auth/callback';
    } else {
      // Mobile: Use custom URL scheme
      return 'echopost://$platform-callback';
    }
  }

  /// Check if the current platform supports OAuth on web
  static bool isPlatformSupported(String platform) {
    if (kIsWeb) {
      // Web supports all platforms but with different redirect handling
      return ['twitter', 'tiktok', 'facebook', 'instagram', 'youtube']
          .contains(platform.toLowerCase());
    } else {
      // Mobile: All platforms supported
      return true;
    }
  }

  /// Get platform-specific OAuth scope requirements
  static List<String> getOAuthScopes(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return ['tweet.read', 'tweet.write', 'users.read', 'offline.access'];
      case 'tiktok':
        return ['user.info.basic', 'video.upload'];
      case 'facebook':
        return [
          'public_profile',
          'email',
          'pages_manage_posts',
          'pages_read_engagement',
          'pages_show_list',
          'instagram_basic',
          'instagram_content_publish',
        ];
      case 'instagram':
        return [
          'instagram_business_basic',
          'instagram_business_content_publish',
          'instagram_business_manage_comments',
        ];
      case 'youtube':
        return ['https://www.googleapis.com/auth/youtube.upload'];
      default:
        return [];
    }
  }

  /// Web-specific OAuth configuration notes
  static Map<String, String> get platformNotes => {
        'twitter':
            'Ensure your Twitter app is configured for web with OAuth 2.0 enabled and redirect URI added',
        'tiktok': 'TikTok requires HTTPS for web redirects in production',
        'facebook':
            'Add your domain to Facebook app settings under Valid OAuth Redirect URIs',
        'instagram':
            'Instagram uses Facebook OAuth - configure Facebook app settings',
        'youtube': 'YouTube uses Google OAuth - configure Google Cloud Console',
      };

  /// Generate state parameter for OAuth flow
  static String generateState([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
        length,
        (i) => chars[
            (DateTime.now().millisecondsSinceEpoch + i) % chars.length]).join();
  }

  /// Validate redirect URI format
  static bool isValidRedirectUri(String uri) {
    try {
      final parsedUri = Uri.parse(uri);

      if (kIsWeb) {
        // Web: Must be HTTP/HTTPS
        return parsedUri.scheme == 'http' || parsedUri.scheme == 'https';
      } else {
        // Mobile: Custom scheme
        return parsedUri.scheme == 'echopost';
      }
    } catch (e) {
      return false;
    }
  }

  /// Check if web OAuth is properly configured
  static bool isWebOAuthConfigured() {
    if (!kIsWeb) return true; // Mobile doesn't need web config

    // Check if we have a proper domain configured
    final domain = webDomain;
    return domain != 'https://your-app-domain.com' &&
        domain != 'https://echopost-app.web.app'; // Default Firebase domain
  }

  /// Get web OAuth setup instructions
  static String getWebOAuthSetupInstructions() {
    return '''
Web OAuth Setup Required:

1. Update web_oauth_config.dart with your actual domain
2. Configure OAuth redirect URIs in each platform's developer console:
   - Twitter: ${webRedirectUris['twitter']}
   - TikTok: ${webRedirectUris['tiktok']}
   - Facebook: ${webRedirectUris['facebook']}
   - Instagram: ${webRedirectUris['instagram']}
   - YouTube: ${webRedirectUris['youtube']}

3. Ensure your domain is added to each platform's allowed domains
4. For production, use HTTPS URLs only

See WEB_DEPLOYMENT.md for detailed instructions.
''';
  }
}
