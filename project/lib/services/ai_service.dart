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
      var mediaContext = _mediaCoordinator?.getMediaContextForAi() ?? {};

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
You are a JSON generator for the EchoPost app.

Your task is to generate a complete SocialAction object, formatted as JSON. This object will be used by the app to preview and post social media content based on a spoken command and available device media.

You will receive these fields from the user:
- "transcription": a string containing the spoken command
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

3. **MEDIA CONTEXT STRUCTURE:**
   The media_context.recent_media array contains objects with:
   - file_uri: Complete file path for the media
   - file_name: Just the filename 
   - mime_type: Media type (image/jpeg, video/mp4, etc.)
   - timestamp: Creation date/time (sorted newest first)
   - directory: Source directory path
   - device_metadata: Width, height, file size, etc.

4. **CONTENT.MEDIA ARRAY FORMAT:**
   When selecting media from context, create MediaItem objects like this:
   ```json
   {
     "file_uri": "file:///storage/emulated/0/DCIM/Camera/IMG_20241219_143022.jpg",
     "mime_type": "image/jpeg",
     "device_metadata": {
       "creation_time": "2024-12-19T14:30:22Z",
       "width": 3024,
       "height": 4032,
       "file_size_bytes": 2847293,
       "latitude": null,
       "longitude": null,
       "orientation": 1,
       "duration": 0,
       "bitrate": null,
       "sampling_rate": null,
       "frame_rate": null
     }
   }
   ```

5. **TEXT GENERATION:**
   - If user specifies post text, use it as content.text
   - If no text provided, generate engaging caption based on selected media or context
   - Never leave content.text empty - always provide meaningful text with hashtags

6. **MEDIA_QUERY FALLBACK:**
   Only create media_query when:
   - User requests specific media that's not in the context (e.g., "sunset photos from last week")
   - No media context is provided but media is clearly needed
   - User requests broad search (e.g., "photos with my dog")

**EXAMPLE WITH DIRECT MEDIA SELECTION:**
User says: "post my last picture"
If media_context.recent_media[0] exists, select it directly:

```json
{
  "action_id": "echo_1734624622000",
  "created_at": "2024-12-19T14:30:22Z",
  "platforms": ["instagram"],
  "content": {
    "text": "Capturing the moment ✨",
    "hashtags": ["photography", "memories"],
    "mentions": [],
    "link": null,
    "media": [
      {
        "file_uri": "file:///storage/emulated/0/DCIM/Camera/IMG_20241219_143022.jpg",
        "mime_type": "image/jpeg",
        "device_metadata": {
          "creation_time": "2024-12-19T14:30:22Z",
          "width": 3024,
          "height": 4032,
          "file_size_bytes": 2847293,
          "latitude": null,
          "longitude": null,
          "orientation": 1,
          "duration": 0,
          "bitrate": null,
          "sampling_rate": null,
          "frame_rate": null
        }
      }
    ]
  },
  "options": {
    "schedule": "now",
    "visibility": {
      "instagram": "public"
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
      "media_file_uri": "file:///storage/emulated/0/DCIM/Camera/IMG_20241219_143022.jpg",
      "video_thumbnail_uri": null,
      "video_file_uri": null,
      "audio_file_uri": null,
      "scheduled_time": null
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
    "original_transcription": "post my last picture",
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

**CRITICAL REQUIREMENTS:**
- Always return complete, valid JSON with ALL required fields
- Use exact field names (snake_case, not camelCase)
- When media context is available and user references it, SELECT from it directly
- Only create media_query as absolute last resort
- Never leave content.media empty if suitable media exists in context
- Always include all platform_data objects (facebook, instagram, twitter, tiktok) even if post_here is false
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
