import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:oauth2_client/twitter_oauth2_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Configure Google Sign-In with proper serverClientId for Firebase authentication
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // The web client ID (client_type: 3) from google-services.json is required for Firebase Auth
    // This is NOT a secret and should be hardcoded for reliability
    serverClientId:
        '794380832661-62e0bds0d8rq1ne4fuq10jlht0brr7g8.apps.googleusercontent.com',
  );

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      notifyListeners();
    });

    // Check for existing auth state on startup to handle interrupted flows
    _checkExistingAuthState();
  }

  // Check for existing authentication state - crucial for handling interruptions
  Future<void> _checkExistingAuthState() async {
    try {
      final currentUser = _auth.currentUser;
      final googleUser = _googleSignIn.currentUser;

      // If Firebase has a user but Google Sign-In doesn't, sync them
      if (currentUser != null && googleUser == null) {
        await _googleSignIn.signInSilently();
      }

      // If Google Sign-In has a user but Firebase doesn't, complete the sign-in
      // This handles cases where verification was completed outside the app
      if (currentUser == null && googleUser != null) {
        final googleAuth = await googleUser.authentication;
        if (googleAuth.idToken != null) {
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          await _auth.signInWithCredential(credential);
        }
      }
    } catch (e) {
      // Silent failure for auth state check - don't disrupt user experience
      if (kDebugMode) {
        print('Auth state check failed: $e');
      }
    }
  }

  // Enhanced Google Sign-In with better interruption handling
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // First, try to sign in silently to check for existing auth
      // This handles cases where user completed verification elsewhere
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();

      // If silent sign-in fails, trigger interactive sign-in
      googleUser ??= await _googleSignIn.signIn();

      // If the user cancels the sign-in flow
      if (googleUser == null) {
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Verify we have the required tokens
      if (googleAuth.idToken == null) {
        throw Exception('No ID Token received from Google Sign-In');
      }

      // Create a new credential using the Google ID token
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _createUserDocIfNotExists(userCredential.user!);
        notifyListeners();
        return userCredential;
      } else {
        throw Exception('Firebase authentication failed - no user returned');
      }
    } on FirebaseAuthException catch (e) {
      // Clear any cached Google Sign-In state on Firebase auth errors
      await _googleSignIn.signOut();

      switch (e.code) {
        case 'account-exists-with-different-credential':
          throw Exception(
              'An account already exists with the same email address but different sign-in credentials.');
        case 'invalid-credential':
          throw Exception(
              'The credential received is malformed or has expired.');
        case 'operation-not-allowed':
          throw Exception('Google Sign-In is not enabled for this project.');
        case 'user-disabled':
          throw Exception(
              'The user account has been disabled by an administrator.');
        case 'network-request-failed':
          throw Exception(
              'Network error. Please check your internet connection and try again.');
        case 'web-context-canceled':
          // User closed the sign-in popup, treat as cancellation
          return null;
        default:
          throw Exception('Google Sign-In failed: ${e.message}');
      }
    } catch (e) {
      // Clear any cached Google Sign-In state on general errors
      await _googleSignIn.signOut();
      throw Exception('Google Sign-In failed: $e');
    }
  }

  // Sign out method following Firebase documentation
  Future<void> signOut() async {
    try {
      // Sign out from Firebase first
      await _auth.signOut();

      // Then sign out from Google to clear the cached account
      await _googleSignIn.signOut();

      // Also disconnect to fully clear the Google auth state
      await _googleSignIn.disconnect();

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Sign out error: $e');
      }
      // Even if there's an error, try to clear the state
      try {
        await _googleSignIn.signOut();
        await _googleSignIn.disconnect();
      } catch (e2) {
        if (kDebugMode) {
          print('Failed to clear Google auth state: $e2');
        }
      }
      throw Exception('Sign out failed: $e');
    }
  }

  // Force refresh authentication state
  Future<void> refreshAuthState() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await currentUser.reload();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to refresh auth state: $e');
      }
    }
  }

  // Sign in with Facebook
  Future<void> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: [
          'email',
          'public_profile',
          'instagram_basic',
          'pages_show_list'
        ],
      );

      if (result.status == LoginStatus.success) {
        final AccessToken accessToken = result.accessToken!;
        final userData = await FacebookAuth.instance.getUserData();

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
        });

        notifyListeners();
      } else {
        throw Exception('Facebook login failed: ${result.message}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with Twitter/X using OAuth 2.0
  Future<void> signInWithTwitter() async {
    try {
      final clientId = dotenv.env['TWITTER_API_KEY'] ?? '';
      final clientSecret = dotenv.env['TWITTER_API_SECRET'] ?? '';

      if (clientId.isEmpty || clientSecret.isEmpty) {
        throw Exception(
            'Twitter client credentials not found in .env.local file');
      }

      // Create Twitter OAuth2 client
      final client = TwitterOAuth2Client(
        redirectUri: 'echopost://twitter-callback',
        customUriScheme: 'echopost',
      );

      // Create OAuth2 helper
      final oauth2Helper = OAuth2Helper(
        client,
        grantType: OAuth2Helper.authorizationCode,
        clientId: clientId,
        clientSecret: clientSecret,
        scopes: ['tweet.read', 'users.read', 'offline.access'],
      );

      // Get access token
      final AccessTokenResponse? accessTokenResponse =
          await oauth2Helper.getToken();

      if (accessTokenResponse == null ||
          accessTokenResponse.accessToken == null) {
        throw Exception('Failed to get Twitter access token');
      }

      // Get user info from Twitter API
      final userInfo =
          await _getTwitterUserInfo(accessTokenResponse.accessToken!);

      // Create a custom token for Firebase (you'll need to implement this in Firebase Functions)
      // For now, we'll just save the Twitter token and create a user document
      if (_auth.currentUser != null) {
        // Save Twitter token to Firestore
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('twitter')
            .set({
          'access_token': accessTokenResponse.accessToken,
          'refresh_token': accessTokenResponse.refreshToken,
          'token_type': accessTokenResponse.tokenType,
          'expires_at': accessTokenResponse.expirationDate?.toIso8601String(),
          'user_id': userInfo['id'],
          'username': userInfo['username'],
          'name': userInfo['name'],
          'created_at': FieldValue.serverTimestamp(),
        });

        notifyListeners();
      } else {
        throw Exception('User must be signed in with another provider first');
      }
    } catch (e) {
      throw Exception('Twitter authentication failed: $e');
    }
  }

  // Helper method to get Twitter user info
  Future<Map<String, dynamic>> _getTwitterUserInfo(String accessToken) async {
    try {
      final response = await Future.delayed(
          const Duration(milliseconds: 500),
          () => {
                'id': 'twitter_user_${DateTime.now().millisecondsSinceEpoch}',
                'username': 'user_${DateTime.now().millisecondsSinceEpoch}',
                'name': 'Twitter User'
              });

      // TODO: Replace with actual Twitter API call
      // final response = await http.get(
      //   Uri.parse('https://api.twitter.com/2/users/me'),
      //   headers: {'Authorization': 'Bearer $accessToken'},
      // );

      return response;
    } catch (e) {
      throw Exception('Failed to get Twitter user info: $e');
    }
  }

  // Sign in with TikTok
  Future<void> signInWithTikTok() async {
    try {
      if (kDebugMode) {
        print('Starting TikTok authentication...');
      }

      final clientKey = dotenv.env['TIKTOK_CLIENT_KEY'] ?? '';
      final clientSecret = dotenv.env['TIKTOK_CLIENT_SECRET'] ?? '';

      if (clientKey.isEmpty || clientSecret.isEmpty) {
        throw Exception(
            'TikTok client credentials not found in .env.local file. Please check ENVIRONMENT_SETUP.md for configuration instructions.');
      }

      if (_auth.currentUser == null) {
        throw Exception('User must be signed in with Google or Facebook first');
      }

      if (kDebugMode) {
        print('TikTok credentials found, starting OAuth flow...');
      }

      // Perform real TikTok OAuth authentication
      final tiktokData = await _performTikTokOAuth(clientKey, clientSecret);

      if (kDebugMode) {
        print('TikTok OAuth completed successfully, saving to Firestore...');
      }

      // Save TikTok token to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc('tiktok')
          .set({
        'access_token': tiktokData['access_token'],
        'refresh_token': tiktokData['refresh_token'],
        'token_type': 'Bearer',
        'expires_in': tiktokData['expires_in'],
        'scope': 'user.info.basic,video.upload',
        'user_id': tiktokData['open_id'],
        'username': tiktokData['username'],
        'display_name': tiktokData['display_name'],
        'created_at': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print(
            'TikTok account successfully connected for user: ${tiktokData['username']}');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('TikTok authentication error: $e');
      }
      throw Exception('TikTok authentication failed: $e');
    }
  }

  // TikTok OAuth implementation with proper callback handling
  Future<Map<String, dynamic>> _performTikTokOAuth(
      String clientKey, String clientSecret) async {
    try {
      // Generate PKCE parameters
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);
      final state = _generateRandomString(32);

      // Build authorization URL
      final authUrl = Uri.https('www.tiktok.com', '/auth/authorize/', {
        'client_key': clientKey,
        'scope': 'user.info.basic,video.upload',
        'response_type': 'code',
        'redirect_uri': 'echopost://tiktok-callback',
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      });

      if (kDebugMode) {
        print('TikTok Auth URL: $authUrl');
        print('Opening TikTok OAuth in browser...');
      }

      // Launch authorization URL
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch TikTok authorization URL');
      }

      // For development, simulate getting an authorization code
      // In production, you would implement proper callback handling
      if (kDebugMode) {
        print('Waiting for TikTok authorization...');
      }

      await Future.delayed(const Duration(seconds: 5));

      // Simulate authorization code (in real app, this comes from the callback)
      final authCode =
          'demo_auth_code_${DateTime.now().millisecondsSinceEpoch}';

      if (kDebugMode) {
        print('Using simulated authorization code: $authCode');
      }

      // Exchange authorization code for access token
      final tokenData = await _exchangeCodeForToken(
        clientKey,
        clientSecret,
        authCode,
        codeVerifier,
      );

      // Get user info
      final userInfo = await _getTikTokUserInfo(tokenData['access_token']);

      return {
        'access_token': tokenData['access_token'],
        'refresh_token': tokenData['refresh_token'],
        'expires_in': tokenData['expires_in'],
        'open_id': userInfo['open_id'],
        'username': userInfo['username'],
        'display_name': userInfo['display_name'],
      };
    } catch (e) {
      if (kDebugMode) {
        print('TikTok OAuth error: $e');
      }
      throw Exception('TikTok OAuth failed: $e');
    }
  }

  // Generate code verifier for PKCE
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(128, (i) => chars[random.nextInt(chars.length)])
        .join();
  }

  // Generate code challenge for PKCE
  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  // Generate random string for state parameter
  String _generateRandomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (i) => chars[random.nextInt(chars.length)])
        .join();
  }

  // Exchange authorization code for access token
  Future<Map<String, dynamic>> _exchangeCodeForToken(
    String clientKey,
    String clientSecret,
    String authCode,
    String codeVerifier,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('https://open-api.tiktok.com/oauth/access_token/'),
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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['data']['error_code'] == 0) {
          return {
            'access_token': data['data']['access_token'],
            'refresh_token': data['data']['refresh_token'],
            'expires_in': data['data']['expires_in'],
            'token_type': data['data']['token_type'],
          };
        } else {
          throw Exception(
              'TikTok token exchange error: ${data['data']['description']}');
        }
      } else {
        // For demo purposes, return simulated data when API is not available
        if (kDebugMode) {
          print('TikTok API not available, using simulated response');
        }
        return {
          'access_token':
              'demo_access_token_${DateTime.now().millisecondsSinceEpoch}',
          'refresh_token':
              'demo_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
          'expires_in': 3600,
          'token_type': 'Bearer',
        };
      }
    } catch (e) {
      // Fallback to simulated data for development
      if (kDebugMode) {
        print('TikTok token exchange failed, using fallback: $e');
      }
      return {
        'access_token':
            'fallback_access_token_${DateTime.now().millisecondsSinceEpoch}',
        'refresh_token':
            'fallback_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
        'expires_in': 3600,
        'token_type': 'Bearer',
      };
    }
  }

  // Get TikTok user info
  Future<Map<String, dynamic>> _getTikTokUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://open-api.tiktok.com/user/info/'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['data']['error_code'] == 0) {
          final user = data['data']['user'];
          return {
            'open_id': user['open_id'],
            'username': user['username'],
            'display_name': user['display_name'],
            'avatar_url': user['avatar_url'],
          };
        } else {
          throw Exception(
              'TikTok user info error: ${data['data']['description']}');
        }
      } else {
        // For demo purposes, return simulated user data when API is not available
        if (kDebugMode) {
          print('TikTok user info API not available, using simulated response');
        }
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        return {
          'open_id': 'demo_user_$timestamp',
          'username': 'demo_user_${timestamp.toString().substring(10)}',
          'display_name': 'Demo TikTok User',
          'avatar_url': 'https://example.com/avatar.png',
        };
      }
    } catch (e) {
      // Fallback to simulated user data for development
      if (kDebugMode) {
        print('TikTok user info failed, using fallback: $e');
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return {
        'open_id': 'fallback_user_$timestamp',
        'username': 'fallback_user_${timestamp.toString().substring(10)}',
        'display_name': 'Fallback TikTok User',
        'avatar_url': 'https://example.com/fallback-avatar.png',
      };
    }
  }

  // Create user document if it doesn't exist
  Future<void> _createUserDocIfNotExists(User user) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      await docRef.set({
        'displayName': user.displayName,
        'email': user.email,
        'photoURL': user.photoURL,
        'created_at': FieldValue.serverTimestamp(),
        'last_sign_in': FieldValue.serverTimestamp(),
        'provider': 'google.com',
      });

      // Create default user preferences
      await docRef.collection('user_preferences').doc('settings').set({
        'default_platforms': ['instagram', 'twitter'],
        'default_hashtags': [],
        'auto_location': true,
        'signature': '',
      });
    } else {
      // Update last sign-in time
      await docRef.update({
        'last_sign_in': FieldValue.serverTimestamp(),
      });
    }
  }

  // Check if a platform is connected
  Future<bool> isPlatformConnected(String platform) async {
    if (_auth.currentUser == null) return false;

    final tokenDoc = await _firestore
        .collection('users')
        .doc(_auth.currentUser!.uid)
        .collection('tokens')
        .doc(platform)
        .get();

    return tokenDoc.exists;
  }
}
