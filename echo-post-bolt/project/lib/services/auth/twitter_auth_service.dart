import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:oauth1/oauth1.dart' as oauth1;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import '../platform_document_service.dart';

/// Twitter (OAuth 1.0a) - required for tweet posting
class TwitterAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in with Twitter using OAuth 1.0a
  Future<void> signInWithTwitter() async {
    try {
      if (kDebugMode) {
        print('🐦 Starting Twitter authentication...');
      }

      if (_auth.currentUser == null) {
        throw Exception('User must be signed in with Google or email first');
      }

      final consumerKey = dotenv.env['TWITTER_API_KEY'] ?? '';
      final consumerSecret = dotenv.env['TWITTER_API_SECRET'] ?? '';

      if (consumerKey.isEmpty || consumerSecret.isEmpty) {
        throw Exception(
            'Twitter API credentials not found in .env.local file. Please check ENVIRONMENT_SETUP.md for configuration instructions.');
      }

      // Step 1: Create OAuth 1.0a platform
      final platform = oauth1.Platform(
        'https://api.twitter.com/oauth/request_token',
        'https://api.twitter.com/oauth/authorize',
        'https://api.twitter.com/oauth/access_token',
        oauth1.SignatureMethods.hmacSha1,
      );

      // Step 2: Create client credentials
      final clientCredentials =
          oauth1.ClientCredentials(consumerKey, consumerSecret);

      // Step 3: Create Authorization object for proper OAuth 1.0a flow
      final auth = oauth1.Authorization(clientCredentials, platform);

      // Step 4: Request temporary credentials (request token) with proper callback
      final tempCredentialsResponse =
          await auth.requestTemporaryCredentials('echopost://twitter-callback');

      if (kDebugMode) {
        print(
            '🐦 Request token obtained: ${tempCredentialsResponse.credentials.token.substring(0, 10)}...');
      }

      // Step 5: Build authorization URL
      final authUrl = auth.getResourceOwnerAuthorizationURI(
          tempCredentialsResponse.credentials.token);

      // Step 6: Launch web authentication
      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'echopost',
      );

      // Step 7: Extract verifier from callback
      final callbackUri = Uri.parse(callbackUrl);
      final verifier = callbackUri.queryParameters['oauth_verifier'];
      final returnedToken = callbackUri.queryParameters['oauth_token'];

      if (verifier == null ||
          returnedToken != tempCredentialsResponse.credentials.token) {
        throw Exception('Twitter authorization failed or was cancelled');
      }

      if (kDebugMode) {
        print(
            '🐦 Authorization verifier received: ${verifier.substring(0, 10)}...');
      }

      // Step 8: Exchange for access token using proper OAuth 1.0a flow
      final tokenCredentialsResponse = await auth.requestTokenCredentials(
          tempCredentialsResponse.credentials, verifier);

      final accessToken = tokenCredentialsResponse.credentials.token;
      final accessTokenSecret =
          tokenCredentialsResponse.credentials.tokenSecret;
      final userId = tokenCredentialsResponse.optionalParameters['user_id']!;
      final screenName =
          tokenCredentialsResponse.optionalParameters['screen_name']!;

      // Step 9: Get user information
      final userInfo = await _getTwitterUserInfo(
          consumerKey, consumerSecret, accessToken, accessTokenSecret, userId);

      // Step 10: Save Twitter credentials to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('twitter')
          .set({
        'oauth_token': accessToken,
        'oauth_token_secret': accessTokenSecret,
        'user_id': userId,
        'screen_name': screenName,
        'name': userInfo['name'],
        'profile_image_url': userInfo['profile_image_url'],
        'followers_count': userInfo['followers_count'],
        'following_count': userInfo['following_count'],
        'tweet_count': userInfo['tweet_count'],
        'verified': userInfo['verified'],
        'created_at': FieldValue.serverTimestamp(),
        'last_updated': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ Twitter authentication completed successfully');
        print('🐦 User ID: $userId');
        print('🐦 Screen Name: @$screenName');
        print('🐦 Name: ${userInfo['name']}');
        print('🐦 Followers: ${userInfo['followers_count']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Twitter authentication error: $e');
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

      final oauthToken = tokenData['oauth_token'] as String?;
      final oauthTokenSecret = tokenData['oauth_token_secret'] as String?;
      final userId = tokenData['user_id'] as String?;

      // Check if we have the required Twitter OAuth 1.0a data
      if (oauthToken == null || oauthTokenSecret == null || userId == null) {
        return false;
      }

      // Twitter OAuth 1.0a tokens don't expire, so just check if they exist
      return true; // Token exists
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking Twitter connection: $e');
      }
      return false;
    }
  }

  /// Get Twitter access token (returns OAuth 1.0a credentials)
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

      final oauthToken = tokenData['oauth_token'] as String?;
      final oauthTokenSecret = tokenData['oauth_token_secret'] as String?;

      if (oauthToken == null || oauthTokenSecret == null) {
        throw Exception(
            'Twitter access token is null. Please re-authenticate with Twitter.');
      }

      // For OAuth 1.0a, we return a composite token string
      // In practice, you'd use both token and secret for signing requests
      return '$oauthToken:$oauthTokenSecret';
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Twitter access token: $e');
      }
      rethrow;
    }
  }

  /// Get Twitter OAuth 1.0a credentials
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

      final oauthToken = tokenData['oauth_token'] as String?;
      final oauthTokenSecret = tokenData['oauth_token_secret'] as String?;
      final userId = tokenData['user_id'] as String?;
      final screenName = tokenData['screen_name'] as String?;

      if (oauthToken == null ||
          oauthTokenSecret == null ||
          userId == null ||
          screenName == null) {
        throw Exception(
            'Twitter credentials are incomplete. Please re-authenticate with Twitter.');
      }

      return {
        'oauth_token': oauthToken,
        'oauth_token_secret': oauthTokenSecret,
        'user_id': userId,
        'screen_name': screenName,
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

  /// Get Twitter user information
  Future<Map<String, dynamic>> _getTwitterUserInfo(
    String consumerKey,
    String consumerSecret,
    String accessToken,
    String accessTokenSecret,
    String userId,
  ) async {
    try {
      final client = oauth1.Client(
        oauth1.SignatureMethods.hmacSha1,
        oauth1.ClientCredentials(consumerKey, consumerSecret),
        oauth1.Credentials(accessToken, accessTokenSecret),
      );

      final response = await client.get(
        Uri.parse('https://api.twitter.com/2/users/$userId').replace(
          queryParameters: {
            'user.fields': 'name,profile_image_url,public_metrics,verified',
          },
        ),
      );

      if (kDebugMode) {
        print('📥 Twitter user info response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['data'];
        final metrics = user['public_metrics'];

        return {
          'name': user['name'],
          'profile_image_url': user['profile_image_url'],
          'followers_count': metrics['followers_count'],
          'following_count': metrics['following_count'],
          'tweet_count': metrics['tweet_count'],
          'verified': user['verified'] ?? false,
        };
      } else {
        if (kDebugMode) {
          print('❌ Twitter user info request failed: ${response.body}');
        }
        // Return basic info if API call fails
        return {
          'name': 'Twitter User',
          'profile_image_url': '',
          'followers_count': 0,
          'following_count': 0,
          'tweet_count': 0,
          'verified': false,
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Twitter user info: $e');
      }
      // Return basic info if error occurs
      return {
        'name': 'Twitter User',
        'profile_image_url': '',
        'followers_count': 0,
        'following_count': 0,
        'tweet_count': 0,
        'verified': false,
      };
    }
  }

  /// Create OAuth 1.0a client for making authenticated requests
  oauth1.Client createTwitterClient() {
    final consumerKey = dotenv.env['TWITTER_API_KEY'] ?? '';
    final consumerSecret = dotenv.env['TWITTER_API_SECRET'] ?? '';

    if (consumerKey.isEmpty || consumerSecret.isEmpty) {
      throw Exception('Twitter API credentials not found in environment');
    }

    return oauth1.Client(
      oauth1.SignatureMethods.hmacSha1,
      oauth1.ClientCredentials(consumerKey, consumerSecret),
      oauth1.Credentials('', ''), // Will be set when making requests
    );
  }

  /// Get Twitter user statistics
  Future<Map<String, dynamic>?> getTwitterUserStats() async {
    try {
      final credentials = await getTwitterCredentials();
      final consumerKey = dotenv.env['TWITTER_API_KEY'] ?? '';
      final consumerSecret = dotenv.env['TWITTER_API_SECRET'] ?? '';

      final client = oauth1.Client(
        oauth1.SignatureMethods.hmacSha1,
        oauth1.ClientCredentials(consumerKey, consumerSecret),
        oauth1.Credentials(
            credentials['oauth_token']!, credentials['oauth_token_secret']!),
      );

      final response = await client.get(
        Uri.parse('https://api.twitter.com/2/users/${credentials['user_id']}')
            .replace(
          queryParameters: {
            'user.fields': 'public_metrics,verified',
          },
        ),
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
}
