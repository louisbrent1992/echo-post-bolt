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

  /// Set the MediaCoordinator instance (called after both services are created)
  void setMediaCoordinator(MediaCoordinator mediaCoordinator) {
    _mediaCoordinator = mediaCoordinator;
  }

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

  Future<SocialAction> processVoiceCommand(String transcription) async {
    if (kDebugMode) {
      print('🎯 Processing voice command: "$transcription"');
    }

    try {
      // Get media context for the prompt
      final mediaContext = _mediaCoordinator?.getMediaContextForAi();

      final messages = [
        {
          'role': 'system',
          'content': '''
You are a JSON generator for the EchoPost app.

Your task is to generate a complete SocialAction object, formatted as JSON. This object will be used by the app to preview and post social media content based on a spoken command and available device media.

You will receive two fields from the user:
- "transcription": a string containing the spoken command
- "media_context": a list of media metadata representing local image, video, or audio files

You must:
1. Interpret the transcription as an intent to create a social post. Extract any spoken content, hashtags, mentions, and platform names.
2. If the user specifies post text, use it as content.text. **If no post text is provided, generate an appropriate caption based on the available media_context. This text must be relevant, engaging, and accompanied by suitable hashtags. Do not leave content.text null or empty. This applies across all platforms.**
3. Extract any media references from the transcription (e.g., "post the sunset photo"), match against media_context, and include selected items in content.media.
4. If media is likely required but cannot be matched exactly, set media_query with appropriate search parameters:
   - directory_path: The most relevant directory based on the user's request
   - search_terms: Keywords from the user's description (e.g., ["sunset", "beach"])
   - date_range: If time is mentioned (e.g., "from yesterday")
   - media_types: Required media types (e.g., ["image", "video"])
   - location_query: If location is mentioned
5. Always return all platform_data keys in the order: facebook, instagram, twitter, tiktok.
6. Each platform object must include `"post_here": true` or `false`.
7. If a platform is not used, still return its object with `"post_here": false` and all other internal fields set to null or defaults.

Return ONLY a valid JSON object. No extra commentary or explanation.

IMPORTANT: Use the exact field names shown below (snake_case, not camelCase).

EXAMPLE with media_query:
{
  "action_id": "echo_1721407200000",
  "created_at": "2025-06-19T15:30:00Z",
  "platforms": ["instagram", "twitter"],
  "content": {
    "text": "A perfect evening by the lake.",
    "hashtags": ["sunset", "nature"],
    "mentions": [],
    "link": null,
    "media": []
  },
  "options": {
    "schedule": "now",
    "visibility": {
      "instagram": "public",
      "twitter": "public"
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
      "media_file_uri": "file:///storage/emulated/0/DCIM/Camera/IMG_1234.jpg",
      "video_thumbnail_uri": null,
      "video_file_uri": null,
      "audio_file_uri": null,
      "scheduled_time": null
    },
    "twitter": {
      "post_here": true,
      "alt_texts": ["Sunset by the lake"],
      "tweet_mode": "extended",
      "media_type": "image",
      "media_file_uri": "file:///storage/emulated/0/DCIM/Camera/IMG_1234.jpg",
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
    "original_transcription": "Post the sunset photo from yesterday to Instagram and Twitter with the caption 'A perfect evening by the lake.'",
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
  "media_query": {
    "directory_path": "/storage/emulated/0/DCIM/Camera",
    "search_terms": ["sunset", "lake", "evening"],
    "date_range": {
      "start_date": "2025-06-18T00:00:00Z",
      "end_date": "2025-06-18T23:59:59Z"
    },
    "media_types": ["image"],
    "location_query": null
  }
}
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
        print('📝 ChatGPT response: $content');
      }

      // Ensure content is a Map<String, dynamic>
      Map<String, dynamic> actionJson;
      if (content is String) {
        try {
          actionJson = json.decode(content);
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed to parse content as JSON string: $e');
            print('📝 Raw content: $content');
          }
          throw Exception('Invalid JSON response from ChatGPT');
        }
      } else if (content is Map<String, dynamic>) {
        actionJson = content;
      } else {
        throw Exception(
            'Unexpected response type from ChatGPT: ${content.runtimeType}');
      }

      // Validate required fields
      final requiredFields = [
        'action_id',
        'created_at',
        'platforms',
        'content',
        'options',
        'platform_data',
        'internal'
      ];

      for (final field in requiredFields) {
        if (!actionJson.containsKey(field)) {
          throw Exception('Missing required field: $field');
        }
      }

      // Create SocialAction from validated JSON
      return SocialAction.fromJson(actionJson);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in processVoiceCommand: $e');
        print('📊 Stack trace: ${StackTrace.current}');
      }
      rethrow;
    }
  }
}
