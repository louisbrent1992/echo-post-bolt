import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/social_action.dart';
import '../services/media_coordinator.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../services/social_post_service.dart';

/// Manages the persistent state and orchestration of social media posts
/// across all screens in the EchoPost application.
class SocialActionPostCoordinator extends ChangeNotifier {
  // Platform requirements constants
  static const _mediaRequiredPlatforms = {'instagram', 'tiktok'};

  // Services - injected via constructor
  final MediaCoordinator _mediaCoordinator;
  final FirestoreService _firestoreService;
  final AIService _aiService;
  final SocialPostService _socialPostService;

  // Current post state
  SocialAction? _currentPost;
  String _currentTranscription = '';
  PostState _postState = PostState.idle;
  List<MediaItem> _preSelectedMedia = [];
  String? _lastError;

  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;

  // Auto-save with debouncing
  Timer? _debounceTimer;
  static const _autoSaveDebounceMs = 1000; // 1 second debounce

  SocialActionPostCoordinator({
    required MediaCoordinator mediaCoordinator,
    required FirestoreService firestoreService,
    required AIService aiService,
    required SocialPostService socialPostService,
  })  : _mediaCoordinator = mediaCoordinator,
        _firestoreService = firestoreService,
        _aiService = aiService,
        _socialPostService = socialPostService {
    if (kDebugMode) {
      print(
          '✅ SocialActionPostCoordinator initialized with constructor injection');
    }
  }

  // Getters
  SocialAction? get currentPost => _currentPost;
  String get currentTranscription => _currentTranscription;
  PostState get postState => _postState;
  List<MediaItem> get preSelectedMedia => List.unmodifiable(_preSelectedMedia);
  String? get lastError => _lastError;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get hasContent => _currentPost?.content.text.isNotEmpty == true;
  bool get hasMedia =>
      _currentPost?.content.media.isNotEmpty == true ||
      _preSelectedMedia.isNotEmpty;
  bool get isPostComplete => hasContent && _isMediaRequirementMet;

  /// Check if media requirement is met based on selected platforms
  bool get _isMediaRequirementMet {
    if (_currentPost == null) return false;

    // If no platforms selected, require media for safety
    if (_currentPost!.platforms.isEmpty) return hasMedia;

    // Check if any selected platform requires media
    final requiresMedia = _currentPost!.platforms.any(
        (platform) => _mediaRequiredPlatforms.contains(platform.toLowerCase()));

    return requiresMedia ? hasMedia : true;
  }

  /// Process voice transcription with flattened, testable pipeline
  Future<void> processVoiceTranscription(String transcription) async {
    _currentTranscription = transcription;
    _postState = PostState.processing;
    _lastError = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        print('🎯 Processing transcription: "$transcription"');
      }

      // Pipeline: each step is a separate, testable method
      final aiPost = await _tryAiGenerate(transcription);
      final mergedPost = _mergeWithExisting(aiPost);
      final mediaPost = await _includeMedia(mergedPost, transcription);
      final finalPost = _sanitizePost(mediaPost);

      _currentPost = finalPost;
      _postState = hasContent ? PostState.ready : PostState.needsContent;
      _triggerDebouncedSave();
      notifyListeners();

      if (kDebugMode) {
        print('✅ Post processing complete');
        print('   Text: "${_currentPost!.content.text}"');
        print('   Hashtags: ${_currentPost!.content.hashtags}');
        print('   Platforms: ${_currentPost!.platforms.join(', ')}');
        print(
            '   Fallback: ${_currentPost!.internal.fallbackReason ?? 'none'}');
      }
    } catch (e) {
      _lastError = e.toString();
      _postState = PostState.error;
      notifyListeners();

      if (kDebugMode) {
        print('❌ Failed to process transcription: $e');
      }
      rethrow;
    }
  }

  /// Step 1: Try AI generation with simplified fallback
  Future<SocialAction> _tryAiGenerate(String transcription) async {
    try {
      return await _aiService.processVoiceCommand(
        transcription,
        preSelectedMedia:
            _preSelectedMedia.isNotEmpty ? _preSelectedMedia : null,
      );
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ AI generation failed, creating baseline post: $e');
      }
      return _createBaselinePost(transcription);
    }
  }

  /// Step 2: Merge with existing post if available
  SocialAction _mergeWithExisting(SocialAction newPost) {
    if (_currentPost == null) return newPost;

    return _currentPost!.copyWith(
      platforms: newPost.platforms.isNotEmpty ? newPost.platforms : null,
      content: _currentPost!.content.copyWith(
        text: newPost.content.text.isNotEmpty ? newPost.content.text : null,
        hashtags: newPost.content.hashtags.isNotEmpty
            ? newPost.content.hashtags
            : null,
        mentions: newPost.content.mentions.isNotEmpty
            ? newPost.content.mentions
            : null,
        media: newPost.content.media.isNotEmpty ? newPost.content.media : null,
      ),
      internal: _currentPost!.internal.copyWith(
        aiGenerated: newPost.internal.aiGenerated,
        originalTranscription: newPost.internal.originalTranscription,
        fallbackReason: newPost.internal.fallbackReason,
      ),
    );
  }

  /// Step 3: Include media intelligently
  Future<SocialAction> _includeMedia(
      SocialAction post, String transcription) async {
    // If post already has media, keep it
    if (post.content.media.isNotEmpty) return post;

    // If we have pre-selected media, use it
    if (_preSelectedMedia.isNotEmpty) {
      return post.copyWith(
        content: post.content.copyWith(media: List.from(_preSelectedMedia)),
      );
    }

    // If user referenced media, try to assign default
    if (_transcriptionReferencesMedia(transcription)) {
      try {
        final recentMedia = await _getRecentMedia(limit: 5);
        if (recentMedia.isNotEmpty) {
          return post.copyWith(
            content: post.content.copyWith(media: [recentMedia.first]),
            internal: post.internal
                .copyWith(fallbackReason: 'default_media_assigned'),
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Failed to get recent media: $e');
        }
      }
    }

    return post;
  }

  /// Step 4: Sanitize and validate post
  SocialAction _sanitizePost(SocialAction post) {
    final actionId = post.actionId.isEmpty
        ? 'sanitized_${DateTime.now().millisecondsSinceEpoch}'
        : post.actionId;

    final sanitizedText =
        post.content.text.replaceAll(RegExp(r'[^\w\s\.,!?@#-]'), '').trim();

    final platforms = post.platforms.isEmpty
        ? _selectDefaultPlatforms(sanitizedText, hasMedia,
            _transcriptionReferencesMedia(post.internal.originalTranscription))
        : post.platforms;

    return post.copyWith(
      actionId: actionId,
      platforms: platforms,
      content: post.content.copyWith(text: sanitizedText),
    );
  }

  /// Create baseline post with intelligent platform selection
  SocialAction _createBaselinePost(String transcription) {
    final hasMedia = _preSelectedMedia.isNotEmpty;
    final hasMediaReference = _transcriptionReferencesMedia(transcription);
    final selectedPlatforms =
        _selectDefaultPlatforms(transcription, hasMedia, hasMediaReference);
    final hashtags = _generateIntelligentHashtags(transcription);

    return SocialAction(
      actionId: 'baseline_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now().toIso8601String(),
      platforms: selectedPlatforms,
      content: Content(
        text: transcription,
        hashtags: hashtags,
        media: hasMedia ? List.from(_preSelectedMedia) : [],
      ),
      options: Options(
        schedule: 'now',
        visibility: _createVisibilityMap(selectedPlatforms),
      ),
      platformData: _createPlatformData(selectedPlatforms),
      internal: Internal(
        aiGenerated: false,
        originalTranscription: transcription,
        fallbackReason: 'baseline_creation',
      ),
    );
  }

  /// Intelligently select default platforms based on content type and media availability
  List<String> _selectDefaultPlatforms(
      String text, bool hasMedia, bool hasMediaReference) {
    final platforms = <String>[];

    // Always include text-supporting platforms for any content
    platforms.addAll(['twitter', 'facebook']);

    // Add media-requiring platforms only if we have media or user referenced media
    if (hasMedia || hasMediaReference) {
      platforms.addAll(['instagram', 'tiktok']);
    }

    if (kDebugMode) {
      print('🎯 Intelligent platform selection:');
      print(
          '   Text: "${text.substring(0, text.length > 50 ? 50 : text.length)}${text.length > 50 ? '...' : ''}"');
      print('   Has media: $hasMedia');
      print('   Has media reference: $hasMediaReference');
      print('   Selected platforms: $platforms');
    }

    return platforms;
  }

  /// Create platform-specific configuration for selected platforms
  Map<String, String> _createVisibilityMap(List<String> platforms) {
    final visibility = <String, String>{};
    for (final platform in platforms) {
      visibility[platform] = 'public';
    }
    return visibility;
  }

  /// Create platform data for selected platforms
  PlatformData _createPlatformData(List<String> platforms) {
    return PlatformData(
      facebook: platforms.contains('facebook')
          ? FacebookData(postHere: true)
          : FacebookData(postHere: false),
      instagram: platforms.contains('instagram')
          ? InstagramData(postHere: true, postType: 'feed')
          : InstagramData(postHere: false, postType: 'feed'),
      twitter: platforms.contains('twitter')
          ? TwitterData(postHere: true)
          : TwitterData(postHere: false),
      tiktok: platforms.contains('tiktok')
          ? TikTokData(postHere: true, sound: Sound())
          : TikTokData(postHere: false, sound: Sound()),
    );
  }

  /// Trigger debounced save - only saves after 1 second of no changes
  void _triggerDebouncedSave() {
    _debounceTimer?.cancel();
    _debounceTimer =
        Timer(const Duration(milliseconds: _autoSaveDebounceMs), () {
      _saveDraft();
    });
  }

  /// Get recent media with performance limit
  Future<List<MediaItem>> _getRecentMedia({int limit = 25}) async {
    try {
      final recentMediaMaps = await _mediaCoordinator.getMediaForQuery(
        '', // Empty search for general recent media
        mediaTypes: ['image', 'video'],
      );

      // Convert to MediaItem objects with limit
      final recentMedia = recentMediaMaps.take(limit).map((mediaMap) {
        return MediaItem(
          fileUri: mediaMap['file_uri'] ?? '',
          mimeType: mediaMap['mime_type'] ?? 'image/jpeg',
          deviceMetadata: DeviceMetadata(
            creationTime:
                mediaMap['timestamp'] ?? DateTime.now().toIso8601String(),
            latitude: mediaMap['device_metadata']?['latitude'],
            longitude: mediaMap['device_metadata']?['longitude'],
            orientation: mediaMap['device_metadata']?['orientation'] ?? 1,
            width: mediaMap['device_metadata']?['width'] ?? 0,
            height: mediaMap['device_metadata']?['height'] ?? 0,
            fileSizeBytes: mediaMap['device_metadata']?['file_size_bytes'] ?? 0,
            duration: mediaMap['device_metadata']?['duration'] ?? 0,
            bitrate: mediaMap['device_metadata']?['bitrate'],
            samplingRate: mediaMap['device_metadata']?['sampling_rate'],
            frameRate: mediaMap['device_metadata']?['frame_rate'],
          ),
        );
      }).toList();

      return recentMedia;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to get recent media: $e');
      }
      return [];
    }
  }

  /// Check if transcription suggests the user wants media included
  bool _transcriptionReferencesMedia(String transcription) {
    final lowerTranscription = transcription.toLowerCase();

    final mediaKeywords = [
      'picture',
      'photo',
      'image',
      'pic',
      'shot',
      'video',
      'clip',
      'recording',
      'last',
      'recent',
      'latest',
      'newest',
      'this picture',
      'this photo',
      'this image',
      'my picture',
      'my photo',
      'my image',
      'the picture',
      'the photo',
      'the image',
    ];

    final hasMediaKeyword =
        mediaKeywords.any((keyword) => lowerTranscription.contains(keyword));

    if (kDebugMode && hasMediaKeyword) {
      final matchedKeywords = mediaKeywords
          .where((keyword) => lowerTranscription.contains(keyword))
          .toList();
      print('🔍 Found media keywords: ${matchedKeywords.join(', ')}');
    }

    return hasMediaKeyword;
  }

  /// Generate intelligent hashtags based on content analysis
  List<String> _generateIntelligentHashtags(String text) {
    final lowerText = text.toLowerCase();
    final hashtags = <String>[];

    // Content-based hashtag mapping
    final hashtagMap = {
      // General engagement
      'photo': ['photography', 'photooftheday', 'picoftheday'],
      'picture': ['photography', 'photooftheday', 'picoftheday'],
      'selfie': ['selfie', 'selfieoftheday', 'me'],
      'video': ['video', 'videooftheday', 'content'],

      // Activities
      'workout': ['fitness', 'workout', 'gym', 'health', 'fitlife'],
      'travel': ['travel', 'wanderlust', 'adventure', 'explore'],
      'food': ['food', 'foodie', 'delicious', 'yummy', 'foodstagram'],
      'coffee': ['coffee', 'coffeetime', 'caffeine', 'morningfuel'],
      'sunset': ['sunset', 'nature', 'sky', 'beautiful', 'golden'],
      'beach': ['beach', 'ocean', 'waves', 'paradise', 'summer'],
      'work': ['work', 'productivity', 'hustle', 'grind', 'business'],
      'art': ['art', 'creative', 'artist', 'artwork', 'design'],
      'music': ['music', 'song', 'musician', 'melody', 'sound'],

      // Emotions/Moods
      'happy': ['happy', 'joy', 'smile', 'positive', 'good'],
      'excited': ['excited', 'thrilled', 'pumped', 'energy'],
      'grateful': ['grateful', 'blessed', 'thankful', 'appreciation'],
      'motivated': ['motivation', 'inspiration', 'goals', 'success'],

      // Time-based
      'monday': ['mondaymotivation', 'newweek', 'fresh'],
      'friday': ['friday', 'weekend', 'tgif'],
      'morning': ['morning', 'sunrise', 'newday', 'fresh'],
      'night': ['night', 'evening', 'nighttime'],
    };

    // Find matching hashtags
    for (final keyword in hashtagMap.keys) {
      if (lowerText.contains(keyword)) {
        hashtags.addAll(hashtagMap[keyword]!);
        if (hashtags.length >= 6) break; // Limit to prevent overflow
      }
    }

    // Add default hashtags if none found
    if (hashtags.isEmpty) {
      hashtags.addAll(['life', 'daily', 'moments', 'share']);
    }

    // Ensure we have 3-6 hashtags
    final uniqueHashtags = hashtags.toSet().take(6).toList();

    // Add generic hashtags if we have less than 3
    if (uniqueHashtags.length < 3) {
      final genericHashtags = [
        'instagood',
        'photooftheday',
        'love',
        'beautiful',
        'amazing'
      ];
      for (final generic in genericHashtags) {
        if (!uniqueHashtags.contains(generic)) {
          uniqueHashtags.add(generic);
          if (uniqueHashtags.length >= 3) break;
        }
      }
    }

    if (kDebugMode) {
      print('🔖 Generated intelligent hashtags: $uniqueHashtags');
    }

    return uniqueHashtags;
  }

  /// Extract hashtags from text content (spoken hashtags)
  List<String> _extractHashtagsFromText(String text) {
    // Match hashtags in the format #hashtag or #HashTag
    final hashtagRegex = RegExp(r'#([a-zA-Z0-9_]+)', multiLine: true);
    final matches = hashtagRegex.allMatches(text);

    final extractedHashtags = matches
        .map((match) => match.group(1)!)
        .where((hashtag) => hashtag.isNotEmpty)
        .map((hashtag) => hashtag.toLowerCase()) // Normalize to lowercase
        .toSet() // Remove duplicates
        .toList();

    if (kDebugMode && extractedHashtags.isNotEmpty) {
      print('🏷️ Extracted hashtags from text: $extractedHashtags');
    }

    return extractedHashtags;
  }

  /// Remove hashtags from text content (clean text for display)
  String _removeHashtagsFromText(String text) {
    // Remove hashtags in the format #hashtag or #HashTag
    final hashtagRegex = RegExp(r'#[a-zA-Z0-9_]+\s*', multiLine: true);
    final cleanText = text.replaceAll(hashtagRegex, '').trim();

    // Clean up extra whitespace
    return cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Format hashtags for specific platform requirements
  String _formatHashtagsForPlatform(List<String> hashtags, String platform) {
    if (hashtags.isEmpty) return '';

    switch (platform.toLowerCase()) {
      case 'instagram':
        // Instagram: hashtags at the end, separated by spaces, max 30 hashtags
        final limitedHashtags = hashtags.take(30).toList();
        return '\n\n${limitedHashtags.map((tag) => '#$tag').join(' ')}';

      case 'twitter':
        // Twitter: hashtags integrated naturally, max 280 chars total, 2-3 hashtags recommended
        final limitedHashtags = hashtags.take(3).toList();
        return ' ${limitedHashtags.map((tag) => '#$tag').join(' ')}';

      case 'facebook':
        // Facebook: hashtags at the end, each on new line for better readability
        return '\n\n${hashtags.map((tag) => '#$tag').join(' ')}';

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
        return '\n\n$formattedHashtags';

      default:
        // Default format: hashtags at the end, space-separated
        return '\n\n${hashtags.map((tag) => '#$tag').join(' ')}';
    }
  }

  /// Get platform-formatted post content with hashtags
  String getFormattedPostContent(String platform) {
    if (_currentPost == null) return '';

    final baseText = _currentPost!.content.text;
    final hashtags = _currentPost!.content.hashtags;

    // Remove any existing hashtags from the base text to avoid duplication
    final cleanText = _removeHashtagsFromText(baseText);

    // Add platform-specific hashtag formatting
    final formattedHashtags = _formatHashtagsForPlatform(hashtags, platform);

    return '$cleanText$formattedHashtags'.trim();
  }

  /// Update post content with unified hashtag handling
  Future<void> updatePostContent(String newText) async {
    if (kDebugMode) {
      print('🔄 Updating post content with unified hashtag handling');
      print('   New text: "$newText"');
    }

    // Extract hashtags from the new text
    final extractedHashtags = _extractHashtagsFromText(newText);

    // Remove hashtags from text to keep them separate
    final cleanText = _removeHashtagsFromText(newText);

    if (_currentPost == null) {
      // Create new post with the text and extracted hashtags
      final intelligentHashtags = _generateIntelligentHashtags(cleanText);
      final allHashtags =
          <String>{...extractedHashtags, ...intelligentHashtags}.toList();

      _currentPost = _createBaselinePost(cleanText).copyWith(
        content: Content(
          text: cleanText,
          hashtags: allHashtags,
          mentions: [],
          media: [],
        ),
      );
    } else {
      // Update existing post - merge extracted hashtags with existing ones
      final existingHashtags = Set<String>.from(_currentPost!.content.hashtags);
      final newHashtags =
          <String>{...existingHashtags, ...extractedHashtags}.toList();

      _currentPost = _currentPost!.copyWith(
        content: _currentPost!.content.copyWith(
          text: cleanText,
          hashtags: newHashtags,
        ),
      );
    }

    _postState = hasContent ? PostState.ready : PostState.needsContent;
    _triggerDebouncedSave();
    notifyListeners();

    if (kDebugMode) {
      print('✅ Post content updated with unified hashtag handling');
      print('   Clean text: "$cleanText"');
      print('   Extracted hashtags: $extractedHashtags');
      print('   Final hashtags: ${_currentPost!.content.hashtags}');
    }
  }

  /// Update post hashtags independently
  Future<void> updatePostHashtags(List<String> newHashtags) async {
    if (_currentPost == null) {
      // Create new post with hashtags only
      _currentPost = _createBaselinePost('').copyWith(
        content: Content(
          text: '',
          hashtags: newHashtags,
          mentions: [],
          media: [],
        ),
      );
    } else {
      // Update existing post hashtags
      _currentPost = _currentPost!.copyWith(
        content: _currentPost!.content.copyWith(hashtags: newHashtags),
      );
    }

    _postState = hasContent ? PostState.ready : PostState.needsContent;
    _triggerDebouncedSave();
    notifyListeners();

    if (kDebugMode) {
      print('✅ Hashtags updated via coordinator');
      print('   New hashtags: $newHashtags');
      print('   Total hashtags: ${newHashtags.length}');
    }
  }

  /// Add media to current post
  Future<void> addMedia(List<MediaItem> media) async {
    _preSelectedMedia.addAll(media);

    if (_currentPost != null) {
      final updatedMedia = List<MediaItem>.from(_currentPost!.content.media);
      updatedMedia.addAll(media);

      _currentPost = _currentPost!.copyWith(
        content: _currentPost!.content.copyWith(media: updatedMedia),
      );
    }

    _postState = isPostComplete ? PostState.ready : PostState.needsMedia;
    _triggerDebouncedSave();
    notifyListeners();
  }

  /// Toggle platform selection
  void togglePlatform(String platform) {
    if (_currentPost == null) return;

    final updatedPlatforms = List<String>.from(_currentPost!.platforms);
    if (updatedPlatforms.contains(platform)) {
      updatedPlatforms.remove(platform);
    } else {
      updatedPlatforms.add(platform);
    }

    _currentPost = _currentPost!.copyWith(platforms: updatedPlatforms);
    notifyListeners();
  }

  /// Set recording state
  void setRecordingState(bool recording) {
    _isRecording = recording;
    if (recording) {
      _postState = PostState.recording;
    } else if (_postState == PostState.recording) {
      _postState = PostState.idle;
    }
    notifyListeners();
  }

  /// Set processing state with proper cleanup
  void setProcessingState(bool processing) {
    if (kDebugMode) {
      print('🔧 SocialActionPostCoordinator.setProcessingState($processing)');
      print('   Current _isProcessing: $_isProcessing');
      print('   Current _postState: $_postState');
    }

    _isProcessing = processing;
    if (processing) {
      _postState = PostState.processing;
    } else {
      // When processing is done, determine the appropriate state
      if (_currentPost != null && hasContent) {
        _postState = PostState.ready;
      } else {
        _postState = PostState.idle;
      }
    }

    if (kDebugMode) {
      print('   New _isProcessing: $_isProcessing');
      print('   New _postState: $_postState');
      print('   hasContent: $hasContent');
      print('   currentPost != null: ${_currentPost != null}');
    }

    notifyListeners();
  }

  /// Reset to initial state with proper cleanup
  void reset() {
    _currentPost = null;
    _currentTranscription = '';
    _postState = PostState.idle;
    _preSelectedMedia.clear();
    _lastError = null;
    _isRecording = false;
    _isProcessing = false;
    notifyListeners();

    if (kDebugMode) {
      print('🔄 SocialActionPostCoordinator: Complete state reset');
    }
  }

  /// Save draft to persistent storage
  Future<void> _saveDraft() async {
    if (_currentPost == null) return;

    try {
      // Only auto-save if this is still a draft
      final isDraft = _currentPost!.actionId.startsWith('baseline_') ||
          _currentPost!.actionId.startsWith('sanitized_') ||
          _currentPost!.actionId.startsWith('echo_');

      if (isDraft) {
        await _firestoreService.saveAction(_currentPost!.toJson());
        if (kDebugMode) {
          print('💾 Draft auto-saved: ${_currentPost!.actionId}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to save draft: $e');
      }
    }
  }

  /// Replace media in current post
  Future<void> replaceMedia(List<MediaItem> media) async {
    if (_currentPost != null) {
      _currentPost = _currentPost!.copyWith(
        content: _currentPost!.content.copyWith(media: media),
      );

      _postState = isPostComplete ? PostState.ready : PostState.needsMedia;
      _triggerDebouncedSave();
      notifyListeners();

      if (kDebugMode) {
        print('✅ Media replaced: ${media.length} items');
      }
    } else {
      // If no current post, treat as pre-selected media
      _preSelectedMedia.clear();
      _preSelectedMedia.addAll(media);
      notifyListeners();

      if (kDebugMode) {
        print(
            '✅ Pre-selected media updated: ${_preSelectedMedia.length} items');
      }
    }
  }

  /// Synchronize coordinator with an existing post
  void syncWithExistingPost(SocialAction existingPost) {
    _currentPost = existingPost;
    _currentTranscription = existingPost.internal.originalTranscription;
    _postState = hasContent ? PostState.ready : PostState.needsContent;
    _lastError = null;

    // Clear pre-selected media since we now have a complete post
    if (existingPost.content.media.isNotEmpty) {
      _preSelectedMedia.clear();
    }

    notifyListeners();

    if (kDebugMode) {
      print(
          '🔄 Coordinator synced with existing post: ${existingPost.actionId}');
    }
  }

  /// Update post schedule through coordinator
  Future<void> updatePostSchedule(String newSchedule) async {
    if (_currentPost == null) return;

    _currentPost = _currentPost!.copyWith(
      options: Options(
        schedule: newSchedule,
        locationTag: _currentPost!.options.locationTag,
        visibility: _currentPost!.options.visibility,
        replyToPostId: _currentPost!.options.replyToPostId,
      ),
    );

    _triggerDebouncedSave();
    notifyListeners();

    if (kDebugMode) {
      print('✅ Schedule updated via coordinator: $newSchedule');
    }
  }

  /// Upload finalized post to Firestore
  Future<void> uploadFinalizedPost() async {
    if (_currentPost == null) {
      throw Exception('No post to upload');
    }

    try {
      await _firestoreService.saveAction(_currentPost!.toJson());

      if (kDebugMode) {
        print('✅ Finalized post uploaded: ${_currentPost!.actionId}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to upload finalized post: $e');
      }
      rethrow;
    }
  }

  /// Execute post across all selected social media platforms
  Future<Map<String, bool>> executePostToSocialMedia() async {
    if (_currentPost == null) {
      throw Exception('No post to execute');
    }

    try {
      if (kDebugMode) {
        print(
            '🚀 Executing post across platforms: ${_currentPost!.platforms.join(', ')}');
      }

      final results =
          await _socialPostService.postToAllPlatforms(_currentPost!);

      if (kDebugMode) {
        print('✅ Social media posting completed');
        for (final entry in results.entries) {
          print('   ${entry.key}: ${entry.value ? 'Success' : 'Failed'}');
        }
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to execute post: $e');
      }
      rethrow;
    }
  }

  /// Complete post workflow: Upload to Firestore + Execute on social media
  Future<Map<String, bool>> finalizeAndExecutePost() async {
    if (_currentPost == null) {
      throw Exception('No post to finalize and execute');
    }

    try {
      if (kDebugMode) {
        print('🎯 Finalizing and executing post: ${_currentPost!.actionId}');
      }

      // Step 1: Upload finalized post to Firestore
      await uploadFinalizedPost();

      // Step 2: Execute post across social media platforms
      final executionResults = await executePostToSocialMedia();

      // Step 3: Clean up coordinator state after successful posting
      final allSucceeded = executionResults.values.every((success) => success);
      if (allSucceeded) {
        reset();
        if (kDebugMode) {
          print('🔄 Coordinator state reset after successful posting');
        }
      }

      return executionResults;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to finalize and execute post: $e');
      }
      rethrow;
    }
  }

  /// Check if post is ready for execution
  bool get isReadyForExecution {
    if (_currentPost == null) return false;

    final hasContent = _currentPost!.content.text.isNotEmpty;
    final hasPlatforms = _currentPost!.platforms.isNotEmpty;

    return hasContent && hasPlatforms && _isMediaRequirementMet;
  }

  /// Get execution readiness status with detailed feedback
  PostExecutionReadiness get executionReadiness {
    if (_currentPost == null) {
      return PostExecutionReadiness(
        isReady: false,
        missingRequirements: ['No post content'],
      );
    }

    final missingRequirements = <String>[];

    if (_currentPost!.content.text.isEmpty) {
      missingRequirements.add('Post text is empty');
    }

    if (_currentPost!.platforms.isEmpty) {
      missingRequirements.add('No platforms selected');
    }

    // Check platform-specific media requirements
    if (!_isMediaRequirementMet) {
      final requiresMediaPlatforms = _currentPost!.platforms
          .where((platform) =>
              _mediaRequiredPlatforms.contains(platform.toLowerCase()))
          .toList();

      if (requiresMediaPlatforms.isNotEmpty) {
        missingRequirements
            .add('Media required for ${requiresMediaPlatforms.join(', ')}');
      }
    }

    return PostExecutionReadiness(
      isReady: missingRequirements.isEmpty,
      missingRequirements: missingRequirements,
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Represents the current state of the post creation process
enum PostState {
  idle,
  recording,
  processing,
  ready,
  needsContent,
  needsMedia,
  error,
}

/// Represents the readiness status for post execution
class PostExecutionReadiness {
  final bool isReady;
  final List<String> missingRequirements;

  const PostExecutionReadiness({
    required this.isReady,
    required this.missingRequirements,
  });

  @override
  String toString() {
    if (isReady) {
      return 'Ready for execution';
    } else {
      return 'Not ready: ${missingRequirements.join(', ')}';
    }
  }
}
