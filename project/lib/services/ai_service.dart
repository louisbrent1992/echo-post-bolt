import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/social_action.dart';
import 'media_coordinator.dart';

class AIService {
  static const String _openaiApiUrl =
      'https://api.openai.com/v1/chat/completions';
  final String _apiKey;
  MediaCoordinator? _mediaCoordinator;

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
      // Get media context for the prompt
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

      final messages = [
        {
          'role': 'system',
          'content': '''
You are a social media content creator and JSON generator for the EchoPost app.

Your task is to transform a spoken transcription into an engaging, platform-ready social media post and generate a complete SocialAction object as JSON.

**CRITICAL: CONTENT TRANSFORMATION REQUIREMENTS**

1. **POST CONTENT CREATION:**
   - The transcription is your STARTING POINT, not the final post
   - Transform the transcription into engaging, concise social media content
   - Make it suitable for platforms like Instagram, Twitter, Facebook, and TikTok
   - Use compelling language, emojis where appropriate, and clear calls-to-action
   - Keep posts concise but engaging (Instagram: 125-150 chars optimal, Twitter: under 280)

2. **HASHTAG REQUIREMENTS (MANDATORY):**
   - ALWAYS generate relevant hashtags and include them in the "hashtags" array
   - Include 3-8 hashtags that are relevant to the content
   - Mix popular hashtags with niche ones for better reach
   - Consider trending hashtags when relevant
   - Examples: ["travel", "sunset", "photography", "wanderlust", "nature"]

3. **CONTENT ENHANCEMENT:**
   - Add context and emotion that may be missing from the transcription
   - Include relevant emojis to increase engagement
   - Create compelling captions that encourage interaction
   - Transform casual speech into polished social media content

**EXAMPLE TRANSFORMATIONS:**
- Transcription: "posting a picture of my coffee"
- Enhanced Post: "Starting my Monday with the perfect brew ☕️ Nothing beats that first sip of morning motivation! What's fueling your week? #MondayMotivation #CoffeeLovers #MorningRitual #CoffeeTime #Productivity"

- Transcription: "sharing my workout video"  
- Enhanced Post: "Crushing today's workout! 💪 Remember: progress over perfection. Every rep counts, every day matters. Who's joining me tomorrow? #FitnessJourney #WorkoutMotivation #HealthyLifestyle #FitLife #NoExcuses"

You will receive these fields from the user:
- "transcription": a string containing the spoken command (TRANSFORM THIS!)
- "media_context": an object containing available media files from the user's device, with recent_media sorted by creation time (newest first)
- "pre_selected_media": (optional) media items that the user has already selected before recording

**CRITICAL MEDIA SELECTION RULES:**

1. **PRIORITY ORDER FOR MEDIA SELECTION:**
   a) If pre_selected_media is provided, ALWAYS include these items in content.media array - these are user's explicit choices
   b) If transcription references specific media (e.g., "last picture", "recent photo", "newest image", "latest video"), DIRECTLY select from media_context.recent_media array
   c) Only create media_query if no suitable media is found in the context AND media is clearly needed

2. **DIRECT MEDIA REFERENCE HANDLING:**
   When the user says phrases like:
   - "post my last picture" → Select media_context.recent_media[0] (most recent)
   - "share my recent photo" → Select media_context.recent_media[0] (most recent)  
   - "upload my newest image" → Select media_context.recent_media[0] (most recent)
   - "post the latest video" → Select first video from media_context.recent_media
   - "share my last 3 photos" → Select first 3 images from media_context.recent_media

3. **CONTENT.MEDIA STRUCTURE:**
   When including media in content.media, use this exact structure:
   ```json
   {
     "file_uri": "file:///path/to/media.jpg",
     "mime_type": "image/jpeg",
     "device_metadata": {
       "creation_time": "2024-01-15T10:30:00.000Z",
       "latitude": 40.7128,
       "longitude": -74.0060,
       "orientation": 1,
       "width": 1920,
       "height": 1080,
       "file_size_bytes": 2048576
     }
   }
   ```

4. **MEDIA_QUERY vs CONTENT.MEDIA:**
   - Use content.media when you have specific media from context to include
   - Use media_query only when no suitable media found but media is needed
   - NEVER use both content.media and media_query for the same content type

**RESPONSE FORMAT:**
Your response must be valid JSON with this exact structure:

```json
{
  "action_id": "echo_[timestamp]",
  "created_at": "[ISO8601 timestamp]", 
  "platforms": ["instagram", "twitter", "facebook", "tiktok"],
  "content": {
    "text": "[ENHANCED social media post - NOT raw transcription]",
    "hashtags": ["MANDATORY", "relevant", "hashtags", "array"],
    "mentions": ["relevant_accounts"],
    "link": null,
    "media": [...]
  },
  "options": {
    "schedule": "now",
    "location_tag": null,
    "visibility": {
      "instagram": "public",
      "twitter": "public", 
      "facebook": "public",
      "tiktok": "public"
    },
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
    "twitter": {
      "post_here": true,
      "alt_texts": [],
      "tweet_mode": "extended",
      "media_type": null,
      "media_file_uri": null,
      "media_duration": null,
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
    "original_transcription": "[exact user transcription]",
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
```

**REQUIREMENTS:**
- ALWAYS transform transcription into engaging social media content
- ALWAYS include relevant hashtags in the hashtags array (3-8 hashtags minimum)
- Always include all platform_data objects (facebook, instagram, twitter, tiktok) even if post_here is false
- Focus on engagement, clarity, and platform optimization
'''
        },
        {
          'role': 'user',
          'content': json.encode({
            'transcription': transcription,
            'media_context': mediaContext,
          })
        }
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

    // CRITICAL: Ensure media is included when available
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
      'platforms': ['instagram', 'twitter', 'facebook', 'tiktok'],
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
          'instagram': 'public',
          'twitter': 'public',
          'facebook': 'public',
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

  /// CRITICAL: Ensures media is included when available
  void _ensureMediaInclusion(
    Map<String, dynamic> result,
    Map<String, dynamic> mediaContext,
    List<MediaItem>? preSelectedMedia,
    String transcription,
    List<String> fallbacksApplied,
  ) {
    final contentMedia = result['content']['media'] as List<dynamic>;

    // Priority 1: Pre-selected media (user's explicit choice)
    if (preSelectedMedia != null && preSelectedMedia.isNotEmpty) {
      if (kDebugMode) {
        print('📎 Using ${preSelectedMedia.length} pre-selected media items');
      }

      result['content']['media'] = preSelectedMedia
          .map((media) => {
                'file_uri': media.fileUri,
                'mime_type': media.mimeType,
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
              })
          .toList();
      return;
    }

    // Priority 2: ChatGPT's media selection (if valid and not empty)
    if (contentMedia.isNotEmpty) {
      if (kDebugMode) {
        print('✅ Using ${contentMedia.length} ChatGPT-selected media items');
      }
      return; // Keep ChatGPT's selection
    }

    // Priority 3: Smart fallback to most recent media
    final recentMedia =
        mediaContext['media_context']?['recent_media'] as List<dynamic>? ?? [];

    if (recentMedia.isNotEmpty && _transcriptionSuggestsMedia(transcription)) {
      final latestMedia = recentMedia.first as Map<String, dynamic>;

      if (kDebugMode) {
        print('🔄 FALLBACK: Using most recent media as default');
        print('   File: ${latestMedia['file_uri']}');
        print(
            '   Reason: ChatGPT omitted media, but transcription suggests media is wanted');
      }

      result['content']
          ['media'] = [_convertMediaContextToMediaItem(latestMedia)];
      fallbacksApplied.add('used_latest_media');
      return;
    }

    if (kDebugMode) {
      print(
          '⚠️ No media included - no pre-selected, no ChatGPT selection, and transcription doesn\'t suggest media');
    }
  }

  /// Checks if transcription suggests the user wants media included
  bool _transcriptionSuggestsMedia(String transcription) {
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
      'this',
      'that',
      'my',
    ];

    return mediaKeywords.any((keyword) => lowerTranscription.contains(keyword));
  }

  /// Converts media context item to MediaItem format
  Map<String, dynamic> _convertMediaContextToMediaItem(
      Map<String, dynamic> contextItem) {
    final deviceMetadata =
        contextItem['device_metadata'] as Map<String, dynamic>? ?? {};

    return {
      'file_uri': contextItem['file_uri'] ?? '',
      'mime_type': contextItem['mime_type'] ?? 'image/jpeg',
      'device_metadata': {
        'creation_time':
            contextItem['timestamp'] ?? DateTime.now().toIso8601String(),
        'latitude': deviceMetadata['latitude'],
        'longitude': deviceMetadata['longitude'],
        'orientation': deviceMetadata['orientation'] ?? 1,
        'width': deviceMetadata['width'] ?? 0,
        'height': deviceMetadata['height'] ?? 0,
        'file_size_bytes': deviceMetadata['file_size_bytes'] ?? 0,
        'duration': deviceMetadata['duration'] ?? 0,
        'bitrate': deviceMetadata['bitrate'],
        'sampling_rate': deviceMetadata['sampling_rate'],
        'frame_rate': deviceMetadata['frame_rate'],
      },
    };
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
}
