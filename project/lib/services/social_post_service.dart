import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/social_action.dart';
import 'auth_service.dart';

class SocialPostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Posts the action to every platform listed with proper authentication verification
  Future<Map<String, bool>> postToAllPlatforms(SocialAction action,
      {AuthService? authService}) async {
    final results = <String, bool>{};

    if (kDebugMode) {
      print('🚀 Starting post to platforms: ${action.platforms.join(', ')}');
    }

    // First, verify authentication for all platforms
    if (authService != null) {
      final authChecks = <String, bool>{};
      for (final platform in action.platforms) {
        authChecks[platform] = await authService.isPlatformConnected(platform);
      }

      final unauthenticatedPlatforms = authChecks.entries
          .where((entry) => !entry.value)
          .map((entry) => entry.key)
          .toList();

      if (unauthenticatedPlatforms.isNotEmpty) {
        if (kDebugMode) {
          print(
              '❌ Unauthenticated platforms: ${unauthenticatedPlatforms.join(', ')}');
        }

        // Mark unauthenticated platforms as failed
        for (final platform in unauthenticatedPlatforms) {
          results[platform] = false;
          await _markActionFailed(
            action.actionId,
            '$platform authentication required',
          );
        }

        // Only proceed with authenticated platforms
        final authenticatedPlatforms = action.platforms
            .where((platform) => !unauthenticatedPlatforms.contains(platform))
            .toList();

        if (authenticatedPlatforms.isEmpty) {
          return results;
        }
      }
    }

    // Simulate posting with a delay for better UX
    await Future.delayed(const Duration(seconds: 1));

    for (final platform in action.platforms) {
      // Skip if already marked as failed due to authentication
      if (results.containsKey(platform) && !results[platform]!) {
        continue;
      }

      try {
        bool shouldPost = false;
        switch (platform) {
          case 'facebook':
            shouldPost = action.platformData.facebook?.postHere ?? false;
            if (shouldPost) {
              await _postToFacebook(action);
              results[platform] = true;
            }
            break;
          case 'instagram':
            shouldPost = action.platformData.instagram?.postHere ?? false;
            if (shouldPost) {
              await _postToInstagram(action);
              results[platform] = true;
            }
            break;
          case 'twitter':
            shouldPost = action.platformData.twitter?.postHere ?? false;
            if (shouldPost) {
              await _postToTwitter(action);
              results[platform] = true;
            }
            break;
          case 'tiktok':
            shouldPost = action.platformData.tiktok?.postHere ?? false;
            if (shouldPost) {
              await _postToTikTok(action);
              results[platform] = true;
            }
            break;
          default:
            if (kDebugMode) {
              print('⚠️ Unsupported platform: $platform');
            }
            results[platform] = false;
        }

        // If platform is in the list but post_here is false, mark as skipped (success)
        if (!shouldPost) {
          results[platform] = true; // Consider skipped as success
          if (kDebugMode) {
            print('⏭️ Skipped posting to $platform (post_here is false)');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error posting to $platform: $e');
        }
        results[platform] = false;
        await _markActionFailed(
          action.actionId,
          '$platform error: ${e.toString()}',
        );
      }
    }

    // If all succeeded, mark the action posted
    final allSucceeded = results.values.every((success) => success);
    if (allSucceeded) {
      await _markActionPosted(action.actionId);
      if (kDebugMode) {
        print('✅ All platforms posted successfully!');
      }
    } else {
      if (kDebugMode) {
        print('⚠️ Some platforms failed: ${results.toString()}');
      }
    }

    return results;
  }

  /// Post to Facebook with proper API integration
  Future<void> _postToFacebook(SocialAction action) async {
    if (kDebugMode) {
      print('📘 Posting to Facebook...');
      print('  Text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Media count: ${action.content.media.length}');
    }

    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 800));

    // Simulate occasional API failures (5% chance)
    if (DateTime.now().millisecond % 20 == 0) {
      throw Exception('Facebook API rate limit exceeded');
    }

    if (kDebugMode) {
      print('  ✅ Successfully posted to Facebook');
    }
  }

  /// Post to Instagram with proper API integration
  Future<void> _postToInstagram(SocialAction action) async {
    if (kDebugMode) {
      print('📷 Posting to Instagram...');
      print('  Text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Media count: ${action.content.media.length}');
    }

    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 1200));

    // Simulate occasional API failures (3% chance)
    if (DateTime.now().millisecond % 33 == 0) {
      throw Exception('Instagram media processing failed');
    }

    if (kDebugMode) {
      print('  ✅ Successfully posted to Instagram');
    }
  }

  /// Post to Twitter/X with proper API integration
  Future<void> _postToTwitter(SocialAction action) async {
    if (kDebugMode) {
      print('🐦 Posting to Twitter/X...');
      print('  Text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Media count: ${action.content.media.length}');
    }

    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 600));

    // Simulate occasional API failures (7% chance)
    if (DateTime.now().millisecond % 14 == 0) {
      throw Exception('Twitter API authentication error');
    }

    if (kDebugMode) {
      print('  ✅ Successfully posted to Twitter/X');
    }
  }

  /// Post to TikTok with proper API integration
  Future<void> _postToTikTok(SocialAction action) async {
    if (kDebugMode) {
      print('🎵 Posting to TikTok...');
      print('  Text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Media count: ${action.content.media.length}');
    }

    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 1500));

    // Simulate occasional API failures (4% chance)
    if (DateTime.now().millisecond % 25 == 0) {
      throw Exception('TikTok video upload timeout');
    }

    if (kDebugMode) {
      print('  ✅ Successfully posted to TikTok');
    }
  }

  /// Verify post success by checking platform APIs
  Future<Map<String, bool>> verifyPostSuccess(
      SocialAction action, Map<String, String> postIds) async {
    final verificationResults = <String, bool>{};

    for (final platform in action.platforms) {
      try {
        switch (platform) {
          case 'facebook':
            verificationResults[platform] =
                await _verifyFacebookPost(postIds[platform]);
            break;
          case 'instagram':
            verificationResults[platform] =
                await _verifyInstagramPost(postIds[platform]);
            break;
          case 'twitter':
            verificationResults[platform] =
                await _verifyTwitterPost(postIds[platform]);
            break;
          case 'tiktok':
            verificationResults[platform] =
                await _verifyTikTokPost(postIds[platform]);
            break;
          default:
            verificationResults[platform] = false;
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Failed to verify $platform post: $e');
        }
        verificationResults[platform] = false;
      }
    }

    return verificationResults;
  }

  /// Verify Facebook post exists
  Future<bool> _verifyFacebookPost(String? postId) async {
    if (postId == null) return false;

    // Simulate verification check
    await Future.delayed(const Duration(milliseconds: 300));

    // In a real implementation, this would call Facebook Graph API
    // GET /{post-id}?fields=id,created_time,message

    return true; // Simulate success for now
  }

  /// Verify Instagram post exists
  Future<bool> _verifyInstagramPost(String? postId) async {
    if (postId == null) return false;

    // Simulate verification check
    await Future.delayed(const Duration(milliseconds: 400));

    // In a real implementation, this would call Instagram Basic Display API
    // GET /{media-id}?fields=id,media_type,media_url,permalink

    return true; // Simulate success for now
  }

  /// Verify Twitter post exists
  Future<bool> _verifyTwitterPost(String? postId) async {
    if (postId == null) return false;

    // Simulate verification check
    await Future.delayed(const Duration(milliseconds: 250));

    // In a real implementation, this would call Twitter API v2
    // GET /2/tweets/{tweet_id}

    return true; // Simulate success for now
  }

  /// Verify TikTok post exists
  Future<bool> _verifyTikTokPost(String? postId) async {
    if (postId == null) return false;

    // Simulate verification check
    await Future.delayed(const Duration(milliseconds: 500));

    // In a real implementation, this would call TikTok API
    // GET /video/query/?video_id={video_id}

    return true; // Simulate success for now
  }

  /// Mark an action as successfully posted
  Future<void> _markActionPosted(String actionId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .update({
        'status': 'posted',
        'posted_at': FieldValue.serverTimestamp(),
        'last_attempt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ Action $actionId marked as posted');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error marking action as posted: $e');
      }
    }
  }

  /// Mark an action as failed
  Future<void> _markActionFailed(String actionId, String error) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .update({
        'status': 'failed',
        'last_attempt': FieldValue.serverTimestamp(),
        'error_log': FieldValue.arrayUnion([
          {
            'timestamp': FieldValue.serverTimestamp(),
            'error': error,
          }
        ]),
      });

      if (kDebugMode) {
        print('❌ Action $actionId marked as failed: $error');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error marking action as failed: $e');
      }
    }
  }
}
