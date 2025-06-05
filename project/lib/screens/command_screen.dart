import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../models/social_action.dart';
import '../services/ai_service.dart';
import '../widgets/mic_button.dart';
import '../widgets/social_icon.dart';
import '../widgets/transcription_dialog.dart';
import '../screens/media_selection_screen.dart';
import '../screens/review_post_screen.dart';
import '../screens/history_screen.dart';
import '../services/firestore_service.dart';

class CommandScreen extends StatefulWidget {
  const CommandScreen({super.key});

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen>
    with TickerProviderStateMixin {
  final AudioRecorder _record = AudioRecorder();

  RecordingState _recordingState = RecordingState.idle;
  String _transcription = '';
  SocialAction? _currentAction;
  String? _currentRecordingPath;

  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

  Timer? _recordingTimer;
  int _recordingDuration = 0;
  final int _maxRecordingDuration = 30; // 30 seconds max

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _backgroundController,
      curve: Curves.easeInOut,
    ));

    _backgroundController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _recordingTimer?.cancel();
    _record.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _record.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
      return;
    }

    try {
      setState(() {
        _recordingState = RecordingState.recording;
      });

      final tempDir = await getTemporaryDirectory();
      final m4aPath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _record.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: m4aPath,
      );

      _currentRecordingPath = m4aPath;
      _startRecordingTimer();
    } catch (e) {
      setState(() {
        _recordingState = RecordingState.idle;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_recordingState != RecordingState.recording) return;

    try {
      await _record.stop();
      _stopRecordingTimer();

      setState(() {
        _recordingState = RecordingState.processing;
      });

      if (_currentRecordingPath != null) {
        final transcription =
            await _transcribeWithWhisper(_currentRecordingPath!);
        await _processTranscription(transcription);
      }
    } catch (e) {
      setState(() {
        _recordingState = RecordingState.idle;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process recording: $e')),
        );
      }
    }
  }

  void _startRecordingTimer() {
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });

      if (_recordingDuration >= _maxRecordingDuration) {
        _stopRecording();
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
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
        throw Exception('Whisper API error: $responseBody');
      }

      // Parse JSON response
      final jsonResponse = Map<String, dynamic>.from(json.decode(responseBody));

      // Clean up the M4A file
      try {
        await File(audioPath).delete();
      } catch (e) {
        if (kDebugMode) {
          print('Warning: Could not delete .m4a recording: $e');
        }
      }

      return jsonResponse['text'] ?? '';
    } catch (e) {
      // Clean up the M4A file even on error
      try {
        await File(audioPath).delete();
      } catch (_) {}

      throw Exception('Failed to transcribe audio: $e');
    }
  }

  Future<void> _processTranscription(String transcription) async {
    try {
      if (!mounted) return;

      final aiService = Provider.of<AIService>(context, listen: false);
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);

      final action = await aiService.processVoiceCommand(transcription);

      // Save the action to Firestore
      await firestoreService.saveAction(action.toJson());

      if (mounted) {
        setState(() {
          _transcription = transcription;
          _currentAction = action;
          _recordingState = RecordingState.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recordingState = RecordingState.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process transcription: $e')),
        );
      }
    }
  }

  void _togglePlatform(String platform) {
    if (_currentAction == null) return;

    final updatedPlatforms = List<String>.from(_currentAction!.platforms);
    if (updatedPlatforms.contains(platform)) {
      updatedPlatforms.remove(platform);
    } else {
      updatedPlatforms.add(platform);
    }

    setState(() {
      _currentAction = SocialAction(
        actionId: _currentAction!.actionId,
        createdAt: _currentAction!.createdAt,
        platforms: updatedPlatforms,
        content: _currentAction!.content,
        options: _currentAction!.options,
        platformData: _currentAction!.platformData,
        internal: _currentAction!.internal,
        mediaQuery: _currentAction!.mediaQuery,
      );
    });
  }

  Future<void> _navigateToMediaSelection() async {
    if (_currentAction == null) return;

    final updatedAction = await Navigator.push<SocialAction>(
      context,
      MaterialPageRoute(
        builder: (context) => MediaSelectionScreen(action: _currentAction!),
      ),
    );

    if (updatedAction != null) {
      setState(() {
        _currentAction = updatedAction;
      });
    }
  }

  Future<void> _navigateToReviewPost() async {
    if (_currentAction == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewPostScreen(action: _currentAction!),
      ),
    );

    if (result == true) {
      // Post was successfully published, reset the state
      setState(() {
        _transcription = '';
        _currentAction = null;
        _recordingState = RecordingState.idle;
      });
    }
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HistoryScreen(),
      ),
    );
  }

  bool get _hasMedia => _currentAction?.content.media.isNotEmpty ?? false;
  bool get _isJsonReady =>
      _currentAction != null && _recordingState == RecordingState.ready;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _backgroundAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Color.lerp(
                    const Color(0xFF1A1A1A),
                    const Color(0xFF2A1A2A),
                    _backgroundAnimation.value * 0.3,
                  )!,
                ],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  // Background floating particles effect
                  _buildFloatingParticles(),

                  // Main content
                  _buildMainContent(),

                  // History button (top-right)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      onPressed: _navigateToHistory,
                      icon: const Icon(
                        Icons.history,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFloatingParticles() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _backgroundAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: ParticlesPainter(_backgroundAnimation.value),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        // Top section - Social Icons
        Container(
          height: 120,
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: SocialIconsRow(
            selectedPlatforms: _currentAction?.platforms ?? [],
            onPlatformToggle: _togglePlatform,
          ),
        ),

        // Middle section - Dialog
        Expanded(
          child: Center(
            child: TranscriptionDialog(
              transcription: _transcription,
              isJsonReady: _isJsonReady,
              hasMedia: _hasMedia,
              onReviewMedia: _navigateToMediaSelection,
              onPostNow: _navigateToReviewPost,
            ),
          ),
        ),

        // Bottom section - Microphone (fixed positioning with safe area)
        SafeArea(
          minimum: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Recording timer
              if (_recordingState == RecordingState.recording)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0080).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFFF0080),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${_maxRecordingDuration - _recordingDuration}s',
                      style: const TextStyle(
                        color: Color(0xFFFF0080),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

              // Microphone button with fixed center position
              SizedBox(
                height: 140, // Fixed height to contain the button and ripple
                child: Center(
                  child: MicButton(
                    state: _recordingState,
                    onRecordStart: _startRecording,
                    onRecordStop: _stopRecording,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ParticlesPainter extends CustomPainter {
  final double animationValue;

  ParticlesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF0080).withValues(alpha: 0.1);

    final particleCount = 15;
    for (int i = 0; i < particleCount; i++) {
      final x = (size.width / particleCount) * i;
      final y = size.height * 0.3 +
          (size.height * 0.4 * ((animationValue + i * 0.1) % 1.0));

      final radius = 2.0 + (animationValue * 3.0);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
