import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import '../models/social_action.dart';

/// Handles manual sharing via native dialogs
/// Extracted from SocialPostService to separate automated vs manual posting
class ManualShareService {
  static final ManualShareService _instance = ManualShareService._internal();
  factory ManualShareService() => _instance;
  ManualShareService._internal();

  /// Share content to multiple platforms using native dialogs
  Future<void> shareToPlatforms({
    required List<String> platforms,
    required SocialAction action,
  }) async {
    if (kDebugMode) {
      print('📤 ManualShareService: Sharing to ${platforms.join(', ')}');
    }

    for (final platform in platforms) {
      try {
        await _shareToPlatform(action, platform);
      } catch (e) {
        if (kDebugMode) {
          print('❌ ManualShareService: Failed to share to $platform: $e');
        }
        rethrow;
      }
    }
  }

  /// Share to a single platform using native dialog
  Future<void> _shareToPlatform(SocialAction action, String platform) async {
    final formattedContent = _formatContentForPlatform(action, platform);

    if (kDebugMode) {
      print('📤 ManualShareService: Sharing to $platform');
      print('  Content: $formattedContent');
      print('  Media count: ${action.content.media.length}');
    }

    try {
      switch (platform.toLowerCase()) {
        case 'facebook':
          await _shareToFacebook(action, formattedContent);
          break;
        case 'instagram':
          await _shareToInstagram(action, formattedContent);
          break;
        case 'youtube':
          await _shareToYouTube(action, formattedContent);
          break;
        case 'twitter':
          await _shareToTwitter(action, formattedContent);
          break;
        case 'tiktok':
          await _shareToTikTok(action, formattedContent);
          break;
        case 'other':
          await _shareToOther(action, formattedContent);
          break;
        default:
          throw Exception('Unsupported platform for manual sharing: $platform');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ ManualShareService: Error sharing to $platform: $e');
      }
      rethrow;
    }
  }

  /// Format content for specific platform
  String _formatContentForPlatform(SocialAction action, String platform) {
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

  /// Share to Facebook via native dialog
  Future<void> _shareToFacebook(SocialAction action, String text) async {
    if (action.content.media.isNotEmpty) {
      // Share with media
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
  }

  /// Share to Instagram via native dialog
  Future<void> _shareToInstagram(SocialAction action, String text) async {
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
      text: text,
      subject: 'Instagram Post',
    );
  }

  /// Share to YouTube via native dialog
  Future<void> _shareToYouTube(SocialAction action, String text) async {
    if (action.content.media.isNotEmpty) {
      // Share with media
      final media = action.content.media.first;
      final fileUri = media.fileUri;
      if (fileUri.startsWith('file://')) {
        final filePath = fileUri.replaceFirst('file://', '');
        await Share.shareXFiles([XFile(filePath)], text: text);
      } else {
        await Share.share(text);
      }
    } else {
      await Share.share(text);
    }
  }

  /// Share to Twitter via native dialog
  Future<void> _shareToTwitter(SocialAction action, String text) async {
    if (action.content.media.isNotEmpty) {
      // Share with media
      final media = action.content.media.first;
      final fileUri = media.fileUri;
      if (fileUri.startsWith('file://')) {
        final filePath = fileUri.replaceFirst('file://', '');
        await Share.shareXFiles([XFile(filePath)], text: text);
      } else {
        await Share.share(text);
      }
    } else {
      await Share.share(text);
    }
  }

  /// Share to TikTok via native dialog
  Future<void> _shareToTikTok(SocialAction action, String text) async {
    if (action.content.media.isNotEmpty) {
      // Share with media
      final media = action.content.media.first;
      final fileUri = media.fileUri;
      if (fileUri.startsWith('file://')) {
        final filePath = fileUri.replaceFirst('file://', '');
        await Share.shareXFiles([XFile(filePath)], text: text);
      } else {
        await Share.share(text);
      }
    } else {
      await Share.share(text);
    }
  }

  /// Share to "other" platform using native dialog
  Future<void> _shareToOther(SocialAction action, String text) async {
    if (action.content.media.isNotEmpty) {
      // Share with media
      final media = action.content.media.first;
      final fileUri = media.fileUri;
      if (fileUri.startsWith('file://')) {
        final filePath = fileUri.replaceFirst('file://', '');
        await Share.shareXFiles([XFile(filePath)], text: text);
      } else {
        await Share.share(text);
      }
    } else {
      await Share.share(text);
    }
  }
}
