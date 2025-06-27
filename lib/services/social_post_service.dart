import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

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

      case 'youtube':
        // YouTube: hashtags at the beginning for better discoverability, max 15 hashtags
        final limitedHashtags = hashtags.take(15).toList();
        final hashtagText = limitedHashtags.map((tag) => '#$tag').join(' ');
        return '$hashtagText\n\n$baseText';

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
              await _postToYouTubeWithStrategy(action, authService);
              results[platform] = true;
            }
            break;
          case 'twitter':
            shouldPost = action.platformData.twitter?.postHere ?? false;
            if (shouldPost) {
              await _postToTwitterWithStrategy(action, authService);
              results[platform] = true;
            }
            break;
          case 'tiktok':
            shouldPost = action.platformData.tiktok?.postHere ?? false;
            if (shouldPost) {
              await _postToTikTokWithStrategy(action, authService);
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

  /// Post to YouTube with strategy-based approach
  Future<void> _postToYouTubeWithStrategy(
      SocialAction action, AuthService? authService) async {
    // YouTube doesn't require business account, but check if user is authenticated
    final isAuthenticated = await authService?.isPlatformConnected('youtube') ?? false;

    if (isAuthenticated) {
      // Use automated posting via YouTube Data API
      await _postToYouTube(action);
    } else {
      // Fall back to SharePlus for manual sharing
      await _shareToYouTubeViaSharePlus(action);
    }
  }

  /// Post to Twitter with strategy-based approach
  Future<void> _postToTwitterWithStrategy(
      SocialAction action, AuthService? authService) async {
    // Twitter doesn't require business account, but check if user is authenticated
    final isAuthenticated = await authService?.isPlatformConnected('twitter') ?? false;

    if (isAuthenticated) {
      // Use automated posting via Twitter API
      await _postToTwitter(action);
    } else {
      // Fall back to SharePlus for manual sharing
      await _shareToTwitterViaSharePlus(action);
    }
  }

  /// Post to TikTok with strategy-based approach
  Future<void> _postToTikTokWithStrategy(
      SocialAction action, AuthService? authService) async {
    // TikTok doesn't require business account, but check if user is authenticated
    final isAuthenticated = await authService?.isPlatformConnected('tiktok') ?? false;

    if (isAuthenticated) {
      // Use automated posting via TikTok API
      await _postToTikTok(action);
    } else {
      // Fall back to SharePlus for manual sharing
      await _shareToTikTokViaSharePlus(action);
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
            final filePath = Uri.parse(mediaItem.fileUri).path;
            if (await File(filePath).exists()) {
              mediaFiles.add(XFile(filePath));
            }
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
            final filePath = Uri.parse(mediaItem.fileUri).path;
            if (await File(filePath).exists()) {
              mediaFiles.add(XFile(filePath));
            }
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

  /// Share to YouTube using SharePlus (manual sharing)
  Future<void> _shareToYouTubeViaSharePlus(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'youtube');

    if (kDebugMode) {
      print('📺 Sharing to YouTube via SharePlus...');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    try {
      // YouTube requires video content
      if (action.content.media.isEmpty || 
          !action.content.media.first.mimeType.startsWith('video/')) {
        throw Exception('YouTube requires video content for sharing');
      }

      List<XFile> mediaFiles = [];
      for (final mediaItem in action.content.media) {
        if (mediaItem.fileUri.startsWith('file://') && 
            mediaItem.mimeType.startsWith('video/')) {
          final filePath = Uri.parse(mediaItem.fileUri).path;
          if (await File(filePath).exists()) {
            mediaFiles.add(XFile(filePath));
          }
        }
      }

      if (mediaFiles.isEmpty) {
        throw Exception('No valid video files found for YouTube sharing');
      }

      // Share using SharePlus with video
      await Share.shareXFiles(
        mediaFiles,
        text: formattedContent,
        subject: 'YouTube Video',
      );

      if (kDebugMode) {
        print('  ✅ Successfully shared to YouTube via SharePlus');
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ SharePlus sharing failed: $e');
      }
      rethrow;
    }
  }

  /// Share to Twitter using SharePlus (manual sharing)
  Future<void> _shareToTwitterViaSharePlus(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'twitter');

    if (kDebugMode) {
      print('🐦 Sharing to Twitter via SharePlus...');
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
            final filePath = Uri.parse(mediaItem.fileUri).path;
            if (await File(filePath).exists()) {
              mediaFiles.add(XFile(filePath));
            }
          }
        }
      }

      // Share using SharePlus
      if (mediaFiles.isNotEmpty) {
        await Share.shareXFiles(
          mediaFiles,
          text: shareText,
          subject: 'Twitter Post',
        );
      } else {
        await Share.share(
          shareText,
          subject: 'Twitter Post',
        );
      }

      if (kDebugMode) {
        print('  ✅ Successfully shared to Twitter via SharePlus');
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ SharePlus sharing failed: $e');
      }
      rethrow;
    }
  }

  /// Share to TikTok using SharePlus (manual sharing)
  Future<void> _shareToTikTokViaSharePlus(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'tiktok');

    if (kDebugMode) {
      print('🎵 Sharing to TikTok via SharePlus...');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    try {
      // TikTok requires video content
      if (action.content.media.isEmpty || 
          !action.content.media.first.mimeType.startsWith('video/')) {
        throw Exception('TikTok requires video content for sharing');
      }

      List<XFile> mediaFiles = [];
      for (final mediaItem in action.content.media) {
        if (mediaItem.fileUri.startsWith('file://') && 
            mediaItem.mimeType.startsWith('video/')) {
          final filePath = Uri.parse(mediaItem.fileUri).path;
          if (await File(filePath).exists()) {
            mediaFiles.add(XFile(filePath));
          }
        }
      }

      if (mediaFiles.isEmpty) {
        throw Exception('No valid video files found for TikTok sharing');
      }

      // Share using SharePlus with video
      await Share.shareXFiles(
        mediaFiles,
        text: formattedContent,
        subject: 'TikTok Video',
      );

      if (kDebugMode) {
        print('  ✅ Successfully shared to TikTok via SharePlus');
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
        if (mimeType.startsWith('image/')) {
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
        } else if (mimeType.startsWith('video/')) {
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

  /// Upload media to Facebook and get the media ID
  Future<String?> _uploadMediaToFacebook(
      String accessToken, String fileUri, String mediaType) async {
    try {
      if (kDebugMode) {
        print('📤 Uploading media to Facebook: $fileUri');
      }

      // For local files, we need to upload them to Facebook first
      if (fileUri.startsWith('file://') || fileUri.startsWith('content://')) {
        final filePath = Uri.parse(fileUri).path;
        final file = File(filePath);
        
        if (!await file.exists()) {
          throw Exception('Media file does not exist: $filePath');
        }
        
        // Determine endpoint based on media type
        final endpoint = mediaType == 'image' 
            ? 'https://graph.facebook.com/v18.0/me/photos'
            : 'https://graph.facebook.com/v18.0/me/videos';
            
        // Create multipart request
        final request = http.MultipartRequest('POST', Uri.parse(endpoint));
        request.fields['access_token'] = accessToken;
        request.fields['published'] = 'false'; // Don't publish yet, just upload
        
        // Add file
        request.files.add(await http.MultipartFile.fromPath(
          'source',
          filePath,
        ));
        
        // Send request
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        
        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          final mediaId = responseData['id'];
          
          if (kDebugMode) {
            print('✅ Successfully uploaded media to Facebook');
            print('🆔 Media ID: $mediaId');
          }
          
          return mediaId;
        } else {
          if (kDebugMode) {
            print('❌ Failed to upload media to Facebook: ${response.body}');
          }
          return null;
        }
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

    try {
      // Get Instagram access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('instagram')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Instagram access token not found. Please authenticate with Instagram first.');
      }

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;
      final igUserId = tokenData['user_id'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        throw Exception(
            'Instagram access token has expired. Please re-authenticate.');
      }

      // Verify we have media (Instagram requires media)
      if (action.content.media.isEmpty) {
        throw Exception('Instagram requires media content for posting');
      }

      final mediaItem = action.content.media.first;
      final isVideo = mediaItem.mimeType.startsWith('video/');
      final mediaPath = Uri.parse(mediaItem.fileUri).path;

      // Step 1: Create container for media upload
      final containerResponse = await http.post(
        Uri.parse('https://graph.facebook.com/v18.0/$igUserId/media'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'access_token': accessToken,
          'caption': formattedContent,
          'media_type': isVideo ? 'VIDEO' : 'IMAGE',
        }),
      );

      if (containerResponse.statusCode != 200) {
        final errorData = jsonDecode(containerResponse.body);
        throw Exception(
            'Instagram container creation failed: ${errorData['error']?['message'] ?? 'Unknown error'}');
      }

      final containerData = jsonDecode(containerResponse.body);
      final containerId = containerData['id'];

      if (kDebugMode) {
        print('  ✅ Created Instagram media container: $containerId');
      }

      // Step 2: Upload media to container
      final uploadUrl = isVideo
          ? 'https://graph.facebook.com/v18.0/$containerId/media_publish'
          : 'https://graph.facebook.com/v18.0/$igUserId/media_publish';

      final file = File(mediaPath);
      if (!await file.exists()) {
        throw Exception('Media file does not exist: $mediaPath');
      }

      final uploadRequest = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      uploadRequest.fields['access_token'] = accessToken;
      uploadRequest.fields['creation_id'] = containerId;
      uploadRequest.files.add(await http.MultipartFile.fromPath(
        'source',
        mediaPath,
      ));

      final uploadStreamResponse = await uploadRequest.send();
      final uploadResponse = await http.Response.fromStream(uploadStreamResponse);

      if (uploadResponse.statusCode != 200) {
        final errorData = jsonDecode(uploadResponse.body);
        throw Exception(
            'Instagram media upload failed: ${errorData['error']?['message'] ?? 'Unknown error'}');
      }

      final uploadData = jsonDecode(uploadResponse.body);
      final mediaId = uploadData['id'];

      if (kDebugMode) {
        print('  ✅ Successfully posted to Instagram');
        print('  🆔 Media ID: $mediaId');
      }

      // Store the post ID for verification
      await _storePostId(action.actionId, 'instagram', mediaId);
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ Instagram posting failed: $e');
      }
      rethrow;
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

    try {
      // Get YouTube access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('youtube')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'YouTube access token not found. Please authenticate with Google first.');
      }

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        throw Exception(
            'YouTube access token has expired. Please re-authenticate.');
      }

      // Verify we have video media (YouTube requires video)
      if (action.content.media.isEmpty) {
        throw Exception('YouTube requires video content for posting');
      }

      final mediaItem = action.content.media.first;
      if (!mediaItem.mimeType.startsWith('video/')) {
        throw Exception('YouTube only supports video content');
      }

      final videoPath = Uri.parse(mediaItem.fileUri).path;
      final file = File(videoPath);
      if (!await file.exists()) {
        throw Exception('Video file does not exist: $videoPath');
      }

      // YouTube Data API v3 upload endpoint
      final uploadUrl = 'https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status';

      // Prepare metadata
      final metadata = {
        'snippet': {
          'title': action.content.text.split('\n')[0].substring(0, 
              action.content.text.split('\n')[0].length > 100 
                  ? 100 
                  : action.content.text.split('\n')[0].length),
          'description': formattedContent,
          'tags': action.content.hashtags,
          'categoryId': action.platformData.youtube?.videoCategoryId ?? '22', // 22 = People & Blogs
        },
        'status': {
          'privacyStatus': action.platformData.youtube?.privacy ?? 'public',
          'selfDeclaredMadeForKids': action.platformData.youtube?.madeForKids ?? false,
        }
      };

      // Create resumable upload session
      final sessionResponse = await http.post(
        Uri.parse('$uploadUrl&uploadType=resumable'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': mediaItem.mimeType,
          'X-Upload-Content-Length': '${await file.length()}',
        },
        body: jsonEncode(metadata),
      );

      if (sessionResponse.statusCode != 200) {
        throw Exception('Failed to create YouTube upload session: ${sessionResponse.statusCode}');
      }

      // Get upload URL from Location header
      final uploadLocation = sessionResponse.headers['location'];
      if (uploadLocation == null) {
        throw Exception('No upload URL provided by YouTube API');
      }

      // Upload the video file
      final videoBytes = await file.readAsBytes();
      final uploadResponse = await http.post(
        Uri.parse(uploadLocation),
        headers: {
          'Content-Type': mediaItem.mimeType,
          'Content-Length': '${videoBytes.length}',
        },
        body: videoBytes,
      );

      if (uploadResponse.statusCode != 200 && uploadResponse.statusCode != 201) {
        throw Exception('YouTube video upload failed: ${uploadResponse.statusCode}');
      }

      final responseData = jsonDecode(uploadResponse.body);
      final videoId = responseData['id'];

      if (kDebugMode) {
        print('  ✅ Successfully uploaded to YouTube');
        print('  🆔 Video ID: $videoId');
      }

      // Store the post ID for verification
      await _storePostId(action.actionId, 'youtube', videoId);
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ YouTube posting failed: $e');
      }
      rethrow;
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

    try {
      // Get Twitter access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('twitter')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Twitter access token not found. Please authenticate with Twitter first.');
      }

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;
      final userId = tokenData['user_id'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'];
      if (expiresAt != null) {
        final expiryDate = DateTime.parse(expiresAt);
        if (expiryDate.isBefore(DateTime.now())) {
          throw Exception(
              'Twitter access token has expired. Please re-authenticate.');
        }
      }

      // Twitter API v2 endpoint for creating tweets
      final endpoint = 'https://api.twitter.com/2/tweets';

      // Prepare tweet data
      Map<String, dynamic> tweetData = {
        'text': formattedContent,
      };

      // Handle media if present
      if (action.content.media.isNotEmpty) {
        final mediaItem = action.content.media.first;
        final mediaPath = Uri.parse(mediaItem.fileUri).path;
        
        // First, upload media to Twitter
        final mediaId = await _uploadMediaToTwitter(accessToken, mediaPath, mediaItem.mimeType);
        
        if (mediaId != null) {
          tweetData['media'] = {
            'media_ids': [mediaId]
          };
        }
      }

      // Make the API request
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(tweetData),
      );

      if (kDebugMode) {
        print('  📥 Response status: ${response.statusCode}');
        print('  📥 Response body: ${response.body}');
      }

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final tweetId = responseData['data']['id'];

        if (kDebugMode) {
          print('  ✅ Successfully posted to Twitter');
          print('  🆔 Tweet ID: $tweetId');
        }

        // Store the post ID for verification
        await _storePostId(action.actionId, 'twitter', tweetId);
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['detail'] ?? 'Unknown Twitter API error';
        
        if (kDebugMode) {
          print('  ❌ Twitter API error: $errorMessage');
        }
        
        throw Exception('Twitter API error: $errorMessage');
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ Twitter posting failed: $e');
      }
      rethrow;
    }
  }

  /// Upload media to Twitter and get the media ID
  Future<String?> _uploadMediaToTwitter(String accessToken, String filePath, String mimeType) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Media file does not exist: $filePath');
      }

      // Twitter API v2 media upload endpoint
      final endpoint = 'https://upload.twitter.com/1.1/media/upload.json';
      
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(endpoint));
      request.headers['Authorization'] = 'Bearer $accessToken';
      
      // Add file
      request.files.add(await http.MultipartFile.fromPath(
        'media',
        filePath,
        contentType: MediaType.parse(mimeType),
      ));
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final mediaId = responseData['media_id_string'];
        
        if (kDebugMode) {
          print('✅ Successfully uploaded media to Twitter');
          print('🆔 Media ID: $mediaId');
        }
        
        return mediaId;
      } else {
        if (kDebugMode) {
          print('❌ Failed to upload media to Twitter: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Twitter media upload failed: $e');
      }
      return null;
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

    try {
      // Get TikTok access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('User not authenticated');
      }

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('tiktok')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'TikTok access token not found. Please authenticate with TikTok first.');
      }

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;
      final openId = tokenData['user_id'] as String;

      // Verify we have video media (TikTok requires video)
      if (action.content.media.isEmpty) {
        throw Exception('TikTok requires video content for posting');
      }

      final mediaItem = action.content.media.first;
      if (!mediaItem.mimeType.startsWith('video/')) {
        throw Exception('TikTok only supports video content');
      }

      final videoPath = Uri.parse(mediaItem.fileUri).path;
      final file = File(videoPath);
      if (!await file.exists()) {
        throw Exception('Video file does not exist: $videoPath');
      }

      // Get Firebase Functions URL from .env
      final backendUrl = dotenv.env['BACKEND_URL'];
      if (backendUrl == null || backendUrl.isEmpty) {
        throw Exception('BACKEND_URL not found in .env file');
      }

      // Create form data for video upload
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$backendUrl/tiktokUploadAndPublish'),
      );

      // Add form fields
      request.fields['access_token'] = accessToken;
      request.fields['open_id'] = openId;
      request.fields['caption'] = formattedContent;
      request.fields['privacy'] = action.platformData.tiktok?.privacy ?? 'PUBLIC';

      // Add video file
      request.files.add(await http.MultipartFile.fromPath(
        'video_file',
        videoPath,
      ));

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) {
        print('  📥 Response status: ${response.statusCode}');
        print('  📥 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['status'] == 'success') {
          final videoId = responseData['video_id'];

          if (kDebugMode) {
            print('  ✅ Successfully posted to TikTok');
            print('  🆔 Video ID: $videoId');
          }

          // Store the post ID for verification
          await _storePostId(action.actionId, 'tiktok', videoId);
        } else {
          throw Exception('TikTok posting failed: ${responseData['message']}');
        }
      } else {
        throw Exception('TikTok API error: ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ TikTok posting failed: $e');
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

    try {
      // Get Instagram access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('instagram')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;
      final igUserId = tokenData['user_id'] as String;

      // Verify media exists using Instagram Graph API
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v18.0/$postId?fields=id,media_type,media_url,permalink&access_token=$accessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print('🔍 Instagram verification response: ${response.statusCode}');
        print('🔍 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final verifiedPostId = data['id'];

        if (verifiedPostId == postId) {
          if (kDebugMode) {
            print('✅ Instagram post verified successfully');
          }
          return true;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Instagram verification failed: $e');
      }
      return false;
    }
  }

  /// Verify YouTube post exists
  Future<bool> _verifyYouTubePost(String? postId) async {
    if (postId == null) return false;

    try {
      // Get YouTube access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('youtube')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;

      // Verify video exists using YouTube Data API v3
      final response = await http.get(
        Uri.parse(
            'https://www.googleapis.com/youtube/v3/videos?id=$postId&part=snippet&access_token=$accessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print('🔍 YouTube verification response: ${response.statusCode}');
        print('🔍 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List;

        if (items.isNotEmpty) {
          if (kDebugMode) {
            print('✅ YouTube video verified successfully');
          }
          return true;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ YouTube verification failed: $e');
      }
      return false;
    }
  }

  /// Verify Twitter post exists
  Future<bool> _verifyTwitterPost(String? postId) async {
    if (postId == null) return false;

    try {
      // Get Twitter access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('twitter')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;

      // Verify tweet exists using Twitter API v2
      final response = await http.get(
        Uri.parse('https://api.twitter.com/2/tweets/$postId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print('🔍 Twitter verification response: ${response.statusCode}');
        print('🔍 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data']['id'] == postId) {
          if (kDebugMode) {
            print('✅ Twitter post verified successfully');
          }
          return true;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Twitter verification failed: $e');
      }
      return false;
    }
  }

  /// Verify TikTok post exists
  Future<bool> _verifyTikTokPost(String? postId) async {
    if (postId == null) return false;

    try {
      // Get TikTok access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid == null) return false;

      final tokenDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('tiktok')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;
      final openId = tokenData['user_id'] as String;

      // Get Firebase Functions URL from .env
      final backendUrl = dotenv.env['BACKEND_URL'];
      if (backendUrl == null || backendUrl.isEmpty) {
        throw Exception('BACKEND_URL not found in .env file');
      }

      // Verify video exists using TikTok API via Cloud Function
      final response = await http.get(
        Uri.parse('$backendUrl/tiktokVerifyVideo?video_id=$postId&open_id=$openId&access_token=$accessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print('🔍 TikTok verification response: ${response.statusCode}');
        print('🔍 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          if (kDebugMode) {
            print('✅ TikTok video verified successfully');
          }
          return true;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ TikTok verification failed: $e');
      }
      return false;
    }
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

/// MediaType class for MIME type parsing
class MediaType {
  final String type;
  final String subtype;
  final Map<String, String> parameters;

  MediaType(this.type, this.subtype, [this.parameters = const {}]);

  factory MediaType.parse(String value) {
    final parts = value.split(';');
    final typeAndSubtype = parts[0].trim().split('/');
    
    if (typeAndSubtype.length != 2) {
      throw FormatException('Invalid media type: $value');
    }
    
    final type = typeAndSubtype[0].trim();
    final subtype = typeAndSubtype[1].trim();
    
    final parameters = <String, String>{};
    for (var i = 1; i < parts.length; i++) {
      final paramParts = parts[i].trim().split('=');
      if (paramParts.length == 2) {
        parameters[paramParts[0].trim()] = paramParts[1].trim();
      }
    }
    
    return MediaType(type, subtype, parameters);
  }

  @override
  String toString() {
    final buffer = StringBuffer('$type/$subtype');
    parameters.forEach((key, value) {
      buffer.write('; $key=$value');
    });
    return buffer.toString();
  }
}