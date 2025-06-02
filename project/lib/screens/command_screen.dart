import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/social_action.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/platform_toggle_row.dart';
import '../widgets/mic_button.dart';
import '../widgets/transcription_preview.dart';
import '../screens/media_selection_screen.dart';
import '../screens/review_post_screen.dart';
import '../screens/history_screen.dart';

class CommandScreen extends StatefulWidget {
  const CommandScreen({super.key});

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen> {
  final _record = Record();
  RecordingState _recordingState = RecordingState.idle;
  String _transcription = '';
  SocialAction? _currentAction;
  List<String> _selectedPlatforms = [];

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
  }

  @override
  void dispose() {
    _record.dispose();
    super.dispose();
  }

  Future<void> _loadUserPreferences() async {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final prefs = await firestoreService.getUserPreferences();
    
    setState(() {
      _selectedPlatforms = List<String>.from(prefs['default_platforms'] ?? []);
    });
  }

  Future<void> _startRecording() async {
    try {
      if (await _record.hasPermission()) {
        await _record.start();
        setState(() {
          _recordingState = RecordingState.recording;
          _transcription = '';
          _currentAction = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _record.stop();
      if (path == null) {
        throw Exception('Recording failed: no file path returned');
      }

      setState(() {
        _recordingState = RecordingState.processing;
      });

      // 1. Transcribe with Whisper
      final transcription = await _transcribeWithWhisper(path);
      setState(() {
        _transcription = transcription;
      });

      // 2. Generate JSON with ChatGPT
      final actionJson = await _getSocialActionJson(transcription);
      
      // 3. Parse JSON into SocialAction
      final action = SocialAction.fromJson(actionJson);
      
      // 4. Save to Firestore
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      await firestoreService.saveAction(actionJson);
      
      setState(() {
        _currentAction = action;
        _recordingState = RecordingState.ready;
      });
    } catch (e) {
      setState(() {
        _recordingState = RecordingState.idle;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processing failed: $e')),
      );
    }
  }

  Future<String> _transcribeWithWhisper(String audioPath) async {
    final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    
    if (apiKey == null) {
      throw Exception('OPENAI_API_KEY not found in .env file');
    }

    final request = http.MultipartRequest('POST', url)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
      })
      ..fields['model'] = 'whisper-1'
      ..files.add(await http.MultipartFile.fromPath('file', audioPath));

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    
    if (response.statusCode != 200) {
      throw Exception('Whisper API error: $responseBody');
    }
    
    final data = jsonDecode(responseBody);
    return data['text'] as String;
  }

  Future<Map<String, dynamic>> _getSocialActionJson(String transcription) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    
    if (apiKey == null) {
      throw Exception('OPENAI_API_KEY not found in .env file');
    }

    final systemPrompt = '''
You are EchoPost AI. 
Input: Plain text transcription from Whisper. 
Output: A valid JSON object with keys:
  "action_id": UUID v4 string
  "created_at": ISO timestamp string
  "platforms": ${jsonEncode(_selectedPlatforms)}
  "content": {
    "text": string,
    "hashtags": [string],
    "mentions": [string],
    "link": { url: string, title?: string, description?: string, thumbnail_url?: string } | null,
    "media": [
      {
        "file_uri": "device URI (content://… or file://…)",
        "mime_type": "image/jpeg" | "video/mp4" | …,
        "device_metadata": {
          "creation_time": ISO timestamp,
          "latitude": number | null,
          "longitude": number | null,
          "orientation": int,
          "width": int,
          "height": int,
          "file_size_bytes": int
        },
        "upload_url": null,
        "cdn_key": null,
        "caption": string | null
      }
    ]
  },
  "options": {
    "schedule": "now" | ISO timestamp,
    "location_tag": { name: string, latitude: number, longitude: number } | null,
    "visibility": { facebook?: string, instagram?: string, twitter?: string, tiktok?: string },
    "reply_to_post_id": { facebook?: string | null, instagram?: string | null, twitter?: string | null, tiktok?: string | null }
  },
  "platform_data": {
    "facebook": { post_as_page: bool, page_id: string, additional_fields: map } | null,
    "instagram": { post_type: "feed"|"story", carousel: { enabled: bool, order?: [int] }, ig_user_id: string } | null,
    "twitter": { alt_texts: [string], tweet_mode: "extended" } | null,
    "tiktok": { privacy: "public"|"private"|"friends", sound: { use_original_sound: bool, music_id?: string } } | null
  },
  "internal": {
    "retry_count": int,
    "user_preferences": { default_platforms: [string], default_hashtags: [string] },
    "media_index_id": string,
    "ui_flags": { is_editing_caption: bool, is_media_preview_open: bool }
  }
''';

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': transcription},
        ],
        'temperature': 0.2,
        'max_tokens': 512,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('ChatGPT API error: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'] as String;
    
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to parse JSON from ChatGPT response: $e');
    }
  }

  void _navigateToMediaSelection() {
    if (_currentAction == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaSelectionScreen(action: _currentAction!),
      ),
    ).then((updatedAction) {
      if (updatedAction != null) {
        setState(() {
          _currentAction = updatedAction as SocialAction;
        });
      }
    });
  }

  void _navigateToReviewPost() {
    if (_currentAction == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewPostScreen(action: _currentAction!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EchoPost'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HistoryScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              // Show user profile or sign out dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () {
                        context.read<AuthService>().signOut();
                        Navigator.pop(context);
                      },
                      child: const Text('SIGN OUT'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Platform toggle row
          PlatformToggleRow(
            selectedPlatforms: _selectedPlatforms,
            onPlatformsChanged: (platforms) {
              setState(() {
                _selectedPlatforms = platforms;
              });
            },
          ),
          
          // Transcription preview
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TranscriptionPreview(
                    transcription: _transcription,
                    isJsonReady: _currentAction != null,
                    hasMedia: _currentAction?.content.media.isNotEmpty ?? false,
                    onReviewMedia: _navigateToMediaSelection,
                    onPostNow: _navigateToReviewPost,
                  ),
                ],
              ),
            ),
          ),
          
          // Mic button
          Padding(
            padding: const EdgeInsets.only(bottom: 32.0),
            child: MicButton(
              state: _recordingState,
              onRecordStart: _startRecording,
              onRecordStop: _stopRecording,
            ),
          ),
        ],
      ),
    );
  }
}