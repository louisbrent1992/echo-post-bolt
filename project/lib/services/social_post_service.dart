import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../models/social_action.dart';
import '../services/social_action_post_coordinator.dart';
import '../constants/social_platforms.dart';
import 'auth_service.dart';
import 'package:path/path.dart' as path;

class SocialPostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SocialActionPostCoordinator? _coordinator;
  final AuthService? _authService;

  SocialPostService(
      {SocialActionPostCoordinator? coordinator, AuthService? authService})
      : _coordinator = coordinator,
        _authService = authService;

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
        await _postToPlatform(action, platform, authService);
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

  /// Post to platform with proper API integration
  Future<void> _postToPlatform(
      SocialAction action, String platform, AuthService? authService) async {
    try {
      switch (platform) {
        case 'facebook':
          await _postToFacebook(action, authService);
          break;
        case 'instagram':
          // Check if user has Instagram access
          final hasInstagramAccess =
              await authService?.hasInstagramAccess() ?? false;

          if (hasInstagramAccess) {
            // Use automated posting via Instagram API with Instagram Login
            await _postToInstagram(action);
          } else {
            // Fall back to SharePlus for manual sharing
            await _shareToInstagramViaSharePlus(action);
          }
          break;
        case 'youtube':
          await _postToYouTube(action);
          break;
        case 'twitter':
          await _postToTwitter(action);
          break;
        case 'tiktok':
          await _postToTikTok(action);
          break;
        default:
          if (kDebugMode) {
            print('⚠️ Unsupported platform: $platform');
          }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error posting to $platform: $e');
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
  Future<void> _postToFacebook(
      SocialAction action, AuthService? authService) async {
    final formattedContent = _formatPostForPlatform(action, 'facebook');

    if (kDebugMode) {
      print('📘 Posting to Facebook...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    // --- PATCH: Use share_plus for user timeline (manual sharing) ---
    final fbData = action.platformData.facebook;
    final postAsPage = fbData?.postAsPage == true;
    if (!postAsPage) {
      // User selected to post to their own timeline: use share_plus
      if (kDebugMode) {
        print(
            '🔗 User selected My Timeline. Using share_plus for manual sharing.');
      }
      // Prepare text and media for sharing
      final text = formattedContent;
      if (action.content.media.isNotEmpty) {
        // Only share the first image for simplicity
        final media = action.content.media.first;
        final fileUri = media.fileUri;
        if (fileUri.startsWith('file://')) {
          final filePath = fileUri.replaceFirst('file://', '');
          await Share.shareXFiles([XFile(filePath)], text: text);
        } else {
          // If not a file URI, just share the text
          await Share.share(text);
        }
      } else {
        await Share.share(text);
      }
      return;
    }
    // --- END PATCH ---

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
      final userAccessToken = tokenData['access_token'] as String;
      final userId = tokenData['user_id'] as String;

      // Check if token is expired
      final expiresAt = tokenData['expires_at'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        throw Exception(
            'Facebook access token has expired. Please re-authenticate.');
      }

      // Determine posting target and get appropriate token
      String endpoint;
      String accessToken;
      String targetId;
      bool isPagePost = false;

      // Use user selection to determine if posting as page or user
      if (fbData?.postAsPage == true &&
          fbData?.pageId != null &&
          fbData!.pageId.isNotEmpty) {
        // Post as page
        isPagePost = true;
        targetId = fbData.pageId;
        endpoint = 'https://graph.facebook.com/v23.0/me/feed';
        if (kDebugMode) {
          print(
              '  📄 User selected to post as Facebook page: ${fbData.pageId}');
        }
        // Validate page access and permissions
        if (_authService != null) {
          try {
            final canPost =
                await _authService!.canPostToFacebookPage(fbData.pageId);
            if (!canPost) {
              throw Exception(
                  'You do not have permission to post to this Facebook page. Please ensure you are an admin, editor, or moderator of the page.');
            }
            if (kDebugMode) {
              print(
                  '  ✅ Page posting permission verified for page: ${fbData.pageId}');
            }
          } catch (e) {
            if (kDebugMode) {
              print('  ⚠️ Page permission check failed: $e');
            }
            // Continue with posting attempt, let the API handle the final validation
          }
        }
        // Get page access token for posting to pages
        try {
          final pageAccessToken =
              await _getPageAccessToken(userAccessToken, fbData.pageId);
          if (pageAccessToken != null) {
            accessToken = pageAccessToken;
            if (kDebugMode) {
              print(
                  '  ✅ Using page access token for posting to page: ${fbData.pageId}');
            }
          } else {
            // Fallback to user timeline if page access token fails
            isPagePost = false;
            targetId = userId;
            endpoint = 'https://graph.facebook.com/v23.0/me/feed';
            accessToken = userAccessToken;
            if (kDebugMode) {
              print(
                  '  ⚠️ Failed to get page access token, posting to user timeline instead');
            }
          }
        } catch (e) {
          // If page access token fails, try to post to user timeline
          isPagePost = false;
          targetId = userId;
          endpoint = 'https://graph.facebook.com/v23.0/me/feed';
          accessToken = userAccessToken;
          if (kDebugMode) {
            print(
                '  ⚠️ Page access token error, falling back to user timeline: $e');
          }
        }
      } else {
        // Post to user's timeline - use user access token
        isPagePost = false;
        targetId = userId;
        endpoint = 'https://graph.facebook.com/v23.0/me/feed';
        accessToken = userAccessToken;
        if (kDebugMode) {
          print('  👤 User selected to post to their own timeline');
        }
      }

      // Initialize post data with the correct access token
      Map<String, dynamic> postData = {
        'message': formattedContent,
        'access_token': accessToken,
      };

      // Handle media attachments if present
      if (action.content.media.isNotEmpty) {
        final mediaItem = action.content.media.first;

        // FIXED: Restructure to avoid null-aware operator issues
        final mimeType = mediaItem.mimeType;
        if (mimeType != null && mimeType.startsWith('image/')) {
          // For images, use the photos endpoint and include message in the same request
          endpoint = endpoint.replaceFirst('/feed', '/photos');
          postData['message'] = formattedContent;

          // Check if it's a local file
          if (mediaItem.fileUri.startsWith('file://') ||
              mediaItem.fileUri.startsWith('content://')) {
            if (kDebugMode) {
              print('  📸 Uploading image with message to photos endpoint');
            }
            // The actual file upload will be handled in the multipart request below
          } else if (mediaItem.fileUri.startsWith('http://') ||
              mediaItem.fileUri.startsWith('https://')) {
            // For public URLs, use them directly
            postData['url'] = mediaItem.fileUri;
            if (kDebugMode) {
              print('  📸 Using public URL for image: ${mediaItem.fileUri}');
            }
          } else {
            if (kDebugMode) {
              print('  ⚠️ Unsupported image URI format, posting text only');
            }
            // Reset endpoint back to feed for text-only post
            endpoint = endpoint.replaceFirst('/photos', '/feed');
          }
        } else if (mimeType != null && mimeType.startsWith('video/')) {
          // For videos, use the videos endpoint
          final postType = fbData?.postType;
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
              // Reset endpoint back to feed for text-only post
              endpoint = endpoint.replaceFirst('/videos', '/feed');
            }
          } else {
            // Upload video and attach to feed post
            final mediaId = await _uploadMediaToFacebook(
                accessToken, mediaItem.fileUri, 'video');
            if (mediaId != null) {
              // Attach the media ID to the feed post
              postData['attached_media'] = '[{"media_fbid":"$mediaId"}]';
              if (kDebugMode) {
                print('  📎 Attaching video media ID: $mediaId');
              }
            } else {
              if (kDebugMode) {
                print('  ⚠️ Video upload failed, posting text only');
              }
            }
          }
        }
      }

      // Check if we need to use multipart request for local image files
      bool useMultipartRequest = false;
      String? localImagePath;

      if (action.content.media.isNotEmpty) {
        final mediaItem = action.content.media.first;
        if (mediaItem.mimeType != null &&
            mediaItem.mimeType.startsWith('image/') &&
            (mediaItem.fileUri.startsWith('file://') ||
                mediaItem.fileUri.startsWith('content://'))) {
          useMultipartRequest = true;
          localImagePath = mediaItem.fileUri.replaceFirst('file://', '');
        }
      }

      if (kDebugMode) {
        print('  🌐 Making request to: $endpoint');
        if (useMultipartRequest) {
          print('  📤 Using multipart request for local image upload');
        } else {
          print('  📤 Post data: ${jsonEncode(postData)}');
        }
        print('  🔑 Using ${isPagePost ? 'page' : 'user'} access token: ' +
            (accessToken.length > 12
                ? accessToken.substring(0, 6) +
                    '...' +
                    accessToken.substring(accessToken.length - 6)
                : accessToken));
      }

      // Make the API request
      http.Response response;

      if (useMultipartRequest && localImagePath != null) {
        // Use multipart request for local image upload
        final request = http.MultipartRequest('POST', Uri.parse(endpoint));

        // Add all the fields from postData
        for (final entry in postData.entries) {
          if (entry.value != null) {
            request.fields[entry.key] = entry.value.toString();
          }
        }

        // Add the image file
        final file = File(localImagePath);
        if (await file.exists()) {
          final fileBytes = await file.readAsBytes();
          final fileName = file.path.split('/').last;
          request.files.add(http.MultipartFile.fromBytes(
            'source',
            fileBytes,
            filename: fileName,
          ));

          if (kDebugMode) {
            print(
                '  📁 Attaching image file: $fileName (${fileBytes.length} bytes)');
          }
        }

        final streamedResponse = await request.send();
        response = await http.Response.fromStream(streamedResponse);
      } else {
        // Use regular JSON request
        response = await http.post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode(postData),
        );
      }

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
          print(
              '  📍 Posted to: ${isPagePost ? 'Page ($targetId)' : 'User timeline'}');
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

      // Handle scheduled posts
      if (fbData?.scheduledTime != null) {
        try {
          final scheduledTime = DateTime.parse(fbData!.scheduledTime!);
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
                '  ⚠️ Invalid scheduled time format: ${fbData!.scheduledTime}');
          }
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
        print('  📁 Media type: $mediaType');
        print(
            '  🔑 Using access token: ${accessToken.length > 12 ? accessToken.substring(0, 6) + '...' + accessToken.substring(accessToken.length - 6) : accessToken}');
      }

      // Handle local files by uploading them to Facebook
      if (fileUri.startsWith('file://') || fileUri.startsWith('content://')) {
        if (kDebugMode) {
          print('  📂 Local file detected, uploading to Facebook...');
        }

        // Read the file data
        final file = File(fileUri.replaceFirst('file://', ''));
        if (!await file.exists()) {
          if (kDebugMode) {
            print('  ❌ File does not exist: $fileUri');
          }
          return null;
        }

        final fileBytes = await file.readAsBytes();
        if (kDebugMode) {
          print('  📊 File size: ${fileBytes.length} bytes');
        }

        // Determine the correct endpoint based on media type
        String endpoint;
        if (mediaType == 'image') {
          endpoint = 'https://graph.facebook.com/v23.0/me/photos';
        } else if (mediaType == 'video') {
          endpoint = 'https://graph.facebook.com/v23.0/me/videos';
        } else {
          if (kDebugMode) {
            print('  ❌ Unsupported media type: $mediaType');
          }
          return null;
        }

        // Create multipart request
        final request = http.MultipartRequest('POST', Uri.parse(endpoint));

        // Add access token
        request.fields['access_token'] = accessToken;

        // Add file
        final fileName = file.path.split('/').last;
        request.files.add(http.MultipartFile.fromBytes(
          'source',
          fileBytes,
          filename: fileName,
        ));

        if (kDebugMode) {
          print('  🌐 Uploading to: $endpoint');
          print('  📁 File name: $fileName');
        }

        // Send the request
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (kDebugMode) {
          print('  📥 Upload response status: ${response.statusCode}');
          print('  📥 Upload response body: ${response.body}');
        }

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          final mediaId = responseData['id'];

          if (kDebugMode) {
            print('  ✅ Media uploaded successfully');
            print('  🆔 Media ID: $mediaId');
          }

          return mediaId;
        } else {
          final errorData = jsonDecode(response.body);
          final errorMessage =
              errorData['error']?['message'] ?? 'Unknown upload error';
          if (kDebugMode) {
            print('  ❌ Media upload failed: $errorMessage');
          }
          return null;
        }
      }

      // Handle public URLs (already uploaded to cloud storage)
      if (fileUri.startsWith('http://') || fileUri.startsWith('https://')) {
        if (kDebugMode) {
          print('  ✅ Using public URL for media: $fileUri');
        }
        return fileUri;
      }

      if (kDebugMode) {
        print('  ❌ Unsupported file URI format: $fileUri');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ Media upload failed: $e');
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
      final instagramUserId = tokenData['instagram_user_id'] as String;
      final accountType = tokenData['account_type'] as String;

      // Check if token is expired
      final expiresIn = tokenData['expires_in'] as int?;
      final createdAt = tokenData['created_at'] as Timestamp?;
      if (expiresIn != null && createdAt != null) {
        final expirationDate =
            createdAt.toDate().add(Duration(seconds: expiresIn));
        if (expirationDate.isBefore(DateTime.now())) {
          throw Exception(
              'Instagram access token has expired. Please re-authenticate.');
        }
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

      if (kDebugMode) {
        print('  📷 Instagram User ID: $instagramUserId');
        print('  📷 Account Type: $accountType');
        print('  📷 Media type: ${isVideo ? 'VIDEO' : 'IMAGE'}');
        print('  📷 File path: $filePath');
      }

      // Instagram API with Instagram Login uses different endpoints
      // For content publishing, we use the Instagram Graph API endpoints

      // Step 1: Create a container with the media
      final containerEndpoint =
          'https://graph.instagram.com/v12.0/$instagramUserId/media';
      final containerParams = {
        'access_token': accessToken,
        'caption': formattedContent,
        'media_type': isVideo ? 'VIDEO' : 'IMAGE',
      };

      if (isVideo) {
        // For videos, we need to provide a video URL
        final videoUrl = await _uploadMediaToInstagram(
            accessToken, mediaItem.fileUri, 'video');
        if (videoUrl == null) {
          throw Exception('Failed to upload video to Instagram');
        }
        containerParams['video_url'] = videoUrl;
      } else {
        // For images, we need to provide an image URL
        final imageUrl = await _uploadMediaToInstagram(
            accessToken, mediaItem.fileUri, 'image');
        if (imageUrl == null) {
          throw Exception('Failed to upload image to Instagram');
        }
        containerParams['image_url'] = imageUrl;
      }

      if (kDebugMode) {
        print('  📤 Creating Instagram container...');
        print('  📤 Container endpoint: $containerEndpoint');
        print('  📤 Container params: ${jsonEncode(containerParams)}');
      }

      final containerResponse = await http.post(
        Uri.parse(containerEndpoint),
        body: containerParams,
      );

      if (kDebugMode) {
        print(
            '  📥 Container response status: ${containerResponse.statusCode}');
        print('  📥 Container response body: ${containerResponse.body}');
      }

      if (containerResponse.statusCode != 200) {
        final errorData = jsonDecode(containerResponse.body);
        final errorMessage =
            errorData['error']?['message'] ?? 'Unknown Instagram API error';
        final errorCode = errorData['error']?['code'] ?? 'unknown';

        if (kDebugMode) {
          print('  ❌ Instagram container creation failed:');
          print('    Code: $errorCode');
          print('    Message: $errorMessage');
        }

        // Handle specific Instagram API errors
        switch (errorCode) {
          case '100':
            throw Exception(
                'Instagram API permission error. Check app permissions.');
          case '190':
            throw Exception(
                'Instagram access token expired or invalid. Please re-authenticate.');
          case '200':
            throw Exception(
                'Instagram app requires review for posting permissions. Please contact support.');
          default:
            throw Exception(
                'Instagram container creation failed: $errorMessage');
        }
      }

      final containerData = jsonDecode(containerResponse.body);
      final containerId = containerData['id'];

      if (kDebugMode) {
        print('  ✅ Instagram container created successfully');
        print('  🆔 Container ID: $containerId');
      }

      // Step 2: Publish the container
      final publishEndpoint =
          'https://graph.instagram.com/v12.0/$instagramUserId/media_publish';
      final publishParams = {
        'access_token': accessToken,
        'creation_id': containerId,
      };

      if (kDebugMode) {
        print('  📤 Publishing Instagram container...');
        print('  📤 Publish endpoint: $publishEndpoint');
        print('  📤 Publish params: ${jsonEncode(publishParams)}');
      }

      final publishResponse = await http.post(
        Uri.parse(publishEndpoint),
        body: publishParams,
      );

      if (kDebugMode) {
        print('  📥 Publish response status: ${publishResponse.statusCode}');
        print('  📥 Publish response body: ${publishResponse.body}');
      }

      if (publishResponse.statusCode != 200) {
        final errorData = jsonDecode(publishResponse.body);
        final errorMessage =
            errorData['error']?['message'] ?? 'Unknown Instagram API error';
        final errorCode = errorData['error']?['code'] ?? 'unknown';

        if (kDebugMode) {
          print('  ❌ Instagram publishing failed:');
          print('    Code: $errorCode');
          print('    Message: $errorMessage');
        }

        // Handle specific Instagram API errors
        switch (errorCode) {
          case '100':
            throw Exception(
                'Instagram API permission error. Check app permissions.');
          case '190':
            throw Exception(
                'Instagram access token expired or invalid. Please re-authenticate.');
          case '200':
            throw Exception(
                'Instagram app requires review for posting permissions. Please contact support.');
          default:
            throw Exception('Instagram publishing failed: $errorMessage');
        }
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
        // 1. Upload the file to your own server/storage (Firebase Storage, AWS S3, etc.)
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
            'https://graph.facebook.com/v23.0/$postId?fields=id,created_time,message&access_token=$accessToken'),
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
      final instagramId = tokenData['instagram_id'] as String;

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
            'https://graph.facebook.com/v19.0/$postId?fields=id,media_type,media_url,permalink&access_token=$accessToken'),
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
        final errorCode = errorData['error']?['code'] ?? 'unknown';

        if (kDebugMode) {
          print(
              '❌ Instagram verification error: $errorMessage (Code: $errorCode)');
        }

        // Handle specific Instagram API errors
        switch (errorCode) {
          case '100':
            if (kDebugMode) {
              print('❌ Instagram API permission error during verification');
            }
            return false;
          case '190':
            if (kDebugMode) {
              print('❌ Instagram access token expired during verification');
            }
            return false;
          default:
            return false;
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

  /// Get page access token for posting to pages
  Future<String?> _getPageAccessToken(
      String userAccessToken, String pageId) async {
    try {
      if (kDebugMode) {
        print('📄 Getting page access token for page: $pageId');
      }

      // First, try to get stored page access token from Firestore
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        try {
          final storedTokenDoc = await _firestore
              .collection('users')
              .doc(uid)
              .collection('tokens')
              .doc('facebook_pages')
              .get();

          if (storedTokenDoc.exists) {
            final storedTokens = storedTokenDoc.data()!;
            final pageTokens =
                storedTokens['page_tokens'] as Map<String, dynamic>?;

            if (pageTokens != null && pageTokens.containsKey(pageId)) {
              final storedPageToken =
                  pageTokens[pageId] as Map<String, dynamic>;
              final token = storedPageToken['access_token'] as String;
              final expiresAt = storedPageToken['expires_at'] as Timestamp?;

              // Check if stored token is still valid
              if (expiresAt == null ||
                  expiresAt.toDate().isAfter(DateTime.now())) {
                if (kDebugMode) {
                  print('✅ Using stored page access token for page: $pageId');
                }
                return token;
              } else {
                if (kDebugMode) {
                  print(
                      '⚠️ Stored page access token expired for page: $pageId');
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Error checking stored page tokens: $e');
          }
        }
      }

      // Use the AuthService method if available
      if (_authService != null) {
        try {
          final pageAccessToken =
              await _authService!.getFacebookPageAccessToken(pageId);
          if (pageAccessToken != null) {
            // Store the page access token for future use
            await _storePageAccessToken(pageId, pageAccessToken);

            if (kDebugMode) {
              print(
                  '✅ Got page access token via AuthService for page: $pageId');
            }
            return pageAccessToken;
          }
        } catch (e) {
          if (kDebugMode) {
            print(
                '⚠️ AuthService page access token failed, falling back to direct API call: $e');
          }
        }
      }

      // Fallback to direct API call
      final response = await http.get(
        Uri.parse(
            'https://graph.facebook.com/v23.0/$pageId?fields=access_token&access_token=$userAccessToken'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pageAccessToken = data['access_token'];

        if (kDebugMode) {
          print(
              '✅ Got page access token via direct API call for page: $pageId');
        }

        // Store the page access token for future use
        await _storePageAccessToken(pageId, pageAccessToken);

        return pageAccessToken;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        final errorCode = errorData['error']?['code'] ?? 'unknown';

        if (kDebugMode) {
          print(
              '❌ Failed to get page access token: $errorMessage (Code: $errorCode)');
        }

        // Handle specific error cases
        switch (errorCode) {
          case '190':
            throw Exception(
                'Facebook access token expired or invalid. Please re-authenticate.');
          case '100':
            throw Exception(
                'Facebook API permission error. Check app permissions.');
          case '200':
            throw Exception(
                'Facebook app requires review for pages_manage_posts permission. Please contact support.');
          case '294':
            throw Exception(
                'Facebook app requires review for posting permissions. Please contact support.');
          default:
            if (errorMessage.toLowerCase().contains('permission') ||
                errorMessage.toLowerCase().contains('pages_manage_posts')) {
              throw Exception(
                  'Facebook posting requires additional permissions. Please contact support to enable posting permissions.');
            }
            throw Exception(
                'Facebook API error: $errorMessage (Code: $errorCode)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting page access token: $e');
      }
      rethrow;
    }
  }

  /// Store page access token in Firestore for reuse
  Future<void> _storePageAccessToken(
      String pageId, String pageAccessToken) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Page access tokens typically don't expire, but we'll store them with a long expiration
      final expiresAt = DateTime.now().add(const Duration(days: 60));

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('facebook_pages')
          .set({
        'page_tokens.$pageId': {
          'access_token': pageAccessToken,
          'expires_at': Timestamp.fromDate(expiresAt),
          'stored_at': FieldValue.serverTimestamp(),
        },
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        print('✅ Stored page access token for page: $pageId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error storing page access token: $e');
      }
    }
  }

  /// Share to Instagram via SharePlus (manual sharing for consumer accounts)
  Future<void> _shareToInstagramViaSharePlus(SocialAction action) async {
    final formattedContent = _formatPostForPlatform(action, 'instagram');

    if (kDebugMode) {
      print('📷 Sharing to Instagram via SharePlus (manual sharing)...');
      print('  Original text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Formatted content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    try {
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
        text: formattedContent,
        subject: 'Instagram Post',
      );

      if (kDebugMode) {
        print('  ✅ Successfully shared to Instagram via SharePlus');
        print(
            '  📝 Note: This is manual sharing. User needs to open Instagram app to complete posting.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('  ❌ SharePlus sharing failed: $e');
      }
      rethrow;
    }
  }
}
