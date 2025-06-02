import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

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
  final _record = AudioRecorder();
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
    try {
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);
      final prefs = await firestoreService.getUserPreferences();

      if (mounted) {
        setState(() {
          _selectedPlatforms = List<String>.from(
              prefs['default_platforms'] ?? ['instagram', 'twitter']);
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading user preferences: $e');
      }
      // Set default platforms if loading fails
      if (mounted) {
        setState(() {
          _selectedPlatforms = ['instagram', 'twitter'];
        });
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      // Check permissions first
      if (!(await _record.hasPermission())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Microphone permission denied. Please grant permission in settings.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Get proper temp directory for the platform
      final tempDir = await getTemporaryDirectory();
      final recordingPath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (kDebugMode) {
        print('Starting recording to path: $recordingPath');
      }

      // Start recording with proper configuration
      await _record.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: recordingPath);

      if (mounted) {
        setState(() {
          _recordingState = RecordingState.recording;
          _transcription = '';
          _currentAction = null;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error starting recording: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _record.stop();
      if (path == null || path.isEmpty) {
        throw Exception('Recording failed: no file path returned');
      }

      // Verify file exists
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('Recording file does not exist at path: $path');
      }

      if (kDebugMode) {
        print('Recording stopped, file saved to: $path');
        print('File size: ${await file.length()} bytes');
      }

      if (mounted) {
        setState(() {
          _recordingState = RecordingState.processing;
        });
      }

      // Process the recording
      await _processRecording(path);
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping recording: $e');
      }
      if (mounted) {
        setState(() {
          _recordingState = RecordingState.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _processRecording(String audioPath) async {
    try {
      // Get service reference before async operations
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);

      // 1. Transcribe with Whisper
      final transcription = await _transcribeWithWhisper(audioPath);

      if (mounted) {
        setState(() {
          _transcription = transcription;
        });
      }

      if (transcription.trim().isEmpty) {
        throw Exception('No speech detected in recording');
      }

      // 2. Generate simplified action JSON
      final actionJson = await _generateSimpleAction(transcription);

      // 3. Parse JSON into SocialAction
      final action = SocialAction.fromJson(actionJson);

      // 4. Save to Firestore
      await firestoreService.saveAction(actionJson);

      if (mounted) {
        setState(() {
          _currentAction = action;
          _recordingState = RecordingState.ready;
        });
      }

      // Clean up the audio file
      try {
        await File(audioPath).delete();
      } catch (e) {
        if (kDebugMode) {
          print('Warning: Could not delete audio file: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing recording: $e');
      }
      if (mounted) {
        setState(() {
          _recordingState = RecordingState.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processing failed: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<String> _transcribeWithWhisper(String audioPath) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
          'OPENAI_API_KEY not found in .env.local file. Please add your OpenAI API key.');
    }

    try {
      final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', url)
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
        })
        ..fields['model'] = 'whisper-1'
        ..fields['language'] = 'en'
        ..files.add(await http.MultipartFile.fromPath('file', audioPath));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception(
            'Whisper API error (${response.statusCode}): $responseBody');
      }

      final data = jsonDecode(responseBody);
      final text = data['text'] as String? ?? '';

      if (kDebugMode) {
        print('Transcription successful: "$text"');
      }
      return text.trim();
    } catch (e) {
      throw Exception('Transcription failed: $e');
    }
  }

  // Simplified action generation to avoid complex JSON parsing issues
  Future<Map<String, dynamic>> _generateSimpleAction(
      String transcription) async {
    const uuid = Uuid();
    final now = DateTime.now();

    // Create a simple, reliable action structure
    return {
      'action_id': uuid.v4(),
      'created_at': now.toIso8601String(),
      'platforms': _selectedPlatforms,
      'content': {
        'text': transcription,
        'hashtags': <String>[],
        'mentions': <String>[],
        'link': null,
        'media': <Map<String, dynamic>>[],
      },
      'options': {
        'schedule': 'now',
        'location_tag': null,
        'visibility': <String, String?>{},
        'reply_to_post_id': <String, String?>{},
      },
      'platform_data': {
        'facebook': null,
        'instagram': null,
        'twitter': null,
        'tiktok': null,
      },
      'internal': {
        'retry_count': 0,
        'user_preferences': {
          'default_platforms': _selectedPlatforms,
          'default_hashtags': <String>[],
        },
        'media_index_id': null,
        'ui_flags': {
          'is_editing_caption': false,
          'is_media_preview_open': false,
        },
      },
    };
  }

  void _navigateToMediaSelection() {
    if (_currentAction == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaSelectionScreen(action: _currentAction!),
      ),
    ).then((updatedAction) {
      if (updatedAction != null && mounted) {
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
