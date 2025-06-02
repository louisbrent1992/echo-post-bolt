import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:twitter_login/twitter_login.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tiktok_sdk_v2/tiktok_sdk_v2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      notifyListeners();
    });
  }

  // Sign in with Google
  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        throw Exception('Google sign in was cancelled');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _createUserDocIfNotExists(userCredential.user!);
      notifyListeners();
      return userCredential;
    } catch (e) {
      print('Error signing in with Google: $e');
      rethrow;
    }
  }

  // Sign in with Facebook
  Future<void> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile', 'instagram_basic', 'pages_show_list'],
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
      print('Error signing in with Facebook: $e');
      rethrow;
    }
  }

  // Sign in with Twitter
  Future<void> signInWithTwitter() async {
    try {
      final twitterLogin = TwitterLogin(
        apiKey: dotenv.env['TWITTER_API_KEY']!,
        apiSecretKey: dotenv.env['TWITTER_API_SECRET']!,
        redirectURI: 'echopost://',
      );

      final authResult = await twitterLogin.login();
      if (authResult.status == TwitterLoginStatus.loggedIn) {
        // Save token to Firestore
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('tokens')
            .doc('twitter')
            .set({
          'auth_token': authResult.authToken!,
          'auth_secret': authResult.authTokenSecret!,
          'expires_at': Timestamp.now().toDate().add(const Duration(days: 90)),
        });

        notifyListeners();
      } else {
        throw Exception('Twitter login failed: ${authResult.errorMessage}');
      }
    } catch (e) {
      print('Error signing in with Twitter: $e');
      rethrow;
    }
  }

  // Sign in with TikTok
  Future<void> signInWithTikTok() async {
    try {
      final tiktokSdk = TiktokSdkV2(
        clientKey: dotenv.env['TIKTOK_CLIENT_KEY']!,
        redirectUri: 'echopost://',
        scope: ['user.info.basic', 'video.upload', 'video.publish'],
      );

      final authResponse = await tiktokSdk.login();
      if (authResponse.isSuccessful) {
        final authCode = authResponse.code;

        // Exchange auth code for access token via backend
        final response = await http.post(
          Uri.parse('${dotenv.env['BACKEND_URL']}/tiktok_exchange'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'auth_code': authCode,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          // Save token to Firestore
          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('tokens')
              .doc('tiktok')
              .set({
            'access_token': data['access_token'],
            'open_id': data['open_id'],
            'expires_at': Timestamp.fromDate(
              DateTime.now().add(Duration(seconds: data['expires_in'])),
            ),
          });

          notifyListeners();
        } else {
          throw Exception('TikTok token exchange failed');
        }
      } else {
        throw Exception('TikTok login failed');
      }
    } catch (e) {
      print('Error signing in with TikTok: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  // Create user document if it doesn't exist
  Future<void> _createUserDocIfNotExists(User user) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      await docRef.set({
        'displayName': user.displayName,
        'email': user.email,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Create default user preferences
      await docRef.collection('user_preferences').doc('settings').set({
        'default_platforms': ['instagram', 'twitter'],
        'default_hashtags': [],
        'auto_location': true,
        'signature': '',
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