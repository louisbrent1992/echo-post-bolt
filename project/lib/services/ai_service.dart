import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/social_action.dart';
import 'media_metadata_service.dart';

class AIService {
  static const String _openai_api_url =
      'https://api.openai.com/v1/chat/completions';
  final String _api_key;
  final MediaMetadataService _media_metadata_service;

  AIService(this._api_key, this._media_metadata_service);

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
      final media_context = _media_metadata_service.get_media_context_for_ai();

      final messages = [
        {
          'role': 'system',
          'content':
              '''You are a JSON generator that creates structured social media post actions.

IMPORTANT: You must return ONLY a valid JSON object with proper nested structures. Do not include any explanatory text.
Every object field must be properly nested - never return flat string values where an object is expected.

Required structure (EXACT format required):
{
  "actionId": "echo_${DateTime.now().millisecondsSinceEpoch}",
  "createdAt": "${DateTime.now().toIso8601String()}",
  "platforms": ["instagram", "twitter"],  // Array of platform names
  "content": {  // Must be an object with these exact fields
    "text": "Your post text here",
    "hashtags": ["tag1", "tag2"],  // Array of strings without # symbol
    "mentions": ["user1", "user2"],  // Array of strings without @ symbol
    "media": [  // Array of media objects
      {
        "fileUri": "file:///path/to/media",
        "mimeType": "image/jpeg",
        "deviceMetadata": {  // Required nested object
          "creationTime": "2024-03-14T12:00:00Z",
          "width": 1920,
          "height": 1080,
          "orientation": 1,
          "fileSizeBytes": 1000000
        }
      }
    ]
  },
  "options": {  // Must be an object
    "schedule": "now",
    "visibility": "public",
    "locationTag": null,  // Optional nested object
    "replyToPostId": null
  },
  "platformData": {  // Must be an object with optional platform-specific settings
    "instagram": {
      "postType": "feed",
      "shareToStory": false
    },
    "twitter": {
      "altText": "",
      "threadMode": false
    }
  },
  "internal": {  // Must be an object with these exact fields
    "retryCount": 0,
    "userPreferences": {  // Required nested object
      "defaultPlatforms": [],
      "defaultHashtags": []
    },
    "uiFlags": {  // Required nested object
      "isEditingCaption": false,
      "isMediaPreviewOpen": false
    },
    "aiGenerated": true,
    "originalTranscription": "transcription here"
  },
  "mediaQuery": null  // Optional string for media search
}

VALIDATION RULES:
1. All object fields must be proper nested objects, never plain strings
2. All array fields must be proper arrays, never comma-separated strings
3. Platform names must be lowercase: "instagram", "twitter", "facebook", "tiktok"
4. No # symbols in hashtags array
5. No @ symbols in mentions array
6. All nested objects must include ALL required fields
7. Use null for optional fields, not empty strings
8. Dates must be in ISO 8601 format
9. Boolean values must be true/false, not strings
10. Numbers must be numeric values, not strings'''
        },
        {
          'role': 'user',
          'content': json.encode({
            'transcription': transcription,
            'media_context': media_context,
          })
        }
      ];

      final response = await http.post(
        Uri.parse(_openai_api_url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_api_key',
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

      final json_response = json.decode(response.body);
      final content = json_response['choices'][0]['message']['content'];

      if (kDebugMode) {
        print('📝 ChatGPT response: $content');
      }

      // Ensure content is a Map<String, dynamic>
      Map<String, dynamic> action_json;
      if (content is String) {
        try {
          action_json = json.decode(content);
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed to parse content as JSON string: $e');
            print('📝 Raw content: $content');
          }
          throw Exception('Invalid JSON response from ChatGPT');
        }
      } else if (content is Map<String, dynamic>) {
        action_json = content;
      } else {
        throw Exception(
            'Unexpected response type from ChatGPT: ${content.runtimeType}');
      }

      // Validate required fields
      final requiredFields = [
        'actionId',
        'createdAt',
        'platforms',
        'content',
        'options',
        'platformData',
        'internal'
      ];

      for (final field in requiredFields) {
        if (!action_json.containsKey(field)) {
          throw Exception('Missing required field: $field');
        }
      }

      // Ensure content object has required fields
      final content_obj = action_json['content'];
      if (content_obj is! Map<String, dynamic>) {
        throw Exception('Content field must be an object');
      }

      final contentFields = ['text', 'hashtags', 'mentions', 'media'];
      for (final field in contentFields) {
        if (!content_obj.containsKey(field)) {
          content_obj[field] = field == 'text' ? '' : [];
        }
      }

      // Ensure internal object has required fields
      final internal = action_json['internal'];
      if (internal is! Map<String, dynamic>) {
        throw Exception('Internal field must be an object');
      }

      internal['retryCount'] = 0;
      internal['aiGenerated'] = true;
      internal['originalTranscription'] = transcription;

      if (!internal.containsKey('userPreferences')) {
        internal['userPreferences'] = {
          'defaultPlatforms': [],
          'defaultHashtags': []
        };
      }

      if (!internal.containsKey('uiFlags')) {
        internal['uiFlags'] = {
          'isEditingCaption': false,
          'isMediaPreviewOpen': false
        };
      }

      // Create SocialAction from validated JSON
      return SocialAction.fromJson(action_json);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in processVoiceCommand: $e');
        print('📊 Stack trace: ${StackTrace.current}');
      }
      rethrow;
    }
  }
}
