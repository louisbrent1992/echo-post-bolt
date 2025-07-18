import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart';
import 'package:intl/intl.dart';

import '../models/social_action.dart';
import '../models/status_message.dart';
import '../services/media_coordinator.dart';
import '../services/social_action_post_coordinator.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/permission_manager.dart';
import '../widgets/social_icon.dart';
import '../widgets/post_content_box.dart';
import '../widgets/transcription_status.dart';
import '../widgets/unified_media_buttons.dart';
import '../widgets/enhanced_media_preview.dart';
import '../widgets/posting_strategy_info.dart';
import '../screens/media_selection_screen.dart';
import '../screens/history_screen.dart';
import '../screens/directory_selection_screen.dart';
import '../screens/profile_screen.dart';
import '../constants/typography.dart';
import '../widgets/triple_action_button_system.dart';
import '../constants/social_platforms.dart';

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
  final ScrollController _scrollController = ScrollController();

  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

  // Scroll indicator animation
  late AnimationController _scrollIndicatorController;
  late Animation<double> _scrollIndicatorAnimation;

  // Triple Action Button System animation controllers
  late AnimationController _leftButtonController;
  late AnimationController _rightButtonController;
  late Animation<double> _leftButtonAnimation;
  late Animation<double> _rightButtonAnimation;

  Timer? _recordingTimer;
  Timer? _amplitudeTimer;

  // Coordinators - SocialActionPostCoordinator accessed via Consumer
  SocialActionPostCoordinator? _postCoordinator;
  late final MediaCoordinator _mediaCoordinator;
  late final AppSettingsService _appSettingsService;

  // Debug message throttling for CommandScreen
  static DateTime? _lastProcessingLog;

  // CRITICAL: Add key to help Flutter track Consumer lifecycle
  final GlobalKey _consumerKey = GlobalKey();

  // Scroll indicator state
  bool _canScroll = false;
  bool _isScrolled = false;
  double _scrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupScrollListener();
    _scrollIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scrollIndicatorAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(
          parent: _scrollIndicatorController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScreen();
      _ensureCleanStateForNewSession();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Access MediaCoordinator only - SocialActionPostCoordinator is accessed via Consumer
    _mediaCoordinator = Provider.of<MediaCoordinator>(context, listen: false);
    _appSettingsService =
        Provider.of<AppSettingsService>(context, listen: false);

    if (kDebugMode) {
      print('🎯 CommandScreen: Connected to MediaCoordinator');
    }
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _leftButtonController.dispose();
    _rightButtonController.dispose();
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _record.dispose();
    _scrollController.dispose();
    _scrollIndicatorController.dispose();
    super.dispose();
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

    // Initialize Triple Action Button System animations
    _leftButtonController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _rightButtonController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _leftButtonAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _leftButtonController,
      curve: Curves.elasticOut,
    ));

    _rightButtonAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _rightButtonController,
      curve: Curves.elasticOut,
    ));
  }

  double get normalizedAmplitude {
    // Convert dBFS to 0.0-1.0 range for UI
    // -60 dBFS = 0.0, -10 dBFS = 1.0
    const double minDb = -60.0;
    const double maxDb = -10.0;

    final amplitude = _postCoordinator?.currentAmplitude ?? minDb;
    if (amplitude <= minDb) return 0.0;
    if (amplitude >= maxDb) return 1.0;

    return (amplitude - minDb) / (maxDb - minDb);
  }

  Future<void> _initializeScreen() async {
    try {
      // Check permissions through PermissionManager without forcing requests
      // This allows the app to work even if permissions are denied initially
      final permissionManager =
          Provider.of<PermissionManager>(context, listen: false);
      await permissionManager.checkPermissions();

      if (kDebugMode) {
        print('📋 Initial permission check completed');
        print('   Media: ${permissionManager.hasMediaPermission ? '✅' : '❌'}');
        print(
            '   Microphone: ${permissionManager.hasMicrophonePermission ? '✅' : '❌'}');
      }

      // Initialize the media coordinator regardless of permission status
      // Media coordinator will handle permissions when needed
      if (mounted) {
        final mediaCoordinator =
            Provider.of<MediaCoordinator>(context, listen: false);
        await mediaCoordinator.initialize();
      }

      if (kDebugMode) {
        print('✅ CommandScreen initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing screen: $e');
      }
      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to initialize: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  /// Ensure coordinator is in clean state for new recording session
  void _ensureCleanStateForNewSession() {
    // This is called when the screen is initialized
    // to ensure the coordinator is ready for new recordings
    if (_postCoordinator != null) {
      if (kDebugMode) {
        print('🔍 Checking coordinator state for new session:');
        print('   _isRecording: ${_postCoordinator!.isRecording}');
        print('   _isProcessing: ${_postCoordinator!.isProcessing}');
        print('   hasContent: ${_postCoordinator!.hasContent}');
        print('   hasMedia: ${_postCoordinator!.hasMedia}');
      }

      // Only reset if coordinator is genuinely stuck in processing state
      // without active recording (indicates a stuck state)
      if (_postCoordinator!.isProcessing &&
          !_postCoordinator!.isRecording &&
          !_postCoordinator!.hasContent) {
        if (kDebugMode) {
          print(
              '⚠️ Coordinator stuck in processing state without content - resetting processing flag');
        }
        _postCoordinator!.setProcessingState(false);
      }

      // Ensure command screen recording timers are clean
      _recordingTimer?.cancel();
      _amplitudeTimer?.cancel();
      _recordingTimer = null;
      _amplitudeTimer = null;

      if (kDebugMode) {
        print('✅ Coordinator state checked for new session');
      }
    }
  }

  /// Starts the unified voice recording process
  /// @param isVoiceDictation - Whether this was triggered by the post content microphone
  Future<void> _startUnifiedRecording({bool isVoiceDictation = false}) async {
    if (_postCoordinator == null) {
      if (kDebugMode) {
        print('❌ Cannot start recording: coordinator not available');
      }
      return;
    }

    try {
      // ALWAYS request microphone permission before recording
      // This ensures permission is re-requested every time if previously denied
      final permissionManager =
          Provider.of<PermissionManager>(context, listen: false);
      final hasPermission =
          await permissionManager.requestMicrophonePermission();

      if (!hasPermission) {
        // Check if permanently denied to provide specific guidance
        final isPermanentlyDenied =
            await permissionManager.isMicrophonePermissionPermanentlyDenied();

        String errorMessage;
        if (isPermanentlyDenied) {
          errorMessage =
              'Microphone access permanently denied. Please enable it in device settings to use voice recording.';
        } else {
          errorMessage =
              'Microphone access is required for voice recording. Please allow access and try again.';
        }

        if (kDebugMode) {
          print(
              '❌ Microphone permission denied. Permanently denied: $isPermanentlyDenied');
        }

        _postCoordinator?.setError(errorMessage);

        if (mounted) {
          // First show the status update
          _postCoordinator?.requestStatusUpdate(
            isPermanentlyDenied
                ? 'Microphone access permanently denied. Please enable in device settings.'
                : errorMessage,
            StatusMessageType.error,
            duration: const Duration(seconds: 6),
          );

          // Then show the snackbar if permanently denied
          if (isPermanentlyDenied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Microphone permission required. Enable in device settings.'),
                backgroundColor: Colors.red.withValues(alpha: 0.8),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () async {
                    await permissionManager.openDeviceSettings();
                  },
                ),
              ),
            );
          }
        }
        return;
      }

      if (kDebugMode) {
        print('✅ Microphone permission granted, starting recording...');
      }

      // Start recording through coordinator
      await _postCoordinator!
          .startRecordingWithMode(isVoiceDictation: isVoiceDictation);

      // Get recording path from coordinator
      final recordingPath = _postCoordinator!.currentRecordingPath;
      if (recordingPath == null) {
        throw Exception('Recording path not initialized');
      }

      // Start actual recording
      await _record.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: recordingPath,
      );

      _startRecordingTimer();
      _startAmplitudeMonitoring();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to start recording: $e');
      }

      _postCoordinator?.setError('Failed to start recording: $e');

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to start recording: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  void _startRecordingTimer() {
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final coordinator = _postCoordinator;
      if (coordinator == null) {
        timer.cancel();
        return;
      }

      final currentDuration = coordinator.recordingDuration + 1;
      coordinator.updateRecordingDuration(currentDuration);

      // Stop recording when max duration is reached
      if (currentDuration >= coordinator.maxRecordingDuration) {
        if (kDebugMode) {
          print('⏰ Max recording duration reached, stopping...');
        }
        timer.cancel();
        _stopRecording();
      }
    });
  }

  void _startAmplitudeMonitoring() {
    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final coordinator = _postCoordinator;
        if (coordinator == null) {
          timer.cancel();
          return;
        }

        // Check if we're still recording
        if (!await _record.isRecording()) {
          if (kDebugMode) {
            print('⚠️ Amplitude monitoring: Recording stopped unexpectedly');
          }
          _stopUnifiedRecording();
          return;
        }

        final amplitude = await _record.getAmplitude();
        coordinator.updateAmplitude(amplitude.current);

        // Monitor file size growth
        final recordingPath = coordinator.currentRecordingPath;
        if (recordingPath != null) {
          final file = File(recordingPath);
          if (await file.exists()) {
            final size = await file.length();
            if (size == 0 && coordinator.recordingDuration > 2) {
              if (kDebugMode) {
                print('⚠️ Warning: Recording file not growing in size');
              }
              _stopUnifiedRecording();
              return;
            }
          } else {
            if (kDebugMode) {
              print('⚠️ Warning: Recording file no longer exists');
            }
            _stopUnifiedRecording();
            return;
          }
        }

        // Check for extended silence during recording
        if (!coordinator.hasSpeechDetected &&
            coordinator.recordingDuration > 5) {
          if (kDebugMode) {
            print('⚠️ Extended silence detected - user may not be speaking');
          }

          if (mounted) {
            _postCoordinator?.requestStatusUpdate(
              '🎤 Speak closer to the microphone - no voice detected',
              StatusMessageType.warning,
              duration: const Duration(seconds: 2),
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error monitoring amplitude: $e');
        }
        // Stop recording if we encounter persistent errors
        final coordinator = _postCoordinator;
        if (coordinator != null && coordinator.recordingDuration > 5) {
          _stopUnifiedRecording();
        }
      }
    });
  }

  /// Stops the unified voice recording process and processes the recording
  Future<void> _stopUnifiedRecording() async {
    if (_postCoordinator == null) return;

    try {
      // Stop the recording
      final pathToProcess = await _record.stop();

      // Reset timers immediately
      _recordingTimer?.cancel();
      _amplitudeTimer?.cancel();

      if (pathToProcess == null) {
        throw Exception('Recording failed to save');
      }

      // Check if speech was detected
      if (!_postCoordinator!.hasSpeechDetected) {
        if (kDebugMode) {
          print('⚠️ No speech detected during recording, resetting state');
        }
        _resetAudioRecordingVariables();
        _postCoordinator!.clearRecordingModeContext();
        _postCoordinator!.setError('No speech detected. Please try again.');
        return;
      }

      // NEW: Start processing immediately with timeout
      _postCoordinator!.startProcessing(
        timeout:
            Duration(seconds: _appSettingsService.voiceTranscriptionTimeout),
      );

      // Process in background without Future wrapper
      _processTranscriptionInBackground(pathToProcess);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to stop recording: $e');
      }

      // CRITICAL: Comprehensive cleanup on recording stop failure
      _resetAudioRecordingVariables();

      // Reset recording state through coordinator
      _postCoordinator!.resetRecordingState();

      // Clear recording mode context
      _postCoordinator!.clearRecordingModeContext();

      _postCoordinator!.setError(e.toString());

      // Ensure processing state is reset in case it was started earlier
      _postCoordinator!.completeProcessing(success: false, error: e.toString());

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to process recording: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 5),
        );
      }
    }
  }

  /// NEW: Background transcription processing without blocking UI
  void _processTranscriptionInBackground(String audioPath) async {
    try {
      final transcription = await _transcribeWithWhisper(audioPath);
      if (transcription.isEmpty) {
        throw Exception('Whisper returned empty transcription');
      }

      await _postCoordinator!.processVoiceTranscription(transcription);

      // Signal success
      _postCoordinator!.completeProcessing(success: true);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Background transcription processing failed: $e');
      }

      // CRITICAL: Reset recording state on ANY failure (including Whisper quota errors)
      // This ensures the UI can recover and allow new recordings
      _resetAudioRecordingVariables();

      // CRITICAL: Also reset coordinator recording state
      _postCoordinator!.resetRecordingState();

      // CRITICAL: Clear recording mode context in MediaCoordinator
      _postCoordinator!.clearRecordingModeContext();

      // Signal failure with proper error message
      _postCoordinator!.completeProcessing(
          success: false, error: 'Failed to process recording: $e');

      if (kDebugMode) {
        print('✅ Recording state reset after transcription failure');
        print('   Ready for new recording attempts');
      }
    }
  }

  /// Reset audio recording variables only (coordinator manages state)
  void _resetAudioRecordingVariables({bool clearPreSelectedMedia = false}) {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recordingTimer = null;
    _amplitudeTimer = null;
    _postCoordinator?.resetRecordingState();

    // Coordinator manages state - only handle media reset if requested
    if (clearPreSelectedMedia) {
      _postCoordinator?.reset(); // Full reset including media
    }

    // Only log reset when clearing media (significant event)
    if (kDebugMode && clearPreSelectedMedia) {
      print('🔄 Audio recording variables reset with media cleared');
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

  Future<void> _togglePlatform(String platform) async {
    try {
      // Get AuthService to check authentication status
      final authService = Provider.of<AuthService>(context, listen: false);

      // Check if platform is currently selected
      final currentPlatforms = _postCoordinator?.currentPost.platforms ?? [];
      final isCurrentlySelected = currentPlatforms.contains(platform);

      if (isCurrentlySelected) {
        // Platform is selected, user wants to deselect it
        _postCoordinator?.togglePlatform(platform);

        if (kDebugMode) {
          print('📱 Platform deselected: $platform');
        }
        return;
      }

      // Platform is not selected, user wants to select it
      // STEP 1: Check platform compatibility with current content
      final toggleResult = _postCoordinator?.canTogglePlatform(platform);
      if (toggleResult != null && !toggleResult.canToggle) {
        // Show compatibility warning through TranscriptionStatusBox
        if (mounted) {
          _postCoordinator?.requestStatusUpdate(
            toggleResult.message,
            StatusMessageType.warning,
            duration: const Duration(seconds: 4),
            priority: StatusPriority.medium,
          );
        }

        if (kDebugMode) {
          print(
              '⚠️ Platform $platform not compatible: ${toggleResult.message}');
        }
        return;
      }

      // STEP 2: Check if they're authenticated for this platform
      final isAuthenticated = await authService.isPlatformConnected(platform);

      if (isAuthenticated) {
        // User is authenticated and platform is compatible, toggle it
        _postCoordinator?.togglePlatform(platform);

        if (kDebugMode) {
          print('📱 Platform selected (authenticated): $platform');
        }
      } else {
        // User is not authenticated, initiate authentication flow
        if (kDebugMode) {
          print('🔐 Platform not authenticated, starting auth flow: $platform');
        }

        await _authenticatePlatform(platform, authService);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error toggling platform $platform: $e');
      }

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to connect to $platform: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _authenticatePlatform(
      String platform, AuthService authService) async {
    try {
      if (kDebugMode) {
        print('🔐 Starting authentication for $platform');
      }

      // Show loading status
      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Connecting to ${platform.substring(0, 1).toUpperCase()}${platform.substring(1)}...',
          StatusMessageType.info,
          duration: const Duration(seconds: 2),
        );
      }

      // Perform platform-specific authentication
      switch (platform.toLowerCase()) {
        case 'facebook':
          await authService.signInWithFacebook();
          break;
        case 'instagram':
          await authService.signInWithInstagramBusiness(context);
          break;
        case 'twitter':
          // TODO: Implement Twitter OAuth when available
          throw Exception('Twitter authentication not yet implemented');
        case 'tiktok':
          await authService.signInWithTikTok();
          break;
        default:
          throw Exception('Unknown platform: $platform');
      }

      // Authentication successful, now select the platform
      _postCoordinator?.togglePlatform(platform);

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          '${platform.substring(0, 1).toUpperCase()}${platform.substring(1)} connected successfully! ✅',
          StatusMessageType.success,
          duration: const Duration(seconds: 2),
        );
      }

      if (kDebugMode) {
        print('✅ Authentication successful for $platform');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Authentication failed for $platform: $e');
      }

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to connect to ${platform.substring(0, 1).toUpperCase()}${platform.substring(1)}: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 4),
        );
      }

      rethrow;
    }
  }

  Future<void> _navigateToMediaSelection() async {
    try {
      // ALWAYS request media permission before accessing media
      // This ensures permission is re-requested every time if previously denied
      final permissionManager =
          Provider.of<PermissionManager>(context, listen: false);
      final hasPermission = await permissionManager.requestMediaPermission();

      if (!hasPermission) {
        // Check if permanently denied to provide specific guidance
        final isPermanentlyDenied =
            await permissionManager.isMediaPermissionPermanentlyDenied();

        String errorMessage;
        if (isPermanentlyDenied) {
          errorMessage =
              'Media access permanently denied. Please enable it in device settings to select photos and videos.';
        } else {
          errorMessage =
              'Media access is required to select photos and videos. Please allow access and try again.';
        }

        if (kDebugMode) {
          print(
              '❌ Media permission denied. Permanently denied: $isPermanentlyDenied');
        }

        if (mounted) {
          // First show the status update
          _postCoordinator?.requestStatusUpdate(
            isPermanentlyDenied
                ? 'Media access permanently denied. Please enable in device settings.'
                : errorMessage,
            StatusMessageType.error,
            duration: const Duration(seconds: 6),
          );

          // Then show the snackbar if permanently denied
          if (isPermanentlyDenied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Media permission required. Enable in device settings.'),
                backgroundColor: Colors.red.withValues(alpha: 0.8),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () async {
                    await permissionManager.openDeviceSettings();
                  },
                ),
              ),
            );
          }
        }
        return;
      }

      if (kDebugMode) {
        print('✅ Media permission granted, proceeding to media selection...');
      }

      // Only log navigation attempts occasionally
      final shouldLogNav = kDebugMode &&
          (_lastProcessingLog == null ||
              DateTime.now().difference(_lastProcessingLog!).inSeconds > 30);

      if (shouldLogNav) {
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

        // Ensure coordinator is in idle state after returning from media selection
        _postCoordinator?.resetProcessing();

        // Clear the needsMediaSelection flag since media has been selected
        _postCoordinator?.clearNeedsMediaSelection();

        if (shouldLogNav) {
          print('✅ Media selection completed via coordinator');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in media selection navigation: $e');
      }

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to load media selection: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileScreen(),
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

  // Voice recording for interactive editing (IDENTICAL to Unified Action Button)
  Future<void> _startVoiceEditing() async {
    final coordinator = _postCoordinator;
    if (coordinator == null) return;

    // Check if processing - if so, don't allow voice editing
    if (coordinator.isProcessing) {
      if (kDebugMode) {
        print('⚠️ Cannot start voice editing: coordinator is processing');
      }
      return;
    }

    // IDENTICAL logic to Unified Action Button - just check current state and toggle
    if (coordinator.isRecording) {
      // If currently recording, stop it (same as Unified Action Button onRecordStop)
      await _stopUnifiedRecording();
    } else {
      // If not recording, start it (same as Unified Action Button onRecordStart)
      // ONLY DIFFERENCE: isVoiceDictation: true instead of false
      await _startUnifiedRecording(isVoiceDictation: true);
    }
  }

  Future<void> _editPostText() async {
    // CRITICAL: Ensure we're not in recording state when showing dialog
    if (_postCoordinator?.isRecording == true) {
      if (kDebugMode) {
        print('⚠️ Cannot edit text while recording - stopping recording first');
      }
      await _stopRecording();
    }

    if (!mounted) return;

    final coordinator = _postCoordinator;
    if (coordinator == null) return;

    try {
      // CRITICAL: Use overlay-based dialog to completely isolate from main widget tree
      // This prevents context invalidation during state transitions
      final result = await _showIsolatedTextEditDialog(coordinator);

      // CRITICAL: Check mounted after async operation
      if (!mounted) return;

      if (result == true) {
        if (mounted) {
          _postCoordinator?.requestStatusUpdate(
            'Post content updated! 📝',
            StatusMessageType.success,
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to edit text: $e');
      }

      // Ensure cleanup even on error
      coordinator.cancelTextEditing();

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to edit text: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  /// Show text editing dialog using overlay to isolate from main widget tree
  Future<bool?> _showIsolatedTextEditDialog(
      SocialActionPostCoordinator coordinator) async {
    // CRITICAL: Start persistent editing session in coordinator
    final textController = coordinator.startTextEditing();

    if (kDebugMode) {
      print('📝 Started isolated text editing session');
    }

    // Create overlay entry that's completely isolated from main widget tree
    OverlayEntry? overlayEntry;
    final completer = Completer<bool?>();

    void closeDialog(bool? result) {
      if (!completer.isCompleted) {
        overlayEntry?.remove();
        completer.complete(result);
      }
    }

    overlayEntry = OverlayEntry(
      builder: (overlayContext) => Material(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            child: AlertDialog(
              backgroundColor: Colors.black.withValues(alpha: 0.9),
              title: const Text(
                'Edit Post Content',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: TextField(
                  controller: textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter your post content...',
                    hintStyle: const TextStyle(color: Colors.white60),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF0055)),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                  ),
                  maxLines: 5,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    coordinator.cancelTextEditing();
                    closeDialog(false);
                  },
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await coordinator.commitTextEditing();
                      closeDialog(true);
                    } catch (e) {
                      if (kDebugMode) {
                        print('❌ Failed to commit text editing: $e');
                      }
                      coordinator.cancelTextEditing();
                      closeDialog(false);
                    }
                  },
                  child: const Text(
                    'SAVE',
                    style: TextStyle(color: Color(0xFFFF0055)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Insert overlay entry
    Overlay.of(context).insert(overlayEntry);

    // Wait for result
    final result = await completer.future;

    if (kDebugMode) {
      print('📝 Isolated text editing completed: $result');
    }

    return result;
  }

  Future<void> _editPostHashtags(List<String> currentHashtags) async {
    // CRITICAL: Ensure we're not in recording state when editing
    if (_postCoordinator?.isRecording == true) {
      if (kDebugMode) {
        print(
            '⚠️ Cannot edit hashtags while recording - stopping recording first');
      }
      await _stopRecording();
    }

    if (!mounted) return;

    final coordinator = _postCoordinator;
    if (coordinator == null) return;

    try {
      // CRITICAL: Use overlay-based dialog to completely isolate from main widget tree
      // This prevents context invalidation during state transitions
      final result = await _showIsolatedHashtagEditDialog(coordinator);

      // CRITICAL: Check mounted after async operation
      if (!mounted) return;

      if (result == true) {
        if (mounted) {
          _postCoordinator?.requestStatusUpdate(
            'Hashtags updated! 🏷️',
            StatusMessageType.success,
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to edit hashtags: $e');
      }

      // Ensure cleanup even on error
      coordinator.cancelHashtagEditing();

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Failed to edit hashtags: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  /// Show hashtag editing dialog using overlay to isolate from main widget tree
  Future<bool?> _showIsolatedHashtagEditDialog(
      SocialActionPostCoordinator coordinator) async {
    // CRITICAL: Start persistent hashtag editing session in coordinator
    final hashtagController = coordinator.startHashtagEditing();

    if (kDebugMode) {
      print('🏷️ Started isolated hashtag editing session');
    }

    // Create overlay entry that's completely isolated from main widget tree
    OverlayEntry? overlayEntry;
    final completer = Completer<bool?>();

    void closeDialog(bool? result) {
      if (!completer.isCompleted) {
        overlayEntry?.remove();
        completer.complete(result);
      }
    }

    overlayEntry = OverlayEntry(
      builder: (overlayContext) => Material(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            child: AlertDialog(
              backgroundColor: Colors.black.withValues(alpha: 0.9),
              title: const Text(
                'Edit Hashtags',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter hashtags separated by spaces or commas (without # symbol):',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TextField(
                        controller: hashtagController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'photography nature sunset beautiful...',
                          hintStyle: const TextStyle(color: Colors.white60),
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF0055)),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        maxLines: null,
                        expands: true,
                        autofocus: true,
                        textAlignVertical: TextAlignVertical.top,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hashtags will be automatically formatted for each platform when posted',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    coordinator.cancelHashtagEditing();
                    closeDialog(false);
                  },
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await coordinator.commitHashtagEdits();
                      closeDialog(true);
                    } catch (e) {
                      if (kDebugMode) {
                        print('❌ Failed to commit hashtag editing: $e');
                      }
                      coordinator.cancelHashtagEditing();
                      closeDialog(false);
                    }
                  },
                  child: const Text(
                    'SAVE',
                    style: TextStyle(color: Color(0xFFFF0055)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Insert overlay entry
    Overlay.of(context).insert(overlayEntry);

    // Wait for result
    final result = await completer.future;

    if (kDebugMode) {
      print('🏷️ Isolated hashtag editing completed: $result');
    }

    return result;
  }

  Future<void> _editSchedule() async {
    // CRITICAL: Ensure we're not in recording state when showing dialog
    if (_postCoordinator?.isRecording == true) {
      if (kDebugMode) {
        print(
            '⚠️ Cannot edit schedule while recording - stopping recording first');
      }
      await _stopRecording();
    }

    if (!mounted) return;

    // CRITICAL: Capture context and coordinator references before async operations
    final dialogContext = context;
    final coordinator = _postCoordinator;

    final now = DateTime.now();
    final currentAction = coordinator?.currentPost;
    final initialDate = currentAction?.options.schedule == 'now'
        ? now
        : DateTime.parse(
            currentAction?.options.schedule ?? now.toIso8601String());

    if (!dialogContext.mounted) return;
    final pickedDate = await showDatePicker(
      context: dialogContext,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    // CRITICAL: Check mounted after async operation
    if (!mounted) return;

    if (pickedDate != null) {
      if (!dialogContext.mounted) return;
      final pickedTime = await showTimePicker(
        context: dialogContext,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );

      // CRITICAL: Check mounted after second async operation
      if (!mounted) return;

      if (pickedTime != null) {
        final scheduledDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        try {
          // CRITICAL: Update through coordinator for centralized state management
          await coordinator
              ?.updatePostSchedule(scheduledDateTime.toIso8601String());

          if (kDebugMode) {
            print('✅ Schedule updated via coordinator');
            print('   New schedule: ${scheduledDateTime.toIso8601String()}');
          }

          if (mounted) {
            _postCoordinator?.requestStatusUpdate(
              'Schedule updated to ${DateFormat('MMM d, yyyy \'at\' h:mm a').format(scheduledDateTime)}',
              StatusMessageType.success,
              duration: const Duration(seconds: 2),
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed to update schedule via coordinator: $e');
          }

          if (mounted) {
            _postCoordinator?.requestStatusUpdate(
              'Failed to update schedule: $e',
              StatusMessageType.error,
              duration: const Duration(seconds: 3),
            );
          }
        }
      }
    }
  }

  Future<void> _confirmAndPost() async {
    if (_postCoordinator == null) {
      if (kDebugMode) {
        print('❌ Cannot confirm post: coordinator not available');
      }
      return;
    }

    try {
      if (kDebugMode) {
        print('🚀 Confirming and posting...');
      }

      // Check post readiness
      if (!_postCoordinator!.isReadyForExecution) {
        if (mounted) {
          _postCoordinator?.requestStatusUpdate(
            'Cannot post: Post is not ready for execution',
            StatusMessageType.warning,
            duration: const Duration(seconds: 4),
          );
        }
        return;
      }

      // Phase 1: Use coordinator state transition, mirror in widget
      _postCoordinator!.stopRecording();

      // Execute posting through coordinator
      final results = await _postCoordinator!.finalizeAndExecutePost();
      final allSucceeded = results.values.every((success) => success);

      if (kDebugMode) {
        print('📊 Posting results:');
        for (final entry in results.entries) {
          print('   ${entry.key}: ${entry.value ? 'Success' : 'Failed'}');
        }
      }

      // Show results dialog
      if (mounted) {
        // CRITICAL: Capture context before dialog
        final dialogContext = context;

        if (!dialogContext.mounted) return;
        await showDialog(
          context: dialogContext,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.black.withValues(alpha: 0.9),
            title: Text(
              allSucceeded ? '🎉 Post Published!' : '⚠️ Posting Issues',
              style: const TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allSucceeded
                      ? 'Your post was successfully published to all selected platforms!'
                      : 'Some platforms encountered issues:',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                for (final platform in results.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(
                          results[platform]! ? Icons.check_circle : Icons.error,
                          color: results[platform]! ? Colors.green : Colors.red,
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
                          results[platform]! ? 'Posted' : 'Failed',
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
                  Navigator.pop(dialogContext); // Close the dialog
                },
                child: const Text('OK',
                    style: TextStyle(color: Color(0xFFFF0055))),
              ),
            ],
          ),
        );

        // CRITICAL: Handle post-posting state based on results
        if (mounted) {
          if (allSucceeded) {
            // Post was successful - coordinator handles reset, widget mirrors
            if (kDebugMode) {
              print(
                  '✅ All posts successful, coordinator reset, navigating to history');
            }

            _resetAudioRecordingVariables(clearPreSelectedMedia: true);

            // Navigate to history screen
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => const HistoryScreen(),
              ),
              (route) => route.isFirst,
            );
          } else {
            // Some posts failed - coordinator handles error state, widget mirrors
            if (kDebugMode) {
              print(
                  '⚠️ Some posts failed, staying on command screen for retry');
            }

            _resetAudioRecordingVariables();
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to confirm and post: $e');
      }

      // Coordinator will handle error state transition
      _resetAudioRecordingVariables();

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Posting failed: $e',
          StatusMessageType.error,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL: Wrap Consumer in Builder to create stable context boundary
    // This prevents the Consumer from being invalidated during state transitions
    return Builder(
      builder: (stableContext) => Consumer<SocialActionPostCoordinator>(
        key: _consumerKey,
        builder: (consumerContext, coordinator, child) {
          // Set the coordinator reference for use in other methods
          _postCoordinator = coordinator;

          // Update button visibility based on coordinator state
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateButtonVisibility(coordinator);
          });

          return Scaffold(
            body: AnimatedBuilder(
              animation: _backgroundAnimation,
              // Build gradient container only; pass heavy child via AnimatedBuilder's child parameter
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
                  child: child, // Use prebuilt child
                );
              },
              // Build once per coordinator change, not every animation tick
              child: SafeArea(
                child: _buildReviewStyleLayout(coordinator),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewStyleLayout(SocialActionPostCoordinator coordinator) {
    const double gridUnit = 6.0;
    const double spacing4 = gridUnit * 4;

    final isProcessing = coordinator.isProcessing == true;
    final contentType = SocialPlatforms.getContentType(
      hasMedia: coordinator.hasMedia,
      mediaItems: coordinator.currentPost.content.media,
    );
    final incompatiblePlatforms = SocialPlatforms.getIncompatiblePlatforms(
      SocialPlatforms.all,
      contentType,
    );

    return Stack(
      children: [
        Column(
          children: [
            Container(
              height: 60,
              child: SevenIconHeader(
                selectedPlatforms: coordinator.currentPost.platforms,
                onPlatformToggle: _togglePlatform,
                leftAction: IconButton(
                  onPressed: isProcessing ? null : _showResetConfirmation,
                  icon:
                      const Icon(Icons.refresh, color: Colors.white, size: 24),
                  tooltip: 'Reset current post',
                ),
                rightAction: IconButton(
                  onPressed: isProcessing ? null : _navigateToProfile,
                  icon: const Icon(Icons.person, color: Colors.white, size: 28),
                  tooltip: 'Profile',
                ),
                enableInteraction: !isProcessing,
                incompatiblePlatforms: incompatiblePlatforms,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 226),
                  child: Column(
                    children: [
                      const SizedBox(height: spacing4),
                      if (coordinator.currentPost.platforms.isNotEmpty)
                        PostingStrategyInfo(coordinator: coordinator),
                      if (coordinator.currentPost.platforms.isNotEmpty)
                        FutureBuilder<List<String>>(
                          future: coordinator
                              .getPlatformsRequiringBusinessAccount(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              return BusinessAccountWarning(
                                platformsRequiringBusiness: snapshot.data!,
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      _buildCommandMediaSection(coordinator),
                      PostContentBox(
                        onVoiceEdit: _startVoiceEditing,
                        onEditText: _editPostText,
                        onEditHashtags: _editPostHashtags,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 226,
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const TranscriptionStatus(),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: SafeArea(
                      minimum: const EdgeInsets.only(bottom: 16),
                      child: Center(
                        child: TripleActionButtonSystem(
                          leftButtonController: _leftButtonController,
                          rightButtonController: _rightButtonController,
                          onRecordStart: _startRecording,
                          onRecordStop: _stopRecording,
                          onConfirmPost: _confirmAndPost,
                          onAddMedia: _navigateToMediaSelection,
                          onSavePost: _savePost,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Prominent animated scroll indicator
        if (_canScroll && !_isScrolled)
          Positioned(
            left: 0,
            right: 0,
            bottom: 226 - 56, // Just above the mic area
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _scrollIndicatorAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _scrollIndicatorAnimation.value),
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCommandMediaSection(SocialActionPostCoordinator coordinator) {
    const double gridUnit = 6.0;
    const double spacing2 = gridUnit * 2;

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
        const SizedBox(height: spacing2),
        UnifiedMediaButtons(
          onDirectorySelection: _navigateToDirectorySelection,
          onMediaSelection: _navigateToMediaSelection,
          hasMedia: coordinator.hasMedia,
        ),
        const SizedBox(height: 0),
      ],
    );
  }

  Widget _buildMediaPreview(
      BuildContext context, SocialActionPostCoordinator coordinator) {
    List<MediaItem> mediaToShow;
    if (coordinator.currentPost.content.media.isNotEmpty == true) {
      mediaToShow = coordinator.currentPost.content.media;
      if (kDebugMode) {
        print(
            '🖼️ _buildMediaPreview: Using currentPost media (${mediaToShow.length} items)');
        for (var i = 0; i < mediaToShow.length; i++) {
          print('   [$i]: ${mediaToShow[i].fileUri}');
        }
      }
    } else if (coordinator.preSelectedMedia.isNotEmpty) {
      mediaToShow = coordinator.preSelectedMedia;
      if (kDebugMode) {
        print(
            '🖼️ _buildMediaPreview: Using preSelectedMedia (${mediaToShow.length} items)');
        for (var i = 0; i < mediaToShow.length; i++) {
          print('   [$i]: ${mediaToShow[i].fileUri}');
        }
      }
    } else {
      if (kDebugMode) {
        print(
            '🖼️ _buildMediaPreview: No media to show, returning empty widget');
      }
      return const SizedBox.shrink();
    }

    final showPreselectedBadge = coordinator.preSelectedMedia.isNotEmpty;

    if (kDebugMode) {
      print(
          '🖼️ _buildMediaPreview: Creating EnhancedMediaPreview with ${mediaToShow.length} items');
      print('   showPreselectedBadge: $showPreselectedBadge');
    }

    return EnhancedMediaPreview(
      mediaItems: mediaToShow,
      selectedPlatforms: coordinator.currentPost.platforms,
      showPreselectedBadge: showPreselectedBadge,
      onTap: _navigateToMediaSelection,
    );
  }

  Widget _buildEmptyMediaPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A2A2A), // Lighter gray for better contrast
            Color(0xFF1F1F1F), // Slightly darker for subtle gradient
          ],
        ),
        // border: Border.all(
        //   color: Colors.white.withValues(alpha: 0.15),
        //   width: 1,
        // ),
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
              'Your media will appear here',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: AppTypography.large,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle save post action for the Triple Action Button System
  Future<void> _savePost() async {
    if (_postCoordinator == null) {
      if (kDebugMode) {
        print('❌ Cannot save post: coordinator not available');
      }
      return;
    }

    try {
      await _postCoordinator!.savePostAsDraft();
      if (kDebugMode) {
        print('✅ Post saved successfully via Triple Action Button');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save post: $e');
      }
    }
  }

  /// Update button visibility based on coordinator state
  void _updateButtonVisibility(SocialActionPostCoordinator coordinator) {
    // Left button (save) visibility
    if (coordinator.shouldShowLeftButton &&
        _leftButtonController.value == 0.0) {
      _leftButtonController.forward();
    } else if (!coordinator.shouldShowLeftButton &&
        _leftButtonController.value == 1.0) {
      _leftButtonController.reverse();
    }

    // Right button (media/confirm) visibility
    if (coordinator.shouldShowRightButton &&
        _rightButtonController.value == 0.0) {
      _rightButtonController.forward();
    } else if (!coordinator.shouldShowRightButton &&
        _rightButtonController.value == 1.0) {
      _rightButtonController.reverse();
    }
  }

  void _showResetConfirmation() async {
    if (!mounted) return;

    // CRITICAL: Capture context and coordinator references before async operations
    final dialogContext = context;
    final coordinator = _postCoordinator;

    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'RESET',
              style: TextStyle(color: Color(0xFFFF0055)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (kDebugMode) {
        print('🔄 User confirmed reset - clearing all post state');
      }

      // CRITICAL: Comprehensive reset sequence
      // 1. Reset coordinator state
      coordinator?.reset();

      // 2. Reset command screen recording variables
      _resetAudioRecordingVariables(clearPreSelectedMedia: true);

      // 3. Ensure clean state for new session
      _ensureCleanStateForNewSession();

      if (mounted) {
        _postCoordinator?.requestStatusUpdate(
          'Post reset successfully! 🔄',
          StatusMessageType.success,
          duration: const Duration(seconds: 2),
        );
      }

      if (kDebugMode) {
        print('✅ Complete reset sequence finished - ready for new recordings');
      }
    }
  }

  /// NEW: User-initiated retry capability
  void _handleRetryProcessing() {
    _postCoordinator?.resetProcessing();

    if (kDebugMode) {
      print('🔄 User initiated processing retry');
    }

    if (mounted) {
      _postCoordinator?.requestStatusUpdate(
        'Ready to record again! 🎤',
        StatusMessageType.success,
        duration: const Duration(seconds: 2),
      );
    }
  }

  // Simple stubs that delegate to the unified recording system
  Future<void> _startRecording() async {
    await _startUnifiedRecording(isVoiceDictation: false);
  }

  Future<void> _stopRecording() async {
    await _stopUnifiedRecording();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      final canScroll = _scrollController.position.maxScrollExtent > 0;
      final isScrolled = _scrollController.offset > 0;
      final scrollProgress = _scrollController.position.maxScrollExtent > 0
          ? _scrollController.offset /
              _scrollController.position.maxScrollExtent
          : 0.0;

      if (canScroll != _canScroll ||
          isScrolled != _isScrolled ||
          scrollProgress != _scrollProgress) {
        setState(() {
          _canScroll = canScroll;
          _isScrolled = isScrolled;
          _scrollProgress = scrollProgress;
        });
      }
    });
  }
}
