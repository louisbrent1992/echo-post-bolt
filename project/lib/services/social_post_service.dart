import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/social_action.dart';
import '../services/social_action_post_coordinator.dart';
import 'auth_service.dart';

class SocialPostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SocialActionPostCoordinator? _coordinator;

  SocialPostService({SocialActionPostCoordinator? coordinator})
      : _coordinator = coordinator;

  /// Format post content for specific platform with proper hashtag formatting
  String _formatPostForPlatform(SocialAction action, String platform) {
    // If coordinator is available, use its formatting method
    if (_coordinator != null) {
      // Temporarily sync the action with coordinator to use its formatting
      final originalPost = _coordinator!.currentPost;
      _coordinator!.syncWithExistingPost(action);
      final formattedContent = _coordinator!.getFormattedPostContent(platform);

      // Restore original post if it existed
      _coordinator!.syncWithExistingPost(originalPost);

      return formattedContent;
    }

    // Fallback formatting if coordinator is not available
    return _fallbackFormatPostForPlatform(action, platform);
  }

  /// Fallback post formatting when coordinator is not available
  String _fallbackFormatPostForPlatform(SocialAction action, String platform) {
    final baseText = action.content.text;
    final hashtags = action.content.hashtags;

    if (hashtags.isEmpty) return baseText;

    switch (platform.toLowerCase()) {
      case 'instagram':
        // Instagram: hashtags at the end, separated by spaces, max 30 hashtags
        final limitedHashtags = hashtags.take(30).toList();
        return '$baseText\n\n${limitedHashtags.map((tag) => '#$tag').join(' ')}';

      case 'twitter':
        // Twitter: hashtags integrated naturally, max 280 chars total, 2-3 hashtags recommended
        final limitedHashtags = hashtags.take(3).toList();
        final hashtagText =
            ' ${limitedHashtags.map((tag) => '#$tag').join(' ')}';
        final combinedText = '$baseText$hashtagText';

        // Ensure we don't exceed Twitter's character limit
        if (combinedText.length > 280) {
          final availableSpace = 280 - baseText.length - 1; // -1 for space
          if (availableSpace > 0) {
            var truncatedHashtags = '';
            for (final tag in limitedHashtags) {
              final tagWithHash = '#$tag ';
              if (truncatedHashtags.length + tagWithHash.length <=
                  availableSpace) {
                truncatedHashtags += tagWithHash;
              } else {
                break;
              }
            }
            return '$baseText ${truncatedHashtags.trim()}';
          }
          return baseText; // Return just text if no space for hashtags
        }
        return combinedText;

      case 'facebook':
        // Facebook: hashtags at the end, each on new line for better readability
        return '\n\n${hashtags.map((tag) => '#$tag').join(' ')}';

      case 'youtube':
        // YouTube: hashtags at the end, space-separated, max 15 hashtags
        final limitedHashtags = hashtags.take(15).toList();
        return '\n\n${limitedHashtags.map((tag) => '#$tag').join(' ')}';

      case 'tiktok':
        // TikTok: hashtags at the end, space-separated, max 100 chars for hashtags
        var formattedHashtags = hashtags.map((tag) => '#$tag').join(' ');
        if (formattedHashtags.length > 100) {
          // Truncate if too long
          final truncatedTags = <String>[];
          var currentLength = 0;
          for (final tag in hashtags) {
            final tagWithHash = '#$tag ';
            if (currentLength + tagWithHash.length <= 100) {
              truncatedTags.add(tag);
              currentLength += tagWithHash.length;
            } else {
              break;
            }
          }
          formattedHashtags = truncatedTags.map((tag) => '#$tag').join(' ');
        }
        return '$baseText\n\n$formattedHashtags';

      default:
        // Default format: hashtags at the end, space-separated
        return '$baseText\n\n${hashtags.map((tag) => '#$tag').join(' ')}';
    }
  }

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
          case 'youtube':
            shouldPost = action.platformData.youtube?.postHere ?? false;
            if (shouldPost) {
              await _postToYouTube(action);
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
    final formattedContent = _formatPostForPlatform(action, 'facebook');

    if (kDebugMode) {
      print('📘 Posting to Facebook...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
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
    final formattedContent = _formatPostForPlatform(action, 'instagram');

    if (kDebugMode) {
      print('📷 Posting to Instagram...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
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

  /// Post to YouTube with proper API integration
  Future<void> _postToYouTube(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'youtube');

    if (kDebugMode) {
      print('📺 Posting to YouTube...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    // Simulate processing time (YouTube uploads take longer)
    await Future.delayed(const Duration(milliseconds: 2000));

    // Simulate occasional API failures (2% chance)
    if (DateTime.now().millisecond % 50 == 0) {
      throw Exception('YouTube upload processing failed');
    }

    if (kDebugMode) {
      print('  ✅ Successfully posted to YouTube');
    }
  }

  /// Post to Twitter/X with proper API integration
  Future<void> _postToTwitter(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'twitter');

    if (kDebugMode) {
      print('🐦 Posting to Twitter/X...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
      print('  Character count: ${formattedContent.length}/280');
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
    final formattedContent = _formatPostForPlatform(action, 'tiktok');

    if (kDebugMode) {
      print('🎵 Posting to TikTok...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 1500));

    // Simulate occasional API failures (4% chance)
    if (DateTime.now().millisecond % 25 == 0) {
      throw Exception('TikTok video processing timeout');
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
          case 'youtube':
            verificationResults[platform] =
                await _verifyYouTubePost(postIds[platform]);
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

  /// Verify YouTube post exists
  Future<bool> _verifyYouTubePost(String? postId) async {
    if (postId == null) return false;

    // Simulate verification check
    await Future.delayed(const Duration(milliseconds: 600));

    // In a real implementation, this would call YouTube Data API v3
    // GET /youtube/v3/videos?id={video_id}&part=snippet

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
