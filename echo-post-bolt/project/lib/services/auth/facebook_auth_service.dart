import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../platform_document_service.dart';

/// Facebook via Graph API - OAuth 2.0
class FacebookAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in with Facebook Business Account
  Future<void> signInWithFacebook() async {
    try {
      if (kDebugMode) {
        print('🔵 Starting Facebook authentication...');
      }

      if (_auth.currentUser == null) {
        throw Exception('User must be signed in with Google or email first');
      }

      final LoginResult result = await FacebookAuth.instance.login(
        permissions: [
          'business_management',
          'pages_show_list',
          'pages_read_engagement',
          'pages_manage_posts',
          'instagram_basic',
          'instagram_content_publish',
        ],
      );

      if (result.status == LoginStatus.success) {
        final AccessToken accessToken = result.accessToken!;
        final userData = await FacebookAuth.instance.getUserData();

        if (kDebugMode) {
          print('🔵 Facebook login successful for user: ${userData['name']}');
        }

        // Save token to Firestore
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('facebook')
            .set({
          'access_token': accessToken.token,
          'user_id': userData['id'],
          'expires_at': Timestamp.fromDate(accessToken.expires),
          'user_name': userData['name'],
          'user_email': userData['email'],
          'created_at': FieldValue.serverTimestamp(),
          'last_updated': FieldValue.serverTimestamp(),
        });

        if (kDebugMode) {
          print('✅ Facebook token saved to Firestore');
        }
      } else {
        throw Exception('Facebook login failed: ${result.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Facebook authentication error: $e');
      }
      rethrow;
    }
  }

  /// Check if Facebook is connected
  Future<bool> isFacebookConnected() async {
    try {
      if (_auth.currentUser == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('facebook')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data();
      if (tokenData == null) return false;

      final accessToken = tokenData['access_token'] as String?;
      if (accessToken == null) return false;

      final expiresAt = tokenData['expires_at'] as Timestamp?;

      // Check if token is expired
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        return false;
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking Facebook connection: $e');
      }
      return false;
    }
  }

  /// Get Facebook access token
  Future<String> getFacebookAccessToken() async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('facebook')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Facebook access token not found. Please authenticate with Facebook first.');
      }

      final tokenData = tokenDoc.data();
      if (tokenData == null) {
        throw Exception(
            'Facebook token data is null. Please re-authenticate with Facebook.');
      }

      final accessToken = tokenData['access_token'] as String?;
      if (accessToken == null) {
        throw Exception(
            'Facebook access token is null. Please re-authenticate with Facebook.');
      }

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        throw Exception(
            'Facebook access token has expired. Please re-authenticate.');
      }

      return accessToken;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Facebook access token: $e');
      }
      rethrow;
    }
  }

  /// Sign out of Facebook
  Future<void> signOutOfFacebook() async {
    try {
      if (kDebugMode) {
        print('🔵 Signing out of Facebook...');
      }

      // Sign out from Facebook SDK
      await FacebookAuth.instance.logOut();

      // NEW: Use PlatformDocumentService for consistent nullification
      if (_auth.currentUser != null) {
        final nullifiedFields =
            PlatformDocumentService.getNullifiedFieldsForPlatform('facebook');
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('facebook')
            .set(nullifiedFields);
      }

      if (kDebugMode) {
        print('✅ Facebook sign out completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error signing out of Facebook: $e');
      }
      rethrow;
    }
  }

  /// Get list of Facebook Pages that the user manages
  Future<List<Map<String, dynamic>>> getFacebookPages() async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final accessToken = await getFacebookAccessToken();

      // Get user's pages using Facebook Graph API
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v23.0/me/accounts?access_token=$accessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pages = data['data'] as List<dynamic>;

        if (kDebugMode) {
          print('📄 Found ${pages.length} Facebook pages');
        }

        return pages
            .map((page) => {
                  'id': page['id'],
                  'name': page['name'],
                  'access_token': page['access_token'],
                  'category': page['category'],
                  'tasks': page['tasks'] ?? [],
                  'permissions': page['perms'] ?? [],
                })
            .toList();
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage =
            errorData['error']?['message'] ?? 'Unknown Facebook API error';
        final errorCode = errorData['error']?['code'] ?? 'unknown';

        if (kDebugMode) {
          print('❌ Facebook API error: $errorMessage (Code: $errorCode)');
        }

        // Handle specific error cases
        switch (errorCode) {
          case '190':
            throw Exception(
                'Facebook access token expired or invalid. Please re-authenticate.');
          case '100':
            throw Exception(
                'Facebook API permission error. Check app permissions.');
          case '200':
            throw Exception(
                'Facebook app requires review for pages_show_list permission. Please contact support.');
          default:
            throw Exception(
                'Facebook API error: $errorMessage (Code: $errorCode)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Facebook pages: $e');
      }
      rethrow;
    }
  }

  /// Get Facebook page access token for a specific page
  Future<String?> getFacebookPageAccessToken(String pageId) async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final userAccessToken = await getFacebookAccessToken();

      // Get page access token using /me/accounts
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v23.0/me/accounts?access_token=$userAccessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pages = data['data'] as List<dynamic>;
        final page = pages.firstWhere(
          (p) => p['id'] == pageId,
          orElse: () => null,
        );

        if (page == null) {
          throw Exception('Page not found in user accounts.');
        }

        final pageAccessToken = page['access_token'] as String?;
        if (pageAccessToken == null) {
          throw Exception('Page access token not found for page $pageId.');
        }

        // Store the page access token for future use
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('facebook_pages')
            .set({
          'page_tokens.$pageId': {
            'access_token': pageAccessToken,
            'expires_at': Timestamp.fromDate(
                DateTime.now().add(const Duration(days: 60))),
            'stored_at': FieldValue.serverTimestamp(),
          },
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (kDebugMode) {
          print(
              '✅ Successfully obtained and stored page access token for page: $pageId');
        }

        return pageAccessToken;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage =
            errorData['error']?['message'] ?? 'Unknown Facebook API error';
        final errorCode = errorData['error']?['code'] ?? 'unknown';

        if (kDebugMode) {
          print(
              '❌ Failed to get page access token: $errorMessage (Code: $errorCode)');
        }

        throw Exception('Facebook API error: $errorMessage (Code: $errorCode)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting page access token: $e');
      }
      rethrow;
    }
  }

  /// Check if user has permission to post to a specific Facebook page
  Future<bool> canPostToFacebookPage(String pageId) async {
    try {
      final pages = await getFacebookPages();

      for (final page in pages) {
        if (page['id'] == pageId) {
          final permissions = page['permissions'] as List<dynamic>;
          final tasks = page['tasks'] as List<dynamic>;

          final hasPostPermission = permissions.contains('ADMINISTER') ||
              permissions.contains('EDIT_PROFILE') ||
              permissions.contains('CREATE_CONTENT') ||
              tasks.contains('MANAGE') ||
              tasks.contains('CREATE_CONTENT');

          if (kDebugMode) {
            print(
                '📄 Page ${page['name']} (${page['id']}) can post: $hasPostPermission');
          }

          return hasPostPermission;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking page posting permission: $e');
      }
      return false;
    }
  }
}
