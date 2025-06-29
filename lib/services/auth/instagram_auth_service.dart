import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:math';
import '../platform_document_service.dart';

/// Instagram OAuth 2.0 - Direct Instagram authentication (not via Facebook)
class InstagramAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String instagramAppId = dotenv.env['INSTAGRAM_APP_ID'] ?? '';
  final String instagramAppSecret = dotenv.env['INSTAGRAM_APP_SECRET'] ?? '';
  final String instagramRedirectUri =
      dotenv.env['INSTAGRAM_REDIRECT_URI'] ?? '';

  /// Sign in with Instagram using OAuth 2.0
  Future<void> signInWithInstagram() async {
    try {
      if (kDebugMode) {
        print('📷 Starting Instagram authentication...');
      }

      if (_auth.currentUser == null) {
        throw Exception('User must be signed in with Google or email first');
      }

      // Validate environment variables
      if (instagramAppId.isEmpty ||
          instagramAppSecret.isEmpty ||
          instagramRedirectUri.isEmpty) {
        throw Exception(
            'Instagram API credentials not found in .env.local file. Please check ENVIRONMENT_SETUP.md for configuration instructions.');
      }

      // Step 1: Generate state parameter for security
      final state = _generateRandomString(32);

      // Step 2: Build authorization URL
      final authUrl =
          Uri.parse('https://www.instagram.com/oauth/authorize').replace(
        queryParameters: {
          'client_id': instagramAppId,
          'redirect_uri': instagramRedirectUri,
          'response_type': 'code',
          'scope':
              'instagram_basic,instagram_content_publish,instagram_manage_comments',
          'state': state,
        },
      );

      if (kDebugMode) {
        print('📷 Instagram Auth URL: $authUrl');
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
        throw Exception('Instagram authorization failed: $error');
      }

      if (authCode == null || returnedState != state) {
        throw Exception('Instagram authorization failed or was cancelled');
      }

      if (kDebugMode) {
        print(
            '📷 Authorization code received: ${authCode.substring(0, 10)}...');
      }

      // Step 5: Exchange authorization code for access token
      final tokenData = await _exchangeCodeForToken(authCode);

      if (tokenData == null) {
        throw Exception(
            'Failed to exchange authorization code for access token');
      }

      // Step 6: Get user information
      final userInfo = await _getInstagramUserInfo(tokenData['access_token']);

      if (userInfo == null) {
        throw Exception('Failed to get Instagram user information');
      }

      // Step 7: Save Instagram token and user info to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('instagram')
          .set({
        'access_token': tokenData['access_token'],
        'user_id': userInfo['id'],
        'username': userInfo['username'],
        'account_type': userInfo['account_type'],
        'media_count': userInfo['media_count'],
        'expires_in': tokenData['expires_in'],
        'token_type': 'Bearer',
        'scope':
            'instagram_basic,instagram_content_publish,instagram_manage_comments',
        'created_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ Instagram authentication completed successfully');
        print('📷 User ID: ${userInfo['id']}');
        print('📷 Username: ${userInfo['username']}');
        print('📷 Account Type: ${userInfo['account_type']}');
        print('📷 Media Count: ${userInfo['media_count']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Instagram authentication error: $e');
      }
      throw Exception('Instagram authentication failed: $e');
    }
  }

  /// Exchange authorization code for access token
  Future<Map<String, dynamic>?> _exchangeCodeForToken(String authCode) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.instagram.com/oauth/access_token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': instagramAppId,
          'client_secret': instagramAppSecret,
          'grant_type': 'authorization_code',
          'redirect_uri': instagramRedirectUri,
          'code': authCode,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'access_token': data['access_token'],
          'user_id': data['user_id'],
          'expires_in': data['expires_in'] ?? 5184000, // 60 days default
        };
      } else {
        if (kDebugMode) {
          print('❌ Failed to exchange code for token: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error exchanging code for token: $e');
      }
      return null;
    }
  }

  /// Get Instagram user information
  Future<Map<String, dynamic>?> _getInstagramUserInfo(
      String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://graph.instagram.com/me').replace(
          queryParameters: {
            'fields': 'id,username,account_type,media_count',
            'access_token': accessToken,
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'username': data['username'],
          'account_type': data['account_type'],
          'media_count': data['media_count'],
        };
      } else {
        if (kDebugMode) {
          print('❌ Failed to get Instagram user info: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Instagram user info: $e');
      }
      return null;
    }
  }

  /// Generate random string for state parameter
  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
          length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  /// Check if Instagram is connected
  Future<bool> isInstagramConnected() async {
    try {
      if (_auth.currentUser == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('instagram')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data();
      if (tokenData == null) return false;

      final accessToken = tokenData['access_token'] as String?;
      final userId = tokenData['user_id'] as String?;

      // Check if we have the required Instagram data
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
        print('❌ Error checking Instagram connection: $e');
      }
      return false;
    }
  }

  /// Get Instagram access token
  Future<String> getInstagramAccessToken() async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('instagram')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Instagram access token not found. Please authenticate with Instagram first.');
      }

      final tokenData = tokenDoc.data();
      if (tokenData == null) {
        throw Exception(
            'Instagram token data is null. Please re-authenticate with Instagram.');
      }

      final accessToken = tokenData['access_token'] as String?;
      if (accessToken == null) {
        throw Exception(
            'Instagram access token is null. Please re-authenticate with Instagram.');
      }

      // Check if token is expired
      final expiresIn = tokenData['expires_in'] as int?;
      final createdAt = tokenData['created_at'] as Timestamp?;
      if (expiresIn != null && createdAt != null) {
        final expirationDate =
            createdAt.toDate().add(Duration(seconds: expiresIn));
        if (expirationDate.isBefore(DateTime.now())) {
          throw Exception(
              'Instagram access token has expired. Please re-authenticate.');
        }
      }

      // Test token validity
      final response = await http.get(
        Uri.parse('https://graph.instagram.com/me').replace(
          queryParameters: {
            'fields': 'id',
            'access_token': accessToken,
          },
        ),
      );

      if (response.statusCode == 401) {
        throw Exception(
            'Instagram access token has expired. Please re-authenticate.');
      } else if (response.statusCode != 200) {
        throw Exception(
            'Instagram access token is invalid. Please re-authenticate.');
      }

      return accessToken;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Instagram access token: $e');
      }
      rethrow;
    }
  }

  /// Sign out of Instagram
  Future<void> signOutOfInstagram() async {
    try {
      if (kDebugMode) {
        print('📷 Signing out of Instagram...');
      }

      // NEW: Use PlatformDocumentService for consistent nullification
      if (_auth.currentUser != null) {
        final nullifiedFields =
            PlatformDocumentService.getNullifiedFieldsForPlatform('instagram');
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('instagram')
            .set(nullifiedFields);
      }

      if (kDebugMode) {
        print('✅ Instagram sign out completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error signing out of Instagram: $e');
      }
      rethrow;
    }
  }
}
