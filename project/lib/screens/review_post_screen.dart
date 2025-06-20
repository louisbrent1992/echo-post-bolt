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
import '../services/firestore_service.dart';
import '../services/social_post_service.dart';
import '../services/ai_service.dart';
import '../services/media_coordinator.dart';
import '../screens/history_screen.dart';
import '../screens/command_screen.dart';
import '../widgets/post_content_box.dart';
import '../widgets/unified_action_button.dart';
import '../widgets/scheduling_status.dart';
import '../screens/media_selection_screen.dart';
import '../widgets/unified_media_buttons.dart';
import '../screens/directory_selection_screen.dart';

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
      if (kDebugMode) {
        print('Error initializing video: $e');
      }
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

  // Media coordinator for validation
  late final MediaCoordinator _mediaCoordinator;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaCoordinator = Provider.of<MediaCoordinator>(context, listen: false);
    _validateMediaOnLoad();
  }

  /// Validates media URIs when the screen loads
  Future<void> _validateMediaOnLoad() async {
    if (_action.content.media.isNotEmpty) {
      try {
        final recoveredAction =
            await _mediaCoordinator.recoverMediaState(_action);
        if (recoveredAction != null && recoveredAction != _action) {
          setState(() {
            _action = recoveredAction;
          });

          if (kDebugMode) {
            print('📊 Media validation completed on ReviewPostScreen load');
            print('   Valid media count: ${_action.content.media.length}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Media validation failed on load: $e');
        }
      }
    }
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
        backgroundColor: Colors.black.withValues(alpha: 0.9), // Dark background
        title:
            const Text('Edit Caption', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _captionController,
          style: const TextStyle(color: Colors.white), // White text
          decoration: InputDecoration(
            hintText: 'Enter your caption',
            hintStyle: TextStyle(color: Colors.white60), // Light hint text
            border: OutlineInputBorder(
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF0080)),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1), // Translucent fill
          ),
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _captionController.text),
            child:
                const Text('SAVE', style: TextStyle(color: Color(0xFFFF0080))),
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
            backgroundColor:
                Colors.black.withValues(alpha: 0.9), // Dark background
            title: const Text('Posting Results',
                style: TextStyle(color: Colors.white)),
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
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          platform.substring(0, 1).toUpperCase() +
                              platform.substring(1),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _postResults[platform]! ? 'Posted' : 'Failed',
                          style: const TextStyle(color: Colors.white70),
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
                child: const Text('OK',
                    style: TextStyle(color: Color(0xFFFF0080))),
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
        backgroundColor: Colors.black.withValues(alpha: 0.9), // Dark background
        title:
            const Text('Discard Post?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to discard this post?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD', style: TextStyle(color: Colors.red)),
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
    final aiService = Provider.of<AIService>(context, listen: false);
    try {
      if (kDebugMode) {
        print('🎵 Processing voice edit from: $audioPath');
      }

      // Transcribe the audio
      final transcription = await _transcribeWithWhisper(audioPath);

      if (kDebugMode) {
        print('📝 Voice edit transcription: "$transcription"');
      }

      final editInstruction = '''
Current post content: "${_action.content.text}"
Current hashtags: ${_action.content.hashtags}
User voice instruction: "$transcription"''';

      final updatedAction =
          await aiService.processVoiceCommand(editInstruction);
      if (mounted) {
        await _applyTextEdit(
            updatedAction.content.text, updatedAction.content.hashtags);
      }
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
          padding: const EdgeInsets.symmetric(horizontal: _spacing3),
          child: _buildHeader(),
        ),

        // Main content area (flexible with controlled spacing) - removed redundant platform indicators
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: _spacing4),

                // Media preview (if available) or placeholder
                _buildMediaSection(),

                // Post content box (main text/hashtags)
                PostContentBox(
                  action: _action,
                  isRecording: _isRecording,
                  isProcessingVoice: _isProcessingVoice,
                  onEditText: _editCaption,
                  onVoiceEdit:
                      _isRecording ? _stopVoiceRecording : _startVoiceRecording,
                ),

                const SizedBox(height: _spacing3),

                // Scheduling moved to bottom area for cleaner layout

                const SizedBox(height: _spacing6),
              ],
            ),
          ),
        ),

        // Bottom unified action area (scheduling + confirmation)
        SizedBox(
          height: 180, // Height to accommodate scheduling status + button
          child: Column(
            children: [
              // Scheduling status area (upper part)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Center(
                    child: SchedulingStatus(
                      schedule: _action.options.schedule,
                      onEditSchedule: _editSchedule,
                    ),
                  ),
                ),
              ),

              // Unified action button area (lower part)
              Expanded(
                flex: 3,
                child: SafeArea(
                  minimum: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: UnifiedActionButton(
                        state: UnifiedButtonState.confirmPost,
                        onConfirmPost: _confirmAndPost,
                        customLabel: 'Confirm & Post',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        const Expanded(
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
        const SizedBox(width: 40), // Balance the back button
      ],
    );
  }

  Widget _buildMediaSection() {
    return Column(
      children: [
        // Media preview area - full width, edge to edge
        Container(
          width: double.infinity, // Full width
          height: 250, // Increased height for more immersive feel
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _action.content.media.isEmpty
              ? _buildMediaPlaceholder()
              : _buildMediaPreview(),
        ),

        const SizedBox(height: _spacing2),

        // Unified media buttons row (Directory + Media selection)
        UnifiedMediaButtons(
          onDirectorySelection: _navigateToDirectorySelection,
          onMediaSelection: _navigateToMediaSelection,
          hasMedia: _action.content.media.isNotEmpty,
        ),

        const SizedBox(height: _spacing3),
      ],
    );
  }

  Widget _buildMediaPreview() {
    final mediaItem = _action.content.media.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');

    return Stack(
      fit: StackFit.expand,
      children: [
        isVideo
            ? VideoPlayerWidget(fileUri: mediaItem.fileUri)
            : Image.file(
                File(Uri.parse(mediaItem.fileUri).path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildVideoPlaceholder();
                },
              ),

        // Media info overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(_spacing2),
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
    );
  }

  Widget _buildMediaPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image,
              color: Colors.grey.shade400,
              size: 48,
            ),
            const SizedBox(height: _spacing2),
            Text(
              'Your image will appear here',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: _spacing1),
            Text(
              'Use the buttons below to select directory and media',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam,
              color: Colors.grey.shade400,
              size: 40,
            ),
            const SizedBox(height: _spacing1),
            Text(
              'Video Preview',
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

  Future<void> _navigateToMediaSelection() async {
    try {
      final updatedAction = await Navigator.push<SocialAction>(
        context,
        MaterialPageRoute(
          builder: (context) => MediaSelectionScreen(
            action: _action,
          ),
        ),
      );

      if (updatedAction != null) {
        // Update the local state with the new action
        setState(() {
          _action = updatedAction;
        });

        // Only update Firestore if this is not a temporary action
        final isTemporaryAction = _action.actionId.startsWith('temp_');
        if (!isTemporaryAction) {
          try {
            // Update Firestore
            final firestoreService =
                Provider.of<FirestoreService>(context, listen: false);
            await firestoreService.updateAction(
              _action.actionId,
              _action.toJson(),
            );

            if (kDebugMode) {
              print(
                  '💾 Media updated in Firestore for action: ${_action.actionId}');
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Media updated successfully! 🎉'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (firestoreError) {
            if (kDebugMode) {
              print('❌ Firestore update failed: $firestoreError');
            }
            // Still show success since local state was updated
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Media updated locally (sync pending)'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        } else {
          if (kDebugMode) {
            print(
                '🔄 Skipping Firestore update for temporary action: ${_action.actionId}');
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Media updated! 🎉'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Media selection navigation error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update media: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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

  String _formatDateTime(DateTime dateTime) {
    final formatter = DateFormat('MMM d, yyyy \'at\' h:mm a');
    return formatter.format(dateTime);
  }

  void _navigateToDirectorySelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DirectorySelectionScreen(),
      ),
    );
  }
}
