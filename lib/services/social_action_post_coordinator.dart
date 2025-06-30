import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/social_action.dart';
import '../models/media_validation.dart';
import '../models/platform_target.dart';
import '../services/media_coordinator.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../services/social_post_service.dart';
import '../services/account_auth_service.dart';
import '../services/auth/facebook_auth_service.dart';
import '../services/auth/instagram_auth_service.dart';
import '../services/auth/youtube_auth_service.dart';
import '../services/auth/twitter_auth_service.dart';
import '../services/auth/tiktok_auth_service.dart';
import '../services/natural_language_parser.dart';
import '../constants/social_platforms.dart';
import '../models/status_message.dart';
import 'platform_document_service.dart';
import 'platform_connection_service.dart';

/// Status message priority levels to prevent important messages from being overridden
enum StatusPriority { low, medium, high, critical }

/// Result of platform toggle validation
class PlatformToggleResult {
  final bool canToggle;
  final String message;

  const PlatformToggleResult({
    required this.canToggle,
    required this.message,
  });
}

/// Manages the persistent state and orchestration of social media posts
/// across all screens in the EchoPost application.
class SocialActionPostCoordinator extends ChangeNotifier {
  // Services - injected via constructor
  final MediaCoordinator _mediaCoordinator;
  final FirestoreService _firestoreService;
  final AIService _aiService;
  final SocialPostService _socialPostService;
  final AccountAuthService _authService;
  final NaturalLanguageParser _naturalLanguageParser;

  // Current post state - CRITICAL: Now non-nullable
  late SocialAction _currentPost;
  String _currentTranscription = '';
  List<MediaItem> _preSelectedMedia = [];

  // Core state flags
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _hasContent = false;
  bool _hasMedia = false;
  bool _needsMediaSelection = false;
  bool _hasError = false;
  String? _errorMessage;

  // CRITICAL: Persistent text editing state
  TextEditingController? _textEditingController;
  bool _isTextEditing = false;
  String? _editingOriginalText;

  // CRITICAL: Persistent hashtag editing state
  TextEditingController? _hashtagEditingController;
  bool _isHashtagEditing = false;
  List<String>? _editingOriginalHashtags;

  // Debouncing for state transitions only (removed auto-save debouncing)
  Timer? _stateTransitionDebouncer;

  // CRITICAL: Track disposal state to prevent notifications after disposal
  bool _isDisposed = false;

  // CRITICAL: State transition lock to prevent simultaneous transitions
  bool _isTransitioning = false;

  // Recording management
  String? _currentRecordingPath;
  int _recordingDuration = 0;
  final int maxRecordingDuration = 30;

  // Voice monitoring variables
  double _currentAmplitude = -160.0;
  double _maxAmplitude = -160.0;
  double _amplitudeSum = 0.0;
  int _amplitudeSamples = 0;
  bool _hasSpeechDetected = false;
  final double _speechThreshold = -40.0;
  final double _silenceThreshold = -50.0;

  // Status management with priority system
  StatusMessage? _temporaryStatus;
  Timer? _statusTimer;
  StatusPriority _currentStatusPriority = StatusPriority.low;
  Timer? _processingWatchdog;
  // Automatically clears error state after a short delay
  Timer? _errorClearTimer;
  static const Duration _defaultProcessingTimeout = Duration(seconds: 45);

  // NEW: Authentication state management
  final Map<String, bool> _platformAuthenticationState = {};
  bool _isInitializingAuthentication = false;
  StreamSubscription? _authStateSubscription;

  SocialActionPostCoordinator({
    required MediaCoordinator mediaCoordinator,
    required FirestoreService firestoreService,
    required AIService aiService,
    required SocialPostService socialPostService,
    required AccountAuthService authService,
    required NaturalLanguageParser naturalLanguageParser,
  })  : _mediaCoordinator = mediaCoordinator,
        _firestoreService = firestoreService,
        _aiService = aiService,
        _socialPostService = socialPostService,
        _authService = authService,
        _naturalLanguageParser = naturalLanguageParser {
    // Initialize with a clean post state immediately
    _initializeCleanPost();

    if (kDebugMode) {
      print(
          '✅ SocialActionPostCoordinator initialized with constructor injection');
      // Test natural language parsing patterns
      _naturalLanguageParser.testPatterns();
    }
  }

  /// Initialize a clean post state
  void _initializeCleanPost() {
    _currentPost = SocialAction(
      actionId: 'new_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now().toIso8601String(),
      platforms: [],
      content: Content(
        text: '',
        hashtags: [],
        mentions: [],
        media: [],
      ),
      options: Options(
        schedule: 'now',
        visibility: {},
      ),
      platformData: PlatformData(),
      internal: Internal(
        aiGenerated: false,
        originalTranscription: '',
        fallbackReason: 'initial_state',
      ),
    );
    _currentTranscription = '';
    _preSelectedMedia = [];
    _hasContent = false;
    _hasMedia = false;
    _needsMediaSelection = false;
    _hasError = false;
    _errorMessage = null;
  }

  // Getters for state flags
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get hasContent {
    final hasText = _currentPost.content.text.isNotEmpty;
    final hasMediaContent = hasMedia;
    return hasText || hasMediaContent;
  }

  bool get hasMedia {
    // Ensure media states are synced before checking
    _syncMediaStates();

    final currentPostHasMedia = _currentPost.content.media.isNotEmpty;

    return currentPostHasMedia;
  }

  bool get needsMediaSelection => _needsMediaSelection;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;

  // Additional state getters
  SocialAction get currentPost => _currentPost;
  String get currentTranscription => _currentTranscription;
  List<MediaItem> get preSelectedMedia => List.unmodifiable(_preSelectedMedia);
  bool get isTextEditing => _isTextEditing;
  TextEditingController? get textEditingController => _textEditingController;
  String? get editingOriginalText => _editingOriginalText;
  bool get isPostComplete => hasContent && _isMediaRequirementMet;
  bool get isReadyForExecution =>
      isPostComplete && !_isRecording && !_isProcessing;

  // Additional getters for recording state
  int get recordingDuration => _recordingDuration;
  double get currentAmplitude => _currentAmplitude;
  bool get hasSpeechDetected => _hasSpeechDetected;
  String? get currentRecordingPath => _currentRecordingPath;

  // Triple Action Button System visibility getters
  bool get shouldShowLeftButton =>
      (hasContent || hasMedia) && !isRecording && !isProcessing;
  bool get shouldShowRightButton => needsMediaSelection || isReadyForExecution;

  /// Check if media requirement is met based on selected platforms
  bool get _isMediaRequirementMet {
    if (_currentPost.platforms.isEmpty) return hasMedia;

    // Check if any selected platform requires media
    final requiresMedia = _currentPost.platforms
        .any((platform) => SocialPlatforms.requiresMedia(platform));

    return requiresMedia ? hasMedia : true;
  }

  /// Initialize recording path
  Future<void> initializeRecordingPath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/recording_$timestamp.m4a';

      if (kDebugMode) {
        print('🎤 Recording path initialized: $_currentRecordingPath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize recording path: $e');
      }
      throw Exception('Failed to initialize recording path: $e');
    }
  }

  /// Start recording with voice dictation option
  Future<void> startRecordingWithMode({required bool isVoiceDictation}) async {
    if (_isDisposed || _isTransitioning || _isProcessing || _isRecording) {
      if (kDebugMode) {
        print('❌ Cannot start recording:');
        print('   _isDisposed: $_isDisposed');
        print('   _isTransitioning: $_isTransitioning');
        print('   _isProcessing: $_isProcessing');
        print('   _isRecording: $_isRecording');
        print('   isVoiceDictation mode: $isVoiceDictation');
      }
      return;
    }
    _isTransitioning = true;

    try {
      // Initialize recording path
      await initializeRecordingPath();

      // Set recording mode context in MediaCoordinator
      _mediaCoordinator.setRecordingModeContext(isVoiceDictation);

      // Clear any previous error states and messages
      _hasError = false;
      _errorMessage = null;
      _isProcessing = false;
      _temporaryStatus = null;
      _statusTimer?.cancel();

      // Update state flags
      _isRecording = true;
      // CRITICAL: Edit mode is now determined by hasContent in MediaCoordinator context
      // No need to set _isEditMode here - it's derived from content presence
      _recordingDuration = 0;
      _hasSpeechDetected = false;

      // Reset voice monitoring variables
      _currentAmplitude = -160.0;
      _maxAmplitude = -160.0;
      _amplitudeSum = 0.0;
      _amplitudeSamples = 0;

      if (kDebugMode) {
        print(
            '🎤 Recording started in ${isVoiceDictation ? "voice dictation" : "command"} mode');
        print('   Recording path: $_currentRecordingPath');
        print('   _isRecording: $_isRecording');
        print(
            '   hasContent: $hasContent (edit mode determined by content presence)');
      }

      _safeNotifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to start recording: $e');
      }
      // CRITICAL: Reset all states on error
      _isRecording = false;
      _isProcessing = false;
      setError('Failed to start recording: $e');
    } finally {
      // CRITICAL: Always reset transition state, even on error
      _isTransitioning = false;
      if (kDebugMode) {
        print('🔄 Transition state reset: _isTransitioning = false');
      }
    }
  }

  /// Update amplitude data
  void updateAmplitude(double amplitude) {
    _currentAmplitude = amplitude;

    if (amplitude > _maxAmplitude) {
      _maxAmplitude = amplitude;
    }

    _amplitudeSamples++;
    _amplitudeSum += amplitude;

    if (amplitude > _speechThreshold) {
      _hasSpeechDetected = true;
    } else if (amplitude < _silenceThreshold && !_hasSpeechDetected) {
      // Only consider silence if we haven't detected speech yet
      _hasSpeechDetected = false;
    }

    _safeNotifyListeners();
  }

  /// Update recording duration
  void updateRecordingDuration(int duration) {
    _recordingDuration = duration;
    _safeNotifyListeners();
  }

  /// Reset recording state
  void resetRecordingState({bool preserveStatus = false}) {
    _currentRecordingPath = null;
    _isRecording = false;
    // NOTE: _isProcessing is managed by parent scope
    _recordingDuration = 0;
    _isTransitioning = false; // Ensure transitions are reset

    // Reset voice monitoring
    _currentAmplitude = -160.0;
    _maxAmplitude = -160.0;
    _amplitudeSum = 0.0;
    _amplitudeSamples = 0;
    _hasSpeechDetected = false;

    // Only clear error/status messages if not preserving status
    if (!preserveStatus) {
      _hasError = false;
      _errorMessage = null;
      _temporaryStatus = null;
      _statusTimer?.cancel();
      _errorClearTimer?.cancel();
    }

    _safeNotifyListeners();
  }

  /// Clear recording mode context in MediaCoordinator
  /// This is a public method to allow CommandScreen to clear the context on errors
  void clearRecordingModeContext() {
    _mediaCoordinator.setRecordingModeContext(false);

    if (kDebugMode) {
      print('🔄 Recording mode context cleared in MediaCoordinator');
    }
  }

  /// Get normalized amplitude for UI
  double get normalizedAmplitude {
    const double minDb = -60.0;
    const double maxDb = -10.0;

    if (_currentAmplitude <= minDb) return 0.0;
    if (_currentAmplitude >= maxDb) return 1.0;

    return (_currentAmplitude - minDb) / (maxDb - minDb);
  }

  /// Check if post is ready for execution
  bool get isPostReady {
    if (_currentPost.platforms.isEmpty) return false;

    final hasContent = _currentPost.content.text.isNotEmpty;
    final hasPlatforms = _currentPost.platforms.isNotEmpty;
    final hasRequiredMedia = _currentPost.platforms
        .any((platform) => SocialPlatforms.requiresMedia(platform));

    // If platforms require media, check media presence
    if (hasRequiredMedia && !hasMedia) return false;

    return hasContent && hasPlatforms;
  }

  /// CRITICAL: Top-level processing state management
  /// These methods ensure isProcessing is controlled at the orchestration level
  void setProcessingState(bool isProcessing) {
    _isProcessing = isProcessing;
    _safeNotifyListeners();

    if (kDebugMode) {
      print('🔄 Processing state changed: $_isProcessing');
    }
  }

  /// NEW: Start processing state with optional watchdog timer
  void startProcessing({Duration? timeout}) {
    // Guard against double-calls
    if (_isProcessing) {
      if (kDebugMode) {
        print(
            '⚠️ startProcessing() called while already processing - ignoring');
      }
      return;
    }

    _isProcessing = true;
    _hasError = false;
    _errorMessage = null;

    // Start watchdog timer
    _processingWatchdog?.cancel();
    _processingWatchdog = Timer(timeout ?? _defaultProcessingTimeout, () {
      if (_isProcessing) {
        if (kDebugMode) {
          print(
              '⏰ Processing watchdog timeout - forcing completion with failure');
        }
        completeProcessing(success: false, error: 'Processing timed out');
      }
    });

    _safeNotifyListeners();

    if (kDebugMode) {
      print(
          '🔄 Processing started with ${timeout?.inSeconds ?? _defaultProcessingTimeout.inSeconds}s timeout');
    }
  }

  /// NEW: Complete processing state with explicit success/failure
  void completeProcessing({required bool success, String? error}) {
    _processingWatchdog?.cancel();
    _processingWatchdog = null;
    _isProcessing = false;

    if (!success && error != null) {
      setError(error);
    }

    _safeNotifyListeners();

    if (kDebugMode) {
      print('✅ Processing completed: ${success ? 'SUCCESS' : 'FAILURE'}');
      if (error != null) print('   Error: $error');
    }
  }

  /// NEW: Allow manual processing reset (for user-initiated retry)
  void resetProcessing() {
    _processingWatchdog?.cancel();
    _processingWatchdog = null;
    _isProcessing = false;
    _hasError = false;
    _errorMessage = null;
    _safeNotifyListeners();

    if (kDebugMode) {
      print('🔄 Processing manually reset');
    }
  }

  /// DEPRECATED: Use startProcessing() and completeProcessing() instead
  /// This method will be removed in a future version
  @Deprecated(
      'Use startProcessing() and completeProcessing() for better state control')
  Future<void> executeWithProcessingState<T>(
      Future<T> Function() operation) async {
    setProcessingState(true);
    try {
      await operation();
    } finally {
      setProcessingState(false);
    }
  }

  /// DEPRECATED: Use startProcessing() and completeProcessing() instead
  /// This method will be removed in a future version
  @Deprecated(
      'Use startProcessing() and completeProcessing() for better state control with timeout')
  Future<void> executeWithProcessingStateAndTimeout<T>(
      Future<T> Function() operation,
      {Duration timeout = const Duration(seconds: 30)}) async {
    setProcessingState(true);
    try {
      await operation().timeout(timeout);
    } catch (e) {
      if (e is TimeoutException) {
        if (kDebugMode) {
          print('⏰ Operation timed out, forcing processing state reset');
        }
      }
      rethrow;
    } finally {
      setProcessingState(false);
    }
  }

  /// Process voice transcription and generate social action
  Future<void> processVoiceTranscription(String transcription) async {
    try {
      // NO _isProcessing management here anymore - controlled by parent
      _currentTranscription = transcription;
      _safeNotifyListeners();

      // CRITICAL: Fetch recent media BEFORE AI processing if requested
      await _handleRecentMediaRequest(transcription);

      final aiPost =
          await _tryAiGenerate(transcription, existingPost: _currentPost);
      final mergedPost = _mergeWithExisting(aiPost);
      final mediaPost = await _includeMedia(mergedPost, transcription);
      final finalPost = _sanitizePost(mediaPost);

      _currentPost = finalPost;
      _hasContent = finalPost.content.text.isNotEmpty;
      _hasMedia = finalPost.content.media.isNotEmpty;
      _needsMediaSelection =
          _transcriptionReferencesMedia(transcription) && !_hasMedia;

      // CRITICAL: Reset recording states but NOT _isProcessing (managed by parent)
      _isRecording = false;
      _isTransitioning = false;
      _hasError = false;
      _errorMessage = null;

      // CRITICAL: Clear recording mode context in MediaCoordinator
      _mediaCoordinator.setRecordingModeContext(false);

      if (kDebugMode) {
        print('✅ Voice transcription processed and states reset:');
        print('   _isRecording: $_isRecording');
        print('   _isProcessing: $_isProcessing (managed by parent)');
        print(
            '   hasContent: $hasContent (edit mode determined by content presence)');
        print('   _isTransitioning: $_isTransitioning');
      }

      _safeNotifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to process voice transcription: $e');
      }

      // CRITICAL: Reset recording states but NOT _isProcessing (managed by parent)
      _isRecording = false;
      _isTransitioning = false;
      _hasError = false;
      _errorMessage = null;

      // CRITICAL: Clear recording mode context even on error
      _mediaCoordinator.setRecordingModeContext(false);

      setError(e.toString());
      _safeNotifyListeners();
      rethrow;
    }
  }

  /// Handle recent media requests before AI processing
  Future<void> _handleRecentMediaRequest(String transcription) async {
    final mediaRequest =
        _naturalLanguageParser.parseMediaRequest(transcription);
    final requestedType = mediaRequest?.mediaType;

    // Check if user wants recent media using the parser
    final wantsRecentMedia =
        _naturalLanguageParser.hasRecentMediaIndicators(transcription);

    if (kDebugMode) {
      print('🔍 Media request analysis:');
      print('   Transcription: "$transcription"');
      print('   Media request: $mediaRequest');
      print('   Wants recent media: $wantsRecentMedia');
      print('   Requested type: $requestedType');
      print('   Current preSelectedMedia count: ${_preSelectedMedia.length}');
    }

    // If recent media is requested, fetch it
    if (wantsRecentMedia) {
      if (kDebugMode) {
        print('📱 Fetching recent media...');
      }

      final recentMedia =
          await _getRecentMedia(limit: 10); // Increase limit for debugging

      if (kDebugMode) {
        print('📱 Recent media fetch result: ${recentMedia.length} items');
        for (int i = 0; i < recentMedia.length && i < 5; i++) {
          final media = recentMedia[i];
          print('   [$i] ${media.fileUri}');
          print('       MIME: ${media.mimeType}');
          print(
              '       Type: ${media.mimeType.startsWith('video/') ? 'VIDEO' : 'IMAGE'}');
        }
      }

      if (recentMedia.isNotEmpty) {
        // Filter by requested type if specified
        List<MediaItem> candidateMedia;
        if (requestedType != null) {
          candidateMedia = recentMedia
              .where((media) => _mediaMatchesType(media, requestedType))
              .toList();

          if (kDebugMode) {
            print(
                '📱 Filtered media for type "$requestedType": ${candidateMedia.length} items');
            for (int i = 0; i < candidateMedia.length && i < 3; i++) {
              final media = candidateMedia[i];
              print('   [$i] ${media.fileUri}');
              print('       MIME: ${media.mimeType}');
            }
          }
        } else {
          candidateMedia = recentMedia;
        }

        if (candidateMedia.isNotEmpty) {
          final media = candidateMedia.first;

          if (kDebugMode) {
            print('📱 Selected media:');
            print('   File: ${media.fileUri}');
            print('   MIME type: ${media.mimeType}');
            print('   Requested type: $requestedType');
            print(
                '   Media matches type: ${requestedType == null || _mediaMatchesType(media, requestedType)}');
          }

          _preSelectedMedia = [media];
          if (kDebugMode) {
            print('✅ Pre-selected recent media: ${media.fileUri}');
            print('   Media type: ${media.mimeType}');
            print('   Requested type: $requestedType');
            print('   hasMedia getter now returns: $hasMedia');
            print('   preSelectedMedia count: ${_preSelectedMedia.length}');
          }
          // Notify listeners immediately so UI updates
          _safeNotifyListeners();
        } else {
          if (kDebugMode) {
            print('⚠️ No media found matching requested type: $requestedType');
            print(
                '   Available media types: ${recentMedia.map((m) => m.mimeType).take(5).join(', ')}');
          }
          // Media found but wrong type - need media selection
          _needsMediaSelection = true;
        }
      } else {
        if (kDebugMode) {
          print(
              '⚠️ No recent media found for request - user needs to configure media sources');
        }
        // No media found - need media selection
        _needsMediaSelection = true;
      }
    } else {
      if (kDebugMode) {
        print('ℹ️ No recent media keywords detected in transcription');
      }
    }
  }

  /// Reset to initial state with proper cleanup
  void reset() {
    _initializeCleanPost();
    _isRecording = false;
    _isProcessing = false; // CRITICAL: Explicitly reset processing state
    _isTransitioning = false; // Reset transition lock

    // CRITICAL: Reset all recording states including locks
    resetRecordingState();

    // CRITICAL: Clean up any active text editing session
    _endTextEditingSession();

    // CRITICAL: Cancel any pending timers
    _statusTimer?.cancel();
    _processingWatchdog?.cancel();
    _temporaryStatus = null;
    _stateTransitionDebouncer?.cancel();
    _errorClearTimer?.cancel();

    _safeNotifyListeners();

    if (kDebugMode) {
      print('🔄 SocialActionPostCoordinator: Complete state reset');
      print('   _isRecording: $_isRecording');
      print('   _isProcessing: $_isProcessing');
      print('   _isTransitioning: $_isTransitioning');
    }
  }

  /// Step 1: Try AI generation with simplified fallback
  Future<SocialAction> _tryAiGenerate(String transcription,
      {SocialAction? existingPost}) async {
    try {
      if (kDebugMode) {
        print('🤖 _tryAiGenerate: Starting AI processing');
        print('   Transcription: "$transcription"');
        print('   PreSelectedMedia count: ${_preSelectedMedia.length}');
        print('   ExistingPost: ${existingPost?.actionId}');
      }

      // CRITICAL: Set existing post context in MediaCoordinator for AI
      // If we have existing content, pass it as context for editing
      _mediaCoordinator
          .setExistingPostContext(hasContent ? _currentPost : existingPost);

      final aiResult = await _aiService.processVoiceCommand(
        transcription,
        preSelectedMedia:
            _preSelectedMedia.isNotEmpty ? _preSelectedMedia : null,
      );

      if (kDebugMode) {
        print('✅ _tryAiGenerate: AI processing successful');
        print('   AI result platforms: ${aiResult.platforms}');
        print('   AI result media count: ${aiResult.content.media.length}');
      }

      return aiResult;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ AI generation failed, creating baseline post: $e');
        print(
            '   Will create baseline with preSelectedMedia: ${_preSelectedMedia.length} items');
      }
      final baselinePost = await _createBaselinePostAsync(transcription);

      if (kDebugMode) {
        print('✅ Baseline post created:');
        print('   Platforms: ${baselinePost.platforms}');
        print('   Media count: ${baselinePost.content.media.length}');
        print('   Text: "${baselinePost.content.text}"');
      }

      return baselinePost;
    } finally {
      // Clear the context after processing
      _mediaCoordinator.setExistingPostContext(null);
    }
  }

  /// Step 2: Merge with existing post if available
  SocialAction _mergeWithExisting(SocialAction newPost) {
    return _currentPost.copyWith(
      platforms: newPost.platforms.isNotEmpty ? newPost.platforms : null,
      content: _currentPost.content.copyWith(
        text: newPost.content.text.isNotEmpty ? newPost.content.text : null,
        hashtags: newPost.content.hashtags.isNotEmpty
            ? newPost.content.hashtags
            : null,
        mentions: newPost.content.mentions.isNotEmpty
            ? newPost.content.mentions
            : null,
        media: newPost.content.media.isNotEmpty ? newPost.content.media : null,
      ),
      internal: _currentPost.internal.copyWith(
        aiGenerated: newPost.internal.aiGenerated,
        originalTranscription: newPost.internal.originalTranscription,
        fallbackReason: newPost.internal.fallbackReason,
      ),
    );
  }

  /// Check if media matches requested type
  bool _mediaMatchesType(MediaItem media, String requestedType) {
    final mimeType = media.mimeType.toLowerCase();
    return requestedType == 'image'
        ? mimeType.startsWith('image/')
        : mimeType.startsWith('video/');
  }

  /// Step 3: Include media in post
  Future<SocialAction> _includeMedia(
      SocialAction post, String transcription) async {
    try {
      if (kDebugMode) {
        print('🖼️ _includeMedia: Starting media inclusion');
        print('   Post already has media: ${post.content.media.length}');
        print('   PreSelectedMedia count: ${_preSelectedMedia.length}');
      }

      // If post already has media from baseline creation or AI, return as-is
      if (post.content.media.isNotEmpty) {
        if (kDebugMode) {
          print('✅ _includeMedia: Post already has media, returning as-is');
        }
        return post;
      }

      // If we have pre-selected media but post doesn't have it, add it
      if (_preSelectedMedia.isNotEmpty) {
        final requestedType = _getRequestedMediaType(transcription);

        // Validate media type if specified
        if (requestedType != null) {
          final matchingMedia = _preSelectedMedia
              .where((media) => _mediaMatchesType(media, requestedType))
              .toList();

          if (matchingMedia.isEmpty) {
            if (kDebugMode) {
              print(
                  '⚠️ Pre-selected media does not match requested type: $requestedType');
            }
            _needsMediaSelection = true;
            return post;
          }

          // Use only matching media
          final updatedPost = post.copyWith(
            content: post.content.copyWith(media: matchingMedia),
          );

          if (kDebugMode) {
            print(
                '✅ _includeMedia: Added ${matchingMedia.length} matching media items');
          }

          return updatedPost;
        } else {
          // No specific type requested, use all pre-selected media
          final updatedPost = post.copyWith(
            content: post.content.copyWith(media: List.from(_preSelectedMedia)),
          );

          if (kDebugMode) {
            print(
                '✅ _includeMedia: Added ${_preSelectedMedia.length} pre-selected media items');
          }

          return updatedPost;
        }
      }

      if (kDebugMode) {
        print('ℹ️ _includeMedia: No media to include, returning post as-is');
      }

      return post;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error including media: $e');
      }
      return post;
    }
  }

  /// Get requested media type from transcription
  String? _getRequestedMediaType(String transcription) {
    final mediaRequest =
        _naturalLanguageParser.parseMediaRequest(transcription);
    return mediaRequest?.mediaType;
  }

  /// Step 4: Sanitize and validate post
  SocialAction _sanitizePost(SocialAction post) {
    final actionId = post.actionId.isEmpty
        ? 'sanitized_${DateTime.now().millisecondsSinceEpoch}'
        : post.actionId;

    final sanitizedText =
        post.content.text.replaceAll(RegExp(r'[^\w\s\.,!?@#-]'), '').trim();

    final platforms = post.platforms.isEmpty
        ? _selectDefaultPlatforms(sanitizedText, hasMedia,
            _transcriptionReferencesMedia(post.internal.originalTranscription))
        : post.platforms;

    return post.copyWith(
      actionId: actionId,
      platforms: platforms,
      content: post.content.copyWith(text: sanitizedText),
    );
  }

  /// Create baseline post with intelligent platform selection
  Future<SocialAction> _createBaselinePostAsync(String transcription) async {
    final hasMedia = _preSelectedMedia.isNotEmpty;
    final hasMediaReference = _transcriptionReferencesMedia(transcription);
    final selectedPlatforms = await _selectDefaultPlatformsAsync(
        transcription, hasMedia, hasMediaReference);
    final hashtags = _generateIntelligentHashtags(transcription);

    return SocialAction(
      actionId: 'baseline_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now().toIso8601String(),
      platforms: selectedPlatforms,
      content: Content(
        text: transcription,
        hashtags: hashtags,
        media: hasMedia ? List.from(_preSelectedMedia) : [],
      ),
      options: Options(
        schedule: 'now',
        visibility: _createVisibilityMap(selectedPlatforms),
      ),
      platformData: _createPlatformData(selectedPlatforms),
      internal: Internal(
        aiGenerated: false,
        originalTranscription: transcription,
        fallbackReason: 'baseline_creation',
      ),
    );
  }

  /// Get list of platforms that the user has authenticated with
  Future<List<String>> _getAuthenticatedPlatforms() async {
    try {
      // Use PlatformConnectionService as the single source of truth
      final connectedPlatforms =
          await PlatformConnectionService.getConnectedPlatforms();

      if (kDebugMode) {
        print('🔐 Authenticated platforms: $connectedPlatforms');
      }

      return connectedPlatforms;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to check platform authentication: $e');
      }
      // Return empty list if auth check fails
      return [];
    }
  }

  /// Intelligently select default platforms based on content type, media availability, and user authentication
  Future<List<String>> _selectDefaultPlatformsAsync(
      String text, bool hasMedia, bool hasMediaReference) async {
    final platforms = <String>[];

    // Get authenticated platforms
    final authenticatedPlatforms = await _getAuthenticatedPlatforms();

    if (authenticatedPlatforms.isEmpty) {
      // No authenticated platforms - use conservative defaults for AI processing
      // These will be filtered during posting based on actual authentication
      platforms.addAll(SocialPlatforms.textSupported);
      if (hasMedia || hasMediaReference) {
        platforms.addAll(SocialPlatforms.mediaRequired);
      }

      if (kDebugMode) {
        print(
            '🎯 No authenticated platforms - using defaults for AI processing: $platforms');
        print('   Note: Actual posting will require authentication');
      }
    } else {
      // User has authenticated platforms - be smarter about selection

      // Always include authenticated text-supporting platforms
      for (final platform in SocialPlatforms.textSupported) {
        if (authenticatedPlatforms.contains(platform)) {
          platforms.add(platform);
        }
      }

      // Add authenticated media-requiring platforms if we have media
      if (hasMedia || hasMediaReference) {
        for (final platform in SocialPlatforms.mediaRequired) {
          if (authenticatedPlatforms.contains(platform)) {
            platforms.add(platform);
          }
        }
      }

      // If no platforms were selected but we have authenticated ones,
      // include at least one authenticated platform
      if (platforms.isEmpty && authenticatedPlatforms.isNotEmpty) {
        platforms.add(authenticatedPlatforms.first);
      }

      if (kDebugMode) {
        print('🎯 Smart platform selection based on authentication:');
        print(
            '   Text: "${text.substring(0, text.length > 50 ? 50 : text.length)}${text.length > 50 ? '...' : ''}"');
        print('   Has media: $hasMedia');
        print('   Has media reference: $hasMediaReference');
        print('   Authenticated platforms: $authenticatedPlatforms');
        print('   Selected platforms: $platforms');
      }
    }

    return platforms;
  }

  /// Intelligently select default platforms based on content type, media availability, and user authentication
  List<String> _selectDefaultPlatforms(
      String text, bool hasMedia, bool hasMediaReference) {
    // For now, use the synchronous version for backwards compatibility
    // The async version should be used when possible
    final platforms = <String>[];

    // Conservative defaults that work without authentication requirements
    platforms.addAll(SocialPlatforms.textSupported);

    // Add media-requiring platforms only if we have media or user referenced media
    if (hasMedia || hasMediaReference) {
      platforms.addAll(SocialPlatforms.mediaRequired);
    }

    if (kDebugMode) {
      print('🎯 Platform selection (sync - backwards compatibility):');
      print('   Selected platforms: $platforms');
      print('   Note: Use _selectDefaultPlatformsAsync for smarter selection');
    }

    return platforms;
  }

  /// Create platform-specific configuration for selected platforms
  Map<String, String> _createVisibilityMap(List<String> platforms) {
    final visibility = <String, String>{};
    for (final platform in platforms) {
      visibility[platform] = 'public';
    }
    return visibility;
  }

  /// Create platform data for selected platforms
  PlatformData _createPlatformData(List<String> platforms) {
    return PlatformData(
      facebook: platforms.contains('facebook')
          ? FacebookData(postHere: true)
          : FacebookData(postHere: false),
      instagram: platforms.contains('instagram')
          ? InstagramData(postHere: true, postType: 'feed')
          : InstagramData(postHere: false, postType: 'feed'),
      youtube: platforms.contains('youtube')
          ? YouTubeData(postHere: true)
          : YouTubeData(postHere: false),
      twitter: platforms.contains('twitter')
          ? TwitterData(postHere: true)
          : TwitterData(postHere: false),
      tiktok: platforms.contains('tiktok')
          ? TikTokData(postHere: true, sound: Sound())
          : TikTokData(postHere: false, sound: Sound()),
    );
  }

  /// Get recent media with performance limit
  Future<List<MediaItem>> _getRecentMedia({int limit = 25}) async {
    try {
      if (kDebugMode) {
        print('🔍 _getRecentMedia: Starting with limit $limit');
      }

      final recentMediaMaps = await _mediaCoordinator.getMediaForQuery(
        '', // Empty search for general recent media
        mediaTypes: ['image', 'video'],
      );

      if (kDebugMode) {
        print(
            '🔍 _getRecentMedia: MediaCoordinator returned ${recentMediaMaps.length} items');
        if (recentMediaMaps.isNotEmpty) {
          final first = recentMediaMaps.first;
          print('   First item: ${first['file_uri']}');
          print('   MIME type: ${first['mime_type']}');
        }
      }

      // Convert to MediaItem objects with limit
      final recentMedia = recentMediaMaps.take(limit).map((mediaMap) {
        final mediaItem = MediaItem(
          fileUri: mediaMap['file_uri'] ?? '',
          mimeType: mediaMap['mime_type'] ?? 'image/jpeg',
          deviceMetadata: DeviceMetadata(
            creationTime:
                mediaMap['timestamp'] ?? DateTime.now().toIso8601String(),
            latitude: mediaMap['device_metadata']?['latitude'],
            longitude: mediaMap['device_metadata']?['longitude'],
            orientation: mediaMap['device_metadata']?['orientation'] ?? 1,
            width: mediaMap['device_metadata']?['width'] ?? 0,
            height: mediaMap['device_metadata']?['height'] ?? 0,
            fileSizeBytes: mediaMap['device_metadata']?['file_size_bytes'] ?? 0,
            duration: mediaMap['device_metadata']?['duration'] ?? 0,
            bitrate: mediaMap['device_metadata']?['bitrate'],
            samplingRate: mediaMap['device_metadata']?['sampling_rate'],
            frameRate: mediaMap['device_metadata']?['frame_rate'],
          ),
        );

        if (kDebugMode) {
          print(
              '   Converted to MediaItem: ${mediaItem.fileUri}, type: ${mediaItem.mimeType}');
        }

        return mediaItem;
      }).toList();

      if (kDebugMode) {
        print(
            '🔍 _getRecentMedia: Returning ${recentMedia.length} MediaItem objects');
      }

      return recentMedia;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to get recent media: $e');
        print('   Stack trace: ${StackTrace.current}');
      }
      return [];
    }
  }

  /// Check if transcription suggests the user wants media included
  bool _transcriptionReferencesMedia(String transcription) {
    return _naturalLanguageParser.hasMediaReference(transcription);
  }

  /// Generate intelligent hashtags based on content analysis
  List<String> _generateIntelligentHashtags(String text) {
    final lowerText = text.toLowerCase();
    final hashtags = <String>[];

    // Content-based hashtag mapping
    final hashtagMap = {
      // General engagement
      'photo': ['photography', 'photooftheday', 'picoftheday'],
      'picture': ['photography', 'photooftheday', 'picoftheday'],
      'selfie': ['selfie', 'selfieoftheday', 'me'],
      'video': ['video', 'videooftheday', 'content'],

      // Activities
      'workout': ['fitness', 'workout', 'gym', 'health', 'fitlife'],
      'travel': ['travel', 'wanderlust', 'adventure', 'explore'],
      'food': ['food', 'foodie', 'delicious', 'yummy', 'foodstagram'],
      'coffee': ['coffee', 'coffeetime', 'caffeine', 'morningfuel'],
      'sunset': ['sunset', 'nature', 'sky', 'beautiful', 'golden'],
      'beach': ['beach', 'ocean', 'waves', 'paradise', 'summer'],
      'work': ['work', 'productivity', 'hustle', 'grind', 'business'],
      'art': ['art', 'creative', 'artist', 'artwork', 'design'],
      'music': ['music', 'song', 'musician', 'melody', 'sound'],

      // Emotions/Moods
      'happy': ['happy', 'joy', 'smile', 'positive', 'good'],
      'excited': ['excited', 'thrilled', 'pumped', 'energy'],
      'grateful': ['grateful', 'blessed', 'thankful', 'appreciation'],
      'motivated': ['motivation', 'inspiration', 'goals', 'success'],

      // Time-based
      'monday': ['mondaymotivation', 'newweek', 'fresh'],
      'friday': ['friday', 'weekend', 'tgif'],
      'morning': ['morning', 'sunrise', 'newday', 'fresh'],
      'night': ['night', 'evening', 'nighttime'],
    };

    // Find matching hashtags
    for (final keyword in hashtagMap.keys) {
      if (lowerText.contains(keyword)) {
        hashtags.addAll(hashtagMap[keyword]!);
        if (hashtags.length >= 6) break; // Limit to prevent overflow
      }
    }

    // Add default hashtags if none found
    if (hashtags.isEmpty) {
      hashtags.addAll(['life', 'daily', 'moments', 'share']);
    }

    // Ensure we have 3-6 hashtags
    final uniqueHashtags = hashtags.toSet().take(6).toList();

    // Add generic hashtags if we have less than 3
    if (uniqueHashtags.length < 3) {
      final genericHashtags = [
        'instagood',
        'photooftheday',
        'love',
        'beautiful',
        'amazing'
      ];
      for (final generic in genericHashtags) {
        if (!uniqueHashtags.contains(generic)) {
          uniqueHashtags.add(generic);
          if (uniqueHashtags.length >= 3) break;
        }
      }
    }

    if (kDebugMode) {
      print('🔖 Generated intelligent hashtags: $uniqueHashtags');
    }

    return uniqueHashtags;
  }

  /// Remove hashtags from text content (clean text for display)
  String _removeHashtagsFromText(String text) {
    // Remove hashtags in the format #hashtag or #HashTag
    final hashtagRegex = RegExp(r'#[a-zA-Z0-9_]+\s*', multiLine: true);
    final cleanText = text.replaceAll(hashtagRegex, '').trim();

    // Clean up extra whitespace
    return cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Format hashtags for specific platform requirements
  String _formatHashtagsForPlatform(List<String> hashtags, String platform) {
    if (hashtags.isEmpty) return '';

    // Ensure hashtags don't have '#' prefix (strip if present)
    final cleanHashtags = hashtags
        .map((tag) => tag.startsWith('#') ? tag.substring(1) : tag)
        .toList();

    switch (platform.toLowerCase()) {
      case 'instagram':
        // Instagram: hashtags at the end, separated by spaces, max 30 hashtags
        final limitedHashtags = cleanHashtags.take(30).toList();
        return '\n\n${limitedHashtags.map((tag) => '#$tag').join(' ')}';

      case 'twitter':
        // Twitter: hashtags integrated naturally, max 280 chars total, 2-3 hashtags recommended
        final limitedHashtags = cleanHashtags.take(3).toList();
        return ' ${limitedHashtags.map((tag) => '#$tag').join(' ')}';

      case 'facebook':
        // Facebook: hashtags at the end, each on new line for better readability
        return '\n\n${cleanHashtags.map((tag) => '#$tag').join(' ')}';

      case 'tiktok':
        // TikTok: hashtags at the end, space-separated, max 100 chars for hashtags
        var formattedHashtags = cleanHashtags.map((tag) => '#$tag').join(' ');
        if (formattedHashtags.length > 100) {
          // Truncate if too long
          final truncatedTags = <String>[];
          var currentLength = 0;
          for (final tag in cleanHashtags) {
            final tagWithHash = '#$tag ';
            if (currentLength + tagWithHash.length <= 100) {
              truncatedTags.add(tag);
              currentLength += tagWithHash.length;
            } else {
              break;
            }
          }
          formattedHashtags = truncatedTags.map((tag) => '#$tag').join(' ');
        }
        return '\n\n$formattedHashtags';

      default:
        // Default format: hashtags at the end, space-separated
        return '\n\n${cleanHashtags.map((tag) => '#$tag').join(' ')}';
    }
  }

  /// Get platform-formatted post content with hashtags
  String getFormattedPostContent(String platform) {
    final baseText = _currentPost.content.text;
    final hashtags = _currentPost.content.hashtags;

    // Remove any existing hashtags from the base text to avoid duplication
    final cleanText = _removeHashtagsFromText(baseText);

    // Add platform-specific hashtag formatting
    final formattedHashtags = _formatHashtagsForPlatform(hashtags, platform);

    return '$cleanText$formattedHashtags'.trim();
  }

  /// Update post content with unified hashtag handling
  Future<void> updatePostContent(String newText) async {
    // Extract hashtags from the text
    final extractedHashtags = _extractHashtagsFromText(newText);

    // Clean text by removing hashtags
    final cleanText = _removeHashtagsFromText(newText);

    // Merge with existing hashtags, avoiding duplicates
    final existingHashtags = _currentPost.content.hashtags;
    final allHashtags = <String>{...existingHashtags, ...extractedHashtags}
        .where((tag) => tag.isNotEmpty)
        .toList();

    _currentPost = _currentPost.copyWith(
      content: _currentPost.content.copyWith(
        text: cleanText,
        hashtags: allHashtags,
      ),
    );

    // Update state flags
    _hasContent = cleanText.isNotEmpty || allHashtags.isNotEmpty;
    _hasError = false;
    _errorMessage = null;
    _safeNotifyListeners(); // Always refresh view

    if (kDebugMode) {
      print('✅ Post content updated with unified hashtag handling');
      print('   Clean text: "$cleanText"');
      print('   Extracted hashtags: $extractedHashtags');
      print('   Final hashtags: ${_currentPost.content.hashtags}');
    }
  }

  /// Update post hashtags independently
  Future<void> updatePostHashtags(List<String> newHashtags) async {
    _currentPost = _currentPost.copyWith(
      content: _currentPost.content.copyWith(hashtags: newHashtags),
    );

    // Update state flags
    _hasContent =
        _currentPost.content.text.isNotEmpty || newHashtags.isNotEmpty;
    _hasError = false;
    _errorMessage = null;
    _safeNotifyListeners();

    if (kDebugMode) {
      print('✅ Hashtags updated via coordinator');
      print('   New hashtags: $newHashtags');
      print('   Total hashtags: ${newHashtags.length}');
    }
  }

  /// Add media to current post
  Future<void> addMedia(List<MediaItem> media) async {
    _preSelectedMedia.addAll(media);

    final updatedMedia = List<MediaItem>.from(_currentPost.content.media);
    updatedMedia.addAll(media);

    _currentPost = _currentPost.copyWith(
      content: _currentPost.content.copyWith(media: updatedMedia),
    );

    // Sync media states and update flags
    _syncMediaStates();
    _hasError = false;
    _errorMessage = null;
    _needsMediaSelection = false;
    _safeNotifyListeners();
  }

  /// Toggle platform selection
  void togglePlatform(String platform) {
    final updatedPlatforms = List<String>.from(_currentPost.platforms);
    if (updatedPlatforms.contains(platform)) {
      updatedPlatforms.remove(platform);
    } else {
      updatedPlatforms.add(platform);
    }

    _currentPost = _currentPost.copyWith(platforms: updatedPlatforms);
    // SIMPLIFIED: Clear state after updating
    _hasError = false;
    _errorMessage = null;
    _safeNotifyListeners();
  }

  /// Replace media in current post
  Future<void> replaceMedia(List<MediaItem> media) async {
    // Update media in current post
    _currentPost = _currentPost.copyWith(
      content: _currentPost.content.copyWith(media: media),
    );

    // Clear pre-selected media since we now have media in the post
    _preSelectedMedia.clear();

    // If no platforms selected, add default platforms based on media type
    if (_currentPost.platforms.isEmpty) {
      final platforms = _selectDefaultPlatforms(
        _currentPost.content.text,
        true, // hasMedia is true since we just added media
        false, // hasMediaReference is false since this is direct selection
      );
      _currentPost = _currentPost.copyWith(platforms: platforms);
    }

    // Sync media states and update flags
    _syncMediaStates();
    _hasError = false;
    _errorMessage = null;
    _needsMediaSelection = false;
    _safeNotifyListeners();

    if (kDebugMode) {
      print('✅ Media replaced: ${media.length} items');
      print('   Platforms: ${_currentPost.platforms}');
      print('   hasMedia getter returns: $hasMedia');
    }
  }

  /// Synchronize coordinator with an existing post
  void syncWithExistingPost(SocialAction existingPost) {
    _currentPost = existingPost;
    _currentTranscription = existingPost.internal.originalTranscription;
    // SIMPLIFIED: Clear state after syncing
    _hasError = false;
    _errorMessage = null;

    // Clear pre-selected media since we now have a complete post
    if (existingPost.content.media.isNotEmpty) {
      _preSelectedMedia.clear();
    }

    if (kDebugMode) {
      print(
          '🔄 Coordinator synced with existing post: ${existingPost.actionId}');
    }
  }

  /// Update post schedule through coordinator
  Future<void> updatePostSchedule(String newSchedule) async {
    _currentPost = _currentPost.copyWith(
      options: Options(
        schedule: newSchedule,
        locationTag: _currentPost.options.locationTag,
        visibility: _currentPost.options.visibility,
        replyToPostId: _currentPost.options.replyToPostId,
      ),
    );

    // SIMPLIFIED: Clear state after updating
    _hasError = false;
    _errorMessage = null;
    _safeNotifyListeners();

    if (kDebugMode) {
      print('✅ Schedule updated via coordinator: $newSchedule');
    }
  }

  /// Upload finalized post to Firestore
  Future<void> uploadFinalizedPost() async {
    try {
      await _firestoreService.saveAction(_currentPost.toJson());

      if (kDebugMode) {
        print('✅ Finalized post uploaded: ${_currentPost.actionId}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to upload finalized post: $e');
      }
      setError(e.toString());
      rethrow;
    }
  }

  /// Save current post as draft to Firestore
  /// This leverages the same persistence mechanism as uploadFinalizedPost but is specifically
  /// for draft saving without requiring social media posting confirmation
  Future<void> savePostAsDraft() async {
    try {
      // Ensure media is synced before saving
      _syncMediaStates();

      // Save current post state to Firestore as draft
      await _firestoreService.saveAction(_currentPost.toJson());

      if (kDebugMode) {
        print('✅ Post saved as draft: ${_currentPost.actionId}');
        print('   Content: "${_currentPost.content.text}"');
        print('   Platforms: ${_currentPost.platforms}');
        print('   Media count: ${_currentPost.content.media.length}');
      }

      // Provide user feedback
      requestStatusUpdate(
        'Post saved as draft! 💾',
        StatusMessageType.success,
        duration: const Duration(seconds: 2),
        priority: StatusPriority.medium,
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save post as draft: $e');
      }
      setError('Failed to save post: $e');
      rethrow;
    }
  }

  /// Execute post across all selected social media platforms
  Future<Map<String, bool>> executePostToSocialMedia() async {
    try {
      if (kDebugMode) {
        print(
            '🚀 Executing post across platforms: ${_currentPost.platforms.join(', ')}');
      }

      final results = await _socialPostService.postToAllPlatforms(_currentPost);

      if (kDebugMode) {
        print('✅ Social media posting completed');
        for (final entry in results.entries) {
          print('   ${entry.key}: ${entry.value ? 'Success' : 'Failed'}');
        }
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to execute post: $e');
      }
      setError(e.toString());
      rethrow;
    }
  }

  /// Synchronize media states to ensure consistency between preSelectedMedia and currentPost
  void _syncMediaStates() {
    // If we have pre-selected media but current post doesn't have it, add it
    if (_preSelectedMedia.isNotEmpty && _currentPost.content.media.isEmpty) {
      _currentPost = _currentPost.copyWith(
        content: _currentPost.content.copyWith(
          media: List.from(_preSelectedMedia),
        ),
      );
      if (kDebugMode) {
        print(
            '🔄 Synced ${_preSelectedMedia.length} pre-selected media to current post');
      }
    }

    // Update hasMedia flag based on final consolidated state
    _hasMedia = _currentPost.content.media.isNotEmpty;
  }

  /// Confirm post and reset state
  Future<void> confirmPost() async {
    try {
      // Confirm the post logic here
      // ... existing code ...

      // Reset recording state to allow further recordings
      resetRecordingState();

      if (kDebugMode) {
        print('✅ Post confirmed and state reset for further recordings');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error confirming post: $e');
      }
      setError('Failed to confirm post: $e');
    }
  }

  /// CRITICAL: Safe notify listeners that checks disposal state
  void _safeNotifyListeners() {
    if (_isDisposed) {
      if (kDebugMode) {
        print('⚠️ Attempted to notify listeners after disposal - skipping');
      }
      return;
    }

    try {
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in notifyListeners: $e');
      }
    }
  }

  /// Extract hashtags from text content (spoken hashtags)
  List<String> _extractHashtagsFromText(String text) {
    // Match hashtags in the format #hashtag or #HashTag
    final hashtagRegex = RegExp(r'#([a-zA-Z0-9_]+)', multiLine: true);
    final matches = hashtagRegex.allMatches(text);

    final extractedHashtags = matches
        .map((match) => match.group(1)!)
        .where((hashtag) => hashtag.isNotEmpty)
        .map((hashtag) => hashtag.toLowerCase()) // Normalize to lowercase
        .toSet() // Remove duplicates
        .toList();

    return extractedHashtags;
  }

  // CRITICAL: Persistent text editing management
  // These methods provide coordinator-managed text editing that persists across UI rebuilds

  /// Start text editing session with persistent controller
  TextEditingController startTextEditing() {
    if (_isDisposed) {
      throw StateError('Cannot start text editing - coordinator is disposed');
    }

    // Dispose existing controller if any
    _textEditingController?.dispose();

    // Create new controller with current text
    final currentText = _currentPost.content.text;
    _textEditingController = TextEditingController(text: currentText);
    _editingOriginalText = currentText;
    _isTextEditing = true;

    if (kDebugMode) {
      print('📝 Text editing session started');
      print('   Original text: "$currentText"');
    }

    _safeNotifyListeners();
    return _textEditingController!;
  }

  /// Commit text editing changes
  Future<void> commitTextEditing() async {
    if (!_isTextEditing || _textEditingController == null) {
      if (kDebugMode) {
        print('⚠️ No active text editing session to commit');
      }
      return;
    }

    final newText = _textEditingController!.text.trim();

    // Only update if text actually changed
    if (newText != _editingOriginalText) {
      await updatePostContent(newText);

      if (kDebugMode) {
        print('✅ Text editing committed');
        print('   Old text: "$_editingOriginalText"');
        print('   New text: "$newText"');
      }
    } else {
      if (kDebugMode) {
        print('📝 Text editing cancelled - no changes made');
      }
    }

    _endTextEditingSession();
  }

  /// Cancel text editing without saving changes
  void cancelTextEditing() {
    if (kDebugMode) {
      print('❌ Text editing cancelled');
    }
    _endTextEditingSession();
  }

  /// Internal method to clean up text editing session
  void _endTextEditingSession() {
    _textEditingController?.dispose();
    _textEditingController = null;
    _editingOriginalText = null;
    _isTextEditing = false;
    _safeNotifyListeners();
  }

  // CRITICAL: Persistent hashtag editing management
  // These methods provide coordinator-managed hashtag editing that integrates with AIService

  /// Start hashtag editing session with persistent controller
  TextEditingController startHashtagEditing() {
    if (_isDisposed) {
      throw StateError(
          'Cannot start hashtag editing - coordinator is disposed');
    }

    // Dispose existing controller if any
    _hashtagEditingController?.dispose();

    // Create new controller with current hashtags (space-separated, no # symbols)
    final currentHashtags = _currentPost.content.hashtags;
    final hashtagText = currentHashtags.join(' ');
    _hashtagEditingController = TextEditingController(text: hashtagText);
    _editingOriginalHashtags = List.from(currentHashtags);
    _isHashtagEditing = true;

    if (kDebugMode) {
      print('🏷️ Hashtag editing session started');
      print('   Original hashtags: $currentHashtags');
      print('   Controller text: "$hashtagText"');
    }

    _safeNotifyListeners();
    return _hashtagEditingController!;
  }

  /// Commit hashtag editing changes with AI integration
  Future<void> commitHashtagEdits() async {
    if (!_isHashtagEditing || _hashtagEditingController == null) {
      if (kDebugMode) {
        print('⚠️ No active hashtag editing session to commit');
      }
      return;
    }

    final newHashtagText = _hashtagEditingController!.text.trim();

    // Parse hashtags from text input (space or comma separated)
    final newHashtags = _parseHashtagInput(newHashtagText);
    final originalHashtags = _editingOriginalHashtags ?? [];

    // Only process if hashtags actually changed
    if (!_hashtagListsEqual(newHashtags, originalHashtags)) {
      if (kDebugMode) {
        print('🏷️ Hashtag editing - changes detected');
        print('   Original: $originalHashtags');
        print('   New: $newHashtags');
        print('   Applying direct hashtag update...');
      }

      // FIXED: Use direct hashtag update instead of AI processing to ensure immediate UI update
      // This preserves the existing text content while only updating hashtags
      _currentPost = _currentPost.copyWith(
        content: _currentPost.content.copyWith(hashtags: newHashtags),
      );

      // Update state flags
      _hasContent =
          _currentPost.content.text.isNotEmpty || newHashtags.isNotEmpty;
      _hasError = false;
      _errorMessage = null;

      // CRITICAL: Notify listeners immediately so UI updates
      _safeNotifyListeners();

      if (kDebugMode) {
        print('✅ Hashtag editing committed via direct update');
        print('   Final hashtags: ${_currentPost.content.hashtags}');
        print('   Text preserved: "${_currentPost.content.text}"');
      }
    } else {
      if (kDebugMode) {
        print('🏷️ Hashtag editing cancelled - no changes made');
      }
    }

    _endHashtagEditingSession();
  }

  /// Cancel hashtag editing without saving changes
  void cancelHashtagEditing() {
    if (kDebugMode) {
      print('❌ Hashtag editing cancelled');
    }
    _endHashtagEditingSession();
  }

  /// Internal method to clean up hashtag editing session
  void _endHashtagEditingSession() {
    _hashtagEditingController?.dispose();
    _hashtagEditingController = null;
    _editingOriginalHashtags = null;
    _isHashtagEditing = false;
    _safeNotifyListeners();
  }

  /// Parse hashtag input text into normalized list
  List<String> _parseHashtagInput(String input) {
    if (input.isEmpty) return [];

    // Split by spaces and commas, clean up each hashtag
    final parts = input.split(RegExp(r'[,\s]+'));
    final hashtags = <String>[];

    for (final part in parts) {
      final cleaned = part.trim();
      if (cleaned.isNotEmpty) {
        // Remove # symbol if present, normalize to lowercase
        final hashtag = cleaned.startsWith('#')
            ? cleaned.substring(1).toLowerCase()
            : cleaned.toLowerCase();

        // Only add if it's a valid hashtag (alphanumeric + underscore)
        if (RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(hashtag)) {
          hashtags.add(hashtag);
        }
      }
    }

    // Remove duplicates and return
    return hashtags.toSet().toList();
  }

  /// Compare two hashtag lists for equality
  bool _hashtagListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    final set1 = list1.toSet();
    final set2 = list2.toSet();
    return set1.containsAll(set2) && set2.containsAll(set1);
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print('🗑️ SocialActionPostCoordinator: Starting disposal...');
    }

    _isDisposed = true;
    _isTransitioning = false; // CRITICAL: Clear any stuck transition state
    _stateTransitionDebouncer?.cancel();
    _endTextEditingSession();
    _endHashtagEditingSession();
    _statusTimer?.cancel();
    _processingWatchdog?.cancel();
    _errorClearTimer?.cancel();
    _authStateSubscription?.cancel(); // NEW: Clean up auth state subscription

    if (kDebugMode) {
      print('🗑️ SocialActionPostCoordinator: Disposal complete');
      print('   _isTransitioning cleared: false');
    }

    super.dispose();
  }

  /// Process voice command with media
  Future<void> processVoiceCommand(String transcription,
      {List<MediaItem>? preSelectedMedia}) async {
    try {
      // NO _isProcessing management here anymore - controlled by parent
      _hasError = false;
      _errorMessage = null;
      notifyListeners();

      final action = await _aiService.processVoiceCommand(
        transcription,
        preSelectedMedia: preSelectedMedia,
      );

      // Check if AI service indicates media selection is needed
      _needsMediaSelection = action.needsMediaSelection;

      // Merge AI-generated content with existing post
      _currentPost = _mergeWithExisting(action);
      _hasContent = _currentPost.content.text.isNotEmpty;
      _hasMedia = _currentPost.content.media.isNotEmpty;
      // _isProcessing managed by parent
      notifyListeners();
    } catch (e) {
      // _isProcessing managed by parent
      setError(e.toString());
      rethrow;
    }
  }

  void clearNeedsMediaSelection() {
    _needsMediaSelection = false;
    _temporaryStatus = null;
    _statusTimer?.cancel();
    _safeNotifyListeners();

    if (kDebugMode) {
      print('✅ Cleared needsMediaSelection flag and status');
    }
  }

  /// Set an error message that auto-dismisses after [duration].
  /// Defaults to 3 seconds.
  void setError(String message,
      {Duration duration = const Duration(seconds: 3)}) {
    _hasError = true;
    _errorMessage = message;

    // Push the message to the status system with the same duration
    requestStatusUpdate(
      message,
      StatusMessageType.error,
      duration: duration,
      priority: StatusPriority.high,
    );

    // Restart the auto-clear timer
    _errorClearTimer?.cancel();
    _errorClearTimer = Timer(duration, () {
      _hasError = false;
      _errorMessage = null;
      _safeNotifyListeners();
    });
  }

  /// Stop recording state
  Future<void> stopRecording() async {
    if (_isDisposed || _isTransitioning) return;
    _isTransitioning = true;

    try {
      // Reset core recording flags
      // NOTE: _isProcessing is managed by parent scope
      _isRecording = false;

      // Clear recording mode context
      _mediaCoordinator.setRecordingModeContext(false);

      // Log recording statistics
      if (kDebugMode) {
        print('🛑 Recording stopped');
        if (_hasSpeechDetected) {
          print('   Speech detected during recording');
          print('   Max amplitude: ${_maxAmplitude.toStringAsFixed(1)} dBFS');
          print(
              '   Average amplitude: ${(_amplitudeSum / _amplitudeSamples).toStringAsFixed(1)} dBFS');
        } else {
          print('⚠️ No speech detected during recording');
        }
      }

      // Handle no speech detection case
      if (!_hasSpeechDetected) {
        // Request a temporary status update that will be cleared on next recording
        requestStatusUpdate(
          'No speech detected. Please try again.',
          StatusMessageType.warning,
          duration: const Duration(seconds: 3),
          priority: StatusPriority.high,
        );

        // Reset state but keep the temporary status
        resetRecordingState(preserveStatus: true);
        return;
      }

      _safeNotifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error stopping recording: $e');
      }
      // CRITICAL: Ensure states are reset even on error
      // NOTE: _isProcessing is managed by parent scope
      _isRecording = false;
      setError('Failed to stop recording: $e');
    } finally {
      // CRITICAL: Always reset transition state, even on error
      _isTransitioning = false;
      if (kDebugMode) {
        print('🔄 Transition state reset: _isTransitioning = false');
      }
    }
  }

  // Semantic Visual State - App-wide UI consistency
  Color getActionButtonColor() {
    if (_isRecording) return const Color(0xFFFF0055);
    if (_isProcessing) return Colors.orange;
    if (_needsMediaSelection) return Colors.blue;
    if (_hasContent) return const Color(0xFFFF0055);
    return Colors.white.withValues(alpha: 0.2);
  }

  IconData getActionButtonIcon() {
    if (_isRecording) return Icons.stop;
    if (_isProcessing) return Icons.hourglass_empty;
    if (_needsMediaSelection) return Icons.photo_library;
    if (_hasContent) return Icons.send;
    return Icons.mic;
  }

  Color getVoiceDictationColor() {
    if (_isRecording && hasContent) return const Color(0xFFFF0055);
    if (_isProcessing) return Colors.orange;
    return Colors.white.withValues(alpha: 0.9);
  }

  IconData getVoiceDictationIcon() {
    return _isRecording && hasContent ? Icons.stop : Icons.mic;
  }

  String getStatusMessage() => _activeStatus!.message;
  Color getStatusColor() => _activeStatus!.getColor();

  // Direct action methods to prevent state derivation in widgets
  bool get isVoiceRecording => _isRecording && hasContent;

  /// Toggle voice dictation mode with proper MediaCoordinator sync
  Future<void> toggleVoiceDictation() async {
    if (_isDisposed || _isTransitioning || _isProcessing) {
      if (kDebugMode) {
        print('⚠️ Cannot toggle voice dictation:');
        print('   _isDisposed: $_isDisposed');
        print('   _isTransitioning: $_isTransitioning');
        print('   _isProcessing: $_isProcessing');
      }
      return;
    }

    _isTransitioning = true;

    try {
      if (hasContent && _isRecording) {
        await stopRecording();
      } else {
        await startRecordingWithMode(isVoiceDictation: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error toggling voice dictation: $e');
      }
      setError('Failed to toggle voice dictation: $e');
    } finally {
      // CRITICAL: Always reset transition state, even on error
      _isTransitioning = false;
      if (kDebugMode) {
        print('🔄 Transition state reset: _isTransitioning = false');
      }
    }
  }

  Future<void> handleActionButtonPress() async {
    if (_isRecording) {
      await stopRecording();
    } else if (_needsMediaSelection) {
      // This should trigger navigation to media selection in the UI
      // The actual navigation happens in the widget, not here
      if (kDebugMode) {
        print(
            '🔵 Media selection needed - UI should navigate to media selection');
      }
      return;
    } else if (_hasContent) {
      // NEW: Start processing for post execution
      startProcessing(timeout: const Duration(seconds: 30));

      // Execute in background without blocking
      _executePostInBackground();
    } else {
      await startRecordingWithMode(isVoiceDictation: false);
    }
  }

  /// NEW: Background post execution without Future wrapper
  void _executePostInBackground() async {
    try {
      await finalizeAndExecutePost();
      completeProcessing(success: true);
    } catch (e) {
      completeProcessing(success: false, error: e.toString());
    }
  }

  StatusMessage _computePrimaryStatus() {
    if (_isProcessing) {
      return StatusMessage(
        message: 'Processing your voice command...',
        type: StatusMessageType.processing,
      );
    }
    if (_isRecording) {
      final remainingSeconds = maxRecordingDuration - _recordingDuration;
      return StatusMessage(
        message: hasContent
            ? 'Dictating... ${remainingSeconds}s'
            : 'Recording command... ${remainingSeconds}s',
        type: StatusMessageType.recording,
      );
    }
    if (_hasError) {
      return StatusMessage(
        message: _errorMessage ?? 'An error occurred',
        type: StatusMessageType.error,
      );
    }
    if (_needsMediaSelection) {
      return StatusMessage(
        message: 'Please select media for your post',
        type: StatusMessageType.info,
      );
    }
    if (_currentTranscription.isEmpty) {
      return StatusMessage(
        message: 'Welcome to EchoPost.',
        type: StatusMessageType.info,
      );
    }
    return StatusMessage(
      message: _currentTranscription,
      type: StatusMessageType.info,
    );
  }

  StatusMessage? get _activeStatus =>
      _temporaryStatus ?? _computePrimaryStatus();

  void requestStatusUpdate(String message, StatusMessageType type,
      {Duration? duration, StatusPriority priority = StatusPriority.medium}) {
    // Only override if new status has higher or equal priority
    if (_temporaryStatus != null &&
        priority.index < _currentStatusPriority.index) {
      if (kDebugMode) {
        print(
            '⚠️ Status update blocked: ${priority.name} < ${_currentStatusPriority.name}');
        print('   Blocked message: "$message"');
        print('   Current message: "${_temporaryStatus?.message}"');
      }
      return;
    }

    _statusTimer?.cancel();
    _currentStatusPriority = priority;

    _temporaryStatus = StatusMessage(
      message: message,
      type: type,
    );

    if (duration != null) {
      _statusTimer = Timer(duration, () {
        _temporaryStatus = null;
        _currentStatusPriority = StatusPriority.low; // Reset priority
        _safeNotifyListeners();
      });
    }

    _safeNotifyListeners();
  }

  /// Request all required permissions (directory and microphone)
  Future<bool> requestAllPermissions() async {
    try {
      if (kDebugMode) {
        print('🔐 Requesting all required permissions...');
      }

      // Request directory permissions first
      final directoryPermissionState =
          await PhotoManager.requestPermissionExtend();
      final hasDirectoryPermission = directoryPermissionState.hasAccess;

      // Request microphone permission
      final hasMicrophonePermission =
          await Permission.microphone.request().isGranted;

      if (kDebugMode) {
        print('📱 Permission status:');
        print('   Directory: ${hasDirectoryPermission ? '✅' : '❌'}');
        print('   Microphone: ${hasMicrophonePermission ? '✅' : '❌'}');
      }

      return hasDirectoryPermission && hasMicrophonePermission;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error requesting permissions: $e');
      }
      setError('Failed to request permissions: $e');
      return false;
    }
  }

  /// Validates and recovers media for the current post
  /// This method ensures all media URIs are valid and attempts recovery for broken ones
  Future<bool> validateAndRecoverCurrentPostMedia({
    MediaValidationConfig? config,
  }) async {
    if (_currentPost.content.media.isEmpty) {
      if (kDebugMode) {
        print(
            'ℹ️ SocialActionPostCoordinator: No media to validate in current post');
      }
      return true;
    }

    final validationConfig = config ??
        (kDebugMode
            ? MediaValidationConfig.debug
            : MediaValidationConfig.production);

    try {
      if (kDebugMode) {
        print(
            '🔍 SocialActionPostCoordinator: Validating ${_currentPost.content.media.length} media items');
      }

      final batchResult = await _mediaCoordinator.validateAndRecoverMediaList(
        _currentPost.content.media,
        config: validationConfig,
      );

      final recoveredMedia = <MediaItem>[];
      bool hasRecoveredItems = false;
      bool hasFailedItems = false;

      for (int i = 0; i < batchResult.results.length; i++) {
        final result = batchResult.results[i];
        final originalMedia = _currentPost.content.media[i];

        if (result.isValid) {
          if (result.wasRecovered) {
            // Create new MediaItem with recovered URI
            final recoveredItem = _mediaCoordinator.createRecoveredMediaItem(
                originalMedia, result);
            if (recoveredItem != null) {
              recoveredMedia.add(recoveredItem);
              hasRecoveredItems = true;

              if (kDebugMode) {
                print(
                    '✅ SocialActionPostCoordinator: Recovered media via ${result.recoveryMethodDescription}');
              }
            } else {
              hasFailedItems = true;
            }
          } else {
            // Keep original valid media
            recoveredMedia.add(originalMedia);
          }
        } else {
          // Media couldn't be recovered
          hasFailedItems = true;
          if (kDebugMode) {
            print(
                '❌ SocialActionPostCoordinator: Failed to recover media: ${result.errorMessage}');
          }
        }
      }

      // Update the current post with recovered media
      if (recoveredMedia.isNotEmpty) {
        _currentPost = _currentPost.copyWith(
          content: _currentPost.content.copyWith(media: recoveredMedia),
        );

        // Sync with pre-selected media if needed
        if (hasRecoveredItems) {
          _preSelectedMedia = List.from(recoveredMedia);
        }

        // Update Firestore with recovered URIs if configured
        if (validationConfig.updateFirestore && hasRecoveredItems) {
          try {
            await _firestoreService.updateAction(
                _currentPost.actionId, _currentPost.toJson());
            if (kDebugMode) {
              print(
                  '✅ SocialActionPostCoordinator: Updated Firestore with recovered media URIs');
            }
          } catch (e) {
            if (kDebugMode) {
              print(
                  '⚠️ SocialActionPostCoordinator: Failed to update Firestore with recovered URIs: $e');
            }
          }
        }
      }

      // Update media states
      _syncMediaStates();
      _safeNotifyListeners();

      // Provide user feedback if there were recoveries or failures
      if (hasRecoveredItems && hasFailedItems) {
        requestStatusUpdate(
          'Some media recovered, others removed',
          StatusMessageType.warning,
          duration: const Duration(seconds: 3),
          priority: StatusPriority.medium,
        );
      } else if (hasRecoveredItems) {
        requestStatusUpdate(
          'Media recovered successfully',
          StatusMessageType.success,
          duration: const Duration(seconds: 2),
          priority: StatusPriority.medium,
        );
      } else if (hasFailedItems) {
        requestStatusUpdate(
          'Some media could not be recovered',
          StatusMessageType.warning,
          duration: const Duration(seconds: 3),
          priority: StatusPriority.medium,
        );
      }

      if (kDebugMode) {
        print(
            '✅ SocialActionPostCoordinator: Media validation completed: $batchResult');
      }

      return batchResult.allItemsValid;
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ SocialActionPostCoordinator: Error during media validation: $e');
      }
      setError('Media validation failed: $e');
      return false;
    }
  }

  /// Validates and recovers media for an existing post (used for loading from Firestore)
  Future<SocialAction> validateAndRecoverPostMedia(
    SocialAction action, {
    MediaValidationConfig? config,
  }) async {
    if (action.content.media.isEmpty) {
      return action;
    }

    final validationConfig = config ??
        (kDebugMode
            ? MediaValidationConfig.debug
            : MediaValidationConfig.production);

    try {
      if (kDebugMode) {
        print(
            '🔍 SocialActionPostCoordinator: Validating media for post: ${action.actionId}');
      }

      final batchResult = await _mediaCoordinator.validateAndRecoverMediaList(
        action.content.media,
        config: validationConfig,
      );

      final recoveredMedia = <MediaItem>[];
      bool hasRecoveredItems = false;

      for (int i = 0; i < batchResult.results.length; i++) {
        final result = batchResult.results[i];
        final originalMedia = action.content.media[i];

        if (result.isValid) {
          if (result.wasRecovered) {
            final recoveredItem = _mediaCoordinator.createRecoveredMediaItem(
                originalMedia, result);
            if (recoveredItem != null) {
              recoveredMedia.add(recoveredItem);
              hasRecoveredItems = true;
            }
          } else {
            recoveredMedia.add(originalMedia);
          }
        }
        // Skip media that couldn't be recovered
      }

      final updatedAction = action.copyWith(
        content: action.content.copyWith(media: recoveredMedia),
      );

      // Update Firestore with recovered URIs if configured and items were recovered
      if (validationConfig.updateFirestore && hasRecoveredItems) {
        try {
          await _firestoreService.updateAction(
              action.actionId, updatedAction.toJson());
          if (kDebugMode) {
            print(
                '✅ SocialActionPostCoordinator: Updated Firestore with recovered media for post: ${action.actionId}');
          }
        } catch (e) {
          if (kDebugMode) {
            print(
                '⚠️ SocialActionPostCoordinator: Failed to update Firestore for post ${action.actionId}: $e');
          }
        }
      }

      if (kDebugMode) {
        print(
            '✅ SocialActionPostCoordinator: Post media validation completed for ${action.actionId}: $batchResult');
      }

      return updatedAction;
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ SocialActionPostCoordinator: Error validating post media for ${action.actionId}: $e');
      }
      return action; // Return original action if validation fails
    }
  }

  /// Validates media before posting to ensure all URIs are accessible
  Future<bool> validateMediaBeforePosting() async {
    if (_currentPost.content.media.isEmpty) {
      return true; // No media to validate
    }

    try {
      if (kDebugMode) {
        print(
            '🔍 SocialActionPostCoordinator: Pre-posting media validation with recovery');
      }

      const config = MediaValidationConfig.production;
      final validationResults = await Future.wait(
        _currentPost.content.media.map((item) => _mediaCoordinator
            .validateAndRecoverMediaURI(item.fileUri, config: config)),
      );

      final validMediaItems = <MediaItem>[];
      bool hasRecoveredMedia = false;
      bool hasFailedMedia = false;

      for (int i = 0; i < _currentPost.content.media.length; i++) {
        final result = validationResults[i];
        final originalItem = _currentPost.content.media[i];

        if (result.isValid) {
          if (result.wasRecovered) {
            // Create updated media item with recovered URI
            final updatedItem = MediaItem(
              fileUri: result.effectiveUri,
              mimeType: originalItem.mimeType,
              deviceMetadata: originalItem.deviceMetadata,
            );
            validMediaItems.add(updatedItem);
            hasRecoveredMedia = true;
          } else {
            validMediaItems.add(originalItem);
          }
        } else {
          hasFailedMedia = true;
        }
      }

      // Update current post with validated media
      if (hasRecoveredMedia || hasFailedMedia) {
        _currentPost = _currentPost.copyWith(
          content: _currentPost.content.copyWith(media: validMediaItems),
        );

        // Sync with pre-selected media
        _preSelectedMedia = List.from(validMediaItems);
        _syncMediaStates();
        _safeNotifyListeners();

        // Provide user feedback
        if (hasFailedMedia && hasRecoveredMedia) {
          requestStatusUpdate(
            'Some media recovered, others excluded from posting',
            StatusMessageType.warning,
            duration: const Duration(seconds: 3),
            priority: StatusPriority.medium,
          );
        } else if (hasRecoveredMedia) {
          requestStatusUpdate(
            'Media files recovered for posting',
            StatusMessageType.success,
            duration: const Duration(seconds: 2),
            priority: StatusPriority.medium,
          );
        } else if (hasFailedMedia) {
          requestStatusUpdate(
            'Some media excluded - files no longer available',
            StatusMessageType.warning,
            duration: const Duration(seconds: 3),
            priority: StatusPriority.medium,
          );
        }
      }

      // Ensure we still have content to post (either text or valid media)
      final hasValidContent =
          _currentPost.content.text.isNotEmpty || validMediaItems.isNotEmpty;

      if (!hasValidContent) {
        setError('No valid content available for posting');
        return false;
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ SocialActionPostCoordinator: Pre-posting validation failed: $e');
      }
      setError('Media validation failed before posting: $e');
      return false;
    }
  }

  /// Enhanced finalizeAndExecutePost method with comprehensive media validation
  Future<Map<String, bool>> finalizeAndExecutePost() async {
    try {
      if (kDebugMode) {
        print(
            '🎯 SocialActionPostCoordinator: Finalizing and executing post with media validation: ${_currentPost.actionId}');
      }

      // CRITICAL: Validate media before posting
      final mediaValidationPassed = await validateMediaBeforePosting();
      if (!mediaValidationPassed) {
        throw Exception(
            'Media validation failed - cannot proceed with posting');
      }

      // CRITICAL: Ensure media is included from preSelectedMedia if not already in post
      if (_currentPost.content.media.isEmpty && _preSelectedMedia.isNotEmpty) {
        _currentPost = _currentPost.copyWith(
          content: _currentPost.content.copyWith(
            media: List.from(_preSelectedMedia),
          ),
        );
        if (kDebugMode) {
          print(
              '✅ SocialActionPostCoordinator: Added ${_preSelectedMedia.length} pre-selected media items to post');
        }
      }

      // Step 1: Upload finalized post to Firestore
      await uploadFinalizedPost();

      // Step 2: Execute post across social media platforms
      final executionResults = await executePostToSocialMedia();

      // Step 3: Handle results and transition to appropriate state
      final allSucceeded = executionResults.values.every((success) => success);

      if (allSucceeded) {
        if (kDebugMode) {
          print(
              '🎉 SocialActionPostCoordinator: Post successfully executed across all platforms');
        }
      } else {
        final failedPlatforms = executionResults.entries
            .where((entry) => !entry.value)
            .map((entry) => entry.key)
            .toList();

        if (kDebugMode) {
          print(
              '⚠️ SocialActionPostCoordinator: Post failed on platforms: ${failedPlatforms.join(', ')}');
        }
      }

      return executionResults;
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ SocialActionPostCoordinator: Failed to finalize and execute post: $e');
      }
      setError('Failed to execute post: $e');
      rethrow;
    }
  }

  /// Check if a platform can be toggled for current content
  PlatformToggleResult canTogglePlatform(String platform) {
    // Determine content type
    final contentType = SocialPlatforms.getContentType(
      hasMedia: hasMedia,
      mediaItems: _currentPost.content.media,
      text: _currentPost.content.text,
    );

    final isCompatible =
        SocialPlatforms.isPlatformCompatible(platform, contentType);

    if (isCompatible) {
      return const PlatformToggleResult(
        canToggle: true,
        message: 'Platform is compatible with current content',
      );
    } else {
      // Get specific incompatibility reason
      final platformName =
          platform.substring(0, 1).toUpperCase() + platform.substring(1);
      String message;

      if (contentType == 'text') {
        message = '$platformName requires media content to post';
      } else if (contentType == 'image' && platform == 'youtube') {
        message = '$platformName requires video content, not just images';
      } else {
        message = '$platformName is not compatible with current content type';
      }

      return PlatformToggleResult(
        canToggle: false,
        message: message,
      );
    }
  }

  /// Load historical post back into coordinator for editing
  /// UNIFIED: Routes all media through replaceMedia() pipeline to eliminate duplication
  Future<void> loadHistoricalPost(SocialAction historicalAction) async {
    if (_isDisposed) {
      throw StateError('Cannot load historical post - coordinator is disposed');
    }

    try {
      if (kDebugMode) {
        print(
            '🔄 UNIFIED: Loading historical post via replaceMedia pipeline: ${historicalAction.actionId}');
        print('   Original platforms: ${historicalAction.platforms}');
        print('   Media count: ${historicalAction.content.media.length}');
        print('   Text: "${historicalAction.content.text}"');
        print('   Hashtags: ${historicalAction.content.hashtags}');
      }

      // Step 1: Reset coordinator to clean state first
      _initializeCleanPost();
      _endTextEditingSession();
      _endHashtagEditingSession();
      _statusTimer?.cancel();
      _processingWatchdog?.cancel();
      _temporaryStatus = null;

      // Step 2: Validate and recover media URIs if present
      List<MediaItem> validatedMedia = [];
      if (historicalAction.content.media.isNotEmpty) {
        final validatedAction = await validateAndRecoverPostMedia(
          historicalAction,
          config: kDebugMode
              ? MediaValidationConfig.debug
              : MediaValidationConfig.production,
        );
        validatedMedia = validatedAction.content.media;

        if (kDebugMode) {
          print('📱 UNIFIED: Media validation completed');
          print(
              '   Original media count: ${historicalAction.content.media.length}');
          print('   Validated media count: ${validatedMedia.length}');
        }
      }

      // Step 3: Create editing post WITHOUT media (will be added via replaceMedia)
      final editingActionId = 'edit_${DateTime.now().millisecondsSinceEpoch}';
      _currentPost = historicalAction.copyWith(
        actionId: editingActionId,
        createdAt: DateTime.now().toIso8601String(),
        content: historicalAction.content
            .copyWith(media: []), // CRITICAL: No media duplication
      );
      _currentTranscription = historicalAction.internal.originalTranscription;

      // Step 4: UNIFIED MEDIA ROUTING - Use replaceMedia as single source of truth
      if (validatedMedia.isNotEmpty) {
        if (kDebugMode) {
          print(
              '🔄 UNIFIED: Routing ${validatedMedia.length} media items through replaceMedia pipeline');
        }

        // Use the existing validated replaceMedia pipeline
        await replaceMedia(validatedMedia);
      } else {
        // No media to route, just update state flags
        _hasContent = _currentPost.content.text.isNotEmpty ||
            _currentPost.content.hashtags.isNotEmpty;
        _hasMedia = false;
        _needsMediaSelection = false;
      }

      // Step 5: Update remaining coordinator state flags
      _hasError = false;
      _errorMessage = null;
      _isRecording = false;
      _isProcessing = false;
      _isTransitioning = false;

      // Step 6: CRITICAL - Defer UI notification until next frame to prevent setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeNotifyListeners();
      });

      if (kDebugMode) {
        print(
            '✅ UNIFIED: Historical post loaded successfully via replaceMedia pipeline');
        print('   Editing action ID: $editingActionId');
        print('   hasContent: $_hasContent');
        print('   hasMedia: $_hasMedia');
        print('   Current platforms: ${_currentPost.platforms}');
        print('   Media routed through single pipeline - no duplication');
        print('   Ready for editing on CommandScreen');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ UNIFIED: Failed to load historical post: $e');
      }
      setError('Failed to load post for editing: $e');
      rethrow;
    }
  }

  /// Check which platforms support automated posting vs manual sharing
  Map<String, String> getPostingStrategyForPlatforms() {
    final strategies = <String, String>{};

    for (final platform in _currentPost.platforms) {
      if (SocialPlatforms.supportsAutomatedPosting(platform)) {
        strategies[platform] = 'automated';
      } else {
        strategies[platform] = 'manual';
      }
    }

    return strategies;
  }

  /// Get platforms that will use automated posting
  List<String> getAutomatedPostingPlatforms() {
    return _currentPost.platforms
        .where((platform) => SocialPlatforms.supportsAutomatedPosting(platform))
        .toList();
  }

  /// Get platforms that will use manual sharing (SharePlus)
  List<String> getManualSharingPlatforms() {
    return _currentPost.platforms
        .where(
            (platform) => !SocialPlatforms.supportsAutomatedPosting(platform))
        .toList();
  }

  /// Get user-friendly message about posting strategy
  String getPostingStrategyMessage() {
    final automatedPlatforms = getAutomatedPostingPlatforms();
    final manualPlatforms = getManualSharingPlatforms();

    if (automatedPlatforms.isEmpty && manualPlatforms.isEmpty) {
      return 'No platforms selected';
    }

    final messages = <String>[];

    if (automatedPlatforms.isNotEmpty) {
      final platformNames = automatedPlatforms
          .map((p) => SocialPlatforms.getDisplayName(p))
          .join(', ');
      messages.add('$platformNames: Automated posting');
    }

    if (manualPlatforms.isNotEmpty) {
      final platformNames = manualPlatforms
          .map((p) => SocialPlatforms.getDisplayName(p))
          .join(', ');
      messages.add('$platformNames: Manual sharing (tap to confirm)');
    }

    return messages.join('\n');
  }

  /// Check if any platforms require business accounts for automated posting
  Future<List<String>> getPlatformsRequiringBusinessAccount() async {
    final requiringBusiness = <String>[];

    for (final platform in _currentPost.platforms) {
      if (SocialPlatforms.requiresBusinessAccount(platform)) {
        final hasAccess = await SocialPlatforms.hasBusinessAccountAccess(
            platform,
            authService: _authService);
        if (!hasAccess) {
          requiringBusiness.add(platform);
        }
      }
    }

    return requiringBusiness;
  }

  /// CRITICAL: Force reset transition state if stuck
  /// This is a safety mechanism to prevent permanent deadlocks
  void forceResetTransitionState() {
    if (_isTransitioning) {
      if (kDebugMode) {
        print('🚨 Force resetting stuck transition state');
        print('   Previous state: _isTransitioning = true');
      }
      _isTransitioning = false;
      _safeNotifyListeners();
      if (kDebugMode) {
        print('✅ Transition state force reset: _isTransitioning = false');
      }
    }
  }

  // NEW: Authentication state getters
  bool isPlatformAuthenticated(String platform) {
    return _platformAuthenticationState[platform] ?? false;
  }

  List<String> getAuthenticatedPlatforms() {
    return _platformAuthenticationState.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  bool get isInitializingAuthentication => _isInitializingAuthentication;

  /// Initialize authentication state on coordinator creation
  Future<void> initializeAuthenticationState() async {
    if (_isInitializingAuthentication) return;

    _isInitializingAuthentication = true;
    _safeNotifyListeners();

    try {
      await _validateExistingTokens();
      _setupAuthStateListener();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing authentication state: $e');
      }
    } finally {
      _isInitializingAuthentication = false;
      _safeNotifyListeners();
    }
  }

  /// Check authentication status for all platforms
  Future<void> refreshAuthenticationState() async {
    try {
      await _validateExistingTokens();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error refreshing authentication state: $e');
      }
    }
  }

  /// Handle platform authentication attempt with error handling
  Future<void> authenticatePlatform(String platform) async {
    try {
      if (kDebugMode) {
        print('🔐 Starting authentication for $platform');
      }

      switch (platform.toLowerCase()) {
        case 'facebook':
          await _authenticateFacebook();
          break;
        case 'instagram':
          await _authenticateInstagram();
          break;
        case 'youtube':
          await _authenticateYouTube();
          break;
        case 'twitter':
          await _authenticateTwitter();
          break;
        case 'tiktok':
          await _authenticateTikTok();
          break;
        default:
          throw Exception('Unsupported platform: $platform');
      }

      // Refresh authentication state after successful auth
      await refreshAuthenticationState();

      // Show success message
      requestStatusUpdate(
        'Successfully connected to ${SocialPlatforms.getDisplayName(platform)}! ✅',
        StatusMessageType.success,
        duration: const Duration(seconds: 3),
        priority: StatusPriority.medium,
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Authentication failed for $platform: $e');
      }

      // Show error message
      requestStatusUpdate(
        'Failed to connect to ${SocialPlatforms.getDisplayName(platform)}: ${e.toString()}',
        StatusMessageType.error,
        duration: const Duration(seconds: 5),
        priority: StatusPriority.high,
      );
    }
  }

  /// Validate and refresh tokens during initialization
  /// NEW: Streamlined logic using PlatformDocumentService and PlatformConnectionService
  Future<void> _validateExistingTokens() async {
    for (final platform in SocialPlatforms.all) {
      try {
        // Since documents are pre-initialized, they always exist
        final tokenDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .collection('tokens')
            .doc(platform)
            .get();

        // Check if token fields are nullified using PlatformDocumentService
        final tokenData = tokenDoc.data()!;
        final isNullified = PlatformDocumentService.isPlatformDocumentNullified(
            tokenData, platform);

        if (isNullified) {
          // Token fields are nullified - user is not authenticated
          _platformAuthenticationState[platform] = false;
          if (kDebugMode) {
            print('❌ $platform token is nullified');
          }
        } else {
          // Token fields are not nullified - use PlatformConnectionService as ground truth
          final isConnected =
              await PlatformConnectionService.isPlatformConnected(platform);
          _platformAuthenticationState[platform] = isConnected;

          if (kDebugMode) {
            print(isConnected
                ? '✅ $platform is connected'
                : '❌ $platform is not connected');
          }
        }
      } catch (e) {
        _platformAuthenticationState[platform] = false;
        if (kDebugMode) {
          print('⚠️ Error checking $platform token: $e');
        }
      }
    }
    _safeNotifyListeners();
  }

  /// Listen for logout events from profile page
  void _setupAuthStateListener() {
    _authStateSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .collection('tokens')
        .snapshots()
        .listen((snapshot) {
      // Check which platforms have been logged out
      for (final platform in SocialPlatforms.all) {
        final tokenDoc =
            snapshot.docs.where((doc) => doc.id == platform).firstOrNull;

        if (tokenDoc == null) {
          // Document was deleted - platform was logged out
          if (_platformAuthenticationState[platform] == true) {
            _handlePlatformLogout(platform);
          }
        } else {
          // Document exists - check if it's nullified using PlatformDocumentService
          final tokenData = tokenDoc.data();
          final isNullified =
              PlatformDocumentService.isPlatformDocumentNullified(
                  tokenData, platform);

          if (isNullified && _platformAuthenticationState[platform] == true) {
            // Token was nullified - platform was logged out
            _handlePlatformLogout(platform);
          }
        }
      }
    });
  }

  /// Handle platform logout from profile page
  void _handlePlatformLogout(String platform) {
    _platformAuthenticationState[platform] = false;
    _safeNotifyListeners();

    // Notify user through TranscriptionStatusWidget
    requestStatusUpdate(
      'Logged out of ${SocialPlatforms.getDisplayName(platform)}',
      StatusMessageType.info,
      duration: const Duration(seconds: 3),
      priority: StatusPriority.medium,
    );
  }

  /// Platform-specific authentication methods
  Future<void> _authenticateFacebook() async {
    final facebookAuth = FacebookAuthService();
    await facebookAuth.signInWithFacebook();
  }

  Future<void> _authenticateInstagram() async {
    final instagramAuth = InstagramAuthService();
    // Instagram OAuth needs a context for WebView dialog, but we don't have one here
    // The auth service will handle this by using a simulated flow or alternative method
    await instagramAuth.signInWithInstagram();
  }

  Future<void> _authenticateYouTube() async {
    final youtubeAuth = YouTubeAuthService();
    await youtubeAuth.signInWithYouTube();
  }

  Future<void> _authenticateTwitter() async {
    final twitterAuth = TwitterAuthService();
    await twitterAuth.signInWithTwitter();
  }

  Future<void> _authenticateTikTok() async {
    final tiktokAuth = TikTokAuthService();
    await tiktokAuth.signInWithTikTok();
  }

  // NEW: Sub-account management and platform bucket computation

  /// Store selected sub-accounts for each platform
  final Map<String, SubAccount> _selectedSubAccounts = {};

  /// Compute which platforms belong in automated vs manual buckets
  Future<Map<String, List<String>>> computePlatformBuckets() async {
    // 1. Start from user's selected platforms
    final List<String> chosen = _currentPost.platforms;

    // 2. Filter by credential status
    List<String> authenticated =
        chosen.where((p) => _platformAuthenticationState[p] == true).toList();

    // 3. Separate business-required platforms
    List<String> automated = [];
    List<String> manual = [];

    for (final p in chosen) {
      final bool isBizReq = SocialPlatforms.requiresBusinessAccount(p);
      final bool hasBiz = !isBizReq || await _hasBusinessAccountAccess(p);

      if (SocialPlatforms.supportsAutomatedPosting(p) &&
          authenticated.contains(p) &&
          hasBiz) {
        automated.add(p);
      } else {
        manual.add(p);
      }
    }

    return {'automated': automated, 'manual': manual};
  }

  /// Check if user has business account access for a platform
  Future<bool> _hasBusinessAccountAccess(String platform) async {
    if (!SocialPlatforms.requiresBusinessAccount(platform)) return true;

    // 1. If the user already picked a sub-account → good to go
    if (_selectedSubAccounts.containsKey(platform)) return true;

    // 2. Otherwise look at stored token metadata
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc(platform)
          .get();

      if (!doc.exists) return false;

      final accountType = doc.data()?['account_type']
          as String?; // "BUSINESS", "CREATOR", "PERSONAL"
      return accountType != null &&
          (accountType == 'BUSINESS' || accountType == 'CREATOR');
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking business account access for $platform: $e');
      }
      return false;
    }
  }

  /// Get sub-accounts (Facebook Pages, Instagram Business Accounts) for a platform
  Future<List<SubAccount>> getSubAccounts(String platform) async {
    try {
      switch (platform.toLowerCase()) {
        case 'facebook':
          return await _getFacebookPages();
        case 'instagram':
          return await _getInstagramBusinessAccounts();
        default:
          return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting sub-accounts for $platform: $e');
      }
      return [];
    }
  }

  /// Get Facebook Pages the user manages
  Future<List<SubAccount>> _getFacebookPages() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return [];

      final tokenDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('facebook')
          .get();

      if (!tokenDoc.exists) return [];

      final tokenData = tokenDoc.data()!;
      final userAccessToken = tokenData['access_token'] as String;

      final response = await http.get(
        Uri.parse('https://graph.facebook.com/v18.0/me/accounts'
            '?fields=id,name,access_token,instagram_business_account'
            '&access_token=$userAccessToken'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pages = data['data'] as List<dynamic>;

        return pages.map((page) {
          final pageData = page as Map<String, dynamic>;
          return SubAccount(
            targetId: pageData['id'] as String,
            name: pageData['name'] as String,
            accessToken: pageData['access_token'] as String,
            igUserId: pageData['instagram_business_account']?['id'] as String?,
          );
        }).toList();
      }

      return [];
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Facebook pages: $e');
      }
      return [];
    }
  }

  /// Get Instagram Business Accounts linked to Facebook Pages
  Future<List<SubAccount>> _getInstagramBusinessAccounts() async {
    try {
      // Get Facebook pages first
      final facebookPages = await _getFacebookPages();

      // Filter pages that have Instagram Business Accounts
      return facebookPages.where((page) => page.igUserId != null).toList();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting Instagram Business Accounts: $e');
      }
      return [];
    }
  }

  /// Set selected sub-account for a platform
  void setSelectedSubAccount(String platform, SubAccount account) {
    _selectedSubAccounts[platform] = account;

    // Update the current post's platform data
    _updatePlatformDataWithSubAccount(platform, account);

    _safeNotifyListeners();
  }

  /// Get selected sub-account for a platform
  SubAccount? getSelectedSubAccount(String platform) {
    return _selectedSubAccounts[platform];
  }

  /// Update platform data with selected sub-account
  void _updatePlatformDataWithSubAccount(String platform, SubAccount account) {
    switch (platform.toLowerCase()) {
      case 'facebook':
        final currentFacebook = _currentPost.platformData.facebook;
        final updatedFacebook = FacebookData(
          postHere: currentFacebook?.postHere ?? false,
          postAsPage: true,
          pageId: account.targetId,
          postType: currentFacebook?.postType,
          mediaFileUri: currentFacebook?.mediaFileUri,
          videoFileUri: currentFacebook?.videoFileUri,
          audioFileUri: currentFacebook?.audioFileUri,
          thumbnailUri: currentFacebook?.thumbnailUri,
          scheduledTime: currentFacebook?.scheduledTime,
          additionalFields: currentFacebook?.additionalFields,
        );

        _currentPost = _currentPost.copyWith(
          platformData: PlatformData(
            facebook: updatedFacebook,
            instagram: _currentPost.platformData.instagram,
            youtube: _currentPost.platformData.youtube,
            twitter: _currentPost.platformData.twitter,
            tiktok: _currentPost.platformData.tiktok,
          ),
        );
        break;
      case 'instagram':
        final currentInstagram = _currentPost.platformData.instagram;
        final updatedInstagram = InstagramData(
          postHere: currentInstagram?.postHere ?? false,
          postType: currentInstagram?.postType,
          carousel: currentInstagram?.carousel,
          igUserId: account.targetId,
          mediaType: currentInstagram?.mediaType,
          mediaFileUri: currentInstagram?.mediaFileUri,
          videoThumbnailUri: currentInstagram?.videoThumbnailUri,
          videoFileUri: currentInstagram?.videoFileUri,
          audioFileUri: currentInstagram?.audioFileUri,
          scheduledTime: currentInstagram?.scheduledTime,
        );

        _currentPost = _currentPost.copyWith(
          platformData: PlatformData(
            facebook: _currentPost.platformData.facebook,
            instagram: updatedInstagram,
            youtube: _currentPost.platformData.youtube,
            twitter: _currentPost.platformData.twitter,
            tiktok: _currentPost.platformData.tiktok,
          ),
        );
        break;
    }
  }

  /// Get platforms that will use automated posting (with business account validation)
  Future<List<String>> getAutomatedPostingPlatformsWithValidation() async {
    final buckets = await computePlatformBuckets();
    return buckets['automated'] ?? [];
  }

  /// Get platforms that will use manual sharing
  Future<List<String>> getManualSharingPlatformsWithValidation() async {
    final buckets = await computePlatformBuckets();
    return buckets['manual'] ?? [];
  }

  /// Get platform targets for automated posting
  Future<List<PlatformTarget>> getPlatformTargetsForAutomatedPosting() async {
    final automatedPlatforms =
        await getAutomatedPostingPlatformsWithValidation();
    final targets = <PlatformTarget>[];

    for (final platform in automatedPlatforms) {
      final target = await _buildPlatformTarget(platform);
      if (target != null) {
        targets.add(target);
      }
    }

    return targets;
  }

  /// Build a platform target for automated posting
  Future<PlatformTarget?> _buildPlatformTarget(String platform) async {
    // A. Facebook / IG need a chosen sub-account
    if (SocialPlatforms.requiresBusinessAccount(platform)) {
      final subAccount = getSelectedSubAccount(platform);
      if (subAccount == null) return null; // still manual
      return PlatformTarget(
        platform: platform,
        accessToken: subAccount.accessToken,
        targetId: subAccount.targetId,
        targetName: subAccount.name,
      );
    }

    // B. All others use stored user token / channel id
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc(platform)
          .get();

      if (!doc.exists) return null; // unauthenticated

      final tokenData = doc.data()!;
      final accessToken = tokenData['access_token'] as String?;
      final targetId = tokenData['default_target'] as String? ?? '';
      final targetName = tokenData['display_name'] as String? ??
          SocialPlatforms.getDisplayName(platform);

      if (accessToken == null) return null; // no token

      return PlatformTarget(
        platform: platform,
        accessToken: accessToken,
        targetId: targetId,
        targetName: targetName,
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error building platform target for $platform: $e');
      }
      return null;
    }
  }
}
