import 'dart:convert';
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
///
/// This coordinator ensures:
/// - Consistent post state management across command, media selection, and review screens
/// - Robust JSON parsing with multiple fallback strategies
/// - Reliable baseline experience even when AI services fail
/// - Persistent storage and recovery of post drafts
/// - Consistent recording behavior across all screens
class SocialActionPostCoordinator extends ChangeNotifier {
  // Services
  MediaCoordinator? _mediaCoordinator;
  FirestoreService? _firestoreService;
  AIService? _aiService;
  SocialPostService? _socialPostService;

  // Current post state
  SocialAction? _currentPost;
  String _currentTranscription = '';
  PostState _postState = PostState.idle;
  List<MediaItem> _preSelectedMedia = [];
  String? _lastError;

  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  Timer? _autoSaveTimer;

  // Initialization
  bool _isInitialized = false;

  SocialActionPostCoordinator();

  // Getters
  SocialAction? get currentPost => _currentPost;
  String get currentTranscription => _currentTranscription;
  PostState get postState => _postState;
  List<MediaItem> get preSelectedMedia => List.unmodifiable(_preSelectedMedia);
  String? get lastError => _lastError;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get isInitialized => _isInitialized;
  bool get hasContent => _currentPost?.content.text.isNotEmpty == true;
  bool get hasMedia =>
      _currentPost?.content.media.isNotEmpty == true ||
      _preSelectedMedia.isNotEmpty;
  bool get isPostComplete => hasContent && hasMedia;

  /// Initialize the coordinator with required services
  Future<void> initialize({
    required MediaCoordinator mediaCoordinator,
    required FirestoreService firestoreService,
    required AIService aiService,
    required SocialPostService socialPostService,
  }) async {
    if (_isInitialized) return;

    _mediaCoordinator = mediaCoordinator;
    _firestoreService = firestoreService;
    _aiService = aiService;
    _socialPostService = socialPostService;

    // Set up auto-save timer for draft persistence
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _autoSaveDraft();
    });

    _isInitialized = true;

    if (kDebugMode) {
      print('✅ SocialActionPostCoordinator initialized');
    }
  }

  /// Process voice transcription with robust error handling and fallbacks
  Future<void> processVoiceTranscription(String transcription) async {
    if (!_isInitialized) {
      throw StateError('SocialActionPostCoordinator not initialized');
    }

    _currentTranscription = transcription;
    _postState = PostState.processing;
    _lastError = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        print(
            '🎯 SocialActionPostCoordinator: Processing transcription: "$transcription"');
      }

      // Attempt AI processing with intelligent fallback handling
      SocialAction? aiGeneratedPost;
      Map<String, dynamic>? partialChatGptData;

      try {
        aiGeneratedPost = await _aiService!.processVoiceCommand(
          transcription,
          preSelectedMedia:
              _preSelectedMedia.isNotEmpty ? _preSelectedMedia : null,
        );

        if (kDebugMode) {
          print('✅ ChatGPT generated complete post');
          print('   Enhanced text: "${aiGeneratedPost.content.text}"');
          print('   Hashtags: ${aiGeneratedPost.content.hashtags}');
          print(
              '   Fallback used: ${aiGeneratedPost.internal.fallbackReason ?? 'none'}');
        }
      } catch (aiError) {
        if (kDebugMode) {
          print('⚠️ AI service failed: $aiError');
        }

        // Try to extract partial data from the error if it contains JSON fragments
        partialChatGptData = _extractPartialJsonData(aiError.toString());

        if (partialChatGptData != null) {
          if (kDebugMode) {
            print('🔧 Extracted partial ChatGPT data:');
            print('   Text: ${partialChatGptData['content']?['text']}');
            print('   Hashtags: ${partialChatGptData['content']?['hashtags']}');
          }
        }

        if (kDebugMode) {
          print('🔄 Creating enhanced baseline post with ChatGPT fragments...');
        }

        // Create enhanced baseline post with any recovered ChatGPT data
        aiGeneratedPost =
            _createEnhancedBaselinePost(transcription, partialChatGptData);
      }

      // Merge with existing state if we have one
      if (_currentPost != null) {
        aiGeneratedPost =
            _mergeWithExistingPost(aiGeneratedPost, _currentPost!);
      }

      // CRITICAL: Ensure media is included with intelligent defaults
      aiGeneratedPost =
          await _ensureMediaInclusion(aiGeneratedPost, transcription);

      // Validate and sanitize the post
      aiGeneratedPost = _validateAndSanitizePost(aiGeneratedPost);

      _currentPost = aiGeneratedPost;
      _postState = hasContent ? PostState.ready : PostState.needsContent;

      // Auto-save the draft
      await _saveDraft();

      notifyListeners();

      if (kDebugMode) {
        print('✅ Post processing complete');
        print('   Final text: "${_currentPost!.content.text}"');
        print('   Final hashtags: ${_currentPost!.content.hashtags}');
        print('   Media count: ${_currentPost!.content.media.length}');
        print('   Platforms: ${_currentPost!.platforms.join(', ')}');
        print(
            '   Fallback reason: ${_currentPost!.internal.fallbackReason ?? 'none'}');
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

  /// Extract partial JSON data from error messages or incomplete responses
  Map<String, dynamic>? _extractPartialJsonData(String errorOrResponse) {
    try {
      // Look for JSON-like structures in the error/response
      final jsonStart = errorOrResponse.indexOf('{');
      final jsonEnd = errorOrResponse.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
        final jsonCandidate = errorOrResponse.substring(jsonStart, jsonEnd + 1);

        // Try to parse the candidate JSON
        final parsedData = robustJsonParse(jsonCandidate);

        // Validate that it has useful content
        if (parsedData.containsKey('content')) {
          return parsedData;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('🔧 Could not extract partial JSON data: $e');
      }
      return null;
    }
  }

  /// Create an enhanced baseline post that incorporates any partial ChatGPT data
  SocialAction _createEnhancedBaselinePost(
      String transcription, Map<String, dynamic>? partialData) {
    final timestamp = DateTime.now().toIso8601String();
    final actionId =
        'enhanced_baseline_${DateTime.now().millisecondsSinceEpoch}';

    // Extract enhanced content from partial ChatGPT data if available
    String enhancedText = transcription;
    List<String> enhancedHashtags = [];
    List<String> enhancedMentions = [];
    String fallbackReason = 'enhanced_baseline_creation';

    if (partialData != null && partialData.containsKey('content')) {
      final contentData = partialData['content'] as Map<String, dynamic>?;

      if (contentData != null) {
        // Use ChatGPT's enhanced text if available
        if (contentData.containsKey('text') && contentData['text'] is String) {
          final chatGptText = contentData['text'] as String;
          if (chatGptText.trim().isNotEmpty && chatGptText != transcription) {
            enhancedText = chatGptText;
            fallbackReason = 'partial_chatgpt_with_enhanced_text';

            if (kDebugMode) {
              print('✅ Preserved ChatGPT enhanced text: "$enhancedText"');
            }
          }
        }

        // Use ChatGPT's hashtags if available
        if (contentData.containsKey('hashtags') &&
            contentData['hashtags'] is List) {
          final chatGptHashtags = (contentData['hashtags'] as List)
              .map((h) => h.toString().replaceAll('#', '').trim())
              .where((h) => h.isNotEmpty)
              .toList();

          if (chatGptHashtags.isNotEmpty) {
            enhancedHashtags = chatGptHashtags;
            fallbackReason = 'partial_chatgpt_with_hashtags';

            if (kDebugMode) {
              print('✅ Preserved ChatGPT hashtags: $enhancedHashtags');
            }
          }
        }

        // Use ChatGPT's mentions if available
        if (contentData.containsKey('mentions') &&
            contentData['mentions'] is List) {
          enhancedMentions = (contentData['mentions'] as List)
              .map((m) => m.toString().trim())
              .where((m) => m.isNotEmpty)
              .toList();
        }
      }
    }

    // If no hashtags from ChatGPT, generate intelligent defaults
    if (enhancedHashtags.isEmpty) {
      enhancedHashtags = _generateIntelligentHashtags(enhancedText);
      if (fallbackReason == 'enhanced_baseline_creation') {
        fallbackReason = 'baseline_with_generated_hashtags';
      }
    }

    // If no mentions from ChatGPT, extract from text
    if (enhancedMentions.isEmpty) {
      enhancedMentions = _extractMentionsFromText(enhancedText);
    }

    return SocialAction(
      actionId: actionId,
      createdAt: timestamp,
      platforms: ['instagram', 'twitter', 'facebook', 'tiktok'],
      content: Content(
        text: enhancedText,
        hashtags: enhancedHashtags,
        mentions: enhancedMentions,
        media: _preSelectedMedia.isNotEmpty ? List.from(_preSelectedMedia) : [],
      ),
      options: Options(
        schedule: 'now',
        visibility: {
          'instagram': 'public',
          'twitter': 'public',
          'facebook': 'public',
          'tiktok': 'public',
        },
      ),
      platformData: PlatformData(
        facebook: FacebookData(postHere: false),
        instagram: InstagramData(postHere: true, postType: 'feed'),
        twitter: TwitterData(postHere: true),
        tiktok: TikTokData(postHere: false, sound: Sound()),
      ),
      internal: Internal(
        aiGenerated: partialData != null, // True if we had some ChatGPT data
        originalTranscription: transcription,
        fallbackReason: fallbackReason,
      ),
    );
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

  /// Robust JSON parsing with multiple repair strategies
  Map<String, dynamic> robustJsonParse(String jsonString) {
    // Strategy 1: Direct parsing
    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('🔧 JSON parse failed, attempting repair...');
      }
    }

    // Strategy 2: Use the existing repairJson function
    try {
      final repairedJson = _aiService?.repairJson(jsonString) ?? jsonString;
      return json.decode(repairedJson) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('🔧 JSON repair failed, attempting advanced repair...');
      }
    }

    // Strategy 3: Advanced repair with type-safe defaults
    try {
      return _advancedJsonRepair(jsonString);
    } catch (e) {
      if (kDebugMode) {
        print('❌ All JSON repair strategies failed: $e');
      }

      // Strategy 4: Return minimal valid structure
      return _createMinimalValidJson();
    }
  }

  /// Advanced JSON repair with intelligent type inference
  Map<String, dynamic> _advancedJsonRepair(String brokenJson) {
    String repaired = brokenJson.trim();

    // Find JSON boundaries
    int start = repaired.indexOf('{');
    if (start == -1) {
      throw Exception('No JSON object found');
    }

    // Extract the JSON portion
    repaired = repaired.substring(start);

    // Fix common truncation issues
    if (!repaired.endsWith('}')) {
      // Count open braces and brackets
      int openBraces = 0;
      int openBrackets = 0;
      bool inString = false;

      for (int i = 0; i < repaired.length; i++) {
        final char = repaired[i];

        if (char == '"' && (i == 0 || repaired[i - 1] != '\\')) {
          inString = !inString;
        }

        if (!inString) {
          if (char == '{')
            openBraces++;
          else if (char == '}')
            openBraces--;
          else if (char == '[')
            openBrackets++;
          else if (char == ']') openBrackets--;
        }
      }

      // Close open structures
      for (int i = 0; i < openBrackets; i++) {
        repaired += ']';
      }
      for (int i = 0; i < openBraces; i++) {
        repaired += '}';
      }
    }

    // Fix trailing commas
    repaired = repaired.replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (match) => match.group(1)!,
    );

    // Fix incomplete key-value pairs
    repaired = repaired.replaceAllMapped(
      RegExp(r'"([^"]+)":\s*([,}\]])'),
      (match) {
        final key = match.group(1)!;
        final terminator = match.group(2)!;

        // Intelligent default based on key name
        if (key.contains('text') || key.contains('transcription')) {
          return '"$key": ""$terminator';
        } else if (key.contains('platforms') ||
            key.contains('hashtags') ||
            key.contains('mentions')) {
          return '"$key": []$terminator';
        } else if (key.contains('media')) {
          return '"$key": []$terminator';
        } else if (key.contains('time') || key.contains('date')) {
          return '"$key": "${DateTime.now().toIso8601String()}"$terminator';
        } else if (key.contains('id')) {
          return '"$key": "generated_${DateTime.now().millisecondsSinceEpoch}"$terminator';
        } else {
          return '"$key": null$terminator';
        }
      },
    );

    try {
      return json.decode(repaired) as Map<String, dynamic>;
    } catch (e) {
      // If all else fails, merge with a template
      return _mergeWithTemplate(repaired);
    }
  }

  /// Create minimal valid JSON structure
  Map<String, dynamic> _createMinimalValidJson() {
    return {
      'action_id': 'fallback_${DateTime.now().millisecondsSinceEpoch}',
      'created_at': DateTime.now().toIso8601String(),
      'platforms': ['instagram', 'twitter'],
      'content': {
        'text': _currentTranscription,
        'hashtags': [],
        'mentions': [],
        'media': [],
      },
      'options': {
        'schedule': 'now',
        'visibility': {
          'instagram': 'public',
          'twitter': 'public',
        },
      },
      'platform_data': {
        'instagram': {'post_here': true},
        'twitter': {'post_here': true},
      },
      'internal': {
        'ai_generated': false,
        'original_transcription': _currentTranscription,
        'fallback_reason': 'minimal_json_creation',
      },
    };
  }

  /// Merge partial JSON with complete template
  Map<String, dynamic> _mergeWithTemplate(String partialJson) {
    final template = _createMinimalValidJson();

    try {
      // Try to extract any valid parts from the partial JSON
      final matches = RegExp(r'"([^"]+)":\s*"([^"]*)"').allMatches(partialJson);
      for (final match in matches) {
        final key = match.group(1)!;
        final value = match.group(2)!;

        if (key == 'text' && value.isNotEmpty) {
          template['content']['text'] = value;
        }
      }

      // Extract arrays
      final arrayMatches =
          RegExp(r'"([^"]+)":\s*\[([^\]]*)\]').allMatches(partialJson);
      for (final match in arrayMatches) {
        final key = match.group(1)!;
        final arrayContent = match.group(2)!;

        if (key == 'platforms' && arrayContent.isNotEmpty) {
          final platforms = arrayContent
              .split(',')
              .map((s) => s.trim().replaceAll('"', ''))
              .where((s) => s.isNotEmpty)
              .toList();
          if (platforms.isNotEmpty) {
            template['platforms'] = platforms;
          }
        }
      }
    } catch (e) {
      // Use template as-is
    }

    return template;
  }

  /// Update post content (text editing)
  Future<void> updatePostContent(String newText) async {
    if (_currentPost == null) {
      // Create new post with the text
      _currentPost = _createEnhancedBaselinePost(newText, null);
    } else {
      // Update existing post
      _currentPost = SocialAction(
        actionId: _currentPost!.actionId,
        createdAt: _currentPost!.createdAt,
        platforms: _currentPost!.platforms,
        content: Content(
          text: newText,
          hashtags: _currentPost!.content.hashtags,
          mentions: _currentPost!.content.mentions,
          link: _currentPost!.content.link,
          media: _currentPost!.content.media,
        ),
        options: _currentPost!.options,
        platformData: _currentPost!.platformData,
        internal: _currentPost!.internal,
        mediaQuery: _currentPost!.mediaQuery,
      );
    }

    _postState = hasContent ? PostState.ready : PostState.needsContent;
    await _saveDraft();
    notifyListeners();
  }

  /// Add media to current post
  Future<void> addMedia(List<MediaItem> media) async {
    _preSelectedMedia.addAll(media);

    if (_currentPost != null) {
      final updatedMedia = List<MediaItem>.from(_currentPost!.content.media);
      updatedMedia.addAll(media);

      _currentPost = SocialAction(
        actionId: _currentPost!.actionId,
        createdAt: _currentPost!.createdAt,
        platforms: _currentPost!.platforms,
        content: Content(
          text: _currentPost!.content.text,
          hashtags: _currentPost!.content.hashtags,
          mentions: _currentPost!.content.mentions,
          link: _currentPost!.content.link,
          media: updatedMedia,
        ),
        options: _currentPost!.options,
        platformData: _currentPost!.platformData,
        internal: _currentPost!.internal,
        mediaQuery: _currentPost!.mediaQuery,
      );
    }

    _postState = isPostComplete ? PostState.ready : PostState.needsMedia;
    await _saveDraft();
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

    _currentPost = SocialAction(
      actionId: _currentPost!.actionId,
      createdAt: _currentPost!.createdAt,
      platforms: updatedPlatforms,
      content: _currentPost!.content,
      options: _currentPost!.options,
      platformData: _currentPost!.platformData,
      internal: _currentPost!.internal,
      mediaQuery: _currentPost!.mediaQuery,
    );

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

  /// Soft reset that preserves pre-selected media (for navigation back scenarios)
  void softReset() {
    _currentPost = null;
    _currentTranscription = '';
    _postState = PostState.idle;
    _lastError = null;
    _isRecording = false;
    _isProcessing = false;
    notifyListeners();

    if (kDebugMode) {
      print(
          '🔄 SocialActionPostCoordinator: Soft reset (preserving ${_preSelectedMedia.length} pre-selected media)');
    }
  }

  /// Validate and sanitize post data
  SocialAction _validateAndSanitizePost(SocialAction post) {
    // Ensure required fields
    final actionId = post.actionId.isEmpty
        ? 'sanitized_${DateTime.now().millisecondsSinceEpoch}'
        : post.actionId;

    final createdAt = post.createdAt.isEmpty
        ? DateTime.now().toIso8601String()
        : post.createdAt;

    final platforms =
        post.platforms.isEmpty ? ['instagram', 'twitter'] : post.platforms;

    // Sanitize text content
    final sanitizedText =
        post.content.text.replaceAll(RegExp(r'[^\w\s\.,!?@#-]'), '').trim();

    return SocialAction(
      actionId: actionId,
      createdAt: createdAt,
      platforms: platforms,
      content: Content(
        text: sanitizedText,
        hashtags: post.content.hashtags,
        mentions: post.content.mentions,
        link: post.content.link,
        media: post.content.media,
      ),
      options: post.options,
      platformData: post.platformData,
      internal: post.internal,
      mediaQuery: post.mediaQuery,
    );
  }

  /// Ensure media is included in the post
  Future<SocialAction> _ensureMediaInclusion(
      SocialAction post, String transcription) async {
    // Priority 1: If post already has media, keep it
    if (post.content.media.isNotEmpty) {
      if (kDebugMode) {
        print('✅ Post already has ${post.content.media.length} media items');
      }
      return post;
    }

    // Priority 2: If we have pre-selected media, use it
    if (_preSelectedMedia.isNotEmpty) {
      if (kDebugMode) {
        print('📎 Using ${_preSelectedMedia.length} pre-selected media items');
      }
      return SocialAction(
        actionId: post.actionId,
        createdAt: post.createdAt,
        platforms: post.platforms,
        content: Content(
          text: post.content.text,
          hashtags: post.content.hashtags,
          mentions: post.content.mentions,
          link: post.content.link,
          media: List.from(_preSelectedMedia),
        ),
        options: post.options,
        platformData: post.platformData,
        internal: post.internal,
        mediaQuery: post.mediaQuery,
      );
    }

    // Priority 3: Check if user referenced media in transcription
    if (_transcriptionReferencesMedia(transcription)) {
      if (kDebugMode) {
        print('🔍 Transcription references media: "$transcription"');
        print('🔍 Attempting to assign default media...');
      }

      try {
        // Get the most recent media from MediaCoordinator
        final recentMedia = await _getRecentMediaFromCoordinator();

        if (recentMedia.isNotEmpty) {
          final defaultMedia = recentMedia.first;

          if (kDebugMode) {
            print('✅ Assigned default media: ${defaultMedia.fileUri}');
            print('   Created: ${defaultMedia.deviceMetadata.creationTime}');
          }

          return SocialAction(
            actionId: post.actionId,
            createdAt: post.createdAt,
            platforms: post.platforms,
            content: Content(
              text: post.content.text,
              hashtags: post.content.hashtags,
              mentions: post.content.mentions,
              link: post.content.link,
              media: [defaultMedia],
            ),
            options: post.options,
            platformData: post.platformData,
            internal: Internal(
              retryCount: post.internal.retryCount,
              aiGenerated: post.internal.aiGenerated,
              originalTranscription: post.internal.originalTranscription,
              userPreferences: post.internal.userPreferences,
              mediaIndexId: post.internal.mediaIndexId,
              uiFlags: post.internal.uiFlags,
              fallbackReason: 'default_media_assigned',
            ),
            mediaQuery: post.mediaQuery,
          );
        } else {
          if (kDebugMode) {
            print('⚠️ No recent media available for default assignment');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Failed to get recent media for default assignment: $e');
        }
      }
    }

    // No media assignment needed or possible
    if (kDebugMode) {
      print('ℹ️ No media inclusion needed');
    }
    return post;
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

  /// Get recent media from MediaCoordinator
  Future<List<MediaItem>> _getRecentMediaFromCoordinator() async {
    if (_mediaCoordinator == null) {
      throw Exception('MediaCoordinator not available');
    }

    try {
      // Get recent media (both images and videos)
      final recentMediaMaps = await _mediaCoordinator!.getMediaForQuery(
        '', // Empty search for general recent media
        mediaTypes: ['image', 'video'],
      );

      // Convert to MediaItem objects
      final recentMedia = recentMediaMaps.map((mediaMap) {
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

      if (kDebugMode) {
        print(
            '📊 Retrieved ${recentMedia.length} recent media items from coordinator');
      }

      return recentMedia;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to get recent media from coordinator: $e');
      }
      return [];
    }
  }

  /// Extract hashtags from text
  List<String> _extractHashtagsFromText(String text) {
    final hashtagRegex = RegExp(r'#(\w+)');
    return hashtagRegex
        .allMatches(text)
        .map((match) => match.group(1)!)
        .toList();
  }

  /// Extract mentions from text
  List<String> _extractMentionsFromText(String text) {
    final mentionRegex = RegExp(r'@(\w+)');
    return mentionRegex
        .allMatches(text)
        .map((match) => match.group(1)!)
        .toList();
  }

  /// Auto-save draft
  void _autoSaveDraft() {
    if (_currentPost != null) {
      _saveDraft();
    }
  }

  /// Save draft to persistent storage (for auto-save, not finalized posts)
  Future<void> _saveDraft() async {
    if (_currentPost == null || _firestoreService == null) return;

    try {
      // Only auto-save if this is still a draft (not a finalized post)
      // Finalized posts should only be saved via uploadFinalizedPost()
      final isDraft = _currentPost!.actionId.startsWith('echo_') ||
          _currentPost!.actionId.startsWith('enhanced_baseline_') ||
          _currentPost!.actionId.startsWith('sanitized_') ||
          _currentPost!.actionId.startsWith('fallback_');

      if (isDraft) {
        await _firestoreService!.saveAction(_currentPost!.toJson());
        if (kDebugMode) {
          print('💾 Draft auto-saved');
          print('   Action ID: ${_currentPost!.actionId}');
          print('   Is draft: $isDraft');
        }
      } else {
        if (kDebugMode) {
          print(
              '⏭️ Skipping auto-save for finalized post: ${_currentPost!.actionId}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to save draft: $e');
      }
    }
  }

  /// Merge AI-generated post with existing post
  SocialAction _mergeWithExistingPost(
      SocialAction aiPost, SocialAction existingPost) {
    return SocialAction(
      actionId: existingPost.actionId,
      createdAt: existingPost.createdAt,
      platforms: aiPost.platforms.isNotEmpty
          ? aiPost.platforms
          : existingPost.platforms,
      content: Content(
        text: aiPost.content.text.isNotEmpty
            ? aiPost.content.text
            : existingPost.content.text,
        hashtags: aiPost.content.hashtags.isNotEmpty
            ? aiPost.content.hashtags
            : existingPost.content.hashtags,
        mentions: aiPost.content.mentions.isNotEmpty
            ? aiPost.content.mentions
            : existingPost.content.mentions,
        link: aiPost.content.link ?? existingPost.content.link,
        media: aiPost.content.media.isNotEmpty
            ? aiPost.content.media
            : existingPost.content.media,
      ),
      options: aiPost.options,
      platformData: aiPost.platformData,
      internal: Internal(
        retryCount: existingPost.internal.retryCount,
        aiGenerated: aiPost.internal.aiGenerated,
        originalTranscription: aiPost.internal.originalTranscription,
        userPreferences: existingPost.internal.userPreferences,
        mediaIndexId: existingPost.internal.mediaIndexId,
        uiFlags: existingPost.internal.uiFlags,
        fallbackReason: aiPost.internal.fallbackReason,
      ),
      mediaQuery: aiPost.mediaQuery ?? existingPost.mediaQuery,
    );
  }

  /// Replace media in current post (for media selection updates)
  Future<void> replaceMedia(List<MediaItem> media) async {
    if (_currentPost != null) {
      _currentPost = SocialAction(
        actionId: _currentPost!.actionId,
        createdAt: _currentPost!.createdAt,
        platforms: _currentPost!.platforms,
        content: Content(
          text: _currentPost!.content.text,
          hashtags: _currentPost!.content.hashtags,
          mentions: _currentPost!.content.mentions,
          link: _currentPost!.content.link,
          media: media, // Replace with new media
        ),
        options: _currentPost!.options,
        platformData: _currentPost!.platformData,
        internal: _currentPost!.internal,
        mediaQuery: _currentPost!.mediaQuery,
      );

      _postState = isPostComplete ? PostState.ready : PostState.needsMedia;
      await _saveDraft();
      notifyListeners();

      if (kDebugMode) {
        print('✅ Media replaced in coordinator');
        print('   New media count: ${media.length}');
        print('   Post complete: $isPostComplete');
      }
    } else {
      // If no current post, treat as pre-selected media
      _preSelectedMedia.clear();
      _preSelectedMedia.addAll(media);
      notifyListeners();

      if (kDebugMode) {
        print('✅ Pre-selected media updated');
        print('   Pre-selected count: ${_preSelectedMedia.length}');
      }
    }
  }

  /// Synchronize coordinator with an existing post (for cross-screen consistency)
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
      print('🔄 Coordinator synced with existing post');
      print('   Action ID: ${existingPost.actionId}');
      print('   Content: "${existingPost.content.text}"');
      print('   Media count: ${existingPost.content.media.length}');
      print('   Platforms: ${existingPost.platforms.join(', ')}');
    }
  }

  /// Update post schedule through coordinator
  Future<void> updatePostSchedule(String newSchedule) async {
    if (_currentPost == null) return;

    _currentPost = SocialAction(
      actionId: _currentPost!.actionId,
      createdAt: _currentPost!.createdAt,
      platforms: _currentPost!.platforms,
      content: _currentPost!.content,
      options: Options(
        schedule: newSchedule,
        locationTag: _currentPost!.options.locationTag,
        visibility: _currentPost!.options.visibility,
        replyToPostId: _currentPost!.options.replyToPostId,
      ),
      platformData: _currentPost!.platformData,
      internal: _currentPost!.internal,
      mediaQuery: _currentPost!.mediaQuery,
    );

    await _saveDraft();
    notifyListeners();

    if (kDebugMode) {
      print('✅ Schedule updated via coordinator');
      print('   New schedule: $newSchedule');
    }
  }

  /// Upload finalized post to Firestore (called when user confirms posting)
  Future<void> uploadFinalizedPost() async {
    if (_currentPost == null || _firestoreService == null) {
      throw Exception('No post to upload or Firestore service unavailable');
    }

    try {
      await _firestoreService!.saveAction(_currentPost!.toJson());

      if (kDebugMode) {
        print('✅ Finalized post uploaded to Firestore');
        print('   Action ID: ${_currentPost!.actionId}');
        print('   Content: "${_currentPost!.content.text}"');
        print('   Media count: ${_currentPost!.content.media.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to upload finalized post to Firestore: $e');
      }
      rethrow;
    }
  }

  /// Load existing post from Firestore into coordinator (for history/editing)
  Future<void> loadPostFromFirestore(String actionId) async {
    if (_firestoreService == null) {
      throw Exception('Firestore service unavailable');
    }

    try {
      final documentSnapshot = await _firestoreService!.getAction(actionId);
      if (documentSnapshot != null && documentSnapshot.exists) {
        final postData = documentSnapshot.data() as Map<String, dynamic>?;
        if (postData != null) {
          final loadedPost = SocialAction.fromJson(postData);

          // Sync coordinator with loaded post
          syncWithExistingPost(loadedPost);

          if (kDebugMode) {
            print('✅ Post loaded from Firestore into coordinator');
            print('   Action ID: ${loadedPost.actionId}');
            print('   Content: "${loadedPost.content.text}"');
            print('   Media count: ${loadedPost.content.media.length}');
          }
        } else {
          throw Exception('Post data is null');
        }
      } else {
        throw Exception('Post not found in Firestore');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to load post from Firestore: $e');
      }
      rethrow;
    }
  }

  /// Execute post across all selected social media platforms
  /// Returns a map of platform -> success status
  Future<Map<String, bool>> executePostToSocialMedia() async {
    if (_currentPost == null) {
      throw Exception('No post to execute');
    }

    if (_socialPostService == null) {
      throw Exception('SocialPostService not available');
    }

    try {
      if (kDebugMode) {
        print(
            '🚀 Executing post across social media platforms via coordinator');
        print('   Post ID: ${_currentPost!.actionId}');
        print('   Platforms: ${_currentPost!.platforms.join(', ')}');
        print('   Content: "${_currentPost!.content.text}"');
        print('   Media count: ${_currentPost!.content.media.length}');
      }

      // Execute the post across all platforms
      final results =
          await _socialPostService!.postToAllPlatforms(_currentPost!);

      if (kDebugMode) {
        print('✅ Social media posting completed');
        for (final entry in results.entries) {
          print('   ${entry.key}: ${entry.value ? 'Success' : 'Failed'}');
        }
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to execute post across social media: $e');
      }
      rethrow;
    }
  }

  /// Complete post workflow: Upload to Firestore + Execute on social media
  /// This is the final step that should be called when user confirms posting
  Future<Map<String, bool>> finalizeAndExecutePost() async {
    if (_currentPost == null) {
      throw Exception('No post to finalize and execute');
    }

    try {
      if (kDebugMode) {
        print('🎯 Finalizing and executing post via coordinator');
        print('   Action ID: ${_currentPost!.actionId}');
        print('   Platforms: ${_currentPost!.platforms.join(', ')}');
      }

      // Step 1: Upload finalized post to Firestore
      await uploadFinalizedPost();

      // Step 2: Execute post across social media platforms
      final executionResults = await executePostToSocialMedia();

      // Step 3: Update post state based on results
      final allSucceeded = executionResults.values.every((success) => success);

      if (kDebugMode) {
        print('✅ Post finalization and execution completed');
        print('   All platforms succeeded: $allSucceeded');
        print('   Individual results: $executionResults');
      }

      // Step 4: Clean up coordinator state after successful posting
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

  /// Check if post is ready for execution (has content, media if needed, and platforms selected)
  bool get isReadyForExecution {
    if (_currentPost == null) return false;

    final hasContent = _currentPost!.content.text.isNotEmpty;
    final hasPlatforms = _currentPost!.platforms.isNotEmpty;

    // Media is optional - some posts might be text-only
    // But if mediaQuery exists, we should have resolved media
    final mediaResolved = _currentPost!.mediaQuery == null ||
        _currentPost!.content.media.isNotEmpty;

    return hasContent && hasPlatforms && mediaResolved;
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

    if (_currentPost!.mediaQuery != null &&
        _currentPost!.content.media.isEmpty) {
      missingRequirements.add('Media query exists but no media selected');
    }

    if (_socialPostService == null) {
      missingRequirements.add('Social posting service not available');
    }

    return PostExecutionReadiness(
      isReady: missingRequirements.isEmpty,
      missingRequirements: missingRequirements,
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
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
