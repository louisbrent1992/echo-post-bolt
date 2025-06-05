import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/social_action.dart';

class AIService extends ChangeNotifier {
  Future<SocialAction> processVoiceCommand(String transcription) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY not found in .env.local file');
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system',
              'content':
                  '''You are a social media assistant. Convert voice commands into structured social media posts.
Return a JSON object with this exact structure:
{
  "text": "the main post content",
  "hashtags": ["hashtag1", "hashtag2"],
  "mentions": ["@user1", "@user2"],
  "platforms": ["instagram", "facebook", "twitter", "tiktok"],
  "mediaQuery": "description of visual content to search for"
}

Extract hashtags without the # symbol. Include platform suggestions based on content type.
For mediaQuery, describe what visual content would complement the post.'''
            },
            {
              'role': 'user',
              'content': transcription,
            }
          ],
          'max_tokens': 500,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('OpenAI API error: ${response.body}');
      }

      final responseData = jsonDecode(response.body);
      final content = responseData['choices'][0]['message']['content'];

      // Parse the JSON response
      final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(content);
      if (jsonMatch == null) {
        throw Exception('Could not parse AI response');
      }

      final parsedContent = jsonDecode(jsonMatch.group(0)!);

      return SocialAction(
        actionId: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now().toIso8601String(),
        platforms: List<String>.from(parsedContent['platforms'] ?? []),
        content: Content(
          text: parsedContent['text'] ?? '',
          hashtags: List<String>.from(parsedContent['hashtags'] ?? []),
          mentions: List<String>.from(parsedContent['mentions'] ?? []),
          link: null,
          media: [],
        ),
        options: Options(
          schedule: 'now',
          locationTag: null,
          visibility: null,
          replyToPostId: null,
        ),
        platformData: PlatformData(
          facebook: null,
          instagram: null,
          twitter: null,
          tiktok: null,
        ),
        internal: Internal(
          retryCount: 0,
          userPreferences: UserPreferences(
            defaultPlatforms: [],
            defaultHashtags: [],
          ),
          mediaIndexId: null,
          uiFlags: UiFlags(
            isEditingCaption: false,
            isMediaPreviewOpen: false,
          ),
          aiGenerated: true,
          originalTranscription: transcription,
          fallbackReason: null,
        ),
        mediaQuery: parsedContent['mediaQuery'],
      );
    } catch (e) {
      throw Exception('Failed to process voice command: $e');
    }
  }
}
