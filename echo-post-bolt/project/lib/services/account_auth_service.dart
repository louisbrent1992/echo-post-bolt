import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'platform_document_service.dart';

/// Custom exception for when a Google account exists for the email
class GoogleAccountExistsException implements Exception {
  final String message;
  final String email;

  GoogleAccountExistsException(this.message, this.email);

  @override
  String toString() => 'GoogleAccountExistsException: $message';
}

/// Custom exception for when an email/password account exists for the email
class EmailPasswordAccountExistsException implements Exception {
  final String message;
  final String email;
  final AuthCredential? googleCredential;

  EmailPasswordAccountExistsException(
      this.message, this.email, this.googleCredential);

  @override
  String toString() => 'EmailPasswordAccountExistsException: $message';
}

/// Main authentication service that coordinates all authentication methods
/// and manages user document creation with platform initialization
class AccountAuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Lazy-initialized service instances
  EmailAuthService? _emailAuthService;
  GoogleAuthService? _googleAuthService;

  EmailAuthService get _emailAuth => _emailAuthService ??= EmailAuthService();
  GoogleAuthService get _googleAuth =>
      _googleAuthService ??= GoogleAuthService();

  // Getters
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  AccountAuthService() {
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
      if (currentUser != null) {
        await currentUser.reload();
        notifyListeners();
      }
    } catch (e) {
      // Silent failure for auth state check - don't disrupt user experience
      if (kDebugMode) {
        print('Auth state check failed: $e');
      }
    }
  }

  // Sign out method following Firebase documentation
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Sign out error: $e');
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

  // Create user document if it doesn't exist
  Future<void> _createUserDocIfNotExists(User user, String provider) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      if (kDebugMode) {
        print('👤 Creating new user document for: ${user.email}');
      }

      await docRef.set({
        'displayName': user.displayName,
        'email': user.email,
        'photoURL': user.photoURL,
        'created_at': FieldValue.serverTimestamp(),
        'last_sign_in': FieldValue.serverTimestamp(),
        'provider': provider,
      });

      // Create default user preferences
      await docRef.collection('user_preferences').doc('settings').set({
        'default_platforms': ['instagram', 'twitter'],
        'default_hashtags': [],
        'auto_location': true,
        'signature': '',
      });

      // NEW: Initialize platform documents for new users
      await PlatformDocumentService.initializePlatformDocuments(user.uid);

      if (kDebugMode) {
        print('✅ User document and platform documents created successfully');
      }
    } else {
      // Update last sign-in time
      await docRef.update({
        'last_sign_in': FieldValue.serverTimestamp(),
      });

      // NEW: Ensure existing users have platform documents (migration)
      await PlatformDocumentService.migrateUserToPlatformDocuments(user.uid);

      if (kDebugMode) {
        print('✅ User document updated and platform documents verified');
      }
    }
  }

  // DEPRECATED: Use PlatformConnectionService.isPlatformConnected() instead
  // This method only checks document existence and doesn't validate tokens
  @Deprecated(
      'Use PlatformConnectionService.isPlatformConnected() for proper validation')
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

  // Disconnect a specific platform (removes its token from Firestore)
  Future<void> disconnectPlatform(String platform) async {
    if (_auth.currentUser == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('tokens')
          .doc(platform)
          .delete();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to disconnect $platform: $e');
      }
      rethrow;
    }
  }

  // Convenience methods that delegate to separate auth services
  // These provide the interface expected by the login screen

  /// Sign in with Google (delegates to GoogleAuthService)
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await _googleAuth.signInWithGoogle();
      notifyListeners();
      return null; // GoogleAuthService doesn't return UserCredential
    } catch (e) {
      rethrow;
    }
  }

  /// Sign in with email and password (delegates to EmailAuthService)
  Future<UserCredential?> signInWithEmailPassword(
      String email, String password) async {
    try {
      await _emailAuth.signInWithEmail(email, password);
      notifyListeners();
      return null; // EmailAuthService doesn't return UserCredential
    } catch (e) {
      rethrow;
    }
  }

  /// Link Google account to existing email/password account (delegates to GoogleAuthService)
  Future<UserCredential?> linkGoogleToEmailAccount(
      String email, String password) async {
    try {
      final result =
          await _googleAuth.linkGoogleToEmailAccount(email, password);
      notifyListeners();
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Send password reset email (delegates to EmailAuthService)
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _emailAuth.sendPasswordResetEmail(email);
    } catch (e) {
      rethrow;
    }
  }
}

/// Email/password via Firebase
class EmailAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in with email and password
  /// Automatically creates account if email doesn't exist
  Future<void> signInWithEmail(String email, String password) async {
    try {
      email = email.trim();

      // 1. Basic local validation
      if (!_isValidEmail(email)) {
        throw Exception('Enter a valid email address');
      }
      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }

      // 2. Get sign-in methods for this e-mail from Firebase
      final methods = await _auth.fetchSignInMethodsForEmail(email);

      if (methods.contains('password')) {
        // Existing email / password user → authenticate
        try {
          final cred = await _auth.signInWithEmailAndPassword(
              email: email, password: password);
          if (cred.user != null) {
            await _createUserDocIfNotExists(cred.user!, 'password');
          }
        } on FirebaseAuthException catch (e) {
          if (e.code == 'wrong-password') {
            throw Exception('Incorrect password. Please try again.');
          }
          rethrow;
        }
      } else if (methods.isEmpty) {
        // Brand-new user → create account
        try {
          final cred = await _auth.createUserWithEmailAndPassword(
              email: email, password: password);
          if (cred.user != null) {
            await _createUserDocIfNotExists(cred.user!, 'password');
          }
        } on FirebaseAuthException catch (e) {
          switch (e.code) {
            case 'weak-password':
              throw Exception('Password is too weak.');
            case 'email-already-in-use':
              // Rare race condition – treat as existing password path next run
              throw Exception('This email is already registered.');
            default:
              throw Exception('Account creation failed: ${e.message}');
          }
        }
      } else if (methods.length == 1 && methods.first == 'google.com') {
        // Google-only account – alert UI and stop
        throw GoogleAccountExistsException(
          'This email is linked to Google Sign-In. Sign in with Google, then add a password from Settings.',
          email,
        );
      } else {
        // Any other combination (future Facebook, etc.)
        throw Exception(
            'This email is linked to a different sign-in method. Please use your original sign-in.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Email/password authentication error: $e');
      }
      rethrow;
    }
  }

  /// Check if email/password is connected
  Future<bool> isEmailConnected() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // Check if user has email/password provider
    final hasEmailProvider =
        user.providerData.any((provider) => provider.providerId == 'password');

    return hasEmailProvider;
  }

  /// Sign out of email
  Future<void> signOutOfEmail() async {
    try {
      await _auth.signOut();
    } catch (e) {
      if (kDebugMode) {
        print('Error signing out: $e');
      }
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      if (!_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account found with this email address');
        case 'invalid-email':
          throw Exception('Please enter a valid email address');
        case 'too-many-requests':
          throw Exception('Too many requests. Please try again later');
        default:
          throw Exception('Failed to send reset email: ${e.message}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Validate email format
  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  /// Create user document if it doesn't exist
  Future<void> _createUserDocIfNotExists(User user, String provider) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      await docRef.set({
        'displayName': user.displayName,
        'email': user.email,
        'photoURL': user.photoURL,
        'created_at': FieldValue.serverTimestamp(),
        'last_sign_in': FieldValue.serverTimestamp(),
        'provider': provider,
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
}

/// Google sign-in (Firebase + Google OAuth)
class GoogleAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Configure Google Sign-In with proper serverClientId for Firebase authentication
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'] ??
        '794380832661-62e0bds0d8rq1ne4fuq10jlht0brr7g8.apps.googleusercontent.com',
  );

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      // First, try to sign in silently to check for existing auth
      // This handles cases where user completed verification elsewhere
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();

      // If silent sign-in fails, trigger interactive sign-in
      googleUser ??= await _googleSignIn.signIn();

      // If the user cancels the sign-in flow
      if (googleUser == null) {
        return;
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

      // Check if email exists with password provider
      final email = googleUser.email;
      try {
        // Try to sign in with a dummy password to check if email exists
        await _auth.signInWithEmailAndPassword(
          email: email,
          password: 'dummy-password-that-will-fail',
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password') {
          // Email exists with password provider
          throw EmailPasswordAccountExistsException(
            'This email already has an account with email/password. To link your Google account, please sign in with your email and password first, then link Google from your account settings.',
            email,
            credential,
          );
        }
      }

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _createUserDocIfNotExists(userCredential.user!, 'google.com');
      } else {
        throw Exception('Firebase authentication failed - no user returned');
      }
    } on FirebaseAuthException catch (e) {
      // Clear any cached Google Sign-In state on Firebase auth errors
      await _googleSignIn.signOut();

      switch (e.code) {
        case 'account-exists-with-different-credential':
          // This should be handled by our pre-check, but handle it anyway
          final email = (await _googleSignIn.signIn())?.email ?? '';
          throw EmailPasswordAccountExistsException(
            'This email already has an account with email/password. To link your Google account, please sign in with your email and password first.',
            email,
            null,
          );
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
          return;
        default:
          throw Exception('Google Sign-In failed: ${e.message}');
      }
    } catch (e) {
      // Clear any cached Google Sign-In state on general errors
      await _googleSignIn.signOut();
      rethrow;
    }
  }

  /// Check if Google is connected
  Future<bool> isGoogleConnected() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // Check if user has Google provider
    final hasGoogleProvider = user.providerData
        .any((provider) => provider.providerId == 'google.com');

    return hasGoogleProvider;
  }

  /// Sign out of Google
  Future<void> signOutOfGoogle() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      if (kDebugMode) {
        print('Error signing out of Google: $e');
      }
      rethrow;
    }
  }

  /// Link Google account to existing email/password account
  /// This enforces Google credentials as the authoritative password
  Future<UserCredential?> linkGoogleToEmailAccount(
      String email, String password) async {
    try {
      // First, verify the email/password credentials
      final emailCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (emailCredential.user == null) {
        throw Exception('Invalid email or password');
      }

      // Now get Google credentials
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign-in was cancelled');
      }

      // Verify the Google email matches
      if (googleUser.email != email) {
        await _googleSignIn.signOut();
        throw Exception('Google account email must match your account email');
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw Exception('No ID Token received from Google Sign-In');
      }

      final googleCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Link the Google credential to the current user
      final linkedCredential =
          await emailCredential.user!.linkWithCredential(googleCredential);

      if (linkedCredential.user != null) {
        // Update user document to reflect Google is now the primary provider
        await _firestore
            .collection('users')
            .doc(linkedCredential.user!.uid)
            .update({
          'provider': 'google.com', // Google becomes primary
          'linked_providers': FieldValue.arrayUnion(['password', 'google.com']),
          'last_sign_in': FieldValue.serverTimestamp(),
          'google_linked_at': FieldValue.serverTimestamp(),
        });

        return linkedCredential;
      }

      return null;
    } on FirebaseAuthException catch (e) {
      await _googleSignIn.signOut();

      switch (e.code) {
        case 'provider-already-linked':
          throw Exception('Google account is already linked to this account');
        case 'credential-already-in-use':
          throw Exception(
              'This Google account is already linked to another account');
        case 'wrong-password':
          throw Exception('Incorrect password. Please try again.');
        case 'user-not-found':
          throw Exception('No account found with this email address');
        case 'invalid-credential':
          throw Exception('Invalid Google credentials');
        default:
          throw Exception('Failed to link accounts: ${e.message}');
      }
    } catch (e) {
      await _googleSignIn.signOut();
      rethrow;
    }
  }

  /// Link email/password to existing Google account
  Future<UserCredential?> linkEmailPasswordToAccount(
      String email, String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user is currently signed in');
      }

      // Validate input
      if (email.trim().isEmpty || password.isEmpty) {
        throw Exception('Email and password are required');
      }

      if (!_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters long');
      }

      // Check if the email matches the current user's email
      if (user.email != email.trim()) {
        throw Exception('Email must match your current account email');
      }

      // Create email/password credential
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );

      // Link the credential to the current user
      final userCredential = await user.linkWithCredential(credential);

      if (userCredential.user != null) {
        // Update user document to reflect linked account
        await _firestore.collection('users').doc(user.uid).update({
          'linked_providers': FieldValue.arrayUnion(['password']),
          'last_sign_in': FieldValue.serverTimestamp(),
        });

        return userCredential;
      }

      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'provider-already-linked':
          throw Exception('Email/password is already linked to this account');
        case 'invalid-credential':
          throw Exception('Invalid email or password');
        case 'credential-already-in-use':
          throw Exception(
              'This email is already associated with another account');
        case 'email-already-in-use':
          throw Exception(
              'This email is already registered with another account');
        case 'weak-password':
          throw Exception(
              'Password is too weak. Please choose a stronger password');
        case 'invalid-email':
          throw Exception('Please enter a valid email address');
        default:
          throw Exception('Failed to link account: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Account linking error: $e');
      }
      rethrow;
    }
  }

  /// Get available sign-in methods for an email
  Future<List<String>> getSignInMethodsForEmail(String email) async {
    try {
      if (!_isValidEmail(email)) {
        return [];
      }

      try {
        await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: 'dummy-password-that-will-fail',
        );
        return ['password'];
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password') {
          return ['password'];
        } else if (e.code == 'user-not-found') {
          return [];
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching sign-in methods: $e');
      }
      return [];
    }
  }

  /// Validate email format
  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  /// Create user document if it doesn't exist
  Future<void> _createUserDocIfNotExists(User user, String provider) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      await docRef.set({
        'displayName': user.displayName,
        'email': user.email,
        'photoURL': user.photoURL,
        'created_at': FieldValue.serverTimestamp(),
        'last_sign_in': FieldValue.serverTimestamp(),
        'provider': provider,
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
}
