import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';

import '../models/social_action.dart';

class SocialPostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Posts the action to every platform listed.
  Future<Map<String, bool>> postToAllPlatforms(SocialAction action) async {
    final uid = _auth.currentUser!.uid;
    final results = <String, bool>{};

    for (final platform in action.platforms) {
      try {
        switch (platform) {
          case 'facebook':
            await _postToFacebook(action);
            results['facebook'] = true;
            break;
          case 'instagram':
            await _postToInstagramViaShareDialog(action);
            results['instagram'] = true;
            break;
          case 'twitter':
            await _postToTwitter(action);
            results['twitter'] = true;
            break;
          case 'tiktok':
            await _postToTikTok(action);
            results['tiktok'] = true;
            break;
          default:
            results[platform] = false;
        }
      } catch (e) {
        results[platform] = false;
        await _markActionFailed(
          action.action_id,
          '$platform error: ${e.toString()}',
        );
      }
    }

    // If all succeeded, mark the action posted
    if (results.values.every((ok) => ok)) {
      await _markActionPosted(action.action_id);
    }

    return results;
  }

  //────────────────────────────────────────────────────────────────────────────
  // FACEBOOK (Multipart upload to Graph API /me/photos)
  //────────────────────────────────────────────────────────────────────────────

  Future<void> _postToFacebook(SocialAction action) async {
    final uid = _auth.currentUser!.uid;
    final tokenDoc = await _getTokenDocument(uid, 'facebook');
    if (tokenDoc == null) {
      throw Exception('Facebook not authenticated');
    }
    final fbToken = tokenDoc.data()!['access_token'] as String;
    final pageId = action.platform_data.facebook?.pageId;
    if (pageId == null || pageId.isEmpty) {
      throw Exception('No Facebook Page ID configured');
    }

    // 1. Retrieve the local file from file_uri
    final mediaItem = action.content.media.first;
    final File file = File(Uri.parse(mediaItem.fileUri).path);

    // 2. Build multipart request to /{pageId}/photos with 'source'
    final uri =
        Uri.https('graph.facebook.com', '/v17.0/$pageId/photos');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $fbToken'
      ..fields['caption'] =
          _buildCaption(action.content.text, action.content.hashtags)
      ..files.add(
        await http.MultipartFile.fromPath(
          'source',
          file.path,
          contentType: MediaType(
            mediaItem.mimeType.split('/')[0],
            mediaItem.mimeType.split('/')[1],
          ),
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data.containsKey('error')) {
      throw Exception(
          'Facebook upload error: ${data['error'] ?? response.body}');
    }

    // Success: photo is posted to the Page's feed
    print('Facebook post successful: ${data['id']}');
  }

  //────────────────────────────────────────────────────────────────────────────
  // INSTAGRAM (via native "Share to Instagram" dialog)
  //────────────────────────────────────────────────────────────────────────────

  Future<void> _postToInstagramViaShareDialog(SocialAction action) async {
    // On Android/iOS, launch the native share intent to Instagram.
    // The user must have Instagram installed. We pass the local fileUri directly.

    final mediaItem = action.content.media.first;
    final uri = Uri.parse(mediaItem.fileUri);

    // Build share text (caption + hashtags)
    final caption = _buildCaption(
      action.content.text,
      action.content.hashtags,
    );

    // On iOS: Use `instagram://library?AssetPath=<localUri>` scheme; on Android: use share Intent.
    // We attempt a universal approach with `url_launcher`.
    final encodedCaption = Uri.encodeComponent(caption);
    final filePath = uri.toString(); // content:// or file://

    // Android: share Intent via Action SEND
    if (Platform.isAndroid) {
      final intentUri =
          'intent:#Intent;action=android.intent.action.SEND;type=${mediaItem.mimeType};'
          'S.android.intent.extra.STREAM=$filePath;'
          'S.android.intent.extra.TEXT=$caption;'
          'package=com.instagram.android;end';
      if (await canLaunch(intentUri)) {
        await launch(intentUri);
      } else {
        throw Exception('Cannot launch Instagram on Android');
      }
    }
    // iOS: Use Instagram URL scheme (iOS 13+ may require using "UIDocumentInteractionController")
    else if (Platform.isIOS) {
      // For iOS, instagram://library?AssetPath=<file path> only works with the image in the Photos library,
      // not arbitrary file paths. If the file is in the Photos library, we can pass the `localIdentifier`.
      // Otherwise, we fallback to the generic share sheet.
      final shareUri = Uri.parse(filePath);
      await launchUrl(
        shareUri,
        mode: LaunchMode.platformDefault,
      );
    } else {
      throw Exception('Unsupported platform for Instagram sharing');
    }
  }

  //────────────────────────────────────────────────────────────────────────────
  // TWITTER (Multipart upload to media/upload + statuses/update)
  //────────────────────────────────────────────────────────────────────────────

  Future<void> _postToTwitter(SocialAction action) async {
    final uid = _auth.currentUser!.uid;
    final tokenDoc = await _getTokenDocument(uid, 'twitter');
    if (tokenDoc == null) {
      throw Exception('Twitter not authenticated');
    }
    final authToken = tokenDoc.data()!['auth_token'] as String;
    final authSecret = tokenDoc.data()!['auth_secret'] as String;

    // 1. Upload media to Twitter's upload endpoint
    final mediaId = await _uploadMediaToTwitter(
      action.content.media.first,
      authToken: authToken,
      authSecret: authSecret,
    );

    // 2. Post Tweet
    final status = _buildCaption(
      action.content.text,
      action.content.hashtags,
    );
    final replyTo = action.options.replyToPostId?['twitter'];

    final tweetUri = Uri.https(
      'api.twitter.com',
      '/1.1/statuses/update.json',
    );

    final oauthHeaders = _buildTwitterOAuth1Header(
      url: tweetUri.toString(),
      method: 'POST',
      params: {
        'status': status,
        if (replyTo != null) 'in_reply_to_status_id': replyTo,
        'media_ids': mediaId,
        'tweet_mode': action.platform_data.twitter!.tweetMode,
      },
      consumerKey: dotenv.env['TWITTER_API_KEY']!,
      consumerSecret: dotenv.env['TWITTER_API_SECRET']!,
      accessToken: authToken,
      accessTokenSecret: authSecret,
    );

    final tweetResp = await http.post(
      tweetUri,
      headers: oauthHeaders,
      body: {
        'status': status,
        if (replyTo != null) 'in_reply_to_status_id': replyTo,
        'media_ids': mediaId,
        'tweet_mode': action.platform_data.twitter!.tweetMode,
      },
    );
    final tweetData = jsonDecode(tweetResp.body) as Map<String, dynamic>;
    if (tweetResp.statusCode != 200 || tweetData.containsKey('errors')) {
      throw Exception(
        'Twitter post error: ${tweetData['errors'] ?? tweetResp.body}',
      );
    }

    print('Twitter post successful: ${tweetData['id_str']}');
  }

  Future<String> _uploadMediaToTwitter(
    MediaItem mediaItem, {
    required String authToken,
    required String authSecret,
  }) async {
    final uri = Uri.parse(mediaItem.fileUri);
    final File file = File(uri.path);

    final uploadUri =
        Uri.https('upload.twitter.com', '/1.1/media/upload.json');
    final oauthHeaders = _buildTwitterOAuth1Header(
      url: uploadUri.toString(),
      method: 'POST',
      params: {},
      consumerKey: dotenv.env['TWITTER_API_KEY']!,
      consumerSecret: dotenv.env['TWITTER_API_SECRET']!,
      accessToken: authToken,
      accessTokenSecret: authSecret,
    );

    final request = http.MultipartRequest('POST', uploadUri)
      ..headers.addAll(oauthHeaders)
      ..files.add(
        await http.MultipartFile.fromPath(
          'media',
          file.path,
          contentType: MediaType(
            mediaItem.mimeType.split('/')[0],
            mediaItem.mimeType.split('/')[1],
          ),
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data.containsKey('errors')) {
      throw Exception(
        'Twitter media upload error: ${data['errors'] ?? response.body}',
      );
    }
    return data['media_id_string'] as String;
  }

  Map<String, String> _buildTwitterOAuth1Header({
    required String url,
    required String method,
    required Map<String, String> params,
    required String consumerKey,
    required String consumerSecret,
    required String accessToken,
    required String accessTokenSecret,
  }) {
    final nonce = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();

    final oauthParams = {
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': accessToken,
      'oauth_version': '1.0',
    };

    final allParams = {...oauthParams, ...params};
    final paramString = allParams.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .toList()
      ..sort();
    final normalizedParams = paramString.join('&');

    final uri = Uri.parse(url);
    final baseString =
        '${method.toUpperCase()}&${Uri.encodeComponent(uri.origin + uri.path)}&${Uri.encodeComponent(normalizedParams)}';

    final signingKey =
        '${Uri.encodeComponent(consumerSecret)}&${Uri.encodeComponent(accessTokenSecret)}';
    
    final hmacSha1 = Hmac(sha1, utf8.encode(signingKey));
    final signatureBytes = hmacSha1.convert(utf8.encode(baseString)).bytes;
    final signature =
        base64Encode(signatureBytes).replaceAll('+', '%2B').replaceAll('/', '%2F');

    final authHeader = 'OAuth ' +
        oauthParams.entries
            .map((e) =>
                '${Uri.encodeComponent(e.key)}="${Uri.encodeComponent(e.value)}"')
            .toList()
            .join(', ') +
        ', oauth_signature="$signature"';

    return {'Authorization': authHeader};
  }

  //────────────────────────────────────────────────────────────────────────────
  // TIKTOK (Client → Backend → TikTok, no Firebase Storage)
  //────────────────────────────────────────────────────────────────────────────

  Future<void> _postToTikTok(SocialAction action) async {
    final uid = _auth.currentUser!.uid;
    final tokenDoc = await _getTokenDocument(uid, 'tiktok');
    if (tokenDoc == null) {
      throw Exception('TikTok not authenticated');
    }
    final accessToken = tokenDoc.data()!['access_token'] as String;
    final openId = tokenDoc.data()!['open_id'] as String;

    // 1. Retrieve local file
    final mediaItem = action.content.media.first;
    final File file = File(Uri.parse(mediaItem.fileUri).path);

    // 2. Send binary + metadata to our backend
    final uri =
        Uri.parse('${dotenv.env['BACKEND_URL']}/tiktok_upload_and_publish');
    final request = http.MultipartRequest('POST', uri)
      ..fields['access_token'] = accessToken
      ..fields['open_id'] = openId
      ..fields['caption'] = action.content.text
      ..fields['privacy'] = action.platform_data.tiktok!.privacy
      ..files.add(
        await http.MultipartFile.fromPath(
          'video_file',
          file.path,
          contentType: MediaType(
            mediaItem.mimeType.split('/')[0],
            mediaItem.mimeType.split('/')[1],
          ),
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['status'] != 'success') {
      throw Exception('TikTok publish error: ${data['message']}');
    }

    print('TikTok post successful: ${data['video_id']}');
  }

  //────────────────────────────────────────────────────────────────────────────
  // HELPERS: Token Fetch, Firestore Updates, Caption Builder
  //────────────────────────────────────────────────────────────────────────────

  Future<DocumentSnapshot<Map<String, dynamic>>?> _getTokenDocument(
      String uid, String platform) async {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('tokens')
        .doc(platform)
        .get();
    if (doc.exists) return doc;
    return null;
  }

  String _buildCaption(String text, List<String> hashtags) {
    final tags = hashtags.map((h) => '#$h').join(' ');
    return text.isNotEmpty ? '$text ${tags.isNotEmpty ? tags : ''}' : tags;
  }

  Future<void> _markActionPosted(String actionId) async {
    final uid = _auth.currentUser!.uid;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('actions')
        .doc(actionId)
        .update({
      'status': 'posted',
      'last_attempt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markActionFailed(
      String actionId, String errorMessage) async {
    final uid = _auth.currentUser!.uid;
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('actions')
        .doc(actionId);
    await ref.update({
      'status': 'failed',
      'retry_count': FieldValue.increment(1),
      'last_attempt': FieldValue.serverTimestamp(),
      'error_log': FieldValue.arrayUnion([
        {
          'timestamp': FieldValue.serverTimestamp(),
          'message': errorMessage,
        }
      ]),
    });
  }
}

// Helper class for HTTP content type
class MediaType {
  final String type;
  final String subtype;

  MediaType(this.type, this.subtype);

  @override
  String toString() => '$type/$subtype';
}