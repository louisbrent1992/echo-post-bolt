import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import 'web_oauth_config.dart';

/// Web-specific OAuth handler for social platform authentication
class WebOAuthHandler {
  static const String _stateKey = 'oauth_state';
  static const String _codeVerifierKey = 'oauth_code_verifier';

  /// Handle OAuth flow for web platforms
  static Future<Map<String, dynamic>> handleOAuthFlow({
    required String platform,
    required String clientId,
    required String clientSecret,
    String? redirectUri,
    List<String>? scopes,
  }) async {
    if (!kIsWeb) {
      throw Exception('WebOAuthHandler is only for web platforms');
    }

    try {
      // Generate OAuth parameters
      final state = WebOAuthConfig.generateState();
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      // Store state and code verifier for verification
      _storeOAuthData(state, codeVerifier);

      // Build authorization URL
      final authUrl = _buildAuthorizationUrl(
        platform: platform,
        clientId: clientId,
        redirectUri: redirectUri ?? WebOAuthConfig.getRedirectUri(platform),
        scopes: scopes ?? WebOAuthConfig.getOAuthScopes(platform),
        state: state,
        codeChallenge: codeChallenge,
      );

      if (kDebugMode) {
        print('🌐 Web OAuth: Starting $platform authentication');
        print('🌐 Web OAuth: Auth URL: ${authUrl.toString()}');
      }

      // Launch OAuth flow
      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme:
            Uri.parse(redirectUri ?? WebOAuthConfig.getRedirectUri(platform))
                .scheme,
        options: const FlutterWebAuth2Options(
          timeout: 120,
          preferEphemeral: false,
        ),
      );

      if (kDebugMode) {
        print('🌐 Web OAuth: Callback URL received: $callbackUrl');
      }

      // Parse callback URL
      final callbackUri = Uri.parse(callbackUrl);
      final queryParams = callbackUri.queryParameters;

      // Verify state parameter
      final returnedState = queryParams['state'];
      if (returnedState != state) {
        throw Exception('OAuth state mismatch - possible CSRF attack');
      }

      // Check for error
      if (queryParams.containsKey('error')) {
        throw Exception(
            'OAuth error: ${queryParams['error']} - ${queryParams['error_description'] ?? 'Unknown error'}');
      }

      // Get authorization code
      final authCode = queryParams['code'];
      if (authCode == null) {
        throw Exception('No authorization code received');
      }

      // Exchange code for tokens
      final tokens = await _exchangeCodeForTokens(
        platform: platform,
        clientId: clientId,
        clientSecret: clientSecret,
        authCode: authCode,
        redirectUri: redirectUri ?? WebOAuthConfig.getRedirectUri(platform),
        codeVerifier: codeVerifier,
      );

      // Clean up stored data
      _clearOAuthData();

      if (kDebugMode) {
        print('🌐 Web OAuth: $platform authentication successful');
      }

      return tokens;
    } catch (e) {
      _clearOAuthData();
      rethrow;
    }
  }

  /// Build authorization URL for OAuth flow
  static Uri _buildAuthorizationUrl({
    required String platform,
    required String clientId,
    required String redirectUri,
    required List<String> scopes,
    required String state,
    String? codeChallenge,
  }) {
    final baseUrl = _getPlatformAuthUrl(platform);
    final queryParams = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scopes.join(' '),
      'state': state,
    };

    // Add PKCE parameters if supported
    if (codeChallenge != null) {
      queryParams['code_challenge'] = codeChallenge;
      queryParams['code_challenge_method'] = 'S256';
    }

    return Uri.https(baseUrl, _getPlatformAuthPath(platform), queryParams);
  }

  /// Get platform-specific authorization URL
  static String _getPlatformAuthUrl(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return 'twitter.com';
      case 'tiktok':
        return 'www.tiktok.com';
      case 'facebook':
        return 'www.facebook.com';
      case 'instagram':
        return 'www.instagram.com';
      case 'youtube':
        return 'accounts.google.com';
      default:
        throw Exception('Unsupported platform: $platform');
    }
  }

  /// Get platform-specific authorization path
  static String _getPlatformAuthPath(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return '/i/oauth2/authorize';
      case 'tiktok':
        return '/auth/authorize';
      case 'facebook':
        return '/v18.0/dialog/oauth';
      case 'instagram':
        return '/oauth/authorize';
      case 'youtube':
        return '/o/oauth2/v2/auth';
      default:
        throw Exception('Unsupported platform: $platform');
    }
  }

  /// Exchange authorization code for access tokens
  static Future<Map<String, dynamic>> _exchangeCodeForTokens({
    required String platform,
    required String clientId,
    required String clientSecret,
    required String authCode,
    required String redirectUri,
    String? codeVerifier,
  }) async {
    final tokenUrl = _getPlatformTokenUrl(platform);
    final body = <String, String>{
      'client_id': clientId,
      'client_secret': clientSecret,
      'grant_type': 'authorization_code',
      'code': authCode,
      'redirect_uri': redirectUri,
    };

    // Add PKCE code verifier if provided
    if (codeVerifier != null) {
      body['code_verifier'] = codeVerifier;
    }

    final response = await http.post(
      Uri.parse(tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Token exchange failed: ${response.statusCode} - ${response.body}');
    }

    final tokenData = json.decode(response.body);
    return Map<String, dynamic>.from(tokenData);
  }

  /// Get platform-specific token URL
  static String _getPlatformTokenUrl(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return 'https://api.twitter.com/2/oauth2/token';
      case 'tiktok':
        return 'https://open.tiktokapis.com/v2/oauth/token/';
      case 'facebook':
        return 'https://graph.facebook.com/v18.0/oauth/access_token';
      case 'instagram':
        return 'https://api.instagram.com/oauth/access_token';
      case 'youtube':
        return 'https://oauth2.googleapis.com/token';
      default:
        throw Exception('Unsupported platform: $platform');
    }
  }

  /// Generate PKCE code verifier
  static String _generateCodeVerifier([int length = 128]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
      length,
      (i) => chars[(DateTime.now().millisecondsSinceEpoch + i) % chars.length],
    ).join();
  }

  /// Generate PKCE code challenge
  static String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = _sha256Hash(bytes);
    return base64Url.encode(digest).replaceAll('=', '');
  }

  /// SHA-256 hash function
  static List<int> _sha256Hash(List<int> bytes) {
    // Simple SHA-256 implementation for web
    // In a real implementation, you'd use a proper crypto library
    return bytes; // Placeholder - implement proper SHA-256
  }

  /// Store OAuth data in browser storage
  static void _storeOAuthData(String state, String codeVerifier) {
    try {
      html.window.localStorage[_stateKey] = state;
      html.window.localStorage[_codeVerifierKey] = codeVerifier;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Could not store OAuth data: $e');
      }
    }
  }

  /// Clear stored OAuth data
  static void _clearOAuthData() {
    try {
      html.window.localStorage.remove(_stateKey);
      html.window.localStorage.remove(_codeVerifierKey);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Could not clear OAuth data: $e');
      }
    }
  }

  /// Check if web OAuth is supported for a platform
  static bool isPlatformSupported(String platform) {
    return WebOAuthConfig.isPlatformSupported(platform);
  }

  /// Get web OAuth setup status
  static bool isWebOAuthConfigured() {
    return WebOAuthConfig.isWebOAuthConfigured();
  }
}
