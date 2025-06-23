import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/social_action.dart';
import 'media_coordinator.dart';

class AIService {
  static const String _openaiApiUrl =
      'https://api.openai.com/v1/chat/completions';
  final String _apiKey;
  final MediaCoordinator? _mediaCoordinator;

  AIService(this._apiKey, [MediaCoordinator? mediaCoordinator])
      : _mediaCoordinator = mediaCoordinator;

  /// Attempts to repair common JSON formatting issues
  String repairJson(String brokenJson) {
    String repaired = brokenJson;

    if (kDebugMode) {
      print('🔧 Attempting to repair JSON...');
      print(
          '🔧 Original: ${brokenJson.substring(0, brokenJson.length.clamp(0, 200))}...');
    }

    // Remove any leading/trailing whitespace and non-JSON content
    repaired = repaired.trim();

    // Find the start and end of the JSON object
    int startIndex = repaired.indexOf('{');
    if (startIndex == -1) {
      throw Exception('No JSON object found in response');
    }

    // Try to find the matching closing brace
    int braceCount = 0;
    int endIndex = -1;

    for (int i = startIndex; i < repaired.length; i++) {
      if (repaired[i] == '{') {
        braceCount++;
      } else if (repaired[i] == '}') {
        braceCount--;
        if (braceCount == 0) {
          endIndex = i;
          break;
        }
      }
    }

    // If we couldn't find matching braces, try to add missing closing braces
    if (endIndex == -1) {
      repaired = repaired.substring(startIndex);
      // Count open braces that need closing
      int openBraces = 0;
      int openBrackets = 0;
      bool inString = false;
      bool escapeNext = false;

      for (int i = 0; i < repaired.length; i++) {
        String currentChar = repaired[i];

        if (escapeNext) {
          escapeNext = false;
          continue;
        }

        if (currentChar == '\\') {
          escapeNext = true;
          continue;
        }

        if (currentChar == '"') {
          inString = !inString;
          continue;
        }

        if (!inString) {
          if (currentChar == '{') {
            openBraces++;
          } else if (currentChar == '}') {
            openBraces--;
          } else if (currentChar == '[') {
            openBrackets++;
          } else if (currentChar == ']') {
            openBrackets--;
          }
        }
      }

      // Add missing closing brackets and braces
      for (int i = 0; i < openBrackets; i++) {
        repaired += ']';
      }
      for (int i = 0; i < openBraces; i++) {
        repaired += '}';
      }
    } else {
      repaired = repaired.substring(startIndex, endIndex + 1);
    }

    // Fix common issues with trailing commas before closing braces/brackets
    repaired = repaired.replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (match) => match.group(1)!,
    );

    // Fix missing quotes around keys (basic regex for simple cases)
    // Only fix keys that are not already in quotes and not inside strings
    repaired = repaired.replaceAllMapped(
      RegExp(r'(\n|\{|\s)(\w+):'),
      (match) => '${match.group(1)!}"${match.group(2)}":',
    );

    // Fix missing values for keys that end with colon but have no value
    repaired = repaired.replaceAllMapped(
      RegExp(r'"([^"]+)":\s*([,}\]])'),
      (match) {
        String key = match.group(1)!;
        String terminator = match.group(2)!;

        // Provide default values based on common key patterns
        if (key.contains('schedule')) return '"$key": "now"$terminator';
        if (key.contains('location') || key.contains('tag')) {
          return '"$key": null$terminator';
        }
        if (key.contains('visibility') || key.contains('reply')) {
          return '"$key": null$terminator';
        }
        if (key.endsWith('_id') || key.contains('id')) {
          return '"$key": null$terminator';
        }
        if (key.contains('url') || key.contains('link')) {
          return '"$key": null$terminator';
        }
        if (key.contains('array') || key.contains('list')) {
          return '"$key": []$terminator';
        }

        // Default to null for unknown keys
        return '"$key": null$terminator';
      },
    );

    if (kDebugMode) {
      print(
          '🔧 Repaired: ${repaired.substring(0, repaired.length.clamp(0, 200))}...');
    }

    return repaired;
  }

  /// Robust JSON parsing using the post coordinator's advanced repair strategies
  Map<String, dynamic> robustJsonParse(String jsonString) {
    // Use fallback JSON parsing since coordinator method was removed
    return _fallbackJsonParse(jsonString);
  }

  /// Fallback JSON parsing when coordinator is not available
  Map<String, dynamic> _fallbackJsonParse(String jsonString) {
    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('🔧 Direct JSON parse failed, attempting basic repair...');
      }

      try {
        final repairedJson = repairJson(jsonString);
        return json.decode(repairedJson) as Map<String, dynamic>;
      } catch (repairError) {
        if (kDebugMode) {
          print('❌ JSON repair failed: $repairError');
        }

        // Return minimal structure to prevent complete failure
        return {
          'action_id': 'emergency_${DateTime.now().millisecondsSinceEpoch}',
          'created_at': DateTime.now().toIso8601String(),
          'platforms': ['instagram', 'twitter'],
          'content': {
            'text': 'Error processing voice command',
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
            'original_transcription': '',
            'fallback_reason': 'emergency_fallback',
          },
        };
      }
    }
  }

  Future<SocialAction> processVoiceCommand(
    String transcription, {
    List<MediaItem>? preSelectedMedia,
  }) async {
    if (kDebugMode) {
      print('🎯 Processing voice command: "$transcription"');
      if (preSelectedMedia != null && preSelectedMedia.isNotEmpty) {
        print('📎 With ${preSelectedMedia.length} pre-selected media items');
      }
    }

    try {
      // Get media context for the prompt (includes existing post context if editing)
      var mediaContext = _mediaCoordinator != null
          ? await _mediaCoordinator!.getMediaContextForAi()
          : <String, dynamic>{};

      // If pre-selected media is provided, add it to the structured media context
      if (preSelectedMedia != null && preSelectedMedia.isNotEmpty) {
        // Convert pre-selected media to the format expected by ChatGPT
        final preSelectedMediaData = preSelectedMedia.map((media) {
          return {
            'file_uri': media.fileUri,
            'file_name': media.fileUri.split('/').last,
            'mime_type': media.mimeType,
            'timestamp': media.deviceMetadata.creationTime,
            'device_metadata': {
              'creation_time': media.deviceMetadata.creationTime,
              'latitude': media.deviceMetadata.latitude,
              'longitude': media.deviceMetadata.longitude,
              'orientation': media.deviceMetadata.orientation,
              'width': media.deviceMetadata.width,
              'height': media.deviceMetadata.height,
              'file_size_bytes': media.deviceMetadata.fileSizeBytes,
              'duration': media.deviceMetadata.duration,
              'bitrate': media.deviceMetadata.bitrate,
              'sampling_rate': media.deviceMetadata.samplingRate,
              'frame_rate': media.deviceMetadata.frameRate,
            },
            'pre_selected': true, // Mark as pre-selected for ChatGPT
          };
        }).toList();

        // Add pre-selected media to the context with a clear indicator
        mediaContext = {
          ...mediaContext,
          'pre_selected_media': preSelectedMediaData,
        };

        if (kDebugMode) {
          print(
              '📎 Added ${preSelectedMediaData.length} pre-selected media items to structured context');
        }
      }

      // SINGLE SYSTEM PROMPT - ChatGPT handles editing vs creation based on context
      const systemPrompt = '''
You are a social media content creator and JSON generator for the EchoPost app.

Your task is to transform a spoken transcription into an engaging, platform-ready social media post and generate a complete SocialAction object as JSON.

**CRITICAL: CONTENT TRANSFORMATION REQUIREMENTS**

1. **POST CONTENT CREATION:**
   - The transcription is your STARTING POINT, not the final post
   - Transform the transcription into engaging, concise social media content
   - Make it suitable for platforms like Instagram, Twitter, Facebook, and TikTok
   - Use compelling language, emojis where appropriate, and clear calls-to-action
   - Keep posts concise but engaging (Instagram: 125-150 chars optimal, Twitter: under 280)

2. **MEDIA TYPE HANDLING (CRITICAL):**
   - ALWAYS check the mime_type of media files to determine their type
   - For images: mime_type starts with "image/" (e.g., "image/jpeg")
   - For videos: mime_type starts with "video/" (e.g., "video/mp4")
   - NEVER use a video when an image is requested, or vice versa
   - When user asks for "picture" or "photo", only use media with image/* mime types
   - When user asks for "video" or "clip", only use media with video/* mime types
   - Check device_metadata.duration and frame_rate (present for videos, null for images)
   - If no media of the requested type is found, do not include any media

3. **HASHTAG REQUIREMENTS (MANDATORY):**
   - ALWAYS generate relevant hashtags and include them in the "hashtags" array
   - Include 3-8 hashtags that are relevant to the content
   - Mix popular hashtags with niche ones for better reach
   - Consider trending hashtags when relevant
   - Examples: ["travel", "sunset", "photography", "wanderlust", "nature"]

4. **CONTENT ENHANCEMENT:**
   - Add context and emotion that may be missing from the transcription
   - Include relevant emojis to increase engagement
   - Create compelling captions that encourage interaction
   - Transform casual speech into polished social media content

5. **EDITING MODE:**
   - If editing_mode is true in the media context, modify the existing post based on the voice instruction
   - Preserve what should stay, change what needs to be changed
   - If user says "change the caption to..." → Replace the text entirely
   - If user says "add..." → Append to existing content
   - If user says "remove..." → Remove specified elements
   - If user gives general feedback → Intelligently modify while preserving intent

**EXAMPLE TRANSFORMATIONS:**
- Transcription: "posting a picture of my coffee"
- Enhanced Post: "Starting my Monday with the perfect brew ☕️ Nothing beats that first sip of morning motivation! What's fueling your week? #MondayMotivation #CoffeeLovers #MorningRitual #CoffeeTime #Productivity"

**REQUIRED JSON STRUCTURE:**
You MUST return a complete JSON object with this exact structure:

{
  "action_id": "echo_[timestamp]",
  "created_at": "[ISO8601 timestamp]",
  "platforms": ["facebook", "instagram", "youtube", "twitter", "tiktok"],
  "content": {
    "text": "[enhanced social media content]",
    "hashtags": ["hashtag1", "hashtag2", "hashtag3"],
    "mentions": [],
    "link": null,
    "media": []
  },
  "options": {
    "schedule": "now",
    "visibility": {
      "facebook": "public",
      "instagram": "public",
      "youtube": "public", 
      "twitter": "public", 
      "tiktok": "public"
    },
    "location_tag": null,
    "reply_to_post_id": null
  },
  "platform_data": {
    "facebook": {
      "post_here": false,
      "post_as_page": false,
      "page_id": "",
      "post_type": null,
      "media_file_uri": null,
      "video_file_uri": null,
      "audio_file_uri": null,
      "thumbnail_uri": null,
      "scheduled_time": null,
      "additional_fields": null
    },
    "instagram": {
      "post_here": true,
      "post_type": "feed",
      "carousel": null,
      "ig_user_id": "",
      "media_type": "image",
      "media_file_uri": null,
      "video_thumbnail_uri": null,
      "video_file_uri": null,
      "audio_file_uri": null,
      "scheduled_time": null
    },
    "youtube": {
      "post_here": false,
      "channel_id": "",
      "privacy": "public",
      "video_category_id": "22",
      "video_file_uri": null,
      "thumbnail_uri": null,
      "scheduled_time": null,
      "tags": null,
      "enable_comments": true,
      "enable_ratings": true,
      "made_for_kids": false
    },
    "twitter": {
      "post_here": false,
      "alt_texts": [],
      "tweet_mode": "extended",
      "media_type": null,
      "media_file_uri": null,
      "media_duration": 0,
      "tweet_link": null,
      "scheduled_time": null
    },
    "tiktok": {
      "post_here": false,
      "privacy": "public",
      "sound": {
        "use_original_sound": true,
        "music_id": null
      },
      "media_file_uri": null,
      "video_file_uri": null,
      "audio_file_uri": null,
      "scheduled_time": null
    }
  },
  "internal": {
    "retry_count": 0,
    "ai_generated": true,
    "original_transcription": "[original voice transcription]",
    "user_preferences": {
      "default_platforms": [],
      "default_hashtags": []
    },
    "media_index_id": null,
    "ui_flags": {
      "is_editing_caption": false,
      "is_media_preview_open": false
    },
    "fallback_reason": null
  },
  "media_query": null
}

**PLATFORM SELECTION RULES:**
- If media is available: Include all platforms ["facebook", "instagram", "youtube", "twitter", "tiktok"]
- If no media: Focus on text platforms ["facebook", "twitter"]
- Set "post_here": true for selected platforms in platform_data
- Instagram, YouTube, and TikTok require media, so only include them if media is present

**MEDIA HANDLING:**
- If media context includes recent_media or pre_selected_media, populate the "media" array
- Set appropriate media_file_uri in platform_data for platforms that will post
- For videos: set media_type to "video" and populate video_file_uri
- For images: set media_type to "image" and populate media_file_uri
- YouTube only supports videos, so only include YouTube if video content is available

**RESPONSE FORMAT:** Return only valid JSON with the complete SocialAction structure.
''';

      final messages = [
        {
          'role': 'system',
          'content': systemPrompt,
        },
        {
          'role': 'user',
          'content': '''
User's voice transcription: "$transcription"

Media Context: ${json.encode(mediaContext)}

Generate a complete SocialAction JSON object based on this input.
''',
        },
      ];

      final response = await http.post(
        Uri.parse(_openaiApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: json.encode({
          'model': 'gpt-4-turbo-preview',
          'messages': messages,
          'temperature': 0.7,
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'OpenAI API error: ${response.statusCode} - ${response.body}');
      }

      final jsonResponse = json.decode(response.body);
      final content = jsonResponse['choices'][0]['message']['content'];

      if (kDebugMode) {
        print('📝 RAW ChatGPT response (before any processing): $content');
        print(
            '📊 Response length: ${content?.toString().length ?? 0} characters');
      }

      // Use robust JSON parsing instead of direct decode
      Map<String, dynamic> actionJson;
      if (content is String) {
        try {
          // CRITICAL FIX: Use robust JSON parsing instead of direct decode
          actionJson = robustJsonParse(content);
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed to parse content with robust parser: $e');
            print('📝 Raw content: $content');
          }
          throw Exception(
              'Invalid JSON response from ChatGPT after all repair attempts');
        }
      } else if (content is Map<String, dynamic>) {
        actionJson = content;
      } else {
        throw Exception(
            'Unexpected response type from ChatGPT: ${content.runtimeType}');
      }

      if (kDebugMode) {
        print('🔍 Parsed ChatGPT JSON keys: ${actionJson.keys.toList()}');
        print(
            '🔍 Content.media present: ${actionJson['content']?.containsKey('media') ?? false}');
        if (actionJson['content']?.containsKey('media') == true) {
          final mediaArray = actionJson['content']['media'] as List? ?? [];
          print('🔍 Content.media length: ${mediaArray.length}');
        }
      }

      // Apply fallback template to ensure complete SocialAction
      final standardizedAction = _mergeWithDefaults(
          actionJson, transcription, mediaContext, preSelectedMedia);

      // Create SocialAction from standardized JSON
      return SocialAction.fromJson(standardizedAction);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in processVoiceCommand: $e');
        print('📊 Stack trace: ${StackTrace.current}');
      }
      rethrow;
    }
  }

  /// Merges ChatGPT response with default template to ensure complete SocialAction
  /// This addresses ChatGPT's tendency to return incomplete JSON
  Map<String, dynamic> _mergeWithDefaults(
    Map<String, dynamic> gptJson,
    String transcription,
    Map<String, dynamic> mediaContext,
    List<MediaItem>? preSelectedMedia,
  ) {
    if (kDebugMode) {
      print('🔧 Merging ChatGPT response with default template...');
    }

    // Create complete default template
    final defaultTemplate = _createDefaultSocialAction(transcription);

    // Start with defaults, then overlay ChatGPT's responses
    final result = Map<String, dynamic>.from(defaultTemplate);
    final fallbacksApplied = <String>[];

    // Merge top-level fields from ChatGPT
    for (final key in gptJson.keys) {
      if (gptJson[key] != null) {
        if (key == 'content' && gptJson[key] is Map) {
          // Special handling for content object - merge fields individually
          _mergeContentObject(result, gptJson, fallbacksApplied);
        } else if (key == 'platforms' && gptJson[key] is List) {
          final platforms = gptJson[key] as List;
          if (platforms.isNotEmpty) {
            result[key] = platforms.cast<String>();
          } else {
            fallbacksApplied.add('empty_platforms');
          }
        } else if (key == 'platform_data' && gptJson[key] is Map) {
          // Merge platform_data carefully
          _mergePlatformData(result, gptJson, fallbacksApplied);
        } else {
          result[key] = gptJson[key];
        }
      } else {
        fallbacksApplied.add('null_$key');
      }
    }

    // CRITICAL: Ensure unified hashtag handling
    _ensureUnifiedHashtagHandling(result, transcription, fallbacksApplied);

    // CRITICAL: Ensure media is included when available and validates media context
    _ensureMediaInclusion(result, mediaContext, preSelectedMedia, transcription,
        fallbacksApplied);

    // Update platform_data to reflect actual media
    _updatePlatformDataWithMedia(result);

    // Record fallback reasons for debugging
    if (fallbacksApplied.isNotEmpty) {
      result['internal']['fallback_reason'] = fallbacksApplied.join(', ');
      if (kDebugMode) {
        print('⚠️ Applied fallbacks: ${fallbacksApplied.join(', ')}');
      }
    }

    if (kDebugMode) {
      final mediaCount = (result['content']['media'] as List).length;
      final hashtagCount = (result['content']['hashtags'] as List).length;
      print(
          '✅ Merge complete. Final media count: $mediaCount, hashtag count: $hashtagCount');
      if (mediaCount > 0) {
        final mediaUris = (result['content']['media'] as List)
            .map((m) => (m as Map)['file_uri'])
            .toList();
        print('📎 Final media: ${mediaUris.join(', ')}');
      }
      if (hashtagCount > 0) {
        final hashtags = (result['content']['hashtags'] as List).cast<String>();
        print('🏷️ Final hashtags: ${hashtags.join(', ')}');
      }
    }

    return result;
  }

  /// Creates a complete default SocialAction template
  Map<String, dynamic> _createDefaultSocialAction(String transcription) {
    final timestamp = DateTime.now().toIso8601String();
    final actionId = 'echo_${DateTime.now().millisecondsSinceEpoch}';

    return {
      'action_id': actionId,
      'created_at': timestamp,
      'platforms': ['facebook', 'instagram', 'youtube', 'twitter', 'tiktok'],
      'content': {
        'text': transcription, // Fallback to original transcription
        'hashtags': <String>[],
        'mentions': <String>[],
        'link': null,
        'media': <Map<String, dynamic>>[], // Empty but will be populated
      },
      'options': {
        'schedule': 'now',
        'visibility': {
          'facebook': 'public',
          'instagram': 'public',
          'youtube': 'public',
          'twitter': 'public',
          'tiktok': 'public',
        },
        'location_tag': null,
        'reply_to_post_id': null,
      },
      'platform_data': {
        'facebook': {
          'post_here': false,
          'post_as_page': false,
          'page_id': '',
          'post_type': null,
          'media_file_uri': null,
          'video_file_uri': null,
          'audio_file_uri': null,
          'thumbnail_uri': null,
          'scheduled_time': null,
          'additional_fields': null,
        },
        'instagram': {
          'post_here': true,
          'post_type': 'feed',
          'carousel': null,
          'ig_user_id': '',
          'media_type': 'image',
          'media_file_uri': null,
          'video_thumbnail_uri': null,
          'video_file_uri': null,
          'audio_file_uri': null,
          'scheduled_time': null,
        },
        'youtube': {
          'post_here': false,
          'channel_id': '',
          'privacy': 'public',
          'video_category_id': '22',
          'video_file_uri': null,
          'thumbnail_uri': null,
          'scheduled_time': null,
          'tags': null,
          'enable_comments': true,
          'enable_ratings': true,
          'made_for_kids': false
        },
        'twitter': {
          'post_here': false,
          'alt_texts': <String>[],
          'tweet_mode': 'extended',
          'media_type': null,
          'media_file_uri': null,
          'media_duration': 0,
          'tweet_link': null,
          'scheduled_time': null,
        },
        'tiktok': {
          'post_here': false,
          'privacy': 'public',
          'sound': {
            'use_original_sound': true,
            'music_id': null,
          },
          'media_file_uri': null,
          'video_file_uri': null,
          'audio_file_uri': null,
          'scheduled_time': null,
        },
      },
      'internal': {
        'retry_count': 0,
        'ai_generated': true,
        'original_transcription': transcription,
        'user_preferences': {
          'default_platforms': <String>[],
          'default_hashtags': <String>[],
        },
        'media_index_id': null,
        'ui_flags': {
          'is_editing_caption': false,
          'is_media_preview_open': false,
        },
        'fallback_reason': null,
      },
      'media_query': null,
    };
  }

  /// Merges content object from ChatGPT with defaults
  void _mergeContentObject(
    Map<String, dynamic> result,
    Map<String, dynamic> gptJson,
    List<String> fallbacksApplied,
  ) {
    final resultContent = result['content'] as Map<String, dynamic>;
    final gptContent = gptJson['content'] as Map<String, dynamic>;

    for (final contentKey in gptContent.keys) {
      if (gptContent[contentKey] != null) {
        if (contentKey == 'media' && gptContent[contentKey] is List) {
          final mediaList = gptContent[contentKey] as List;
          if (mediaList.isNotEmpty) {
            // Validate media items have required fields
            final validMedia = mediaList.where((item) {
              return item is Map<String, dynamic> &&
                  item.containsKey('file_uri') &&
                  item['file_uri'] != null &&
                  item['file_uri'].toString().isNotEmpty;
            }).toList();

            if (validMedia.isNotEmpty) {
              resultContent[contentKey] = validMedia;
            } else {
              fallbacksApplied.add('invalid_media_items');
            }
          } else {
            fallbacksApplied.add('empty_media_array');
          }
        } else {
          resultContent[contentKey] = gptContent[contentKey];
        }
      }
    }
  }

  /// Merges platform_data from ChatGPT with defaults
  void _mergePlatformData(
    Map<String, dynamic> result,
    Map<String, dynamic> gptJson,
    List<String> fallbacksApplied,
  ) {
    final resultPlatformData = result['platform_data'] as Map<String, dynamic>;
    final gptPlatformData = gptJson['platform_data'] as Map<String, dynamic>;

    for (final platform in gptPlatformData.keys) {
      if (gptPlatformData[platform] is Map &&
          resultPlatformData.containsKey(platform)) {
        final resultPlatform =
            resultPlatformData[platform] as Map<String, dynamic>;
        final gptPlatform = gptPlatformData[platform] as Map<String, dynamic>;

        // Merge individual platform fields
        for (final field in gptPlatform.keys) {
          if (gptPlatform[field] != null) {
            resultPlatform[field] = gptPlatform[field];
          }
        }
      }
    }
  }

  /// Checks if transcription suggests the user wants media included
  bool _transcriptionReferencesMedia(String transcription) {
    final lowerTranscription = transcription.toLowerCase();

    // Separate keywords by media type
    final imageKeywords = [
      'picture',
      'photo',
      'image',
      'pic',
      'shot',
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

    final videoKeywords = [
      'video',
      'clip',
      'recording',
      'this video',
      'this clip',
      'my video',
      'my clip',
      'the video',
      'the clip',
    ];

    // Generic keywords that don't specify type
    final genericKeywords = [
      'last',
      'recent',
      'latest',
      'newest',
    ];

    // Check for specific media type first
    final hasImageKeyword =
        imageKeywords.any((keyword) => lowerTranscription.contains(keyword));
    final hasVideoKeyword =
        videoKeywords.any((keyword) => lowerTranscription.contains(keyword));
    final hasGenericKeyword =
        genericKeywords.any((keyword) => lowerTranscription.contains(keyword));

    if (kDebugMode) {
      if (hasImageKeyword) {
        final matchedKeywords = imageKeywords
            .where((keyword) => lowerTranscription.contains(keyword))
            .toList();
        print('🔍 Found image keywords: ${matchedKeywords.join(', ')}');
      }
      if (hasVideoKeyword) {
        final matchedKeywords = videoKeywords
            .where((keyword) => lowerTranscription.contains(keyword))
            .toList();
        print('🔍 Found video keywords: ${matchedKeywords.join(', ')}');
      }
      if (hasGenericKeyword) {
        final matchedKeywords = genericKeywords
            .where((keyword) => lowerTranscription.contains(keyword))
            .toList();
        print('🔍 Found generic keywords: ${matchedKeywords.join(', ')}');
      }
    }

    // Return true if any media type is referenced
    return hasImageKeyword || hasVideoKeyword || hasGenericKeyword;
  }

  /// Get the requested media type from transcription
  String? _getRequestedMediaType(String transcription) {
    final lowerTranscription = transcription.toLowerCase();

    final imageKeywords = [
      'picture',
      'photo',
      'image',
      'pic',
      'shot',
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

    final videoKeywords = [
      'video',
      'clip',
      'recording',
      'this video',
      'this clip',
      'my video',
      'my clip',
      'the video',
      'the clip',
    ];

    if (imageKeywords.any((keyword) => lowerTranscription.contains(keyword))) {
      return 'image';
    }
    if (videoKeywords.any((keyword) => lowerTranscription.contains(keyword))) {
      return 'video';
    }
    return null;
  }

  /// CRITICAL: Ensures media is included when available and validates media context
  void _ensureMediaInclusion(
    Map<String, dynamic> result,
    Map<String, dynamic> mediaContext,
    List<MediaItem>? preSelectedMedia,
    String transcription,
    List<String> fallbacksApplied,
  ) {
    // If media already exists in the result, validate it
    final resultContent = result['content'] as Map<String, dynamic>;
    final existingMedia = resultContent['media'] as List? ?? [];

    if (existingMedia.isNotEmpty) {
      if (kDebugMode) {
        print('📎 Media already present in result: ${existingMedia.length}');
      }
      return;
    }

    // Check if we're in voice dictation mode
    final isVoiceDictation = mediaContext['isVoiceDictation'] as bool? ?? false;

    // In voice dictation mode, only include media if explicitly referenced
    if (isVoiceDictation && !_transcriptionReferencesMedia(transcription)) {
      if (kDebugMode) {
        print('🎤 Voice dictation mode - skipping media inclusion');
      }
      return;
    }

    // Check if transcription references media
    if (_transcriptionReferencesMedia(transcription)) {
      // Get all available media sources
      final recentMedia = mediaContext['recent_media'] as List? ?? [];
      final mediaByDate = mediaContext['mediaByDate'] as List? ?? [];
      final mediaByLocation = mediaContext['mediaByLocation'] as List? ?? [];
      final preSelectedMediaList = preSelectedMedia
              ?.map((item) => {
                    'file_uri': item.fileUri,
                    'mime_type': item.mimeType,
                    'timestamp': item.deviceMetadata.creationTime,
                    'device_metadata': item.deviceMetadata.toJson(),
                    'pre_selected': true,
                  })
              .toList() ??
          [];

      // Combine all media sources, prioritizing in this order:
      // 1. Pre-selected media
      // 2. Recent media
      // 3. Media by date
      // 4. Media by location
      final allAvailableMedia = {
        ...preSelectedMediaList,
        ...recentMedia,
        ...mediaByDate,
        ...mediaByLocation,
      }.toList(); // Remove duplicates based on file_uri

      if (allAvailableMedia.isEmpty) {
        if (kDebugMode) {
          print('⚠️ No media available in any context');
        }
        fallbacksApplied.add('no_media_available');
        result['needs_media_selection'] = true;
        return;
      }

      // Get requested media type
      final requestedType = _getRequestedMediaType(transcription);
      if (requestedType != null) {
        final matchingMedia = allAvailableMedia
            .where((media) => _mediaMatchesType(media, requestedType))
            .take(4) // Limit to 4 matching media items
            .toList();

        if (matchingMedia.isNotEmpty) {
          resultContent['media'] = matchingMedia;
          if (kDebugMode) {
            print(
                '📎 Added ${matchingMedia.length} matching media items of type: $requestedType');
            print(
                '   Sources: ${_getMediaSources(matchingMedia, preSelectedMediaList)}');
          }
          return;
        }
      }

      // If no specific type requested or no matching media found, use most recent
      resultContent['media'] = [allAvailableMedia.first];
      if (kDebugMode) {
        print('📎 Added most recent media item as fallback');
        print(
            '   Source: ${_getMediaSource(allAvailableMedia.first, preSelectedMediaList)}');
      }
    }
  }

  /// Helper to identify media source for debugging
  String _getMediaSource(
      Map<String, dynamic> media, List<dynamic> preSelectedMedia) {
    if (media['pre_selected'] == true) return 'pre-selected';
    if (media['source'] == 'date') return 'by-date';
    if (media['source'] == 'location') return 'by-location';
    return 'recent';
  }

  /// Helper to summarize media sources for debugging
  String _getMediaSources(List<dynamic> media, List<dynamic> preSelectedMedia) {
    final sources = media
        .map(
            (m) => _getMediaSource(m as Map<String, dynamic>, preSelectedMedia))
        .toSet()
        .toList();
    return sources.join(', ');
  }

  /// Updates platform_data to reflect the actual media being used
  void _updatePlatformDataWithMedia(Map<String, dynamic> result) {
    final mediaItems = result['content']['media'] as List<dynamic>;
    if (mediaItems.isEmpty) return;

    final firstMedia = mediaItems.first as Map<String, dynamic>;
    final fileUri = firstMedia['file_uri'] as String;
    final mimeType = firstMedia['mime_type'] as String;
    final isVideo = mimeType.startsWith('video/');

    // Update Instagram platform data
    final instagramData =
        result['platform_data']['instagram'] as Map<String, dynamic>;
    instagramData['media_file_uri'] = fileUri;
    instagramData['media_type'] = isVideo ? 'video' : 'image';
    if (isVideo) {
      instagramData['video_file_uri'] = fileUri;
    }

    // Update YouTube platform data (video only)
    if (isVideo) {
      final youtubeData =
          result['platform_data']['youtube'] as Map<String, dynamic>;
      youtubeData['video_file_uri'] = fileUri;
    }

    // Update Twitter platform data
    final twitterData =
        result['platform_data']['twitter'] as Map<String, dynamic>;
    twitterData['media_file_uri'] = fileUri;
    twitterData['media_type'] = isVideo ? 'video' : 'image';

    if (kDebugMode) {
      print('🔄 Updated platform_data with media: $fileUri');
    }
  }

  /// Ensures unified hashtag handling between text content and hashtag array
  void _ensureUnifiedHashtagHandling(
    Map<String, dynamic> result,
    String transcription,
    List<String> fallbacksApplied,
  ) {
    final content = result['content'] as Map<String, dynamic>;
    final postText = content['text'] as String? ?? '';
    final hashtagArray = content['hashtags'] as List<dynamic>? ?? [];

    // Extract hashtags from text content (spoken hashtags)
    final extractedHashtags = _extractHashtagsFromText(postText);

    // Clean text content (remove hashtags for unified management)
    final cleanText = _removeHashtagsFromText(postText);

    // Merge extracted hashtags with ChatGPT's hashtag array
    final gptHashtags =
        hashtagArray.cast<String>().map((tag) => tag.toLowerCase()).toList();
    final allHashtags = <String>{...extractedHashtags, ...gptHashtags}.toList();

    // If no hashtags found, generate intelligent ones
    if (allHashtags.isEmpty) {
      final intelligentHashtags = _generateIntelligentHashtags(
          cleanText.isNotEmpty ? cleanText : transcription);
      allHashtags.addAll(intelligentHashtags);
      fallbacksApplied.add('generated_intelligent_hashtags');
    }

    // Update content with unified hashtag handling
    content['text'] = cleanText;
    content['hashtags'] = allHashtags;

    if (kDebugMode) {
      print('🔄 Unified hashtag handling applied:');
      print('   Original text: "$postText"');
      print('   Clean text: "$cleanText"');
      print('   Extracted hashtags: $extractedHashtags');
      print('   ChatGPT hashtags: $gptHashtags');
      print('   Final hashtags: $allHashtags');
    }
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

    return uniqueHashtags;
  }

  /// Check if media matches requested type
  bool _mediaMatchesType(Map<String, dynamic> media, String requestedType) {
    final mimeType = (media['mime_type'] as String? ?? '').toLowerCase();
    return requestedType == 'image'
        ? mimeType.startsWith('image/')
        : mimeType.startsWith('video/');
  }
}
