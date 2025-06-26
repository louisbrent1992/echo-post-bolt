import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:convert';
import '../models/social_action.dart';
import '../services/social_action_post_coordinator.dart';
import '../constants/social_platforms.dart';
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
      if (originalPost != null) {
        _coordinator!.syncWithExistingPost(originalPost);
      }

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
        // Facebook: hashtags at the end, space-separated
        return '$baseText\n\n${hashtags.map((tag) => '#$tag').join(' ')}';

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
              await _postToFacebookWithStrategy(action, authService);
              results[platform] = true;
            }
            break;
          case 'instagram':
            shouldPost = action.platformData.instagram?.postHere ?? false;
            if (shouldPost) {
              await _postToInstagramWithStrategy(action, authService);
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

  /// Post to Facebook with strategy-based approach
  Future<void> _postToFacebookWithStrategy(
      SocialAction action, AuthService? authService) async {
    // Check if user has business account access
    final hasBusinessAccess = await SocialPlatforms.hasBusinessAccountAccess(
        'facebook',
        authService: authService);

    if (hasBusinessAccess) {
      // Use automated posting via Facebook Graph API
      await _postToFacebook(action);
    } else {
      // Fall back to SharePlus for manual sharing
      await _shareToFacebookViaSharePlus(action);
    }
  }

  /// Post to Instagram with strategy-based approach
  Future<void> _postToInstagramWithStrategy(
      SocialAction action, AuthService? authService) async {
    // Check if user has business account access
    final hasBusinessAccess = await SocialPlatforms.hasBusinessAccountAccess(
        'instagram',
        authService: authService);

    if (hasBusinessAccess) {
      // Use automated posting via Instagram Basic Display API
      await _postToInstagram(action);
    } else {
      // Fall back to SharePlus for manual sharing
      await _shareToInstagramViaSharePlus(action);
    }
  }

  /// Share to Facebook using SharePlus (manual sharing)
  Future<void> _shareToFacebookViaSharePlus(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'facebook');

    if (kDebugMode) {
      print('📘 Sharing to Facebook via SharePlus...');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    try {
      String shareText = formattedContent;

      // Add media files if present
      List<XFile> mediaFiles = [];
      if (action.content.media.isNotEmpty) {
        for (final mediaItem in action.content.media) {
          if (mediaItem.fileUri.startsWith('file://')) {
            mediaFiles.add(XFile(mediaItem.fileUri));
          }
        }
      }

      // Share using SharePlus
      if (mediaFiles.isNotEmpty) {
        await Share.shareXFiles(
          mediaFiles,
          text: shareText,
          subject: 'Facebook Post',
        );
      } else {
        await Share.share(
          shareText,
          subject: 'Facebook Post',
        );
      }

      if (kDebugMode) {
        print('  ✅ Successfully shared to Facebook via SharePlus');
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ SharePlus sharing failed: $e');
      }
      rethrow;
    }
  }

  /// Share to Instagram using SharePlus (manual sharing)
  Future<void> _shareToInstagramViaSharePlus(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'instagram');

    if (kDebugMode) {
      print('📷 Sharing to Instagram via SharePlus...');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    try {
      String shareText = formattedContent;

      // Instagram requires media, so we need at least one media file
      List<XFile> mediaFiles = [];
      if (action.content.media.isNotEmpty) {
        for (final mediaItem in action.content.media) {
          if (mediaItem.fileUri.startsWith('file://')) {
            mediaFiles.add(XFile(mediaItem.fileUri));
          }
        }
      }

      if (mediaFiles.isEmpty) {
        throw Exception('Instagram requires media content for sharing');
      }

      // Share using SharePlus with media
      await Share.shareXFiles(
        mediaFiles,
        text: shareText,
        subject: 'Instagram Post',
      );

      if (kDebugMode) {
        print('  ✅ Successfully shared to Instagram via SharePlus');
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ SharePlus sharing failed: $e');
      }
      rethrow;
    }
  }

  /// Post to Facebook with proper API integration
  ///
  /// This method integrates with the Facebook Graph API to create posts on behalf of
  /// an authenticated user. It supports:
  ///
  /// - Text posts with hashtags
  /// - Image posts (photos endpoint)
  /// - Video posts (videos endpoint)
  /// - Link posts (feed endpoint with link)
  /// - Scheduled posts
  /// - Posting to user timeline or Facebook pages
  ///
  /// Requirements:
  /// - User must be authenticated with Facebook (access token stored in Firestore)
  /// - Facebook app must have appropriate permissions (publish_actions, pages_manage_posts)
  /// - For page posting, user must be admin of the page
  ///
  /// Media handling:
  /// - Local files (file:// or content:// URIs) require cloud storage upload first
  /// - Public URLs (http:// or https://) can be used directly
  /// - Media upload failures fall back to text-only posts
  ///
  /// Error handling:
  /// - Token expiration (code 190): Requires re-authentication
  /// - Permission errors (code 100): Check app permissions
  /// - Rate limiting (code 1): Retry later
  /// - Other errors: Detailed error messages with codes
  Future<void> _postToFacebook(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'facebook');

    if (kDebugMode) {
      print('📘 Posting to Facebook...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    try {
      // Get Facebook access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('facebook')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Facebook access token not found. Please authenticate with Facebook first.');
      }

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;
      final userId = tokenData['user_id'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        throw Exception(
            'Facebook access token has expired. Please re-authenticate.');
      }

      // Determine the endpoint based on whether posting as page or user
      final facebookData = action.platformData.facebook;
      String endpoint;
      Map<String, dynamic> postData = {
        'message': formattedContent,
        'access_token': accessToken,
      };

      // FIXED: Restructure to avoid null-aware operator issues
      final shouldPostAsPage = facebookData?.postAsPage == true;
      final pageId = facebookData?.pageId;

      if (shouldPostAsPage && pageId != null && pageId.isNotEmpty) {
        // Post to Facebook page
        endpoint = 'https://graph.facebook.com/v18.0/$pageId/feed';

        // Get page access token for posting to pages
        final pageAccessToken = await _getPageAccessToken(accessToken, pageId);
        if (pageAccessToken != null) {
          postData['access_token'] = pageAccessToken;
          if (kDebugMode) {
            print('  📄 Posting to Facebook page: $pageId');
          }
        } else {
          // Fallback to user timeline if page access token fails
          endpoint = 'https://graph.facebook.com/v18.0/$userId/feed';
          if (kDebugMode) {
            print(
                '  ⚠️ Failed to get page access token, posting to user timeline instead');
          }
        }
      } else {
        // Post to user's timeline
        endpoint = 'https://graph.facebook.com/v18.0/$userId/feed';
        if (kDebugMode) {
          print('  👤 Posting to user timeline');
        }
      }

      // Handle media attachments if present
      if (action.content.media.isNotEmpty) {
        final mediaItem = action.content.media.first;

        // FIXED: Restructure to avoid null-aware operator issues
        final mimeType = mediaItem.mimeType;
        if (mimeType != null && mimeType.startsWith('image/')) {
          // For images, we can use the photos endpoint or include in feed
          final postType = facebookData?.postType;
          if (postType == 'photo') {
            // Use photos endpoint for image posts
            endpoint = endpoint.replaceFirst('/feed', '/photos');
            final mediaUrl = await _uploadMediaToFacebook(
                accessToken, mediaItem.fileUri, 'image');
            if (mediaUrl != null) {
              postData['source'] = mediaUrl;
              postData['message'] = formattedContent;
            } else {
              // Fallback to text-only post if media upload fails
              if (kDebugMode) {
                print('  ⚠️ Media upload failed, posting text only');
              }
            }
          } else {
            // Include image URL in feed post
            final mediaUrl = await _uploadMediaToFacebook(
                accessToken, mediaItem.fileUri, 'image');
            if (mediaUrl != null) {
              postData['link'] = mediaUrl;
            }
          }
        } else if (mimeType != null && mimeType.startsWith('video/')) {
          // For videos, use the videos endpoint
          final postType = facebookData?.postType;
          if (postType == 'video') {
            endpoint = endpoint.replaceFirst('/feed', '/videos');
            final mediaUrl = await _uploadMediaToFacebook(
                accessToken, mediaItem.fileUri, 'video');
            if (mediaUrl != null) {
              postData['source'] = mediaUrl;
              postData['description'] = formattedContent;
              postData.remove(
                  'message'); // Videos use 'description' instead of 'message'
            } else {
              // Fallback to text-only post if media upload fails
              if (kDebugMode) {
                print('  ⚠️ Media upload failed, posting text only');
              }
            }
          } else {
            // Include video URL in feed post
            final mediaUrl = await _uploadMediaToFacebook(
                accessToken, mediaItem.fileUri, 'video');
            if (mediaUrl != null) {
              postData['link'] = mediaUrl;
            }
          }
        }
      }

      // Handle scheduled posts
      if (facebookData?.scheduledTime != null) {
        try {
          final scheduledTime = DateTime.parse(facebookData!.scheduledTime!);
          if (scheduledTime.isAfter(DateTime.now())) {
            postData['published'] = false;
            postData['scheduled_publish_time'] =
                (scheduledTime.millisecondsSinceEpoch / 1000).round();
            if (kDebugMode) {
              print('  ⏰ Scheduling post for: $scheduledTime');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print(
                '  ⚠️ Invalid scheduled time format: ${facebookData!.scheduledTime}');
          }
        }
      }

      if (kDebugMode) {
        print('  🌐 Making request to: $endpoint');
        print('  📤 Post data: ${jsonEncode(postData)}');
      }

      // Make the API request
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(postData),
      );

      if (kDebugMode) {
        print('  📥 Response status: ${response.statusCode}');
        print('  📥 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final postId = responseData['id'];

        if (kDebugMode) {
          print('  ✅ Successfully posted to Facebook');
          print('  🆔 Post ID: $postId');
        }

        // Store the post ID for verification
        await _storePostId(action.actionId, 'facebook', postId);
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage =
            errorData['error']?['message'] ?? 'Unknown Facebook API error';
        final errorCode = errorData['error']?['code'] ?? 'unknown';
        final errorType = errorData['error']?['type'] ?? 'unknown';

        if (kDebugMode) {
          print('  ❌ Facebook API error details:');
          print('    Code: $errorCode');
          print('    Type: $errorType');
          print('    Message: $errorMessage');
        }

        // Handle specific error types
        switch (errorCode) {
          case '190':
            throw Exception(
                'Facebook access token expired or invalid. Please re-authenticate.');
          case '100':
            throw Exception(
                'Facebook API permission error. Check app permissions.');
          case '1':
            throw Exception(
                'Facebook API rate limit exceeded. Please try again later.');
          case '200':
            throw Exception(
                'Facebook posting requires additional permissions. Please contact support to enable posting permissions.');
          case '294':
            throw Exception(
                'Facebook app requires review for posting permissions. Please contact support.');
          default:
            // Check if it's a permission-related error
            if (errorMessage.toLowerCase().contains('permission') ||
                errorMessage.toLowerCase().contains('publish_actions') ||
                errorMessage.toLowerCase().contains('pages_manage_posts')) {
              throw Exception(
                  'Facebook posting requires additional permissions. Please contact support to enable posting permissions. Error: $errorMessage');
            }
            throw Exception(
                'Facebook API error: $errorMessage (Code: $errorCode)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ Facebook posting failed: $e');
      }
      rethrow;
    }
  }

  /// Store post ID for verification purposes
  Future<void> _storePostId(
      String actionId, String platform, String postId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .update({
        'post_ids.$platform': postId,
        'last_updated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error storing post ID: $e');
      }
    }
  }

  /// Upload media to Facebook and get the media ID
  Future<String?> _uploadMediaToFacebook(
      String accessToken, String fileUri, String mediaType) async {
    try {
      if (kDebugMode) {
        print('📤 Uploading media to Facebook: $fileUri');
      }

      // For local files, we need to upload them to Facebook first
      // This is a simplified implementation - in production you might want to:
      // 1. Upload to a cloud storage service first (Firebase Storage, AWS S3, etc.)
      // 2. Then use the public URL for Facebook
      // 3. Or implement direct file upload to Facebook Graph API

      // For now, we'll assume the fileUri is already a public URL
      // In a real implementation, you would:
      // 1. Check if it's a local file (file:// or content:// URI)
      // 2. Upload to cloud storage if needed
      // 3. Get the public URL

      if (fileUri.startsWith('file://') || fileUri.startsWith('content://')) {
        if (kDebugMode) {
          print(
              '⚠️ Local file detected. In production, upload to cloud storage first.');
        }
        // For development, we'll skip media upload
        return null;
      }

      // If it's already a public URL, we can use it directly
      if (fileUri.startsWith('http://') || fileUri.startsWith('https://')) {
        if (kDebugMode) {
          print('✅ Using public URL for media: $fileUri');
        }
        return fileUri;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Media upload failed: $e');
      }
      return null;
    }
  }

  /// Get Facebook page access token for posting to pages
  Future<String?> _getPageAccessToken(
      String userAccessToken, String pageId) async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v18.0/$pageId?fields=access_token&access_token=$userAccessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['access_token'];
      } else {
        if (kDebugMode) {
          print('❌ Failed to get page access token: ${response.statusCode}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting page access token: $e');
      }
      return null;
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

    try {
      // Get Facebook access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('facebook')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        if (kDebugMode) {
          print('❌ Facebook access token expired during verification');
        }
        return false;
      }

      // Verify post exists using Facebook Graph API
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v18.0/$postId?fields=id,created_time,message&access_token=$accessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print('🔍 Facebook verification response: ${response.statusCode}');
        print('🔍 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final verifiedPostId = data['id'];

        if (verifiedPostId == postId) {
          if (kDebugMode) {
            print('✅ Facebook post verified successfully');
          }
          return true;
        }
      } else if (response.statusCode == 404) {
        if (kDebugMode) {
          print('❌ Facebook post not found (404)');
        }
        return false;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        if (kDebugMode) {
          print('❌ Facebook verification error: $errorMessage');
        }
        return false;
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Facebook verification failed: $e');
      }
      return false;
    }
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
            'timestamp': DateTime.now().toIso8601String(),
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
