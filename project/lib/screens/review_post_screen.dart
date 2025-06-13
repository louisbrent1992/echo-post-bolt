import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

import '../models/social_action.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/social_post_service.dart';
import '../services/ai_service.dart';
import '../screens/history_screen.dart';
import '../screens/command_screen.dart';
import '../widgets/post_content_box.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String fileUri;
  const VideoPlayerWidget({required this.fileUri, super.key});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller =
          VideoPlayerController.file(File(Uri.parse(widget.fileUri).path))
            ..initialize().then((_) {
              if (mounted) {
                setState(() {
                  _isInitialized = true;
                });
              }
            });
    } catch (e) {
      print('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              if (_controller.value.isPlaying) {
                _controller.pause();
              } else {
                _controller.play();
              }
            });
          },
          icon: Icon(
            _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 50,
          ),
        ),
      ],
    );
  }
}

class ReviewPostScreen extends StatefulWidget {
  final SocialAction action;

  const ReviewPostScreen({
    super.key,
    required this.action,
  });

  @override
  State<ReviewPostScreen> createState() => _ReviewPostScreenState();
}

class _ReviewPostScreenState extends State<ReviewPostScreen> {
  late SocialAction _action;
  bool _isPosting = false;
  Map<String, bool> _postResults = {};
  final TextEditingController _captionController = TextEditingController();

  // Voice recording for interactive editing
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  String? _currentRecordingPath;

  // Grid spacing constants (multiples of 6 for consistency)
  static const double _gridUnit = 6.0;
  static const double _spacing1 = _gridUnit; // 6px
  static const double _spacing2 = _gridUnit * 2; // 12px
  static const double _spacing3 = _gridUnit * 3; // 18px
  static const double _spacing4 = _gridUnit * 4; // 24px
  static const double _spacing5 = _gridUnit * 5; // 30px
  static const double _spacing6 = _gridUnit * 6; // 36px

  @override
  void initState() {
    super.initState();
    _action = widget.action;
    _captionController.text = _action.content.text;
  }

  @override
  void dispose() {
    _captionController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _editCaption() async {
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Caption'),
        content: TextField(
          controller: _captionController,
          decoration: const InputDecoration(
            hintText: 'Enter your caption',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _captionController.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (result != null) {
      final updatedAction = SocialAction(
        actionId: _action.actionId,
        createdAt: _action.createdAt,
        platforms: _action.platforms,
        content: Content(
          text: result,
          hashtags: _action.content.hashtags,
          mentions: _action.content.mentions,
          link: _action.content.link,
          media: _action.content.media,
        ),
        options: _action.options,
        platformData: _action.platformData,
        internal: _action.internal,
      );

      await firestoreService.updateAction(
        updatedAction.actionId,
        updatedAction.toJson(),
      );

      if (mounted) {
        setState(() {
          _action = updatedAction;
          _captionController.text = result;
        });
      }
    }
  }

  Future<void> _editSchedule() async {
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);

    final now = DateTime.now();
    final initialDate = _action.options.schedule == 'now'
        ? now
        : DateTime.parse(_action.options.schedule);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );

      if (pickedTime != null) {
        final scheduledDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        final updatedAction = SocialAction(
          actionId: _action.actionId,
          createdAt: _action.createdAt,
          platforms: _action.platforms,
          content: _action.content,
          options: Options(
            schedule: scheduledDateTime.toIso8601String(),
            locationTag: _action.options.locationTag,
            visibility: _action.options.visibility,
            replyToPostId: _action.options.replyToPostId,
          ),
          platformData: _action.platformData,
          internal: _action.internal,
        );

        await firestoreService.updateAction(
          updatedAction.actionId,
          updatedAction.toJson(),
        );

        if (mounted) {
          setState(() {
            _action = updatedAction;
          });
        }
      }
    }
  }

  Future<void> _confirmAndPost() async {
    final socialPostService =
        Provider.of<SocialPostService>(context, listen: false);

    setState(() {
      _isPosting = true;
      _postResults = {};
    });

    try {
      final results = await socialPostService.postToAllPlatforms(_action);

      setState(() {
        _postResults = results;
        _isPosting = false;
      });

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Posting Results'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final platform in _postResults.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(
                          _postResults[platform]!
                              ? Icons.check_circle
                              : Icons.error,
                          color: _postResults[platform]!
                              ? Colors.green
                              : Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          platform.substring(0, 1).toUpperCase() +
                              platform.substring(1),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _postResults[platform]! ? 'Posted' : 'Failed',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (_postResults.values.every((success) => success)) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HistoryScreen(),
                      ),
                      (route) => route.isFirst,
                    );
                  }
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isPosting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Posting failed: $e')),
        );
      }
    }
  }

  Future<void> _cancelPost() async {
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Post?'),
        content: const Text('Are you sure you want to discard this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await firestoreService.deleteAction(_action.actionId);
      if (mounted) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const CommandScreen(),
          ),
          (route) => route.isFirst,
        );
      }
    }
  }

  // Voice recording methods for interactive editing
  Future<void> _startVoiceRecording() async {
    if (_isRecording || _isProcessingVoice) return;

    try {
      // Check permissions
      if (!await _audioRecorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Get temporary directory for recording
      final tempDir = await getTemporaryDirectory();
      final m4aPath =
          '${tempDir.path}/voice_edit_${DateTime.now().millisecondsSinceEpoch}.m4a';

      _currentRecordingPath = m4aPath;

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: m4aPath,
      );

      setState(() {
        _isRecording = true;
      });

      if (kDebugMode) {
        print('🎙️ Started voice recording for text editing');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to start voice recording: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopVoiceRecording() async {
    if (!_isRecording) return;

    try {
      await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessingVoice = true;
      });

      if (_currentRecordingPath != null) {
        await _processVoiceEdit(_currentRecordingPath!);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to stop voice recording: $e');
      }
      setState(() {
        _isRecording = false;
        _isProcessingVoice = false;
      });
    }
  }

  Future<void> _processVoiceEdit(String audioPath) async {
    try {
      if (kDebugMode) {
        print('🎵 Processing voice edit from: $audioPath');
      }

      // Transcribe the audio
      final transcription = await _transcribeWithWhisper(audioPath);

      if (kDebugMode) {
        print('📝 Voice edit transcription: "$transcription"');
      }

      // Use AI to process the voice edit instruction
      final aiService = Provider.of<AIService>(context, listen: false);
      final editInstruction = '''
Current post content: "${_action.content.text}"
Current hashtags: ${_action.content.hashtags}
User voice instruction: "$transcription"

Update the post with the user's instruction. If they want to add text, append or replace as appropriate. If they mention hashtags, add them. Return a JSON with updated text and hashtags only:
{
  "text": "updated text content",
  "hashtags": ["updated", "hashtags"]
}
''';

      final response = await _sendEditRequest(editInstruction);
      await _applyTextEdit(response['text'], response['hashtags']);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Voice edit processing error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice edit failed: $e')),
        );
      }
    } finally {
      setState(() {
        _isProcessingVoice = false;
      });
    }
  }

  Future<String> _transcribeWithWhisper(String audioPath) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY not found');
    }

    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('Audio file does not exist');
    }

    final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
    final request = http.MultipartRequest('POST', url);

    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'whisper-1';
    request.fields['response_format'] = 'json';
    request.fields['language'] = 'en';
    request.fields['temperature'] = '0.0';

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      audioPath,
      filename: 'audio.m4a',
    );
    request.files.add(multipartFile);

    final response = await request.send().timeout(const Duration(seconds: 30));
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception('Whisper API error: $responseBody');
    }

    final jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
    final transcription = jsonResponse['text'] as String? ?? '';

    // Clean up audio file
    try {
      await file.delete();
    } catch (_) {}

    return transcription.trim();
  }

  Future<Map<String, dynamic>> _sendEditRequest(String instruction) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY not found');
    }

    final requestBody = {
      'model': 'gpt-4o-mini',
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a social media post editor. Update posts based on user voice instructions. Return only valid JSON with "text" and "hashtags" fields.',
        },
        {
          'role': 'user',
          'content': instruction,
        }
      ],
      'max_tokens': 256,
      'temperature': 0.1,
      'response_format': {'type': 'json_object'},
    };

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception('ChatGPT API error: ${response.body}');
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = responseData['choices'] as List;
    final content = choices[0]['message']['content'] as String;

    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<void> _applyTextEdit(String newText, List<dynamic> newHashtags) async {
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);

    final updatedAction = SocialAction(
      actionId: _action.actionId,
      createdAt: _action.createdAt,
      platforms: _action.platforms,
      content: Content(
        text: newText.trim(),
        hashtags: newHashtags
            .map((h) => h.toString().replaceAll('#', '').trim())
            .toList(),
        mentions: _action.content.mentions,
        link: _action.content.link,
        media: _action.content.media,
      ),
      options: _action.options,
      platformData: _action.platformData,
      internal: _action.internal,
    );

    // Update in Firestore
    await firestoreService.updateAction(
        _action.actionId, updatedAction.toJson());

    // Update local state
    setState(() {
      _action = updatedAction;
      _captionController.text = newText.trim();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post updated with voice edit! 🎉'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isPosting
          ? _buildLoadingView()
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Color(0xFF1A1A1A),
                  ],
                ),
              ),
              child: SafeArea(
                child: _buildGridLayout(),
              ),
            ),
    );
  }

  Widget _buildGridLayout() {
    return Column(
      children: [
        // Header section (60px height)
        Container(
          height: 60,
          padding: EdgeInsets.symmetric(horizontal: _spacing3),
          child: _buildHeader(),
        ),

        // Social platforms section (72px height with spacing)
        Container(
          height: 72,
          padding: EdgeInsets.symmetric(horizontal: _spacing4),
          margin: EdgeInsets.only(top: _spacing2),
          child: _buildPlatformsRow(),
        ),

        // Main content area (flexible with controlled spacing)
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                SizedBox(height: _spacing4),

                // Media preview (if available)
                if (_action.content.media.isNotEmpty) ...[
                  _buildMediaPreview(),
                  SizedBox(height: _spacing3),
                ],

                // Post content box (main text/hashtags)
                PostContentBox(
                  action: _action,
                  isRecording: _isRecording,
                  isProcessingVoice: _isProcessingVoice,
                  onEditText: _editCaption,
                  onVoiceEdit:
                      _isRecording ? _stopVoiceRecording : _startVoiceRecording,
                ),

                SizedBox(height: _spacing3),

                // Schedule info
                _buildScheduleInfo(),

                SizedBox(height: _spacing6),
              ],
            ),
          ),
        ),

        // Bottom action bar (fixed height: 102px)
        Container(
          height: 102,
          padding: EdgeInsets.all(_spacing3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(_spacing3),
              topRight: Radius.circular(_spacing3),
            ),
          ),
          child: _buildActionButtons(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
        ),
        Expanded(
          child: Text(
            'Review Your Post',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(width: 40), // Balance the back button
      ],
    );
  }

  Widget _buildPlatformsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.share,
              color: Colors.white70,
              size: 14,
            ),
            SizedBox(width: _spacing1),
            Text(
              'Posting to:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        SizedBox(height: _spacing1),
        Consumer<AuthService>(
          builder: (context, authService, _) {
            return Wrap(
              spacing: _spacing1,
              runSpacing: _spacing1,
              children: _action.platforms.map((platform) {
                return FutureBuilder<bool>(
                  future: authService.isPlatformConnected(platform),
                  builder: (context, snapshot) {
                    final isConnected = snapshot.data ?? false;

                    return Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: _spacing2,
                        vertical: _spacing1,
                      ),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? _getPlatformColor(platform).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(_spacing2),
                        border: Border.all(
                          color: isConnected
                              ? _getPlatformColor(platform)
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _getPlatformIcon(platform),
                          SizedBox(width: _spacing1),
                          Text(
                            platform.substring(0, 1).toUpperCase() +
                                platform.substring(1),
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isConnected ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMediaPreview() {
    if (_action.content.media.isEmpty) return const SizedBox.shrink();

    final mediaItem = _action.content.media.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');

    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      height: 200,
      margin: EdgeInsets.symmetric(horizontal: _spacing3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(_spacing3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_spacing3),
        child: Stack(
          fit: StackFit.expand,
          children: [
            isVideo
                ? VideoPlayerWidget(fileUri: mediaItem.fileUri)
                : Image.file(
                    File(Uri.parse(mediaItem.fileUri).path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildMediaPlaceholder(isVideo);
                    },
                  ),

            // Media info overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(_spacing2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  '${mediaItem.deviceMetadata.width} × ${mediaItem.deviceMetadata.height}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPlaceholder(bool isVideo) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isVideo ? Icons.videocam : Icons.image,
              color: Colors.grey.shade400,
              size: 40,
            ),
            SizedBox(height: _spacing1),
            Text(
              isVideo ? 'Video Preview' : 'Image Preview',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleInfo() {
    final isNow = _action.options.schedule == 'now';
    final scheduleText = isNow
        ? 'Posting immediately'
        : 'Scheduled for ${_formatDateTime(DateTime.parse(_action.options.schedule))}';

    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      margin: EdgeInsets.symmetric(horizontal: _spacing3),
      padding: EdgeInsets.all(_spacing3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(_spacing2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isNow ? Icons.send : Icons.schedule,
            color: const Color(0xFFFF0080),
            size: 18,
          ),
          SizedBox(width: _spacing2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Schedule',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  scheduleText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _editSchedule,
            child: Text(
              'Change',
              style: TextStyle(
                color: const Color(0xFFFF0080),
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Posting to your social networks...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we process your request',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 42, // Fixed height for main button
          child: ElevatedButton.icon(
            icon: const Icon(Icons.send, color: Colors.white, size: 18),
            label: const Text(
              'Confirm & Post',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            onPressed: _confirmAndPost,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0080),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_spacing2),
              ),
              elevation: 2,
            ),
          ),
        ),
        SizedBox(height: _spacing2),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36, // Fixed height for secondary buttons
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text(
                    'Edit Media',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_spacing2),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: _spacing2),
            Expanded(
              child: SizedBox(
                height: 36, // Fixed height for secondary buttons
                child: TextButton.icon(
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text(
                    'Cancel Post',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  onPressed: _cancelPost,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_spacing2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _getPlatformIcon(String platform) {
    IconData icon;
    switch (platform) {
      case 'facebook':
        icon = Icons.facebook;
        break;
      case 'instagram':
        icon = Icons.camera_alt;
        break;
      case 'twitter':
        icon = Icons.flutter_dash;
        break;
      case 'tiktok':
        icon = Icons.music_note;
        break;
      default:
        icon = Icons.public;
    }

    return Icon(
      icon,
      size: 14,
      color: _getPlatformColor(platform),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'facebook':
        return Colors.blue.shade800;
      case 'instagram':
        return Colors.pink.shade400;
      case 'twitter':
        return Colors.lightBlue.shade400;
      case 'tiktok':
        return Colors.black87;
      default:
        return Colors.grey.shade600;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final formatter = DateFormat('MMM d, yyyy \'at\' h:mm a');
    return formatter.format(dateTime);
  }
}
