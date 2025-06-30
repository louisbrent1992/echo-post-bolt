import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:math';
import '../platform_document_service.dart';

/// TikTok (OAuth 2.0 with PKCE) - Updated for 2024 API requirements
class TikTokAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Updated TikTok OAuth endpoints (2024)
  static const String _authorizationEndpoint =
      'https://www.tiktok.com/v2/auth/authorize/';
  static const String _tokenEndpoint =
      'https://open.tiktokapis.com/v2/oauth/token/';
  static const String _userInfoEndpoint =
      'https://open.tiktokapis.com/v2/user/info/';

  /// Sign in with TikTok using OAuth 2.0 with PKCE
  Future<void> signInWithTikTok() async {
    try {
      if (kDebugMode) {
        print('🎵 Starting TikTok authentication...');
      }

      if (_auth.currentUser == null) {
        throw Exception('User must be signed in with Google or email first');
      }

      final clientKey = dotenv.env['TIKTOK_CLIENT_KEY'] ?? '';
      final clientSecret = dotenv.env['TIKTOK_CLIENT_SECRET'] ?? '';

      if (clientKey.isEmpty || clientSecret.isEmpty) {
        throw Exception(
            'TikTok client credentials not found in .env.local file. Please check ENVIRONMENT_SETUP.md for configuration instructions.');
      }

      // Step 1: Generate PKCE parameters
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);
      final state = _generateRandomString(32);

      // Step 2: Build authorization URL (CORRECTED)
      final authUrl = Uri.parse(_authorizationEndpoint).replace(
        queryParameters: {
          'client_key': clientKey,
          'scope': 'user.info.basic,video.upload',
          'response_type': 'code',
          'redirect_uri': 'echopost://tiktok-callback',
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      );

      if (kDebugMode) {
        print('🎵 TikTok Auth URL: $authUrl');
      }

      // Step 3: Launch web authentication
      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: 'echopost',
      );

      // Step 4: Extract authorization code from callback
      final callbackUri = Uri.parse(callbackUrl);
      final authCode = callbackUri.queryParameters['code'];
      final returnedState = callbackUri.queryParameters['state'];
      final error = callbackUri.queryParameters['error'];

      if (error != null) {
        throw Exception('TikTok authorization failed: $error');
      }

      if (authCode == null || returnedState != state) {
        throw Exception('TikTok authorization failed or was cancelled');
      }

      if (kDebugMode) {
        print(
            '🎵 Authorization code received: ${authCode.substring(0, 10)}...');
      }

      // Step 5: Exchange authorization code for access token (CORRECTED)
      final tokenData = await _exchangeCodeForToken(
        clientKey,
        clientSecret,
        authCode,
        codeVerifier,
      );

      if (tokenData == null) {
        throw Exception(
            'Failed to exchange authorization code for access token');
      }

      // Step 6: Get user information (CORRECTED)
      final userInfo = await _getTikTokUserInfo(tokenData['access_token']);

      if (userInfo == null) {
        throw Exception('Failed to get TikTok user information');
      }

      // Step 7: Save TikTok token and user info to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('tiktok')
          .set({
        'access_token': tokenData['access_token'],
        'refresh_token': tokenData['refresh_token'],
        'token_type': tokenData['token_type'] ?? 'Bearer',
        'expires_in': tokenData['expires_in'],
        'scope': tokenData['scope'] ?? 'user.info.basic,video.upload',
        'user_id': tokenData['open_id'] ?? userInfo['open_id'],
        'username': userInfo['username'],
        'display_name': userInfo['display_name'],
        'avatar_url': userInfo['avatar_url'],
        'follower_count': userInfo['follower_count'],
        'following_count': userInfo['following_count'],
        'likes_count': userInfo['likes_count'],
        'video_count': userInfo['video_count'],
        'created_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ TikTok authentication completed successfully');
        print('🎵 Open ID: ${tokenData['open_id'] ?? userInfo['open_id']}');
        print('🎵 Username: ${userInfo['username']}');
        print('🎵 Display Name: ${userInfo['display_name']}');
        print('🎵 Followers: ${userInfo['follower_count']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ TikTok authentication error: $e');
      }
      throw Exception('TikTok authentication failed: $e');
    }
  }

  /// Check if TikTok is connected
  Future<bool> isTikTokConnected() async {
    try {
      if (_auth.currentUser == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('tiktok')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data();
      if (tokenData == null) return false;

      final accessToken = tokenData['access_token'] as String?;
      final userId = tokenData['user_id'] as String?;

      // Check if we have the required TikTok data
      if (accessToken == null || userId == null) return false;

      // Check if token is expired using expires_in and created_at
      final expiresIn = tokenData['expires_in'] as int?;
      final createdAt = tokenData['created_at'] as Timestamp?;
      if (expiresIn != null && createdAt != null) {
        final expirationDate =
            createdAt.toDate().add(Duration(seconds: expiresIn));
        if (expirationDate.isBefore(DateTime.now())) {
          return false;
        }
      }

      return true; // Token exists and is not expired
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking TikTok connection: $e');
      }
      return false;
    }
  }

  /// Get TikTok access token
  Future<String> getTikTokAccessToken() async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('tiktok')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'TikTok access token not found. Please authenticate with TikTok first.');
      }

      final tokenData = tokenDoc.data();
      if (tokenData == null) {
        throw Exception(
            'TikTok token data is null. Please re-authenticate with TikTok.');
      }

      final accessToken = tokenData['access_token'] as String?;
      if (accessToken == null) {
        throw Exception(
            'TikTok access token is null. Please re-authenticate with TikTok.');
      }

      // Check if token is expired
      final expiresIn = tokenData['expires_in'] as int?;
      final createdAt = tokenData['created_at'] as Timestamp?;
      if (expiresIn != null && createdAt != null) {
        final expirationDate =
            createdAt.toDate().add(Duration(seconds: expiresIn));
        if (expirationDate.isBefore(DateTime.now())) {
          throw Exception(
              'TikTok access token has expired. Please re-authenticate.');
        }
      }

      return accessToken;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting TikTok access token: $e');
      }
      rethrow;
    }
  }

  /// Sign out of TikTok
  Future<void> signOutOfTikTok() async {
    try {
      if (kDebugMode) {
        print('🎵 Signing out of TikTok...');
      }

      // NEW: Use PlatformDocumentService for consistent nullification
      if (_auth.currentUser != null) {
        final nullifiedFields =
            PlatformDocumentService.getNullifiedFieldsForPlatform('tiktok');
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('tiktok')
            .set(nullifiedFields);
      }

      if (kDebugMode) {
        print('✅ TikTok sign out completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error signing out of TikTok: $e');
      }
      rethrow;
    }
  }

  /// Generate code verifier for PKCE
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(128, (i) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Generate code challenge for PKCE
  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Generate random string for state parameter
  String _generateRandomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (i) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Exchange authorization code for access token (CORRECTED)
  Future<Map<String, dynamic>?> _exchangeCodeForToken(
    String clientKey,
    String clientSecret,
    String authCode,
    String codeVerifier,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cache-Control': 'no-cache',
        },
        body: {
          'client_key': clientKey,
          'client_secret': clientSecret,
          'code': authCode,
          'grant_type': 'authorization_code',
          'redirect_uri': 'echopost://tiktok-callback',
          'code_verifier': codeVerifier,
        },
      );

      if (kDebugMode) {
        print(
            '📥 TikTok token exchange response status: ${response.statusCode}');
        print('📥 TikTok token exchange response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check for error in response (TikTok 2024 format)
        if (data.containsKey('error')) {
          throw Exception(
              'TikTok token exchange error: ${data['error_description'] ?? data['error']}');
        }

        // CORRECTED: Direct access to response fields (no nested 'data' object)
        return {
          'access_token': data['access_token'],
          'refresh_token': data['refresh_token'],
          'expires_in': data['expires_in'],
          'token_type': data['token_type'],
          'scope': data['scope'],
          'open_id': data['open_id'],
        };
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'TikTok token exchange failed: ${errorData['error_description'] ?? response.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ TikTok token exchange error: $e');
      }
      rethrow;
    }
  }

  /// Get TikTok user info (CORRECTED)
  Future<Map<String, dynamic>?> _getTikTokUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse(_userInfoEndpoint).replace(queryParameters: {
          'fields':
              'open_id,union_id,avatar_url,display_name,username,follower_count,following_count,likes_count,video_count',
        }),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (kDebugMode) {
        print('📥 TikTok user info response status: ${response.statusCode}');
        print('📥 TikTok user info response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check for error in response
        if (data.containsKey('error')) {
          throw Exception(
              'TikTok user info error: ${data['error_description'] ?? data['error']}');
        }

        // CORRECTED: Access user data from 'data.user' structure
        final user = data['data']['user'];
        return {
          'open_id': user['open_id'],
          'username': user['username'] ?? '',
          'display_name': user['display_name'] ?? '',
          'avatar_url': user['avatar_url'] ?? '',
          'follower_count': user['follower_count'] ?? 0,
          'following_count': user['following_count'] ?? 0,
          'likes_count': user['likes_count'] ?? 0,
          'video_count': user['video_count'] ?? 0,
        };
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'TikTok user info request failed: ${errorData['error_description'] ?? response.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting TikTok user info: $e');
      }
      rethrow;
    }
  }

  /// Get TikTok user statistics
  Future<Map<String, dynamic>?> getTikTokUserStats() async {
    try {
      final accessToken = await getTikTokAccessToken();
      return await _getTikTokUserInfo(accessToken);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting TikTok user stats: $e');
      }
      return null;
    }
  }

  /// Check if user can upload videos to TikTok
  Future<bool> canUploadToTikTok() async {
    try {
      // Check if we have a valid access token with upload scope
      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('tiktok')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data()!;
      final scope = tokenData['scope'] as String?;

      // Check if the scope includes video upload permissions
      if (scope == null || !scope.contains('video.upload')) {
        return false;
      }

      // Verify token is still valid
      return await isTikTokConnected();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking TikTok upload permission: $e');
      }
      return false;
    }
  }
}
