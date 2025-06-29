import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../platform_document_service.dart';

/// Instagram Business Login (Graph API) – EchoPost
///
/// Requirements:
///  • Instagram Business / Creator account
///  • Account linked to a Facebook Page
///  • Facebook App with Instagram Graph API product + permissions
///
/// No Instagram-specific client_id / secret are needed; we use the
/// Facebook App ID already present in android/iOS config files.
class InstagramAuthService {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  /* ─────────────────────────  PUBLIC API  ───────────────────────── */

  Future<void> signInWithInstagram() async {
    _assertPrimaryAuth();
    final fbToken = await _facebookLogin();
    final page    = await _findPageWithIgAccount(fbToken);
    final igInfo  = await _fetchIgAccountInfo(page);

    await _persistTokens(page, igInfo, fbToken.token);
  }

  Future<bool> isInstagramConnected() async {
    final doc = await _tokenDoc().get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final exp  = data['expires_at'] as int?;
    return exp != null && DateTime.now().isBefore(
      DateTime.fromMillisecondsSinceEpoch(exp)
    );
  }

  Future<String> getInstagramAccessToken() async {
    final doc = await _tokenDoc().get();
    if (!doc.exists) throw Exception('IG not connected');
    final data = doc.data()!;
    final exp  = data['expires_at'] as int?;
    if (exp != null && DateTime.now().isAfter(
          DateTime.fromMillisecondsSinceEpoch(exp))) {
      throw Exception('IG token expired');
    }
    return data['access_token'];
  }

  Future<void> signOutOfInstagram() async =>
      _tokenDoc().set(PlatformDocumentService
          .getNullifiedFieldsForPlatform('instagram'));

  /* ─────────────────────────  INTERNALS  ───────────────────────── */

  void _assertPrimaryAuth() {
    if (_auth.currentUser == null) {
      throw Exception('User must be logged-in (Firebase) first');
    }
  }

  CollectionReference<Map<String, dynamic>> _tokenCol() =>
      _db.collection('users')
          .doc(_auth.currentUser!.uid)
         .collection('tokens');

  DocumentReference<Map<String, dynamic>> _tokenDoc() =>
      _tokenCol().doc('instagram');

  Future<AccessToken> _facebookLogin() async {
    final result = await FacebookAuth.instance.login(
      permissions: [
        'pages_show_list',
        'pages_read_engagement',
        'instagram_basic',
        'instagram_content_publish',
        'instagram_manage_comments',
      ],
    );
    if (result.status != LoginStatus.success) {
      throw Exception('Facebook login failed: ${result.message}');
    }
    return result.accessToken!;
  }

  /// Returns the first page that has an attached Instagram business account
  Future<Map<String, dynamic>> _findPageWithIgAccount(
      AccessToken fbToken) async {
    final uri = Uri.https('graph.facebook.com', '/v18.0/me/accounts', {
      'fields': 'id,name,access_token,instagram_business_account',
      'access_token': fbToken.token,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Could not list pages: ${res.body}');
    }

    final pages = (jsonDecode(res.body)['data'] as List)
        .cast<Map<String, dynamic>>();
    final page  = pages.firstWhere(
      (p) => p['instagram_business_account'] != null,
      orElse: () => throw Exception(
          'No FB Page linked to an Instagram Business account.\n'
          'Link the IG account to a Page and retry.'),
    );
    return page;
  }

  Future<Map<String, dynamic>> _fetchIgAccountInfo(
      Map<String, dynamic> page) async {
    final igId = page['instagram_business_account']['id'];
    final uri  = Uri.https('graph.facebook.com', '/v18.0/$igId', {
      'fields':
          'id,username,name,biography,website,followers_count,follows_count,'
          'media_count,profile_picture_url',
      'access_token': page['access_token'],
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Fetching IG info failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _persistTokens(
      Map<String, dynamic> page,
      Map<String, dynamic> ig,
      String fbUserToken) async {
    final expiry = DateTime.now().add(const Duration(days: 60));
    await _tokenDoc().set({
      'access_token'          : page['access_token'],   // page token
      'facebook_user_token'   : fbUserToken,
      'expires_at'            : expiry.millisecondsSinceEpoch,
      'token_type'            : 'Bearer',
      'scope'                 : 'instagram_basic,instagram_content_publish,instagram_manage_comments',

      // IG account info
      'account_id'            : ig['id'],
      'username'              : ig['username'],
      'name'                  : ig['name'],
      'biography'             : ig['biography'],
      'website'               : ig['website'],
      'followers_count'       : ig['followers_count'],
      'follows_count'         : ig['follows_count'],
      'media_count'           : ig['media_count'],
      'profile_picture_url'   : ig['profile_picture_url'],

      // FB page info
      'facebook_page_id'      : page['id'],
      'facebook_page_name'    : page['name'],

      'api_version'           : 'v18.0',
      'authentication_method' : 'facebook_login',
      'account_type'          : 'business',
      'created_at'            : FieldValue.serverTimestamp(),
      'last_updated'          : FieldValue.serverTimestamp(),
    });
  }
}
