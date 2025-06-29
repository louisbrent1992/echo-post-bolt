import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../platform_document_service.dart';

/// Twitter (OAuth 2.0) - required for tweet posting
class TwitterAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in with Twitter using OAuth 2.0 with PKCE
  Future<void> signInWithTwitter() async {
    try {
      if (kDebugMode) {
        print('🐦 Starting Twitter OAuth 2.0 authentication...');
      }

      if (_auth.currentUser == null) {
        throw Exception('User must be signed in with Google or email first');
      }

      final clientId = dotenv.env['TWITTER_CLIENT_ID'] ?? '';
      final clientSecret = dotenv.env['TWITTER_CLIENT_SECRET'] ?? '';
      final redirectUri = dotenv.env['TWITTER_REDIRECT_URI'] ?? '';

      if (clientId.isEmpty || clientSecret.isEmpty || redirectUri.isEmpty) {
        throw Exception(
            'Twitter OAuth 2.0 credentials not found in .env.local file. Please check ENVIRONMENT_SETUP.md for configuration instructions.');
      }

      // Step 1: Generate PKCE code verifier and challenge
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      if (kDebugMode) {
        print('🐦 Generated PKCE code challenge');
      }

      // Step 2: Build authorization URL
      final authUrl = Uri.https('twitter.com', '/i/oauth2/authorize', {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': 'tweet.read tweet.write users.read offline.access',
        'state': _generateState(),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      });

      if (kDebugMode) {
        print('🐦 Authorization URL: ${authUrl.toString()}');
      }

      // Step 3: Launch web authentication with improved error handling
      String? callbackUrl;
      try {
        callbackUrl = await FlutterWebAuth2.authenticate(
          url: authUrl.toString(),
          callbackUrlScheme: Uri.parse(redirectUri).scheme,
          options: const FlutterWebAuth2Options(
            timeout: 120, // 2 minutes timeout
            preferEphemeral: true, // Use ephemeral session for better security
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          print('❌ Twitter OAuth 2.0 authentication failed: $e');
        }

        // Handle specific error cases
        if (e.toString().contains('User cancelled') ||
            e.toString().contains('CANCELLED')) {
          throw Exception('Twitter authentication was cancelled by user');
        } else if (e.toString().contains('timeout') ||
            e.toString().contains('TIMEOUT')) {
          throw Exception(
              'Twitter authentication timed out. Please try again.');
        } else if (e.toString().contains('redirect') ||
            e.toString().contains('callback')) {
          throw Exception(
              'Twitter authentication redirect failed. Please check your app configuration in Twitter Developer Console and ensure the redirect URI "echopost://twitter-callback" is properly registered.');
        } else {
          throw Exception('Twitter authentication failed: $e');
        }
      }

      if (callbackUrl.isEmpty) {
        throw Exception(
            'Twitter authentication failed: No callback URL received');
      }

      if (kDebugMode) {
        print('🐦 Callback URL received: $callbackUrl');
      }

      // Step 4: Extract authorization code from callback
      final callbackUri = Uri.parse(callbackUrl);

      if (kDebugMode) {
        print('🐦 Parsing callback URI: ${callbackUri.toString()}');
        print('🐦 Callback URI scheme: ${callbackUri.scheme}');
        print('🐦 Callback URI host: ${callbackUri.host}');
        print('🐦 Callback URI path: ${callbackUri.path}');
        print(
            '🐦 Callback URI query parameters: ${callbackUri.queryParameters}');
      }

      final authCode = callbackUri.queryParameters['code'];
      final error = callbackUri.queryParameters['error'];
      final errorDescription = callbackUri.queryParameters['error_description'];

      // Check for OAuth errors first
      if (error != null) {
        final errorMsg = errorDescription ?? error;
        if (kDebugMode) {
          print('❌ Twitter OAuth error: $error - $errorDescription');
        }
        throw Exception('Twitter authentication failed: $errorMsg');
      }

      if (authCode == null) {
        if (kDebugMode) {
          print('❌ No authorization code found in callback URL');
          print(
              '🐦 Available parameters: ${callbackUri.queryParameters.keys.join(', ')}');
        }
        throw Exception(
            'Twitter authorization failed: No authorization code received. This may indicate a redirect URI mismatch in your Twitter Developer Console configuration.');
      }

      if (kDebugMode) {
        print(
            '🐦 Authorization code received: ${authCode.substring(0, 10)}...');
      }

      // Step 5: Exchange authorization code for access token
      final tokenResponse = await http.post(
        Uri.parse('https://api.twitter.com/2/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': authCode,
          'redirect_uri': redirectUri,
          'code_verifier': codeVerifier,
        },
      );

      if (tokenResponse.statusCode != 200) {
        throw Exception(
            'Failed to exchange authorization code for token: ${tokenResponse.body}');
      }

      final tokenData = jsonDecode(tokenResponse.body);
      final accessToken = tokenData['access_token'];
      final refreshToken = tokenData['refresh_token'];
      final tokenType = tokenData['token_type'];
      final scope = tokenData['scope'];
      final expiresIn = tokenData['expires_in'];

      if (kDebugMode) {
        print('🐦 Access token received: ${accessToken.substring(0, 10)}...');
      }

      // Step 6: Get user information
      final userInfo = await _getTwitterUserInfo(accessToken);

      // Step 7: Save Twitter credentials to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('twitter')
          .set({
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'token_type': tokenType,
        'scope': scope,
        'expires_in': expiresIn,
        'expires_at':
            DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String(),
        'user_id': userInfo['id'],
        'username': userInfo['username'],
        'name': userInfo['name'],
        'profile_image_url': userInfo['profile_image_url'],
        'followers_count': userInfo['public_metrics']['followers_count'],
        'following_count': userInfo['public_metrics']['following_count'],
        'tweet_count': userInfo['public_metrics']['tweet_count'],
        'verified': userInfo['verified'],
        'created_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ Twitter OAuth 2.0 authentication completed successfully');
        print('🐦 User ID: ${userInfo['id']}');
        print('🐦 Username: @${userInfo['username']}');
        print('🐦 Name: ${userInfo['name']}');
        print('🐦 Followers: ${userInfo['public_metrics']['followers_count']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Twitter OAuth 2.0 authentication error: $e');
      }
      throw Exception('Twitter authentication failed: $e');
    }
  }

  /// Check if Twitter is connected
  Future<bool> isTwitterConnected() async {
    try {
      if (_auth.currentUser == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('twitter')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data();
      if (tokenData == null) return false;

      final accessToken = tokenData['access_token'] as String?;
      final userId = tokenData['user_id'] as String?;

      // Check if we have the required Twitter OAuth 2.0 data
      if (accessToken == null || userId == null) {
        return false;
      }

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as String?;
      if (expiresAt != null) {
        final expiryDate = DateTime.parse(expiresAt);
        if (DateTime.now().isAfter(expiryDate)) {
          // Token is expired, try to refresh it
          return await _refreshTwitterToken();
        }
      }

      return true; // Token exists and is valid
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking Twitter connection: $e');
      }
      return false;
    }
  }

  /// Get Twitter access token (returns OAuth 2.0 access token)
  Future<String> getTwitterAccessToken() async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('twitter')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Twitter access token not found. Please authenticate with Twitter first.');
      }

      final tokenData = tokenDoc.data();
      if (tokenData == null) {
        throw Exception(
            'Twitter token data is null. Please re-authenticate with Twitter.');
      }

      final accessToken = tokenData['access_token'] as String?;

      if (accessToken == null) {
        throw Exception(
            'Twitter access token is null. Please re-authenticate with Twitter.');
      }

      // Check if token is expired and refresh if needed
      final expiresAt = tokenData['expires_at'] as String?;
      if (expiresAt != null) {
        final expiryDate = DateTime.parse(expiresAt);
        if (DateTime.now().isAfter(expiryDate)) {
          // Token is expired, refresh it
          await _refreshTwitterToken();
          // Get the refreshed token
          return await getTwitterAccessToken();
        }
      }

      return accessToken;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Twitter access token: $e');
      }
      rethrow;
    }
  }

  /// Get Twitter OAuth 2.0 credentials
  Future<Map<String, String>> getTwitterCredentials() async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('twitter')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Twitter credentials not found. Please authenticate with Twitter first.');
      }

      final tokenData = tokenDoc.data();
      if (tokenData == null) {
        throw Exception(
            'Twitter token data is null. Please re-authenticate with Twitter.');
      }

      final accessToken = tokenData['access_token'] as String?;
      final userId = tokenData['user_id'] as String?;
      final username = tokenData['username'] as String?;

      if (accessToken == null || userId == null || username == null) {
        throw Exception(
            'Twitter credentials are incomplete. Please re-authenticate with Twitter.');
      }

      return {
        'access_token': accessToken,
        'user_id': userId,
        'username': username,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Twitter credentials: $e');
      }
      rethrow;
    }
  }

  /// Sign out of Twitter
  Future<void> signOutOfTwitter() async {
    try {
      if (kDebugMode) {
        print('🐦 Signing out of Twitter...');
      }

      // NEW: Use PlatformDocumentService for consistent nullification
      if (_auth.currentUser != null) {
        final nullifiedFields =
            PlatformDocumentService.getNullifiedFieldsForPlatform('twitter');
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('twitter')
            .set(nullifiedFields);
      }

      if (kDebugMode) {
        print('✅ Twitter sign out completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error signing out of Twitter: $e');
      }
      rethrow;
    }
  }

  /// Get Twitter user information using OAuth 2.0
  Future<Map<String, dynamic>> _getTwitterUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.twitter.com/2/users/me').replace(
          queryParameters: {
            'user.fields': 'name,profile_image_url,public_metrics,verified',
          },
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print('📥 Twitter user info response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      } else {
        if (kDebugMode) {
          print('❌ Twitter user info request failed: ${response.body}');
        }
        // Return basic info if API call fails
        return {
          'id': 'unknown',
          'username': 'twitter_user',
          'name': 'Twitter User',
          'profile_image_url': '',
          'public_metrics': {
            'followers_count': 0,
            'following_count': 0,
            'tweet_count': 0,
          },
          'verified': false,
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Twitter user info: $e');
      }
      // Return basic info if error occurs
      return {
        'id': 'unknown',
        'username': 'twitter_user',
        'name': 'Twitter User',
        'profile_image_url': '',
        'public_metrics': {
          'followers_count': 0,
          'following_count': 0,
          'tweet_count': 0,
        },
        'verified': false,
      };
    }
  }

  /// Refresh Twitter access token using refresh token
  Future<bool> _refreshTwitterToken() async {
    try {
      if (kDebugMode) {
        print('🔄 Refreshing Twitter access token...');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('twitter')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data();
      if (tokenData == null) return false;

      final refreshToken = tokenData['refresh_token'] as String?;
      if (refreshToken == null) return false;

      final clientId = dotenv.env['TWITTER_CLIENT_ID'] ?? '';
      final clientSecret = dotenv.env['TWITTER_CLIENT_SECRET'] ?? '';

      final refreshResponse = await http.post(
        Uri.parse('https://api.twitter.com/2/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );

      if (refreshResponse.statusCode == 200) {
        final newTokenData = jsonDecode(refreshResponse.body);

        // Update the stored token
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('twitter')
            .update({
          'access_token': newTokenData['access_token'],
          'refresh_token': newTokenData['refresh_token'],
          'expires_in': newTokenData['expires_in'],
          'expires_at': DateTime.now()
              .add(Duration(seconds: newTokenData['expires_in']))
              .toIso8601String(),
          'last_updated': FieldValue.serverTimestamp(),
        });

        if (kDebugMode) {
          print('✅ Twitter token refreshed successfully');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('❌ Failed to refresh Twitter token: ${refreshResponse.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error refreshing Twitter token: $e');
      }
      return false;
    }
  }

  /// Get Twitter user statistics
  Future<Map<String, dynamic>?> getTwitterUserStats() async {
    try {
      final accessToken = await getTwitterAccessToken();

      final response = await http.get(
        Uri.parse('https://api.twitter.com/2/users/me').replace(
          queryParameters: {
            'user.fields': 'public_metrics,verified',
          },
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['data'];
        final metrics = user['public_metrics'];

        return {
          'followers_count': metrics['followers_count'],
          'following_count': metrics['following_count'],
          'tweet_count': metrics['tweet_count'],
          'listed_count': metrics['listed_count'],
          'verified': user['verified'] ?? false,
        };
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Twitter user stats: $e');
      }
      return null;
    }
  }

  /// Generate PKCE code verifier
  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Generate PKCE code challenge
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// Generate random state parameter
  String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
