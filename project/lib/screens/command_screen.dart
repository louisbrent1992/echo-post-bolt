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
import '../services/media_coordinator.dart';
import '../widgets/mic_button.dart';
import '../widgets/social_icon.dart';
import '../widgets/post_preview.dart';
import '../widgets/transcription_status.dart';
import '../widgets/directory_selector.dart';
import '../screens/media_selection_screen.dart';
import '../screens/review_post_screen.dart';
import '../screens/history_screen.dart';
import '../services/firestore_service.dart';

/// EchoPost Voice-to-Post Pipeline
///
/// This screen orchestrates the end-to-end workflow that turns a user's spoken command into a fully-formed social-media post:
///
/// 1. Voice Capture – When the user taps the microphone, the `record` package
///    begins capturing audio in M4A format for optimal file size.
/// 2. Transcription – Once stopped, the finalized M4A file is shipped to
///    OpenAI Whisper (`/v1/audio/transcriptions`) where it is transcribed
///    into plain-text English.
/// 3. Command Parsing – The raw transcript is forwarded to ChatGPT (`/v1/chat/completions`).
///    Using a strict JSON schema, ChatGPT returns a `SocialAction` description
///    that contains every field needed to publish a post: text, hashtags,
///    mentions, media placeholders, platform targets, scheduling info, etc.
/// 4. Persistence – The resulting `SocialAction` is persisted to Firestore via
///    `FirestoreService.saveAction` so that drafts and history survive app
///    restarts or network failures.
/// 5. Media Resolution – If the JSON includes a `media_query`, the user is
///    routed to `MediaSelectionScreen` to pick matching local assets.  If the
///    JSON already contains concrete `media.file_uri` entries, this step is
///    skipped. This is now coordinated through `MediaCoordinator` for consistent
///    validation, metadata enrichment, and recovery mechanisms.
/// 6. Review & Publish – Finally, the user lands on `ReviewPostScreen`,
///    previews the composed post, edits if necessary, and confirms.  Upon
///    confirmation, the background posting workflow dispatches the post to the
///    respective social-media APIs once account authentication is verified.
///
/// Each stage contains robust validation, error handling, and debug logging so
/// that any break in the pipeline (Whisper outages, malformed JSON, network
/// errors, etc.) is surfaced early and the UI gracefully degrades.  Keep this
/// contract intact whenever UI or service changes are introduced.

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
  bool _isStoppingRecording = false;
  bool _isStartingRecording = false;
  DateTime? _recordingStartTime;

  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

  Timer? _recordingTimer;
  Timer? _amplitudeTimer;
  int _recordingDuration = 0;
  final int _maxRecordingDuration = 30; // 30 seconds max

  // Voice monitoring variables
  double _currentAmplitude = -160.0; // dBFS
  double _maxAmplitude = -160.0;
  double _amplitudeSum = 0.0;
  int _amplitudeSamples = 0;
  bool _hasSpeechDetected = false;
  int _silenceCount = 0;
  final double _speechThreshold = -40.0; // dBFS threshold for speech detection
  final double _silenceThreshold = -50.0; // dBFS threshold for silence
  final int _maxSilenceBeforeWarning =
      10; // 5 seconds of silence before warning

  // Media coordinator for centralized media handling
  late final MediaCoordinator _mediaCoordinator;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaCoordinator = Provider.of<MediaCoordinator>(context, listen: false);
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
    _amplitudeTimer?.cancel();
    _record.dispose();
    super.dispose();
  }

  void _resetRecordingState() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recordingTimer = null;
    _amplitudeTimer = null;
    _recordingDuration = 0;
    _transcription = '';
    _currentAction = null;
    _currentRecordingPath = null;
    _isStartingRecording = false;
    _isStoppingRecording = false;
    _recordingState = RecordingState.idle;
    _recordingStartTime = null;

    // Reset voice monitoring
    _currentAmplitude = -160.0;
    _maxAmplitude = -160.0;
    _amplitudeSum = 0.0;
    _amplitudeSamples = 0;
    _hasSpeechDetected = false;
    _silenceCount = 0;

    if (kDebugMode) {
      print('🔄 Recording state reset to idle');
    }
  }

  double get normalizedAmplitude {
    // Convert dBFS to 0.0-1.0 range for UI
    // -60 dBFS = 0.0, -10 dBFS = 1.0
    const double minDb = -60.0;
    const double maxDb = -10.0;

    if (_currentAmplitude <= minDb) return 0.0;
    if (_currentAmplitude >= maxDb) return 1.0;

    return (_currentAmplitude - minDb) / (maxDb - minDb);
  }

  Future<void> _startRecording() async {
    if (kDebugMode) {
      print(
          '🎤 Starting recording... Current state: $_recordingState, isStartingRecording: $_isStartingRecording');
    }

    if (_recordingState != RecordingState.idle) {
      if (kDebugMode) {
        print('❌ Cannot start recording: not in idle state');
      }
      return;
    }

    if (_isStartingRecording) {
      if (kDebugMode) {
        print(
            '❌ Already starting recording, ignoring additional start request');
      }
      return;
    }

    _isStartingRecording = true;

    try {
      // Check and request microphone permission
      if (kDebugMode) {
        print('🔍 Checking microphone permission...');
      }

      bool hasPermission = await _record.hasPermission();
      if (kDebugMode) {
        print('🔍 Initial microphone permission: $hasPermission');
      }

      // Final permission check - the record package automatically requests permission if needed
      if (!hasPermission) {
        _isStartingRecording = false;
        if (kDebugMode) {
          print('❌ Microphone permission denied by user');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Microphone permission is required for voice recording. Please grant permission when prompted or check app settings.'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry recording which will trigger permission request again
                  _startRecording();
                },
              ),
            ),
          );
        }
        return;
      }

      if (kDebugMode) {
        print('✅ Microphone permission granted');
      }

      // Validate recording environment
      if (kDebugMode) {
        print('🔍 Validating recording environment...');
      }

      if (!await _validateRecordingEnvironment()) {
        _isStartingRecording = false;
        if (kDebugMode) {
          print('❌ Recording environment validation failed');
        }
        return;
      }

      // Set up recording path - use M4A format for optimal file size
      final tempDir = await getTemporaryDirectory();

      // Ensure temp directory exists and is writable
      if (!await tempDir.exists()) {
        try {
          await tempDir.create(recursive: true);
          if (kDebugMode) {
            print('📁 Created temp directory: ${tempDir.path}');
          }
        } catch (e) {
          throw Exception('Failed to create temporary directory: $e');
        }
      }

      // Use M4A format for optimal file size
      final m4aPath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (kDebugMode) {
        print('📁 Recording to path: $m4aPath');
        print('📁 Temp directory exists: ${await tempDir.exists()}');
        print('📁 Temp directory path: ${tempDir.path}');
      }

      // Set the path BEFORE starting recording
      _currentRecordingPath = m4aPath;

      // Update UI state immediately
      setState(() {
        _recordingState = RecordingState.recording;
      });

      if (kDebugMode) {
        print('🎛️ UI state updated to recording');
      }

      // Configure optimal recording settings for speech recognition
      // Using M4A format for optimal file size
      const recordConfig = RecordConfig(
        encoder: AudioEncoder.aacLc, // AAC-LC codec for M4A format
        bitRate: 128000, // 128 kbps - good quality for speech
        sampleRate:
            16000, // 16kHz - optimal for speech recognition (Whisper's native rate)
        numChannels: 1, // Mono recording for voice
        autoGain: true, // Enable auto gain for consistent levels
        echoCancel: true, // Enable echo cancellation
        noiseSuppress: true, // Enable noise suppression
      );

      if (kDebugMode) {
        print('🎛️ Recording config:');
        print('   Encoder: ${recordConfig.encoder}');
        print('   Bitrate: ${recordConfig.bitRate} bps');
        print('   Sample Rate: ${recordConfig.sampleRate} Hz');
        print('   Channels: ${recordConfig.numChannels}');
        print('   Auto Gain: ${recordConfig.autoGain}');
        print('   Echo Cancel: ${recordConfig.echoCancel}');
        print('   Noise Suppress: ${recordConfig.noiseSuppress}');
      }

      // Start the actual recording
      if (kDebugMode) {
        print('🚀 Starting audio recording...');
      }

      _recordingStartTime = DateTime.now();
      await _record.start(recordConfig, path: m4aPath);

      if (kDebugMode) {
        print(
            '🎙️ Audio recording started at: ${_recordingStartTime!.toIso8601String()}');
      }

      // Small delay to allow microphone to fully initialize before starting timer
      // This prevents timing mismatch between timer and actual audio capture
      await Future.delayed(const Duration(milliseconds: 100));

      // Start the recording timer and amplitude monitoring
      _startRecordingTimer();
      _startAmplitudeMonitoring();

      if (kDebugMode) {
        print('✅ Recording setup complete. Path: $_currentRecordingPath');
        print('⏰ Recording timer and amplitude monitoring started');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to start recording: $e');
        print('📊 Error type: ${e.runtimeType}');
      }

      // Reset state on error
      setState(() {
        _recordingState = RecordingState.idle;
      });
      _currentRecordingPath = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      _isStartingRecording = false;
      if (kDebugMode) {
        print('🔚 _startRecording completed. Final state: $_recordingState');
      }
    }
  }

  void _startAmplitudeMonitoring() {
    _currentAmplitude = -160.0;
    _maxAmplitude = -160.0;
    _amplitudeSum = 0.0;
    _amplitudeSamples = 0;
    _hasSpeechDetected = false;
    _silenceCount = 0;

    if (kDebugMode) {
      print('🔊 Starting amplitude monitoring...');
    }

    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final amplitude = await _record.getAmplitude();
        final current = amplitude.current;

        setState(() {
          _currentAmplitude = current;

          if (current > _maxAmplitude) {
            _maxAmplitude = current;
          }

          _amplitudeSamples++;
          _amplitudeSum += current;

          // Check for speech detection
          if (current > _speechThreshold) {
            _hasSpeechDetected = true;
            _silenceCount = 0;
          } else if (current < _silenceThreshold) {
            _silenceCount++;
          }
        });

        if (kDebugMode) {
          print(
              '🔊 Amplitude: ${current.toStringAsFixed(1)} dBFS (Max: ${_maxAmplitude.toStringAsFixed(1)}, Normalized: ${normalizedAmplitude.toStringAsFixed(2)})');

          // Warn about potential issues
          if (current < -50.0 && _amplitudeSamples > 4) {
            print(
                '⚠️ Low audio level detected. Speak louder or closer to microphone.');
          }
        }

        // Check for extended silence during recording
        if (_silenceCount >= _maxSilenceBeforeWarning && !_hasSpeechDetected) {
          if (kDebugMode) {
            print('⚠️ Extended silence detected - user may not be speaking');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    '🎤 Speak closer to the microphone - no voice detected'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error getting amplitude: $e');
        }
      }
    });
  }

  void _stopAmplitudeMonitoring() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    if (kDebugMode) {
      final averageAmplitude =
          _amplitudeSamples > 0 ? _amplitudeSum / _amplitudeSamples : -160.0;

      print('🔊 Final audio analysis:');
      print('   Max amplitude: ${_maxAmplitude.toStringAsFixed(1)} dBFS');
      print(
          '   Average amplitude: ${averageAmplitude.toStringAsFixed(1)} dBFS');
      print('   Speech detected: $_hasSpeechDetected');
      print('   Samples: $_amplitudeSamples');

      // Provide audio quality assessment
      if (!_hasSpeechDetected) {
        print('❌ CRITICAL: No speech detected throughout recording');
        print('   This explains why Whisper returns very short transcriptions');
        print(
            '   Recommendation: Speak louder, closer to microphone, or check microphone permissions');
      } else if (_maxAmplitude < -30.0) {
        print('⚠️ WARNING: Low speech levels detected');
        print(
            '   Recommendation: Speak louder or closer to microphone for better accuracy');
      } else {
        print('✅ Good speech levels detected');
      }
    }
  }

  Future<void> _stopRecording() async {
    final stopTime = DateTime.now();
    if (kDebugMode) {
      print('🛑 Stopping recording at: ${stopTime.toIso8601String()}');
      print(
          '🛑 Current state: $_recordingState, isStoppingRecording: $_isStoppingRecording');
      print('🛑 Recording duration when stop called: ${_recordingDuration}s');
    }

    // Handle different states
    if (_recordingState == RecordingState.idle) {
      if (kDebugMode) {
        print('❌ Already in idle state, nothing to stop');
      }
      return;
    }

    // If we're in processing or ready state, just reset to idle
    if (_recordingState == RecordingState.processing ||
        _recordingState == RecordingState.ready) {
      if (kDebugMode) {
        print('🔄 Resetting from $_recordingState to idle');
      }
      setState(() {
        _resetRecordingState();
      });
      return;
    }

    // Handle the actual recording stop (only when in recording state)
    if (_recordingState != RecordingState.recording) {
      if (kDebugMode) {
        print(
            '❌ Cannot stop recording: not in recording state (current: $_recordingState)');
      }
      return;
    }

    if (_isStoppingRecording) {
      if (kDebugMode) {
        print('❌ Already stopping recording, ignoring additional stop request');
      }
      return;
    }

    _isStoppingRecording = true;

    try {
      if (kDebugMode) {
        print('📍 About to call _record.stop()');
      }

      // Stop the recording and get the path
      final recordedPath = await _record.stop();
      _stopRecordingTimer();
      _stopAmplitudeMonitoring();

      final actualDuration = _recordingStartTime != null
          ? stopTime.difference(_recordingStartTime!).inMilliseconds / 1000.0
          : 0.0;

      if (kDebugMode) {
        print('📍 Recording stopped, returned path: $recordedPath');
        print('📍 Current recording path: $_currentRecordingPath');
        print('📍 Timer duration: ${_recordingDuration}s');
        print('📍 Actual duration: ${actualDuration.toStringAsFixed(2)}s');
      }

      // Check if speech was detected during recording
      if (!_hasSpeechDetected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '🎤 No speech detected. Try speaking louder, closer to the microphone, or check your microphone permissions.'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
        }
        throw Exception(
            'No speech detected during recording. Please speak louder, closer to the microphone, or check microphone permissions.');
      }

      // Check minimum recording duration (0.5 second minimum for meaningful speech)
      const minRecordingDuration = 0.5;
      if (actualDuration < minRecordingDuration) {
        throw Exception(
            'Recording too short (${actualDuration.toStringAsFixed(2)}s). Please hold the button longer and speak clearly. Minimum duration: ${minRecordingDuration}s');
      }

      setState(() {
        _recordingState = RecordingState.processing;
      });

      // Use the returned path or fallback to stored path
      final pathToProcess = recordedPath ?? _currentRecordingPath;

      if (pathToProcess == null || pathToProcess.isEmpty) {
        throw Exception('No recording path available');
      }

      // Verify file exists before processing
      final file = File(pathToProcess);
      if (!await file.exists()) {
        throw Exception('Recording file does not exist: $pathToProcess');
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Recording file is empty');
      }

      // Validate M4A file format
      await _validateM4aFile(file, fileSize);

      if (kDebugMode) {
        print('⏳ Processing recording from: $pathToProcess ($fileSize bytes)');
      }

      final transcription = await _transcribeWithWhisper(pathToProcess);

      if (transcription.isEmpty) {
        throw Exception('Whisper returned empty transcription');
      }

      await _processTranscription(transcription);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _stopRecording: $e');
      }
      setState(() {
        _recordingState = RecordingState.idle;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process recording: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      _isStoppingRecording = false;
    }
  }

  void _startRecordingTimer() {
    _recordingDuration = 0;
    if (kDebugMode) {
      print('⏰ Starting recording timer...');
    }

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });

      if (kDebugMode) {
        print(
            '⏰ Recording duration: ${_recordingDuration}s / ${_maxRecordingDuration}s');
      }

      if (_recordingDuration >= _maxRecordingDuration) {
        if (kDebugMode) {
          print('⏰ Max recording duration reached, stopping...');
        }
        _stopRecording();
      }
    });
  }

  void _stopRecordingTimer() {
    if (kDebugMode) {
      print(
          '⏰ Stopping recording timer. Final duration: ${_recordingDuration}s');
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  /// Validates that the recorded file is a proper M4A format and contains audio data
  Future<void> _validateM4aFile(File file, int fileSize) async {
    try {
      // Check minimum file size (M4A header is typically 32+ bytes)
      if (fileSize < 100) {
        throw Exception(
            'M4A file too small ($fileSize bytes), likely corrupted or incomplete');
      }

      // Check reasonable maximum size for a 30-second recording
      // At 128kbps, 30 seconds should be roughly 480KB, so anything over 5MB is suspicious
      if (fileSize > 5 * 1024 * 1024) {
        if (kDebugMode) {
          print(
              '⚠️ Warning: M4A file unusually large (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
        }
      }

      // Read first 32 bytes to check M4A header
      final bytes = await file.openRead(0, 32).toList();
      final headerBytes = bytes.expand((x) => x).toList();

      if (headerBytes.length < 32) {
        throw Exception(
            'Unable to read M4A file header (got ${headerBytes.length} bytes)');
      }

      // Check for M4A/MP4 container signature (ftyp box)
      // Bytes 4-7 should contain 'ftyp'
      final ftypSignature = String.fromCharCodes(headerBytes.sublist(4, 8));
      if (ftypSignature != 'ftyp') {
        if (kDebugMode) {
          print('⚠️ Warning: Expected ftyp signature, got: $ftypSignature');
          print('   File may still be valid M4A, continuing...');
        }
      }

      if (kDebugMode) {
        print('✅ M4A file validation passed:');
        print(
            '   File size: $fileSize bytes (${(fileSize / 1024).toStringAsFixed(1)} KB)');
        print('   Header signature: $ftypSignature');
        print('   Speech detected during recording: $_hasSpeechDetected');
        print('   Max amplitude: ${_maxAmplitude.toStringAsFixed(1)} dBFS');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ M4A validation error: $e');
      }
      throw Exception('M4A file validation failed: $e');
    }
  }

  /// Validates the recording environment before starting
  Future<bool> _validateRecordingEnvironment() async {
    try {
      if (kDebugMode) {
        print('🔍 Validating recording environment...');
      }

      // Check if we can access the temp directory
      final tempDir = await getTemporaryDirectory();

      if (kDebugMode) {
        print('📁 Temp directory: ${tempDir.path}');
      }

      // Verify directory exists and is accessible
      final dirStat = await tempDir.stat();
      final dirExists = dirStat.type != FileSystemEntityType.notFound;

      if (kDebugMode) {
        print('📁 Directory exists: $dirExists');
      }

      if (!dirExists) {
        throw Exception('Temp directory does not exist');
      }

      // Check if temp directory is writable by trying to create a test file
      try {
        final testFile = File(
            '${tempDir.path}/test_${DateTime.now().millisecondsSinceEpoch}.tmp');

        if (kDebugMode) {
          print('🧪 Testing write access with file: ${testFile.path}');
        }

        await testFile.writeAsBytes([1, 2, 3, 4]);

        // Verify file was created
        final exists = await testFile.exists();
        if (!exists) {
          throw Exception('Test file was not created');
        }

        // Clean up test file
        await testFile.delete();

        if (kDebugMode) {
          print('✅ Temp directory is writable');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Temp directory not writable: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Cannot access storage for recording. Please check app permissions.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return false;
      }

      if (kDebugMode) {
        print('✅ Recording environment validation passed');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Recording environment validation failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording environment check failed: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      return false;
    }
  }

  /// Validates that the SocialAction created from ChatGPT response is complete and ready for UI
  void _validateSocialAction(
      SocialAction action, String originalTranscription) {
    try {
      // Validate basic structure
      if (action.actionId.isEmpty) {
        throw Exception('SocialAction missing actionId');
      }

      if (action.platforms.isEmpty) {
        throw Exception('SocialAction has no platforms selected');
      }

      if (action.content.text.isEmpty) {
        throw Exception('SocialAction has empty text content');
      }

      // Validate platform consistency
      final validPlatforms = ['instagram', 'twitter', 'facebook', 'tiktok'];
      for (final platform in action.platforms) {
        if (!validPlatforms.contains(platform)) {
          throw Exception('Invalid platform: $platform');
        }
      }

      // Validate content structure
      if (action.content.hashtags.any((tag) => tag.startsWith('#'))) {
        throw Exception('Hashtags should not include # symbol');
      }

      // Validate internal metadata
      if (action.internal.originalTranscription != originalTranscription) {
        if (kDebugMode) {
          print('⚠️ Warning: Original transcription mismatch');
          print('   Expected: "$originalTranscription"');
          print('   Stored: "${action.internal.originalTranscription}"');
        }
      }

      if (!action.internal.aiGenerated) {
        throw Exception('SocialAction should be marked as AI generated');
      }

      // Log validation success
      if (kDebugMode) {
        print('✅ SocialAction validation passed:');
        print('   ID: ${action.actionId}');
        print(
            '   Platforms: ${action.platforms.length} (${action.platforms.join(', ')})');
        print('   Text: ${action.content.text.length} chars');
        print('   Hashtags: ${action.content.hashtags.length}');
        print('   Mentions: ${action.content.mentions.length}');
        print(
            '   Media Query: ${action.mediaQuery?.isNotEmpty == true ? 'Yes' : 'No'}');
        print('   Created: ${action.createdAt}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ SocialAction validation failed: $e');
        print('📊 Action JSON: ${action.toJson()}');
      }
      throw Exception('ChatGPT response validation failed: $e');
    }
  }

  Future<String> _transcribeWithWhisper(String audioPath) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
          'OPENAI_API_KEY not found in .env.local file. Please add your OpenAI API key.');
    }

    if (kDebugMode) {
      print('🎵 Transcribing M4A audio file: $audioPath');
    }

    try {
      // Check if file exists and validate
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file does not exist: $audioPath');
      }

      final fileSize = await file.length();

      // Check file size limit (25MB = 26,214,400 bytes)
      const maxFileSize = 26214400;
      if (fileSize > maxFileSize) {
        throw Exception(
            'Audio file too large: $fileSize bytes. Maximum allowed: $maxFileSize bytes (25MB)');
      }

      if (fileSize == 0) {
        throw Exception('Audio file is empty');
      }

      if (kDebugMode) {
        print(
            '📁 File size: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
      }

      final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', url);

      // Set headers
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['User-Agent'] = 'EchoPost/1.0.0';

      // Set required fields
      request.fields['model'] = 'whisper-1';
      request.fields['response_format'] = 'json';

      // Optional: specify language for better accuracy
      request.fields['language'] = 'en';

      // Optional: lower temperature for more deterministic results
      request.fields['temperature'] = '0.0';

      // Add the audio file
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        audioPath,
        filename: 'audio.m4a',
      );
      request.files.add(multipartFile);

      if (kDebugMode) {
        print('🚀 Sending request to Whisper API...');
        print('📋 Request fields: ${request.fields}');
        print(
            '📎 File: ${multipartFile.filename} (${multipartFile.length} bytes)');
      }

      // Send request with timeout
      final response = await request.send().timeout(
        const Duration(seconds: 60), // 60 second timeout for audio processing
        onTimeout: () {
          throw Exception('Whisper API request timed out after 60 seconds');
        },
      );

      final responseBody = await response.stream.bytesToString();

      if (kDebugMode) {
        print('📡 Whisper API response status: ${response.statusCode}');
        print('📡 Whisper API response headers: ${response.headers}');
      }

      if (response.statusCode != 200) {
        String errorMessage = 'Whisper API error (${response.statusCode})';

        try {
          final errorJson = json.decode(responseBody);
          if (errorJson.containsKey('error')) {
            final errorDetails = errorJson['error'];
            errorMessage +=
                ': ${errorDetails['message'] ?? errorDetails['type'] ?? 'Unknown error'}';

            if (errorDetails.containsKey('code')) {
              errorMessage += ' (Code: ${errorDetails['code']})';
            }
          }
        } catch (e) {
          errorMessage += ': $responseBody';
        }

        throw Exception(errorMessage);
      }

      if (kDebugMode) {
        print('📡 Whisper API response body: $responseBody');
      }

      // Parse JSON response
      final jsonResponse = json.decode(responseBody) as Map<String, dynamic>;

      if (!jsonResponse.containsKey('text')) {
        throw Exception(
            'Invalid response from Whisper API: missing "text" field');
      }

      final transcription = jsonResponse['text'] as String? ?? '';

      if (transcription.isEmpty) {
        throw Exception('Whisper API returned empty transcription');
      }

      if (kDebugMode) {
        print('✅ Transcription received: "$transcription"');
      }

      // Clean up the audio file
      try {
        await file.delete();
        if (kDebugMode) {
          print('🗑️ Cleaned up audio file');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Warning: Could not delete audio file: $e');
        }
      }

      return transcription.trim();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Whisper transcription error: $e');
      }

      // Clean up the audio file even on error
      try {
        await File(audioPath).delete();
      } catch (_) {
        // Ignore cleanup errors
      }

      rethrow;
    }
  }

  Future<void> _processTranscription(String transcription) async {
    if (kDebugMode) {
      print('🔄 Processing transcription: "$transcription"');
    }

    try {
      if (!mounted) return;

      final aiService = Provider.of<AIService>(context, listen: false);
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);

      if (kDebugMode) {
        print('🚀 Calling AIService.processVoiceCommand...');
      }

      final action = await aiService.processVoiceCommand(transcription);

      if (kDebugMode) {
        print('✅ Received SocialAction from AI service');
        print('📋 Platforms: ${action.platforms}');
        print('📝 Text: "${action.content.text}"');
        print('🏷️ Hashtags: ${action.content.hashtags}');
        print('🔍 Media Query: "${action.mediaQuery}"');
      }

      // Validate the created SocialAction
      _validateSocialAction(action, transcription);

      // Save the action to Firestore
      try {
        await firestoreService.saveAction(action.toJson());
        if (kDebugMode) {
          print('💾 Saved action to Firestore');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Failed to save to Firestore: $e');
        }
        // Continue even if Firestore save fails
      }

      // Use MediaCoordinator to recover and validate media state
      if (kDebugMode) {
        print('🔄 Using MediaCoordinator to recover/validate media state...');
      }

      final recoveredAction = await _mediaCoordinator.recoverMediaState(action);
      final finalAction = recoveredAction ?? action;

      if (mounted) {
        setState(() {
          _transcription = transcription;
          _currentAction = finalAction;
          _recordingState = RecordingState.ready;
        });

        // Enhanced media status logging using MediaCoordinator
        if (kDebugMode) {
          print('🎯 UI updated with validated action');

          // Check media status through coordinator
          final hasValidMedia = finalAction.content.media.isNotEmpty &&
              finalAction.content.media
                  .any((media) => media.fileUri.isNotEmpty);
          final hasMediaQuery =
              finalAction.mediaQuery?.searchTerms.isNotEmpty == true;

          if (hasValidMedia) {
            // Validate existing media URIs
            var validCount = 0;
            for (final media in finalAction.content.media) {
              if (await _mediaCoordinator.validateMediaURI(media.fileUri)) {
                validCount++;
              }
            }
            print(
                '✅ Action contains $validCount valid media file URIs out of ${finalAction.content.media.length}');
          } else if (hasMediaQuery) {
            print('🔍 Action contains media query - will need media selection');
            print(
                '   Search Terms: "${finalAction.mediaQuery!.searchTerms.join(', ')}"');
            print('   Media Types: ${finalAction.mediaQuery!.mediaTypes}');
          } else {
            print('⚠️ Action has no media or media query');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _processTranscription: $e');
        print('📊 Stack trace: ${StackTrace.current}');
      }

      if (mounted) {
        setState(() {
          _recordingState = RecordingState.idle;
        });

        // Show more detailed error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process transcription: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                if (_transcription.isNotEmpty) {
                  _processTranscription(_transcription);
                }
              },
            ),
          ),
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

    try {
      if (kDebugMode) {
        print('🔍 Navigating to media selection with MediaCoordinator...');
      }

      // Fetch candidates via MediaCoordinator if we have a query
      List<Map<String, dynamic>>? initialCandidates;
      if (_currentAction!.mediaQuery != null) {
        final query = _currentAction!.mediaQuery!;
        final searchTerms = query.searchTerms.join(' ');

        // Build date range if available
        DateTimeRange? dateRange;
        if (query.dateRange != null) {
          dateRange = DateTimeRange(
            start: query.dateRange!.startDate ??
                DateTime.now().subtract(const Duration(days: 365)),
            end: query.dateRange!.endDate ?? DateTime.now(),
          );
        }

        if (kDebugMode) {
          print('   Search Terms: "$searchTerms"');
          print('   Media Types: ${query.mediaTypes}');
          print('   Date Range: ${dateRange?.toString() ?? 'None'}');
          print('   Directory: ${query.directoryPath ?? 'All'}');
        }

        // Get media candidates through coordinator
        initialCandidates = await _mediaCoordinator.getMediaForQuery(
          searchTerms,
          dateRange: dateRange,
          mediaTypes: query.mediaTypes.isNotEmpty ? query.mediaTypes : null,
          directory: query.directoryPath,
        );

        if (kDebugMode) {
          print('📊 Found ${initialCandidates.length} media candidates');
        }
      }

      final updatedAction = await Navigator.push<SocialAction>(
        context,
        MaterialPageRoute(
          builder: (context) => MediaSelectionScreen(
            action: _currentAction!,
            initialCandidates: initialCandidates,
          ),
        ),
      );

      if (updatedAction != null) {
        // Validate the updated action through coordinator before setting state
        final validatedAction =
            await _mediaCoordinator.recoverMediaState(updatedAction);
        setState(() {
          _currentAction = validatedAction ?? updatedAction;
        });

        if (kDebugMode) {
          print('✅ Media selection completed and validated');
          print(
              '📊 Selected media count: ${_currentAction!.content.media.length}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in media selection navigation: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load media selection: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _navigateToReviewPost() async {
    if (_currentAction == null) return;

    try {
      if (kDebugMode) {
        print('🔍 Navigating to review post with final validation...');
      }

      // Last-minute sanity check through MediaCoordinator
      final safeAction =
          await _mediaCoordinator.recoverMediaState(_currentAction!);
      final actionToReview = safeAction ?? _currentAction!;

      if (kDebugMode) {
        print('✅ Final action validated for review');
        print('📊 Media count: ${actionToReview.content.media.length}');

        // Log any media validation issues
        if (actionToReview.content.media.isNotEmpty) {
          var validCount = 0;
          for (final media in actionToReview.content.media) {
            if (await _mediaCoordinator.validateMediaURI(media.fileUri)) {
              validCount++;
            }
          }
          print(
              '📊 Valid media URIs: $validCount/${actionToReview.content.media.length}');
        }
      }

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewPostScreen(action: actionToReview),
        ),
      );

      if (result == true) {
        // Post was successfully published, reset the state
        if (kDebugMode) {
          print('✅ Post published successfully, resetting state');
        }
        setState(() {
          _resetRecordingState();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in review post navigation: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to prepare post for review: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
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

        // Directory selector (positioned underneath social icons)
        const DirectorySelector(),

        // Middle section - Post Preview (main content area)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: PostPreview(
                action: _currentAction,
                onReviewMedia: _navigateToMediaSelection,
                onReviewPost: _navigateToReviewPost,
              ),
            ),
          ),
        ),

        // Transcription status (smaller dialog below center)
        if (_transcription.isNotEmpty ||
            _recordingState == RecordingState.processing)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TranscriptionStatus(
              transcription: _transcription,
              isProcessing: _recordingState == RecordingState.processing,
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
                    amplitude: normalizedAmplitude,
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

    const particleCount = 15;
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
