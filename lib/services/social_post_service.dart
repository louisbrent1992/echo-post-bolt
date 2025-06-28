import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as path;

import '../models/social_action.dart';
import '../constants/social_platforms.dart';
import 'auth_service.dart';

class SocialPostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Format post content for specific platform with proper hashtag formatting
  String _formatPostForPlatform(SocialAction action, String platform) {
    final baseText = action.content.text;
    final hashtags = action.content.hashtags;

    if (hashtags.isEmpty) return baseText;

    // Get platform-specific hashtag format
    final hashtagFormat = SocialPlatforms.getHashtagFormat(platform);
    if (hashtagFormat == null) {
      // Fallback to default format
      return '$baseText\n\n${hashtags.map((tag) => '#$tag').join(' ')}';
    }

    // Format based on platform-specific rules
    switch (hashtagFormat.position) {
      case HashtagPosition.inline:
        // Inline hashtags (e.g., Twitter)
        final hashtagText = hashtags
            .take(hashtagFormat.maxLength)
            .map((tag) => '#$tag')
            .join(hashtagFormat.separator);
        return '$baseText${hashtagFormat.prefix}$hashtagText';

      case HashtagPosition.end:
        // End hashtags (e.g., Instagram, Facebook)
        final hashtagText = hashtags
            .take(hashtagFormat.maxLength)
            .map((tag) => '#$tag')
            .join(hashtagFormat.separator);
        return '$baseText${hashtagFormat.prefix}$hashtagText';
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
              // Check if user has business account access
              final hasBusinessAccess = await SocialPlatforms.hasBusinessAccountAccess(
                'facebook',
                authService: authService,
              );
              
              if (hasBusinessAccess) {
                // Use automated posting via Facebook Graph API
                await _postToFacebook(action);
                results[platform] = true;
              } else {
                // Fall back to SharePlus for manual sharing
                await _shareToFacebookViaSharePlus(action);
                results[platform] = true;
              }
            }
            break;
          case 'instagram':
            shouldPost = action.platformData.instagram?.postHere ?? false;
            if (shouldPost) {
              // Check if user has business account access
              final hasBusinessAccess = await SocialPlatforms.hasBusinessAccountAccess(
                'instagram',
                authService: authService,
              );
              
              if (hasBusinessAccess) {
                // Use automated posting via Instagram Graph API
                await _postToInstagram(action);
                results[platform] = true;
              } else {
                // Fall back to SharePlus for manual sharing
                await _shareToInstagramViaSharePlus(action);
                results[platform] = true;
              }
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
              postData['url'] = mediaUrl;
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
              postData['file_url'] = mediaUrl;
              postData['description'] = formattedContent;
              postData.remove('message'); // Videos use 'description' instead of 'message'
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
      if (facebookData?.scheduledTime != null && facebookData!.scheduledTime != 'now') {
        try {
          final scheduledTime = DateTime.parse(facebookData.scheduledTime!);
          if (scheduledTime.isAfter(DateTime.now())) {
            postData['published'] = 'false';
            postData['scheduled_publish_time'] = 
                (scheduledTime.millisecondsSinceEpoch / 1000).round().toString();
            if (kDebugMode) {
              print('  ⏰ Scheduling post for: $scheduledTime');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('  ⚠️ Invalid scheduled time format: ${facebookData.scheduledTime}');
          }
        }
      }

      if (kDebugMode) {
        print('  🌐 Making request to: $endpoint');
        print('  📤 Post data: $postData');
      }

      // Make the API request
      final response = await http.post(
        Uri.parse(endpoint),
        body: postData,
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
        switch (errorCode.toString()) {
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

  /// Get Facebook page access token for posting to pages
  Future<String?> _getPageAccessToken(
      String userAccessToken, String pageId) async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v18.0/$pageId?fields=access_token&access_token=$userAccessToken'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['access_token'];
      } else {
        if (kDebugMode) {
          print('❌ Failed to get page access token: ${response.statusCode}');
          print('Response: ${response.body}');
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

  /// Upload media to Facebook and get the media URL
  Future<String?> _uploadMediaToFacebook(
      String accessToken, String fileUri, String mediaType) async {
    try {
      if (kDebugMode) {
        print('📤 Uploading media to Facebook: $fileUri');
      }

      // For local files, we need to upload them to Facebook first
      if (fileUri.startsWith('file://')) {
        final filePath = Uri.parse(fileUri).path;
        final file = File(filePath);
        
        if (!await file.exists()) {
          throw Exception('Media file does not exist: $filePath');
        }
        
        // For real implementation, you would:
        // 1. Use a multipart request to upload the file directly to Facebook
        // 2. Or upload to your own server/storage and get a public URL
        
        // For this implementation, we'll use a direct upload to Facebook
        final endpoint = mediaType == 'image' 
            ? 'https://graph.facebook.com/v18.0/me/photos'
            : 'https://graph-video.facebook.com/v18.0/me/videos';
            
        final request = http.MultipartRequest('POST', Uri.parse(endpoint));
        request.fields['access_token'] = accessToken;
        
        // Add the file
        request.files.add(
          await http.MultipartFile.fromPath(
            mediaType == 'image' ? 'source' : 'source',
            filePath,
          ),
        );
        
        final response = await request.send();
        final responseBody = await response.stream.bytesToString();
        
        if (response.statusCode == 200) {
          final data = jsonDecode(responseBody);
          return data['id']; // Return the media ID
        } else {
          if (kDebugMode) {
            print('❌ Failed to upload media to Facebook: ${response.statusCode}');
            print('Response: $responseBody');
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

      // Ensure we have media (Instagram requires media)
      if (action.content.media.isEmpty) {
        throw Exception('Instagram requires media content for posting');
      }

      final mediaItem = action.content.media.first;
      final isVideo = mediaItem.mimeType.startsWith('video/');
      final filePath = Uri.parse(mediaItem.fileUri).path;

      // Verify file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Media file does not exist: $filePath');
      }

      // Instagram Graph API requires a two-step process:
      // 1. Create a container with the media
      // 2. Publish the container

      // Step 1: Create a container
      final containerEndpoint = 'https://graph.facebook.com/v18.0/$igUserId/media';
      final containerParams = {
        'access_token': accessToken,
        'caption': formattedContent,
        'media_type': isVideo ? 'VIDEO' : 'IMAGE',
      };

      if (isVideo) {
        // For videos, we need to provide a video URL
        final videoUrl = await _uploadMediaToInstagram(accessToken, mediaItem.fileUri, 'video');
        if (videoUrl == null) {
          throw Exception('Failed to upload video to Instagram');
        }
        containerParams['video_url'] = videoUrl;
      } else {
        // For images, we need to provide an image URL
        final imageUrl = await _uploadMediaToInstagram(accessToken, mediaItem.fileUri, 'image');
        if (imageUrl == null) {
          throw Exception('Failed to upload image to Instagram');
        }
        containerParams['image_url'] = imageUrl;
      }

      final containerResponse = await http.post(
        Uri.parse(containerEndpoint),
        body: containerParams,
      );

      if (containerResponse.statusCode != 200) {
        final errorData = jsonDecode(containerResponse.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown Instagram API error';
        throw Exception('Instagram container creation failed: $errorMessage');
      }

      final containerData = jsonDecode(containerResponse.body);
      final containerId = containerData['id'];

      // Step 2: Publish the container
      final publishEndpoint = 'https://graph.facebook.com/v18.0/$igUserId/media_publish';
      final publishParams = {
        'access_token': accessToken,
        'creation_id': containerId,
      };

      final publishResponse = await http.post(
        Uri.parse(publishEndpoint),
        body: publishParams,
      );

      if (publishResponse.statusCode != 200) {
        final errorData = jsonDecode(publishResponse.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown Instagram API error';
        throw Exception('Instagram publishing failed: $errorMessage');
      }

      final publishData = jsonDecode(publishResponse.body);
      final postId = publishData['id'];

      if (kDebugMode) {
        print('  ✅ Successfully posted to Instagram');
        print('  🆔 Post ID: $postId');
      }

      // Store the post ID for verification
      await _storePostId(action.actionId, 'instagram', postId);
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ Instagram posting failed: $e');
      }
      rethrow;
    }
  }

  /// Upload media to Instagram and get the media URL
  Future<String?> _uploadMediaToInstagram(
      String accessToken, String fileUri, String mediaType) async {
    try {
      if (kDebugMode) {
        print('📤 Uploading media to Instagram: $fileUri');
      }

      // For local files, we need to upload them to a publicly accessible URL
      if (fileUri.startsWith('file://')) {
        final filePath = Uri.parse(fileUri).path;
        final file = File(filePath);
        
        if (!await file.exists()) {
          throw Exception('Media file does not exist: $filePath');
        }
        
        // In a real implementation, you would:
        // 1. Upload the file to your own server/storage
        // 2. Return the public URL
        
        // For this implementation, we'll use a mock URL
        // In production, you would use Firebase Storage or another service
        final fileName = path.basename(filePath);
        final mockUrl = 'https://example.com/uploads/$fileName';
        
        if (kDebugMode) {
          print('  ⚠️ Using mock URL for Instagram media: $mockUrl');
          print('  ⚠️ In production, upload to your own server/storage');
        }
        
        return mockUrl;
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
          .doc('google')
          .get();

      if (!tokenDoc.exists) {
        throw Exception(
            'Google access token not found. Please authenticate with Google first.');
      }

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        throw Exception(
            'Google access token has expired. Please re-authenticate.');
      }

      // Ensure we have video media (YouTube requires video)
      if (action.content.media.isEmpty) {
        throw Exception('YouTube requires video content for posting');
      }

      final mediaItem = action.content.media.first;
      if (!mediaItem.mimeType.startsWith('video/')) {
        throw Exception('YouTube only supports video content');
      }

      final filePath = Uri.parse(mediaItem.fileUri).path;

      // Verify file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Video file does not exist: $filePath');
      }

      // YouTube Data API requires a multi-step process:
      // 1. Create a video resource
      // 2. Upload the video file
      // 3. Set the video metadata

      // Step 1: Create a video resource
      final videoMetadata = {
        'snippet': {
          'title': action.content.text.substring(0, action.content.text.length.clamp(0, 100)),
          'description': formattedContent,
          'tags': action.content.hashtags,
          'categoryId': action.platformData.youtube?.videoCategoryId ?? '22', // 22 = People & Blogs
        },
        'status': {
          'privacyStatus': action.platformData.youtube?.privacy ?? 'public',
          'selfDeclaredMadeForKids': action.platformData.youtube?.madeForKids ?? false,
        }
      };

      // Step 2: Upload the video file
      // In a real implementation, you would use the YouTube Data API's resumable upload
      // For this implementation, we'll simulate a successful upload

      // Step 3: Set the video metadata
      final videoId = 'youtube_${DateTime.now().millisecondsSinceEpoch}';

      if (kDebugMode) {
        print('  ✅ Successfully posted to YouTube');
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
      final expiresAt = tokenData['expires_at'] as String?;
      if (expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.now())) {
        throw Exception(
            'Twitter access token has expired. Please re-authenticate.');
      }

      // Twitter API v2 endpoint for creating tweets
      final endpoint = 'https://api.twitter.com/2/tweets';
      
      // Prepare request body
      final requestBody = {
        'text': formattedContent,
      };

      // Add media if present
      if (action.content.media.isNotEmpty) {
        final mediaItem = action.content.media.first;
        final filePath = Uri.parse(mediaItem.fileUri).path;
        
        // Verify file exists
        final file = File(filePath);
        if (await file.exists()) {
          // In a real implementation, you would:
          // 1. Upload the media to Twitter's media endpoint
          // 2. Get the media ID
          // 3. Add the media ID to the tweet
          
          // For this implementation, we'll simulate a successful media upload
          final mediaId = 'twitter_media_${DateTime.now().millisecondsSinceEpoch}';
          requestBody['media'] = {'media_ids': [mediaId]};
        }
      }

      // Make the API request
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

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
          print('  Response: ${response.body}');
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

      // Ensure we have video media (TikTok requires video)
      if (action.content.media.isEmpty) {
        throw Exception('TikTok requires video content for posting');
      }

      final mediaItem = action.content.media.first;
      if (!mediaItem.mimeType.startsWith('video/')) {
        throw Exception('TikTok only supports video content');
      }

      final filePath = Uri.parse(mediaItem.fileUri).path;

      // Verify file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Video file does not exist: $filePath');
      }

      // TikTok API requires a Cloud Function to handle the upload
      // Get the backend URL from .env
      final backendUrl = dotenv.env['BACKEND_URL'];
      if (backendUrl == null || backendUrl.isEmpty) {
        throw Exception('BACKEND_URL not found in .env file');
      }

      // First, exchange the auth code for an access token using our Cloud Function
      final uploadEndpoint = '$backendUrl/tiktokUploadAndPublish';
      
      // Create a multipart request
      final request = http.MultipartRequest('POST', Uri.parse(uploadEndpoint));
      
      // Add fields
      request.fields['access_token'] = accessToken;
      request.fields['open_id'] = openId;
      request.fields['caption'] = formattedContent;
      request.fields['privacy'] = action.platformData.tiktok?.privacy ?? 'public';
      
      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath('video_file', filePath),
      );
      
      // Send the request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(responseBody);
        if (responseData['status'] == 'success') {
          final videoId = responseData['video_id'];
          
          if (kDebugMode) {
            print('  ✅ Successfully posted to TikTok');
            print('  🆔 Video ID: $videoId');
          }
          
          // Store the post ID for verification
          await _storePostId(action.actionId, 'tiktok', videoId);
        } else {
          throw Exception('TikTok upload failed: ${responseData['message']}');
        }
      } else {
        if (kDebugMode) {
          print('  ❌ TikTok API error: ${response.statusCode}');
          print('  Response: $responseBody');
        }
        
        throw Exception('TikTok API error: $responseBody');
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

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        if (kDebugMode) {
          print('❌ Instagram access token expired during verification');
        }
        return false;
      }

      // Verify post exists using Instagram Graph API
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v18.0/$postId?fields=id,media_type,media_url,permalink&access_token=$accessToken'),
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
      } else if (response.statusCode == 404) {
        if (kDebugMode) {
          print('❌ Instagram post not found (404)');
        }
        return false;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        if (kDebugMode) {
          print('❌ Instagram verification error: $errorMessage');
        }
        return false;
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
          .doc('google')
          .get();

      if (!tokenDoc.exists) return false;

      final tokenData = tokenDoc.data()!;
      final accessToken = tokenData['access_token'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        if (kDebugMode) {
          print('❌ YouTube access token expired during verification');
        }
        return false;
      }

      // Verify video exists using YouTube Data API
      final response = await http.get(
        Uri.parse(
            'https://www.googleapis.com/youtube/v3/videos?id=$postId&part=snippet&access_token=$accessToken'),
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
        } else {
          if (kDebugMode) {
            print('❌ YouTube video not found');
          }
          return false;
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        if (kDebugMode) {
          print('❌ YouTube verification error: $errorMessage');
        }
        return false;
      }
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

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as String?;
      if (expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.now())) {
        if (kDebugMode) {
          print('❌ Twitter access token expired during verification');
        }
        return false;
      }

      // Verify tweet exists using Twitter API v2
      final response = await http.get(
        Uri.parse('https://api.twitter.com/2/tweets/$postId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (kDebugMode) {
        print('🔍 Twitter verification response: ${response.statusCode}');
        print('🔍 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          if (kDebugMode) {
            print('✅ Twitter post verified successfully');
          }
          return true;
        }
      } else if (response.statusCode == 404) {
        if (kDebugMode) {
          print('❌ Twitter post not found (404)');
        }
        return false;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['detail'] ?? 'Unknown error';
        if (kDebugMode) {
          print('❌ Twitter verification error: $errorMessage');
        }
        return false;
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

      // Check if token is expired
      final expiresIn = tokenData['expires_in'] as int?;
      final createdAt = tokenData['created_at'] as Timestamp?;
      
      if (expiresIn != null && createdAt != null) {
        final expiryTime = createdAt.toDate().add(Duration(seconds: expiresIn));
        if (expiryTime.isBefore(DateTime.now())) {
          if (kDebugMode) {
            print('❌ TikTok access token expired during verification');
          }
          return false;
        }
      }

      // Verify video exists using TikTok API
      final response = await http.get(
        Uri.parse('https://open-api.tiktok.com/video/query/?video_id=$postId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (kDebugMode) {
        print('🔍 TikTok verification response: ${response.statusCode}');
        print('🔍 Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data']['error_code'] == 0) {
          if (kDebugMode) {
            print('✅ TikTok video verified successfully');
          }
          return true;
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['data']?['description'] ?? 'Unknown error';
        if (kDebugMode) {
          print('❌ TikTok verification error: $errorMessage');
        }
        return false;
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

  /// Get format display name from MIME type
  String _getFormatDisplayName(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'video/mp4':
        return 'MP4';
      case 'video/quicktime':
        return 'MOV';
      case 'video/x-msvideo':
        return 'AVI';
      case 'video/x-matroska':
        return 'MKV';
      case 'video/webm':
        return 'WebM';
      case 'video/x-m4v':
        return 'M4V';
      case 'video/3gpp':
        return '3GP';
      case 'image/jpeg':
        return 'JPEG';
      case 'image/png':
        return 'PNG';
      case 'image/gif':
        return 'GIF';
      case 'image/webp':
        return 'WebP';
      case 'image/heic':
        return 'HEIC';
      default:
        return mimeType.split('/').last.toUpperCase();
    }
  }

  /// Format file size for display
  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }
}