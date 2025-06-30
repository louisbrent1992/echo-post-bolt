import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'web_oauth_config.dart';

/// Web OAuth status checker and diagnostic tool
class WebOAuthStatus {
  /// Check overall web OAuth configuration status
  static Map<String, dynamic> checkWebOAuthStatus() {
    final status = <String, dynamic>{
      'isWeb': kIsWeb,
      'isConfigured': false,
      'domain': WebOAuthConfig.webDomain,
      'issues': <String>[],
      'warnings': <String>[],
      'platforms': <String, Map<String, dynamic>>{},
    };

    if (!kIsWeb) {
      status['issues'].add('Not running on web platform');
      return status;
    }

    // Check domain configuration
    final domain = WebOAuthConfig.webDomain;
    if (domain == 'https://your-app-domain.com' ||
        domain == 'https://echopost-app.web.app') {
      status['issues']
          .add('Web domain not configured - using placeholder domain');
    } else if (!domain.startsWith('https://')) {
      status['warnings'].add('Production domain should use HTTPS');
    }

    // Check environment variables
    _checkEnvironmentVariables(status);

    // Check platform configurations
    _checkPlatformConfigurations(status);

    // Determine overall configuration status
    status['isConfigured'] = status['issues'].isEmpty;

    return status;
  }

  /// Check environment variables for web OAuth
  static void _checkEnvironmentVariables(Map<String, dynamic> status) {
    final requiredVars = {
      'TWITTER_CLIENT_ID': 'Twitter Client ID',
      'TWITTER_CLIENT_SECRET': 'Twitter Client Secret',
      'TIKTOK_CLIENT_KEY': 'TikTok Client Key',
      'TIKTOK_CLIENT_SECRET': 'TikTok Client Secret',
    };

    for (final entry in requiredVars.entries) {
      final value = dotenv.env[entry.key];
      if (value == null || value.isEmpty) {
        status['issues'].add('Missing ${entry.value} in .env.local');
      } else if (value.contains('your_') || value.contains('placeholder')) {
        status['warnings']
            .add('${entry.value} appears to be a placeholder value');
      }
    }
  }

  /// Check platform-specific configurations
  static void _checkPlatformConfigurations(Map<String, dynamic> status) {
    final platforms = ['twitter', 'tiktok', 'facebook', 'instagram', 'youtube'];

    for (final platform in platforms) {
      final platformStatus = <String, dynamic>{
        'supported': WebOAuthConfig.isPlatformSupported(platform),
        'redirectUri': WebOAuthConfig.getRedirectUri(platform),
        'scopes': WebOAuthConfig.getOAuthScopes(platform),
        'notes': WebOAuthConfig.platformNotes[platform] ?? '',
      };

      // Platform-specific checks
      switch (platform) {
        case 'twitter':
          _checkTwitterConfiguration(platformStatus, status);
          break;
        case 'tiktok':
          _checkTikTokConfiguration(platformStatus, status);
          break;
        case 'facebook':
        case 'instagram':
          _checkFacebookConfiguration(platformStatus, status);
          break;
        case 'youtube':
          _checkYouTubeConfiguration(platformStatus, status);
          break;
      }

      status['platforms'][platform] = platformStatus;
    }
  }

  /// Check Twitter-specific configuration
  static void _checkTwitterConfiguration(
      Map<String, dynamic> platformStatus, Map<String, dynamic> status) {
    final clientId = dotenv.env['TWITTER_CLIENT_ID'];
    final clientSecret = dotenv.env['TWITTER_CLIENT_SECRET'];

    if (clientId == null || clientSecret == null) {
      platformStatus['configured'] = false;
      platformStatus['issues'] = ['Missing Twitter credentials'];
      return;
    }

    final redirectUri = platformStatus['redirectUri'] as String;
    if (!redirectUri.startsWith('https://') && !kDebugMode) {
      platformStatus['warnings'] = ['Production redirect URI should use HTTPS'];
    }

    platformStatus['configured'] = true;
  }

  /// Check TikTok-specific configuration
  static void _checkTikTokConfiguration(
      Map<String, dynamic> platformStatus, Map<String, dynamic> status) {
    final clientKey = dotenv.env['TIKTOK_CLIENT_KEY'];
    final clientSecret = dotenv.env['TIKTOK_CLIENT_SECRET'];

    if (clientKey == null || clientSecret == null) {
      platformStatus['configured'] = false;
      platformStatus['issues'] = ['Missing TikTok credentials'];
      return;
    }

    final redirectUri = platformStatus['redirectUri'] as String;
    if (!redirectUri.startsWith('https://') && !kDebugMode) {
      platformStatus['warnings'] = ['Production redirect URI should use HTTPS'];
    }

    platformStatus['configured'] = true;
  }

  /// Check Facebook/Instagram configuration
  static void _checkFacebookConfiguration(
      Map<String, dynamic> platformStatus, Map<String, dynamic> status) {
    // Facebook/Instagram uses flutter_facebook_auth package
    // Configuration is done in app settings, not environment variables
    platformStatus['configured'] = true;
    platformStatus['notes'] = 'Configure Facebook App ID in app settings';
  }

  /// Check YouTube configuration
  static void _checkYouTubeConfiguration(
      Map<String, dynamic> platformStatus, Map<String, dynamic> status) {
    // YouTube uses google_sign_in package
    // Configuration is done in Google Cloud Console
    platformStatus['configured'] = true;
    platformStatus['notes'] =
        'Configure OAuth credentials in Google Cloud Console';
  }

  /// Get detailed setup instructions for web OAuth
  static String getSetupInstructions() {
    return '''
Web OAuth Setup Instructions:

1. Update Domain Configuration:
   - Edit lib/services/auth/web_oauth_config.dart
   - Replace placeholder domain with your actual domain
   - Use HTTPS for production

2. Configure Platform OAuth:
   - Twitter: Add redirect URI to Twitter Developer Console
   - TikTok: Add redirect URI to TikTok for Developers
   - Facebook/Instagram: Add domain to Facebook App settings
   - YouTube: Add redirect URI to Google Cloud Console

3. Set Environment Variables:
   - Create .env.local file
   - Add Twitter and TikTok credentials
   - Never commit .env.local to version control

4. Test OAuth Flows:
   - Run flutter run -d chrome --web-port=8080
   - Test each platform authentication
   - Check browser console for errors

See WEB_OAUTH_SETUP.md for detailed instructions.
''';
  }

  /// Get troubleshooting steps for common issues
  static String getTroubleshootingSteps(List<String> issues) {
    if (issues.isEmpty) return 'No issues detected.';

    final steps = StringBuffer();
    steps.writeln('Troubleshooting Steps:');
    steps.writeln();

    for (final issue in issues) {
      steps.writeln('• $issue');

      if (issue.contains('domain')) {
        steps.writeln(
            '  → Update web_oauth_config.dart with your actual domain');
      } else if (issue.contains('Missing')) {
        steps.writeln('  → Add the missing environment variable to .env.local');
      } else if (issue.contains('redirect URI')) {
        steps.writeln(
            '  → Configure redirect URI in platform developer console');
      }
      steps.writeln();
    }

    return steps.toString();
  }

  /// Validate redirect URI format
  static bool isValidRedirectUri(String uri) {
    return WebOAuthConfig.isValidRedirectUri(uri);
  }

  /// Get recommended redirect URIs for a platform
  static List<String> getRecommendedRedirectUris(String platform) {
    final domain = WebOAuthConfig.webDomain;
    return [
      '$domain/auth/$platform/callback',
      if (kDebugMode) 'http://localhost:8080/auth/$platform/callback',
    ];
  }

  /// Check if a platform is ready for OAuth
  static bool isPlatformReady(String platform) {
    final status = checkWebOAuthStatus();
    final platformStatus =
        status['platforms'][platform] as Map<String, dynamic>?;

    return platformStatus?['configured'] == true &&
        platformStatus?['supported'] == true;
  }
}
