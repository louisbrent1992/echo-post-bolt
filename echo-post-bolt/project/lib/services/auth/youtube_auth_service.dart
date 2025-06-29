import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../platform_document_service.dart';

/// YouTube Data API login - OAuth 2.0 (separate from Google sign-in)
class YouTubeAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String youtubeApiKey = dotenv.env['YOUTUBE_API_KEY'] ?? '';

  // YouTube-specific Google Sign-In with YouTube scopes
  final GoogleSignIn _youtubeGoogleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/youtube',
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
    ],
  );

  /// Sign in with YouTube (requires YouTube scopes)
  Future<void> signInWithYouTube() async {
    try {
      if (kDebugMode) {
        print('🔴 Starting YouTube authentication...');
      }

      if (_auth.currentUser == null) {
        throw Exception('User must be signed in with Google or email first');
      }

      // Validate environment variables
      if (youtubeApiKey.isEmpty) {
        throw Exception(
            'YOUTUBE_API_KEY not found in .env.local file. Please check ENVIRONMENT_SETUP.md for configuration instructions.');
      }

      // Sign in with YouTube-specific scopes
      final GoogleSignInAccount? googleUser =
          await _youtubeGoogleSignIn.signIn();

      if (googleUser == null) {
        throw Exception('YouTube sign-in was cancelled');
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.accessToken == null) {
        throw Exception('No access token received from YouTube sign-in');
      }

      if (kDebugMode) {
        print('✅ Google authentication successful');
        print(
            '🔴 Access token: ${googleAuth.accessToken!.substring(0, 20)}...');
      }

      // Verify YouTube channel access
      final channelInfo = await _getYouTubeChannelInfo(googleAuth.accessToken!);

      if (channelInfo == null) {
        throw Exception(
            'Failed to get YouTube channel information. Please ensure you have a YouTube channel.');
      }

      // Save YouTube token and channel info to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('youtube')
          .set({
        'access_token': googleAuth.accessToken,
        'refresh_token': googleAuth.idToken,
        'token_type': 'Bearer',
        'scope': 'youtube,youtube.upload,youtube.readonly',
        'channel_id': channelInfo['id'],
        'channel_title': channelInfo['title'],
        'channel_description': channelInfo['description'],
        'subscriber_count': channelInfo['subscriberCount'],
        'video_count': channelInfo['videoCount'],
        'view_count': channelInfo['viewCount'],
        'created_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ YouTube authentication completed successfully');
        print('🔴 Channel ID: ${channelInfo['id']}');
        print('🔴 Channel Title: ${channelInfo['title']}');
        print('🔴 Subscriber Count: ${channelInfo['subscriberCount']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ YouTube authentication error: $e');
      }
      // Clean up on error
      await _youtubeGoogleSignIn.signOut();
      throw Exception('YouTube authentication failed: $e');
    }
  }

  /// Check if YouTube is connected
  Future<bool> isYouTubeConnected() async {
    try {
      if (_auth.currentUser == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('youtube')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data();
      if (tokenData == null) return false;

      final accessToken = tokenData['access_token'] as String?;
      final channelId = tokenData['channel_id'] as String?;

      // Check if we have the required YouTube data
      if (accessToken == null || channelId == null) return false;

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
        print('❌ Error checking YouTube connection: $e');
      }
      return false;
    }
  }

  /// Get YouTube access token
  Future<String> getYouTubeAccessToken() async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('youtube')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'YouTube access token not found. Please authenticate with YouTube first.');
      }

      final tokenData = tokenDoc.data();
      if (tokenData == null) {
        throw Exception(
            'YouTube token data is null. Please re-authenticate with YouTube.');
      }

      final accessToken = tokenData['access_token'] as String?;
      if (accessToken == null) {
        throw Exception(
            'YouTube access token is null. Please re-authenticate with YouTube.');
      }

      // Test token validity
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/youtube/v3/channels').replace(
          queryParameters: {
            'part': 'id',
            'mine': 'true',
          },
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 401) {
        throw Exception(
            'YouTube access token has expired. Please re-authenticate.');
      } else if (response.statusCode != 200) {
        throw Exception(
            'YouTube access token is invalid. Please re-authenticate.');
      }

      return accessToken;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting YouTube access token: $e');
      }
      rethrow;
    }
  }

  /// Sign out of YouTube
  Future<void> signOutOfYouTube() async {
    try {
      if (kDebugMode) {
        print('🔴 Signing out of YouTube...');
      }

      // Sign out from YouTube-specific Google Sign-In
      await _youtubeGoogleSignIn.signOut();
      await _youtubeGoogleSignIn.disconnect();

      // NEW: Use PlatformDocumentService for consistent nullification
      if (_auth.currentUser != null) {
        final nullifiedFields =
            PlatformDocumentService.getNullifiedFieldsForPlatform('youtube');
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('youtube')
            .set(nullifiedFields);
      }

      if (kDebugMode) {
        print('✅ YouTube sign out completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error signing out of YouTube: $e');
      }
      rethrow;
    }
  }

  /// Get YouTube channel information
  Future<Map<String, dynamic>?> _getYouTubeChannelInfo(
      String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/youtube/v3/channels').replace(
          queryParameters: {
            'part': 'id,snippet,statistics',
            'mine': 'true',
          },
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print(
            '📥 YouTube channel info response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final channels = data['items'] as List<dynamic>;

        if (channels.isEmpty) {
          throw Exception('No YouTube channel found for this account');
        }

        final channel = channels.first;
        return {
          'id': channel['id'],
          'title': channel['snippet']['title'],
          'description': channel['snippet']['description'],
          'subscriberCount': channel['statistics']['subscriberCount'],
          'videoCount': channel['statistics']['videoCount'],
          'viewCount': channel['statistics']['viewCount'],
        };
      } else {
        if (kDebugMode) {
          print('❌ YouTube channel info request failed: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting YouTube channel info: $e');
      }
      return null;
    }
  }

  /// Get YouTube channel statistics
  Future<Map<String, dynamic>?> getYouTubeChannelStats() async {
    try {
      final accessToken = await getYouTubeAccessToken();
      return await _getYouTubeChannelInfo(accessToken);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting YouTube channel stats: $e');
      }
      return null;
    }
  }

  /// Check if user can upload videos to YouTube
  Future<bool> canUploadToYouTube() async {
    try {
      final accessToken = await getYouTubeAccessToken();

      // Test upload permissions by checking channel capabilities
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/youtube/v3/channels').replace(
          queryParameters: {
            'part': 'status',
            'mine': 'true',
          },
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final channels = data['items'] as List<dynamic>;

        if (channels.isNotEmpty) {
          final status = channels.first['status'];
          final isLinked = status['isLinked'] ?? false;
          final longUploadsStatus = status['longUploadsStatus'] ?? 'disallowed';

          if (kDebugMode) {
            print('🔴 YouTube upload capabilities:');
            print('   Channel linked: $isLinked');
            print('   Long uploads: $longUploadsStatus');
          }

          return isLinked;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking YouTube upload permission: $e');
      }
      return false;
    }
  }
}
