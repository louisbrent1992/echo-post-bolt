import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
// import 'package:twitter_login/twitter_login.dart';  // Temporarily disabled

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Configure Google Sign-In according to Firebase documentation
  final GoogleSignIn _googleSignIn = GoogleSignIn(
      // Add your web client ID here when you have it
      // serverClientId: 'your-web-client-id.googleusercontent.com',
      );

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      notifyListeners();
    });
  }

  // Enhanced Google Sign-In following Firebase documentation pattern
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Check if user is already signed in
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        return null;
      }

      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

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
        default:
          throw Exception('Google Sign-In failed: ${e.message}');
      }
    } catch (e) {
      throw Exception('Google Sign-In failed: $e');
    }
  }

  // Sign out method following Firebase documentation
  Future<void> signOut() async {
    try {
      // Sign out from Firebase
      await _auth.signOut();

      // Sign out from Google to clear the cached account
      await _googleSignIn.signOut();

      notifyListeners();
    } catch (e) {
      throw Exception('Sign out failed: $e');
    }
  }

  // Check current authentication state
  Future<void> checkAuthState() async {
    final user = _auth.currentUser;
    if (user != null) {
    } else {}
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

  // Sign in with Twitter - TEMPORARILY DISABLED
  Future<void> signInWithTwitter() async {
    throw UnimplementedError(
        'Twitter authentication temporarily disabled due to namespace issues');
  }

  // Sign in with TikTok
  Future<void> signInWithTikTok() async {
    try {
      throw UnimplementedError('TikTok authentication not yet implemented');
    } catch (e) {
      rethrow;
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
