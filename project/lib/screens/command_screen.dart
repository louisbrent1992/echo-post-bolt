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
import '../services/media_coordinator.dart';
import '../services/social_action_post_coordinator.dart';
import '../widgets/social_icon.dart';
import '../widgets/post_content_box.dart';
import '../widgets/transcription_status.dart';
import '../widgets/unified_action_button.dart';
import '../widgets/unified_media_buttons.dart';
import '../screens/media_selection_screen.dart';
import '../screens/review_post_screen.dart';
import '../screens/history_screen.dart';
import '../screens/directory_selection_screen.dart';

/// Recording states for voice capture workflow
enum RecordingState { idle, recording, processing, ready }

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
/// 4. Persistence – The resulting `SocialAction` is persisted via the
///    `SocialActionPostCoordinator` so that drafts and history survive app
///    restarts or network failures.
/// 5. Media Resolution – Media is automatically assigned when users reference
///    images in their voice commands (e.g., "post my last picture"). The
///    `MediaCoordinator` handles intelligent media selection and validation.
///    Users can also manually select media via `MediaSelectionScreen` if needed.
/// 6. Review & Publish – Finally, the user lands on `ReviewPostScreen`,
///    previews the composed post, edits if necessary, and confirms. Upon
///    confirmation, the `SocialActionPostCoordinator` handles both Firestore
///    persistence and posting to social media platforms.
///
/// Each stage contains robust validation, error handling, and debug logging so
/// that any break in the pipeline (Whisper outages, malformed JSON, network
/// errors, etc.) is surfaced early and the UI gracefully degrades. The entire
/// workflow is coordinated through the `SocialActionPostCoordinator` for
/// consistent state management across all screens.

class CommandScreen extends StatefulWidget {
  const CommandScreen({super.key});

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen>
    with TickerProviderStateMixin {
  final AudioRecorder _record = AudioRecorder();

  RecordingState _recordingState = RecordingState.idle;
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

  // Coordinators - now using SocialActionPostCoordinator for all state management
  SocialActionPostCoordinator? _postCoordinator;
  late final MediaCoordinator _mediaCoordinator;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Access MediaCoordinator only - SocialActionPostCoordinator is accessed via Consumer
    _mediaCoordinator = Provider.of<MediaCoordinator>(context, listen: false);

    if (kDebugMode) {
      print('🎯 CommandScreen: Connected to MediaCoordinator');
    }
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

  void _resetRecordingState({bool clearPreSelectedMedia = false}) {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recordingTimer = null;
    _amplitudeTimer = null;
    _recordingDuration = 0;
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

    // Use coordinator to manage state reset
    _postCoordinator?.setRecordingState(false);

    if (clearPreSelectedMedia) {
      _postCoordinator?.reset(); // Full reset including media
    }

    if (kDebugMode) {
      print('🔄 Recording state reset to idle via coordinator');
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
      print('🎤 Starting recording... Current state: $_recordingState');
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

    // Update coordinator recording state
    _postCoordinator?.setRecordingState(true);

    try {
      // Check and request microphone permission
      bool hasPermission = await _record.hasPermission();
      if (!hasPermission) {
        _isStartingRecording = false;
        _postCoordinator?.setRecordingState(false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Microphone permission is required for voice recording.'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: _startRecording,
              ),
            ),
          );
        }
        return;
      }

      // Validate recording environment
      if (!await _validateRecordingEnvironment()) {
        _isStartingRecording = false;
        _postCoordinator?.setRecordingState(false);
        return;
      }

      // Set up recording path
      final tempDir = await getTemporaryDirectory();
      final m4aPath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = m4aPath;

      // Update UI state
      setState(() {
        _recordingState = RecordingState.recording;
      });

      // Configure and start recording
      const recordConfig = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );

      _recordingStartTime = DateTime.now();
      await _record.start(recordConfig, path: m4aPath);

      await Future.delayed(const Duration(milliseconds: 100));
      _startRecordingTimer();
      _startAmplitudeMonitoring();

      if (kDebugMode) {
        print('✅ Recording started successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to start recording: $e');
      }

      setState(() {
        _recordingState = RecordingState.idle;
      });
      _postCoordinator?.setRecordingState(false);
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
    }

    // Handle different states
    if (_recordingState == RecordingState.idle) {
      return;
    }

    if (_recordingState == RecordingState.processing ||
        _recordingState == RecordingState.ready) {
      setState(() {
        _resetRecordingState();
      });
      return;
    }

    if (_recordingState != RecordingState.recording) {
      return;
    }

    if (_isStoppingRecording) {
      return;
    }

    _isStoppingRecording = true;

    try {
      // Stop recording
      final recordedPath = await _record.stop();
      _stopRecordingTimer();
      _stopAmplitudeMonitoring();

      final actualDuration = _recordingStartTime != null
          ? stopTime.difference(_recordingStartTime!).inMilliseconds / 1000.0
          : 0.0;

      // Validate recording quality
      if (!_hasSpeechDetected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '🎤 No speech detected. Try speaking louder or closer to the microphone.'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
        }
        throw Exception('No speech detected during recording.');
      }

      const minRecordingDuration = 0.5;
      if (actualDuration < minRecordingDuration) {
        throw Exception(
            'Recording too short (${actualDuration.toStringAsFixed(2)}s). Minimum duration: ${minRecordingDuration}s');
      }

      // Update coordinator processing state
      _postCoordinator?.setProcessingState(true);
      setState(() {
        _recordingState = RecordingState.processing;
      });

      // Use recorded path or fallback
      final pathToProcess = recordedPath ?? _currentRecordingPath;
      if (pathToProcess == null) {
        throw Exception('No recording path available');
      }

      // Validate file
      final file = File(pathToProcess);
      if (!await file.exists()) {
        throw Exception('Recording file does not exist: $pathToProcess');
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Recording file is empty');
      }

      await _validateM4aFile(file, fileSize);

      // Transcribe and process through coordinator
      if (kDebugMode) {
        print('⏳ Processing recording through SocialActionPostCoordinator...');
      }

      final transcription = await _transcribeWithWhisper(pathToProcess);
      if (transcription.isEmpty) {
        throw Exception('Whisper returned empty transcription');
      }

      // CRITICAL: Use coordinator for all processing
      await _postCoordinator?.processVoiceTranscription(transcription);

      // CRITICAL: Clean up coordinator processing state after completion
      _postCoordinator?.setProcessingState(false);

      // Update UI based on coordinator state
      setState(() {
        // If coordinator has content, we're ready to proceed
        // Don't require "complete" post since that depends on platform-specific media requirements
        _recordingState = (_postCoordinator?.hasContent == true)
            ? RecordingState.ready
            : RecordingState.idle;
      });

      if (kDebugMode) {
        print('✅ Voice processing complete via coordinator');
        print('   Post complete: ${_postCoordinator?.isPostComplete}');
        print('   Has content: ${_postCoordinator?.hasContent}');
        print('   Has media: ${_postCoordinator?.hasMedia}');
        print('   Recording state: $_recordingState');
        print('   Coordinator post state: ${_postCoordinator?.postState}');
        print(
            '   Media requirement met: ${_postCoordinator?.hasContent == true ? 'checking...' : 'N/A'}');
        if (_postCoordinator?.hasContent == true) {
          print(
              '   Platform-specific media requirement: ${_postCoordinator?.isPostComplete == true ? 'MET' : 'NOT MET'}');
        }
      }

      // Auto-advance if post is complete (has content + meets platform media requirements)
      if (_postCoordinator?.isPostComplete == true) {
        await _checkAndAdvanceToReview();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _stopRecording: $e');
      }

      _postCoordinator?.setProcessingState(false);
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

  Future<String> _transcribeWithWhisper(String audioPath) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY not found in .env.local file.');
    }

    if (kDebugMode) {
      print('🎵 Transcribing M4A audio file: $audioPath');
    }

    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file does not exist: $audioPath');
      }

      final fileSize = await file.length();
      const maxFileSize = 26214400;
      if (fileSize > maxFileSize) {
        throw Exception(
            'Audio file too large: $fileSize bytes. Maximum allowed: $maxFileSize bytes (25MB)');
      }

      if (fileSize == 0) {
        throw Exception('Audio file is empty');
      }

      final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', url);

      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['User-Agent'] = 'EchoPost/1.0.0';
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

      final response = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('Whisper API request timed out after 60 seconds');
        },
      );

      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        String errorMessage = 'Whisper API error (${response.statusCode})';
        try {
          final errorJson = json.decode(responseBody);
          if (errorJson.containsKey('error')) {
            final errorDetails = errorJson['error'];
            errorMessage +=
                ': ${errorDetails['message'] ?? errorDetails['type'] ?? 'Unknown error'}';
          }
        } catch (e) {
          errorMessage += ': $responseBody';
        }
        throw Exception(errorMessage);
      }

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

      // Clean up audio file
      try {
        await file.delete();
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

      try {
        await File(audioPath).delete();
      } catch (_) {}

      rethrow;
    }
  }

  void _togglePlatform(String platform) {
    _postCoordinator?.togglePlatform(platform);
  }

  Future<void> _navigateToMediaSelection() async {
    try {
      if (kDebugMode) {
        print('🔍 Navigating to media selection via coordinator...');
      }

      // Get current post from coordinator
      final currentPost = _postCoordinator?.currentPost;
      List<Map<String, dynamic>>? initialCandidates;

      if (currentPost != null) {
        // Post-recording: Use existing action
        if (currentPost.mediaQuery != null) {
          final query = currentPost.mediaQuery!;
          final searchTerms = query.searchTerms.join(' ');

          DateTimeRange? dateRange;
          if (query.dateRange != null) {
            dateRange = DateTimeRange(
              start: query.dateRange!.startDate ??
                  DateTime.now().subtract(const Duration(days: 365)),
              end: query.dateRange!.endDate ?? DateTime.now(),
            );
          }

          initialCandidates = await _mediaCoordinator.getMediaForQuery(
            searchTerms,
            dateRange: dateRange,
            mediaTypes: query.mediaTypes.isNotEmpty ? query.mediaTypes : null,
            directory: query.directoryPath,
          );
        }
      } else {
        // Pre-selection: Get general media candidates
        initialCandidates = await _mediaCoordinator.getMediaForQuery(
          '',
          mediaTypes: ['image', 'video'],
        );
      }

      if (!mounted) return;

      final actionForSelection = currentPost ??
          SocialAction(
            actionId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
            createdAt: DateTime.now().toIso8601String(),
            platforms: ['instagram'],
            content: Content(
              text: '',
              hashtags: [],
              mentions: [],
              media: _postCoordinator?.preSelectedMedia ?? [],
            ),
            options: Options(),
            platformData: PlatformData(),
            internal: Internal(
              originalTranscription: '',
              aiGenerated: false,
            ),
          );

      final navigator = Navigator.of(context);
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      final updatedAction = await navigator.push<SocialAction>(
        MaterialPageRoute(
          builder: (context) => MediaSelectionScreen(
            action: actionForSelection,
            initialCandidates: initialCandidates,
          ),
        ),
      );

      if (updatedAction != null) {
        // Update coordinator with new media - use replaceMedia to allow overriding pre-selected images
        await _postCoordinator?.replaceMedia(updatedAction.content.media);

        if (kDebugMode) {
          print('✅ Media selection completed via coordinator');
          print(
              '📊 Selected media count: ${updatedAction.content.media.length}');
        }

        // Auto-advance if post is now complete
        if (mounted && _postCoordinator?.isPostComplete == true) {
          await _checkAndAdvanceToReview();
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
    final currentPost = _postCoordinator?.currentPost;
    if (currentPost == null) return;

    try {
      if (kDebugMode) {
        print('🔍 Navigating to review post via coordinator...');
      }

      // Final validation through MediaCoordinator
      final safeAction = await _mediaCoordinator.recoverMediaState(currentPost);
      final actionToReview = safeAction ?? currentPost;

      if (!mounted) return;

      final navigator = Navigator.of(context);

      // CRITICAL: Ensure clean state before navigation
      // Reset any processing flags that might cause spinning indicator
      _postCoordinator?.setProcessingState(false);
      setState(() {
        _recordingState = RecordingState.idle;
        _isStoppingRecording = false;
        _isStartingRecording = false;
      });

      // Navigate to review screen
      final result = await navigator.push(
        MaterialPageRoute(
          builder: (context) => ReviewPostScreen(action: actionToReview),
        ),
      );

      // CRITICAL: Only reset on explicit success (post published)
      // Back navigation should preserve all state
      if (mounted && result == true) {
        // Post was successfully published - full reset
        if (kDebugMode) {
          print('✅ Post published successfully, performing full reset');
        }
        _postCoordinator?.reset();
        setState(() {
          _resetRecordingState(clearPreSelectedMedia: true);
        });
      } else {
        // User navigated back or posting failed - preserve all state
        if (kDebugMode) {
          print(
              '🔙 User navigated back or posting failed, preserving post state');
        }
        // CRITICAL: Ensure clean UI state on return
        // The coordinator preserves post content, but UI should be clean
        _postCoordinator?.setProcessingState(false);
        setState(() {
          _recordingState = RecordingState.idle;
          _isStoppingRecording = false;
          _isStartingRecording = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in review post navigation: $e');
      }

      if (mounted) {
        // Reset processing state on error but preserve post content
        _postCoordinator?.setProcessingState(false);
        setState(() {
          _recordingState = RecordingState.idle;
          _isStoppingRecording = false;
          _isStartingRecording = false;
        });

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

  void _navigateToDirectorySelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DirectorySelectionScreen(),
      ),
    );
  }

  // Voice recording for interactive editing (integrated with main recording system)
  Future<void> _startVoiceEditing() async {
    // Use the main recording system instead of separate voice editing
    if (_recordingState == RecordingState.idle) {
      await _startRecording();
    }
  }

  Future<void> _stopVoiceEditing() async {
    // Use the main recording system
    if (_recordingState == RecordingState.recording) {
      await _stopRecording();
    }
  }

  Future<void> _editPostText() async {
    final textController = TextEditingController(
        text: _postCoordinator?.currentPost?.content.text ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        title: const Text('Edit Post Content',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your post content...',
            hintStyle: TextStyle(color: Colors.white60),
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
            fillColor: Colors.white.withValues(alpha: 0.1),
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
            onPressed: () => Navigator.pop(context, textController.text),
            child:
                const Text('SAVE', style: TextStyle(color: Color(0xFFFF0080))),
          ),
        ],
      ),
    );

    textController.dispose();

    if (result != null && result.trim().isNotEmpty) {
      try {
        // Direct coordinator update - no deferral needed with architectural fix
        await _postCoordinator?.updatePostContent(result.trim());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Post content updated! 📝'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Failed to update post content: $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update post content: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _editPostHashtags(List<String> newHashtags) async {
    try {
      // Direct coordinator update - no deferral needed with architectural fix
      await _postCoordinator?.updatePostHashtags(newHashtags);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newHashtags.isEmpty
                  ? 'All hashtags removed 🏷️'
                  : 'Hashtags updated! ${newHashtags.length} tags 🏷️',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to update hashtags: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update hashtags: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  bool _isPostComplete() => _postCoordinator?.isPostComplete == true;
  bool _needsMediaSelection() {
    final hasContent = _postCoordinator?.hasContent == true;
    final hasMedia = _postCoordinator?.hasMedia == true;
    final hasMediaQuery =
        _postCoordinator?.currentPost?.mediaQuery?.isNotEmpty == true;

    // Only need media selection if:
    // 1. We have content but no media
    // 2. There's a media query (user referenced media in their command)
    // 3. At least one selected platform requires media (Instagram, TikTok)
    if (!hasContent || hasMedia || !hasMediaQuery) {
      if (kDebugMode) {
        print('🔍 _needsMediaSelection: NO');
        print('   hasContent: $hasContent');
        print('   hasMedia: $hasMedia');
        print('   hasMediaQuery: $hasMediaQuery');
        print('   → Early return: false');
      }
      return false;
    }

    final platforms = _postCoordinator?.currentPost?.platforms ?? [];
    final requiresMedia = platforms.any((platform) =>
        platform.toLowerCase() == 'instagram' ||
        platform.toLowerCase() == 'tiktok');

    if (kDebugMode) {
      print('🔍 _needsMediaSelection: CHECKING PLATFORMS');
      print('   hasContent: $hasContent');
      print('   hasMedia: $hasMedia');
      print('   hasMediaQuery: $hasMediaQuery');
      print('   platforms: $platforms');
      print('   requiresMedia: $requiresMedia');
      print('   → Final result: $requiresMedia');
    }

    return requiresMedia;
  }

  Future<void> _checkAndAdvanceToReview() async {
    if (_postCoordinator?.isPostComplete == true) {
      if (kDebugMode) {
        print(
            '🚀 Post is complete via coordinator, automatically advancing to review');
      }

      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        await _navigateToReviewPost();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialActionPostCoordinator>(
      builder: (context, coordinator, child) {
        // Set the coordinator reference for use in other methods
        _postCoordinator = coordinator;

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
                  child: _buildReviewStyleLayout(coordinator),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildReviewStyleLayout(SocialActionPostCoordinator coordinator) {
    const double _gridUnit = 6.0;
    const double _spacing1 = _gridUnit;
    const double _spacing2 = _gridUnit * 2;
    const double _spacing3 = _gridUnit * 3;
    const double _spacing4 = _gridUnit * 4;
    const double _spacing5 = _gridUnit * 5;

    return Column(
      children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: _spacing3),
          child: CommandHeader(
            selectedPlatforms: coordinator.currentPost?.platforms ?? [],
            onPlatformToggle: _togglePlatform,
            leftAction: coordinator.hasContent || coordinator.hasMedia
                ? IconButton(
                    onPressed: _showResetConfirmation,
                    icon: const Icon(Icons.refresh,
                        color: Colors.white, size: 24),
                    tooltip: 'Reset current post',
                  )
                : null,
            rightAction: IconButton(
              onPressed: _navigateToHistory,
              icon: const Icon(Icons.history, color: Colors.white, size: 28),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: _spacing4),
                _buildCommandMediaSection(coordinator),
                const SizedBox(height: _spacing1),
                PostContentBox(
                  action: coordinator.currentPost ?? _createEmptyAction(),
                  isRecording: _recordingState == RecordingState.recording,
                  isProcessingVoice:
                      _recordingState == RecordingState.processing,
                  onEditText: _editPostText,
                  onEditHashtags: _editPostHashtags,
                  onVoiceEdit: _recordingState == RecordingState.recording
                      ? _stopVoiceEditing
                      : _startVoiceEditing,
                ),
                const SizedBox(height: _spacing5),
                const SizedBox(height: _spacing2),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Center(
                  child: TranscriptionStatus(
                    transcription: coordinator.currentTranscription,
                    isProcessing: _recordingState == RecordingState.processing,
                    isRecording: _recordingState == RecordingState.recording,
                    recordingDuration: _recordingDuration,
                    maxRecordingDuration: _maxRecordingDuration,
                    context: _getTranscriptionContext(coordinator),
                    customMessage: _getCustomMessage(coordinator),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: SafeArea(
                  minimum: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: UnifiedActionButton(
                        state: _getUnifiedButtonState(coordinator),
                        amplitude: normalizedAmplitude,
                        onRecordStart: _startRecording,
                        onRecordStop: _stopRecording,
                        onReviewPost: _navigateToReviewPost,
                        onAddMedia: _navigateToMediaSelection,
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

  Widget _buildCommandMediaSection(SocialActionPostCoordinator coordinator) {
    const double _gridUnit = 6.0;
    const double _spacing2 = _gridUnit * 2;

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 250,
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: coordinator.hasMedia
              ? _buildMediaPreview(context, coordinator)
              : _buildEmptyMediaPlaceholder(),
        ),
        const SizedBox(height: _spacing2),
        UnifiedMediaButtons(
          onDirectorySelection: _navigateToDirectorySelection,
          onMediaSelection: _navigateToMediaSelection,
          hasMedia: coordinator.hasMedia,
        ),
        const SizedBox(height: _spacing2),
      ],
    );
  }

  Widget _buildMediaPreview(
      BuildContext context, SocialActionPostCoordinator coordinator) {
    List<MediaItem> mediaToShow;
    if (coordinator.currentPost?.content.media.isNotEmpty == true) {
      mediaToShow = coordinator.currentPost!.content.media;
    } else if (coordinator.preSelectedMedia.isNotEmpty) {
      mediaToShow = coordinator.preSelectedMedia;
    } else {
      return const SizedBox.shrink();
    }

    final mediaItem = mediaToShow.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');

    return Container(
      width: double.infinity,
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          isVideo
              ? Container(
                  decoration: const BoxDecoration(color: Color(0xFF2A2A2A)),
                  child: const Center(
                    child: Icon(Icons.videocam, color: Colors.grey, size: 40),
                  ),
                )
              : Image.file(
                  File(Uri.parse(mediaItem.fileUri).path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: const BoxDecoration(color: Color(0xFF2A2A2A)),
                      child: const Center(
                        child: Icon(Icons.image, color: Colors.grey, size: 40),
                      ),
                    );
                  },
                ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
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
              child: Row(
                children: [
                  Text(
                    '${mediaItem.deviceMetadata.width} × ${mediaItem.deviceMetadata.height}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (coordinator.preSelectedMedia.isNotEmpty &&
                      coordinator.currentPost == null) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0080).withValues(alpha: 0.8),
                      ),
                      child: const Text(
                        'Pre-selected',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyMediaPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A2A2A), // Lighter gray for better contrast
            const Color(0xFF1F1F1F), // Slightly darker for subtle gradient
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.image_outlined,
                color: Colors.white.withValues(alpha: 0.8),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your image will appear here',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  UnifiedButtonState _getUnifiedButtonState(
      SocialActionPostCoordinator coordinator) {
    switch (_recordingState) {
      case RecordingState.idle:
        if (coordinator.isPostComplete) {
          return UnifiedButtonState.reviewPost;
        }
        return UnifiedButtonState.idle;
      case RecordingState.recording:
        return UnifiedButtonState.recording;
      case RecordingState.processing:
        return UnifiedButtonState.processing;
      case RecordingState.ready:
        if (coordinator.isPostComplete) {
          return UnifiedButtonState.reviewPost;
        }
        if (_needsMediaSelection()) {
          return UnifiedButtonState.addMedia;
        }
        return UnifiedButtonState.reviewPost;
    }
  }

  TranscriptionContext _getTranscriptionContext(
      SocialActionPostCoordinator coordinator) {
    // CRITICAL: Only use local recording state, not coordinator processing state
    // This prevents spinning indicator from appearing due to coordinator operations

    if (kDebugMode) {
      print('🔍 _getTranscriptionContext called:');
      print('   Recording state: $_recordingState');
      print('   Coordinator hasContent: ${coordinator.hasContent}');
      print('   Coordinator isPostComplete: ${coordinator.isPostComplete}');
      print('   Needs media selection: ${_needsMediaSelection()}');
    }

    switch (_recordingState) {
      case RecordingState.idle:
        if (kDebugMode) print('   → Returning TranscriptionContext.recording');
        return TranscriptionContext.recording;
      case RecordingState.recording:
        if (kDebugMode) print('   → Returning TranscriptionContext.recording');
        return TranscriptionContext.recording;
      case RecordingState.processing:
        if (kDebugMode) print('   → Returning TranscriptionContext.processing');
        return TranscriptionContext.processing;
      case RecordingState.ready:
        if (_needsMediaSelection()) {
          if (kDebugMode)
            print('   → Returning TranscriptionContext.addMediaReady');
          return TranscriptionContext.addMediaReady;
        }
        if (kDebugMode)
          print('   → Returning TranscriptionContext.reviewReady');
        return TranscriptionContext.reviewReady;
    }
  }

  String? _getCustomMessage(SocialActionPostCoordinator coordinator) {
    if (_recordingState == RecordingState.idle &&
        coordinator.currentTranscription.isEmpty &&
        coordinator.currentPost == null) {
      return 'Welcome to EchoPost. Say what you want to post.';
    }

    // CRITICAL: Only show coordinator errors if we're not in an active recording workflow
    if (_recordingState == RecordingState.idle &&
        coordinator.lastError != null) {
      return 'Error: ${coordinator.lastError}';
    }

    return null;
  }

  SocialAction _createEmptyAction() {
    return SocialAction(
      actionId: '',
      createdAt: '',
      platforms: [],
      content: Content(
        text: '',
        hashtags: [],
        mentions: [],
        media: [],
      ),
      options: Options(),
      platformData: PlatformData(),
      internal: Internal(
        originalTranscription: '',
        aiGenerated: false,
      ),
      mediaQuery: null,
    );
  }

  void _showResetConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        title: const Text(
          'Reset Current Post?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will clear your current post content and selected media. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'RESET',
              style: TextStyle(color: Color(0xFFFF0080)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (kDebugMode) {
        print('🔄 User confirmed reset - clearing all post state');
      }

      _postCoordinator?.reset();
      setState(() {
        _resetRecordingState(clearPreSelectedMedia: true);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post reset successfully! 🔄'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
