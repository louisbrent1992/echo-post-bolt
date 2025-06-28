import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../models/social_action.dart';
import '../models/status_message.dart';
import '../constants/social_platforms.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'ai_service.dart';
import 'media_coordinator.dart';
import 'natural_language_parser.dart';
import 'social_post_service.dart';

/// Coordinates the entire social action posting workflow
///
/// This class is the central coordinator for the entire voice-to-post pipeline:
/// 1. Recording voice commands
/// 2. Transcribing audio
/// 3. Processing transcription with AI
/// 4. Managing media selection
/// 5. Formatting posts for different platforms
/// 6. Executing the final post
///
/// It maintains the current state of the post being created and provides
/// methods for each step of the workflow.
class SocialActionPostCoordinator extends ChangeNotifier {
  // Dependencies
  final MediaCoordinator _mediaCoordinator;
  final FirestoreService _firestoreService;
  final AIService _aiService;
  final SocialPostService _socialPostService;
  final AuthService _authService;
  final NaturalLanguageParser _naturalLanguageParser;

  // State
  SocialAction? _currentPost;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _hasContent = false;
  bool _hasMedia = false;
  bool _needsMediaSelection = false;
  bool _isReadyForExecution = false;
  String _transcription = '';
  String _statusMessage = 'Tap and hold the mic to start recording';
  StatusMessageType _statusType = StatusMessageType.info;
  double _currentAmplitude = -160.0; // dBFS
  double _maxAmplitude = -160.0;
  bool _hasSpeechDetected = false;

  // Getters
  SocialAction get currentPost => _currentPost ?? _createEmptySocialAction();
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get hasContent => _hasContent;
  bool get hasMedia => _hasMedia;
  bool get needsMediaSelection => _needsMediaSelection;
  bool get isReadyForExecution => _isReadyForExecution;
  String get transcription => _transcription;
  String get statusMessage => _statusMessage;
  StatusMessageType get statusType => _statusType;
  double get currentAmplitude => _currentAmplitude;
  double get maxAmplitude => _maxAmplitude;
  bool get hasSpeechDetected => _hasSpeechDetected;

  // Computed properties
  double get normalizedAmplitude {
    // Convert dBFS to 0.0-1.0 range for UI
    // -60 dBFS = 0.0, -10 dBFS = 1.0
    const double minDb = -60.0;
    const double maxDb = -10.0;

    if (_currentAmplitude <= minDb) return 0.0;
    if (_currentAmplitude >= maxDb) return 1.0;

    return (_currentAmplitude - minDb) / (maxDb - minDb);
  }

  SocialActionPostCoordinator({
    required MediaCoordinator mediaCoordinator,
    required FirestoreService firestoreService,
    required AIService aiService,
    required SocialPostService socialPostService,
    required AuthService authService,
    required NaturalLanguageParser naturalLanguageParser,
  })  : _mediaCoordinator = mediaCoordinator,
        _firestoreService = firestoreService,
        _aiService = aiService,
        _socialPostService = socialPostService,
        _authService = authService,
        _naturalLanguageParser = naturalLanguageParser;

  /// Create an empty SocialAction with default values
  SocialAction _createEmptySocialAction() {
    final timestamp = DateTime.now().toIso8601String();
    final actionId = 'echo_${DateTime.now().millisecondsSinceEpoch}';

    return SocialAction(
      actionId: actionId,
      createdAt: timestamp,
      platforms: ['instagram', 'twitter'],
      content: Content(
        text: '',
        hashtags: [],
        mentions: [],
        media: [],
      ),
      options: Options(
        schedule: 'now',
      ),
      platformData: PlatformData(
        facebook: FacebookData(postHere: false),
        instagram: InstagramData(postHere: true),
        youtube: YouTubeData(postHere: false),
        twitter: TwitterData(postHere: true),
        tiktok: TikTokData(postHere: false, sound: Sound()),
      ),
      internal: Internal(
        aiGenerated: false,
      ),
    );
  }

  /// Start recording a voice command
  void startRecording() {
    if (_isRecording || _isProcessing) return;

    _isRecording = true;
    _currentAmplitude = -160.0;
    _maxAmplitude = -160.0;
    _hasSpeechDetected = false;
    _statusMessage = 'Recording... Speak your command';
    _statusType = StatusMessageType.recording;
    notifyListeners();

    if (kDebugMode) {
      print('🎤 SocialActionPostCoordinator: Started recording');
    }
  }

  /// Update the current amplitude during recording
  void updateAmplitude(double amplitude) {
    _currentAmplitude = amplitude;

    if (amplitude > _maxAmplitude) {
      _maxAmplitude = amplitude;
    }

    // Check for speech detection
    if (amplitude > -40.0) {
      _hasSpeechDetected = true;
    }

    notifyListeners();
  }

  /// Stop recording and process the transcription
  void stopRecording() {
    if (!_isRecording) return;

    _isRecording = false;
    _isProcessing = true;
    _statusMessage = 'Processing your voice command...';
    _statusType = StatusMessageType.processing;
    notifyListeners();

    if (kDebugMode) {
      print('🎤 SocialActionPostCoordinator: Stopped recording');
      print('   Max amplitude: ${_maxAmplitude.toStringAsFixed(1)} dBFS');
      print('   Speech detected: $_hasSpeechDetected');
    }
  }

  /// Process a transcription from Whisper
  Future<void> processTranscription(String transcription) async {
    if (transcription.isEmpty) {
      _isProcessing = false;
      _statusMessage = 'No transcription received. Please try again.';
      _statusType = StatusMessageType.error;
      notifyListeners();
      return;
    }

    _transcription = transcription;
    _statusMessage = 'Creating post from: "$transcription"';
    _statusType = StatusMessageType.processing;
    notifyListeners();

    if (kDebugMode) {
      print('🔄 Processing transcription: "$transcription"');
    }

    try {
      // Check if transcription references media
      final mediaRequest = _naturalLanguageParser.parseMediaRequest(transcription);
      final hasExplicitMediaReference = mediaRequest != null;

      // Get platforms mentioned in transcription
      final platformRequests = _naturalLanguageParser.extractPlatforms(transcription);
      final mentionedPlatforms = platformRequests
          .map((p) => p.platform)
          .toList();

      // Process with AI service
      final List<MediaItem> preSelectedMedia = [];
      final action = await _aiService.processVoiceCommand(
        transcription,
        preSelectedMedia: preSelectedMedia,
      );

      // Update platforms based on natural language parsing if needed
      if (mentionedPlatforms.isNotEmpty) {
        final updatedPlatforms = List<String>.from(action.platforms);
        
        // Add any platforms explicitly mentioned that aren't already included
        for (final platform in mentionedPlatforms) {
          if (!updatedPlatforms.contains(platform)) {
            updatedPlatforms.add(platform);
          }
        }
        
        // Update platform data to match
        for (final platform in updatedPlatforms) {
          _setPlatformPostHere(action, platform, true);
        }
        
        // Update the action with new platforms
        action.platforms.clear();
        action.platforms.addAll(updatedPlatforms);
      }

      // Save the action to Firestore
      await _firestoreService.saveAction(action.toJson());

      // Update state
      _currentPost = action;
      _hasContent = true;
      _hasMedia = action.content.media.isNotEmpty;
      _needsMediaSelection = action.mediaQuery?.isNotEmpty == true;
      _isReadyForExecution = _hasContent && (_hasMedia || !_needsMediaSelection);
      _isProcessing = false;

      // Update status message
      if (_needsMediaSelection) {
        _statusMessage = 'Please select media for your post';
        _statusType = StatusMessageType.info;
      } else if (_hasMedia) {
        _statusMessage = 'Post ready with media! Tap to review and post.';
        _statusType = StatusMessageType.success;
      } else {
        _statusMessage = 'Post created! Tap to review and post.';
        _statusType = StatusMessageType.success;
      }

      notifyListeners();

      if (kDebugMode) {
        print('✅ Processed transcription successfully');
        print('   Has content: $_hasContent');
        print('   Has media: $_hasMedia');
        print('   Needs media selection: $_needsMediaSelection');
        print('   Is ready for execution: $_isReadyForExecution');
        print('   Platforms: ${action.platforms.join(', ')}');
      }
    } catch (e) {
      _isProcessing = false;
      _statusMessage = 'Error processing command: $e';
      _statusType = StatusMessageType.error;
      notifyListeners();

      if (kDebugMode) {
        print('❌ Error processing transcription: $e');
      }
    }
  }

  /// Update the current post with selected media
  void updateWithSelectedMedia(List<MediaItem> selectedMedia) {
    if (_currentPost == null) return;

    final updatedContent = Content(
      text: _currentPost!.content.text,
      hashtags: _currentPost!.content.hashtags,
      mentions: _currentPost!.content.mentions,
      link: _currentPost!.content.link,
      media: selectedMedia,
    );

    _currentPost = _currentPost!.copyWith(
      content: updatedContent,
      needsMediaSelection: false,
    );

    _hasMedia = selectedMedia.isNotEmpty;
    _needsMediaSelection = false;
    _isReadyForExecution = _hasContent && _hasMedia;

    // Update platform data with media
    if (_hasMedia) {
      _updatePlatformDataWithMedia(selectedMedia.first);
    }

    _statusMessage = 'Media selected! Ready to post.';
    _statusType = StatusMessageType.success;
    notifyListeners();

    if (kDebugMode) {
      print('✅ Updated post with ${selectedMedia.length} media items');
    }
  }

  /// Update platform data with selected media
  void _updatePlatformDataWithMedia(MediaItem mediaItem) {
    if (_currentPost == null) return;

    final isVideo = mediaItem.mimeType.startsWith('video/');
    final fileUri = mediaItem.fileUri;

    // Update Instagram platform data
    if (_currentPost!.platforms.contains('instagram')) {
      final instagramData = _currentPost!.platformData.instagram ?? InstagramData(postHere: true);
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: InstagramData(
          postHere: instagramData.postHere,
          postType: instagramData.postType ?? 'feed',
          carousel: instagramData.carousel,
          igUserId: instagramData.igUserId,
          mediaType: isVideo ? 'video' : 'image',
          mediaFileUri: fileUri,
          videoThumbnailUri: isVideo ? null : null,
          videoFileUri: isVideo ? fileUri : null,
          audioFileUri: instagramData.audioFileUri,
          scheduledTime: instagramData.scheduledTime,
        ),
        youtube: _currentPost!.platformData.youtube,
        twitter: _currentPost!.platformData.twitter,
        tiktok: _currentPost!.platformData.tiktok,
      );
    }

    // Update YouTube platform data (video only)
    if (_currentPost!.platforms.contains('youtube') && isVideo) {
      final youtubeData = _currentPost!.platformData.youtube ?? YouTubeData(postHere: true);
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: _currentPost!.platformData.instagram,
        youtube: YouTubeData(
          postHere: youtubeData.postHere,
          channelId: youtubeData.channelId,
          privacy: youtubeData.privacy,
          videoCategoryId: youtubeData.videoCategoryId,
          videoFileUri: fileUri,
          thumbnailUri: youtubeData.thumbnailUri,
          scheduledTime: youtubeData.scheduledTime,
          tags: youtubeData.tags,
          enableComments: youtubeData.enableComments,
          enableRatings: youtubeData.enableRatings,
          madeForKids: youtubeData.madeForKids,
        ),
        twitter: _currentPost!.platformData.twitter,
        tiktok: _currentPost!.platformData.tiktok,
      );
    }

    // Update Twitter platform data
    if (_currentPost!.platforms.contains('twitter')) {
      final twitterData = _currentPost!.platformData.twitter ?? TwitterData(postHere: true);
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: _currentPost!.platformData.instagram,
        youtube: _currentPost!.platformData.youtube,
        twitter: TwitterData(
          postHere: twitterData.postHere,
          altTexts: twitterData.altTexts,
          tweetMode: twitterData.tweetMode,
          mediaType: isVideo ? 'video' : 'image',
          mediaFileUri: fileUri,
          mediaDuration: isVideo ? mediaItem.deviceMetadata.duration : null,
          tweetLink: twitterData.tweetLink,
          scheduledTime: twitterData.scheduledTime,
        ),
        tiktok: _currentPost!.platformData.tiktok,
      );
    }

    // Update TikTok platform data (video only)
    if (_currentPost!.platforms.contains('tiktok') && isVideo) {
      final tiktokData = _currentPost!.platformData.tiktok ?? TikTokData(postHere: true, sound: Sound());
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: _currentPost!.platformData.instagram,
        youtube: _currentPost!.platformData.youtube,
        twitter: _currentPost!.platformData.twitter,
        tiktok: TikTokData(
          postHere: tiktokData.postHere,
          privacy: tiktokData.privacy,
          sound: tiktokData.sound,
          mediaFileUri: fileUri,
          videoFileUri: fileUri,
          audioFileUri: tiktokData.audioFileUri,
          scheduledTime: tiktokData.scheduledTime,
        ),
      );
    }

    // Update Facebook platform data
    if (_currentPost!.platforms.contains('facebook')) {
      final facebookData = _currentPost!.platformData.facebook ?? FacebookData(postHere: true);
      _currentPost!.platformData = PlatformData(
        facebook: FacebookData(
          postHere: facebookData.postHere,
          postAsPage: facebookData.postAsPage,
          pageId: facebookData.pageId,
          postType: isVideo ? 'video' : 'photo',
          mediaFileUri: fileUri,
          videoFileUri: isVideo ? fileUri : null,
          audioFileUri: facebookData.audioFileUri,
          thumbnailUri: facebookData.thumbnailUri,
          scheduledTime: facebookData.scheduledTime,
          additionalFields: facebookData.additionalFields,
        ),
        instagram: _currentPost!.platformData.instagram,
        youtube: _currentPost!.platformData.youtube,
        twitter: _currentPost!.platformData.twitter,
        tiktok: _currentPost!.platformData.tiktok,
      );
    }
  }

  /// Update post text content
  void updatePostText(String text) {
    if (_currentPost == null) return;

    final updatedContent = Content(
      text: text,
      hashtags: _currentPost!.content.hashtags,
      mentions: _currentPost!.content.mentions,
      link: _currentPost!.content.link,
      media: _currentPost!.content.media,
    );

    _currentPost = _currentPost!.copyWith(
      content: updatedContent,
    );

    _hasContent = text.isNotEmpty;
    _isReadyForExecution = _hasContent && (_hasMedia || !_needsMediaSelection);

    notifyListeners();

    if (kDebugMode) {
      print('✅ Updated post text: "${text.substring(0, text.length.clamp(0, 50))}"...');
    }
  }

  /// Update post hashtags
  void updatePostHashtags(List<String> hashtags) {
    if (_currentPost == null) return;

    final updatedContent = Content(
      text: _currentPost!.content.text,
      hashtags: hashtags,
      mentions: _currentPost!.content.mentions,
      link: _currentPost!.content.link,
      media: _currentPost!.content.media,
    );

    _currentPost = _currentPost!.copyWith(
      content: updatedContent,
    );

    notifyListeners();

    if (kDebugMode) {
      print('✅ Updated post hashtags: ${hashtags.join(', ')}');
    }
  }

  /// Update post schedule
  void updatePostSchedule(String schedule) {
    if (_currentPost == null) return;

    final updatedOptions = Options(
      schedule: schedule,
      locationTag: _currentPost!.options.locationTag,
      visibility: _currentPost!.options.visibility,
      replyToPostId: _currentPost!.options.replyToPostId,
    );

    _currentPost = _currentPost!.copyWith(
      options: updatedOptions,
    );

    // Update platform-specific scheduled times
    _updatePlatformScheduledTimes(schedule);

    notifyListeners();

    if (kDebugMode) {
      print('✅ Updated post schedule: $schedule');
    }
  }

  /// Update platform-specific scheduled times
  void _updatePlatformScheduledTimes(String schedule) {
    if (_currentPost == null || schedule == 'now') return;

    // Facebook
    if (_currentPost!.platformData.facebook != null) {
      final facebookData = _currentPost!.platformData.facebook!;
      _currentPost!.platformData = PlatformData(
        facebook: FacebookData(
          postHere: facebookData.postHere,
          postAsPage: facebookData.postAsPage,
          pageId: facebookData.pageId,
          postType: facebookData.postType,
          mediaFileUri: facebookData.mediaFileUri,
          videoFileUri: facebookData.videoFileUri,
          audioFileUri: facebookData.audioFileUri,
          thumbnailUri: facebookData.thumbnailUri,
          scheduledTime: schedule,
          additionalFields: facebookData.additionalFields,
        ),
        instagram: _currentPost!.platformData.instagram,
        youtube: _currentPost!.platformData.youtube,
        twitter: _currentPost!.platformData.twitter,
        tiktok: _currentPost!.platformData.tiktok,
      );
    }

    // Instagram
    if (_currentPost!.platformData.instagram != null) {
      final instagramData = _currentPost!.platformData.instagram!;
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: InstagramData(
          postHere: instagramData.postHere,
          postType: instagramData.postType,
          carousel: instagramData.carousel,
          igUserId: instagramData.igUserId,
          mediaType: instagramData.mediaType,
          mediaFileUri: instagramData.mediaFileUri,
          videoThumbnailUri: instagramData.videoThumbnailUri,
          videoFileUri: instagramData.videoFileUri,
          audioFileUri: instagramData.audioFileUri,
          scheduledTime: schedule,
        ),
        youtube: _currentPost!.platformData.youtube,
        twitter: _currentPost!.platformData.twitter,
        tiktok: _currentPost!.platformData.tiktok,
      );
    }

    // YouTube
    if (_currentPost!.platformData.youtube != null) {
      final youtubeData = _currentPost!.platformData.youtube!;
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: _currentPost!.platformData.instagram,
        youtube: YouTubeData(
          postHere: youtubeData.postHere,
          channelId: youtubeData.channelId,
          privacy: youtubeData.privacy,
          videoCategoryId: youtubeData.videoCategoryId,
          videoFileUri: youtubeData.videoFileUri,
          thumbnailUri: youtubeData.thumbnailUri,
          scheduledTime: schedule,
          tags: youtubeData.tags,
          enableComments: youtubeData.enableComments,
          enableRatings: youtubeData.enableRatings,
          madeForKids: youtubeData.madeForKids,
        ),
        twitter: _currentPost!.platformData.twitter,
        tiktok: _currentPost!.platformData.tiktok,
      );
    }

    // Twitter
    if (_currentPost!.platformData.twitter != null) {
      final twitterData = _currentPost!.platformData.twitter!;
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: _currentPost!.platformData.instagram,
        youtube: _currentPost!.platformData.youtube,
        twitter: TwitterData(
          postHere: twitterData.postHere,
          altTexts: twitterData.altTexts,
          tweetMode: twitterData.tweetMode,
          mediaType: twitterData.mediaType,
          mediaFileUri: twitterData.mediaFileUri,
          mediaDuration: twitterData.mediaDuration,
          tweetLink: twitterData.tweetLink,
          scheduledTime: schedule,
        ),
        tiktok: _currentPost!.platformData.tiktok,
      );
    }

    // TikTok
    if (_currentPost!.platformData.tiktok != null) {
      final tiktokData = _currentPost!.platformData.tiktok!;
      _currentPost!.platformData = PlatformData(
        facebook: _currentPost!.platformData.facebook,
        instagram: _currentPost!.platformData.instagram,
        youtube: _currentPost!.platformData.youtube,
        twitter: _currentPost!.platformData.twitter,
        tiktok: TikTokData(
          postHere: tiktokData.postHere,
          privacy: tiktokData.privacy,
          sound: tiktokData.sound,
          mediaFileUri: tiktokData.mediaFileUri,
          videoFileUri: tiktokData.videoFileUri,
          audioFileUri: tiktokData.audioFileUri,
          scheduledTime: schedule,
        ),
      );
    }
  }

  /// Toggle a platform on/off
  void togglePlatform(String platform) {
    if (_currentPost == null) return;

    final updatedPlatforms = List<String>.from(_currentPost!.platforms);
    
    if (updatedPlatforms.contains(platform)) {
      updatedPlatforms.remove(platform);
      _setPlatformPostHere(_currentPost!, platform, false);
    } else {
      updatedPlatforms.add(platform);
      _setPlatformPostHere(_currentPost!, platform, true);
    }

    _currentPost = _currentPost!.copyWith(
      platforms: updatedPlatforms,
    );

    notifyListeners();

    if (kDebugMode) {
      print('✅ Toggled platform: $platform (${updatedPlatforms.contains(platform) ? 'added' : 'removed'})');
    }
  }

  /// Set platform postHere flag
  void _setPlatformPostHere(SocialAction action, String platform, bool postHere) {
    switch (platform.toLowerCase()) {
      case 'facebook':
        final facebookData = action.platformData.facebook ?? FacebookData();
        action.platformData = PlatformData(
          facebook: FacebookData(
            postHere: postHere,
            postAsPage: facebookData.postAsPage,
            pageId: facebookData.pageId,
            postType: facebookData.postType,
            mediaFileUri: facebookData.mediaFileUri,
            videoFileUri: facebookData.videoFileUri,
            audioFileUri: facebookData.audioFileUri,
            thumbnailUri: facebookData.thumbnailUri,
            scheduledTime: facebookData.scheduledTime,
            additionalFields: facebookData.additionalFields,
          ),
          instagram: action.platformData.instagram,
          youtube: action.platformData.youtube,
          twitter: action.platformData.twitter,
          tiktok: action.platformData.tiktok,
        );
        break;
      case 'instagram':
        final instagramData = action.platformData.instagram ?? InstagramData(postHere: false);
        action.platformData = PlatformData(
          facebook: action.platformData.facebook,
          instagram: InstagramData(
            postHere: postHere,
            postType: instagramData.postType,
            carousel: instagramData.carousel,
            igUserId: instagramData.igUserId,
            mediaType: instagramData.mediaType,
            mediaFileUri: instagramData.mediaFileUri,
            videoThumbnailUri: instagramData.videoThumbnailUri,
            videoFileUri: instagramData.videoFileUri,
            audioFileUri: instagramData.audioFileUri,
            scheduledTime: instagramData.scheduledTime,
          ),
          youtube: action.platformData.youtube,
          twitter: action.platformData.twitter,
          tiktok: action.platformData.tiktok,
        );
        break;
      case 'youtube':
        final youtubeData = action.platformData.youtube ?? YouTubeData();
        action.platformData = PlatformData(
          facebook: action.platformData.facebook,
          instagram: action.platformData.instagram,
          youtube: YouTubeData(
            postHere: postHere,
            channelId: youtubeData.channelId,
            privacy: youtubeData.privacy,
            videoCategoryId: youtubeData.videoCategoryId,
            videoFileUri: youtubeData.videoFileUri,
            thumbnailUri: youtubeData.thumbnailUri,
            scheduledTime: youtubeData.scheduledTime,
            tags: youtubeData.tags,
            enableComments: youtubeData.enableComments,
            enableRatings: youtubeData.enableRatings,
            madeForKids: youtubeData.madeForKids,
          ),
          twitter: action.platformData.twitter,
          tiktok: action.platformData.tiktok,
        );
        break;
      case 'twitter':
        final twitterData = action.platformData.twitter ?? TwitterData();
        action.platformData = PlatformData(
          facebook: action.platformData.facebook,
          instagram: action.platformData.instagram,
          youtube: action.platformData.youtube,
          twitter: TwitterData(
            postHere: postHere,
            altTexts: twitterData.altTexts,
            tweetMode: twitterData.tweetMode,
            mediaType: twitterData.mediaType,
            mediaFileUri: twitterData.mediaFileUri,
            mediaDuration: twitterData.mediaDuration,
            tweetLink: twitterData.tweetLink,
            scheduledTime: twitterData.scheduledTime,
          ),
          tiktok: action.platformData.tiktok,
        );
        break;
      case 'tiktok':
        final tiktokData = action.platformData.tiktok ?? TikTokData(sound: Sound());
        action.platformData = PlatformData(
          facebook: action.platformData.facebook,
          instagram: action.platformData.instagram,
          youtube: action.platformData.youtube,
          twitter: action.platformData.twitter,
          tiktok: TikTokData(
            postHere: postHere,
            privacy: tiktokData.privacy,
            sound: tiktokData.sound,
            mediaFileUri: tiktokData.mediaFileUri,
            videoFileUri: tiktokData.videoFileUri,
            audioFileUri: tiktokData.audioFileUri,
            scheduledTime: tiktokData.scheduledTime,
          ),
        );
        break;
    }
  }

  /// Execute the post to all selected platforms
  Future<Map<String, bool>> executePost() async {
    if (_currentPost == null) {
      return {'error': false};
    }

    _isProcessing = true;
    _statusMessage = 'Posting to ${_currentPost!.platforms.join(', ')}...';
    _statusType = StatusMessageType.processing;
    notifyListeners();

    try {
      // Save the action to Firestore before posting
      await _firestoreService.saveAction(_currentPost!.toJson());

      // Post to all platforms
      final results = await _socialPostService.postToAllPlatforms(
        _currentPost!,
        authService: _authService,
      );

      // Update status based on results
      final allSucceeded = results.values.every((success) => success);
      if (allSucceeded) {
        _statusMessage = 'Successfully posted to all platforms!';
        _statusType = StatusMessageType.success;
      } else {
        final failedPlatforms = results.entries
            .where((entry) => !entry.value)
            .map((entry) => entry.key)
            .toList();
        _statusMessage =
            'Failed to post to ${failedPlatforms.join(', ')}. Please try again.';
        _statusType = StatusMessageType.error;
      }

      _isProcessing = false;
      notifyListeners();

      return results;
    } catch (e) {
      _isProcessing = false;
      _statusMessage = 'Error posting: $e';
      _statusType = StatusMessageType.error;
      notifyListeners();

      if (kDebugMode) {
        print('❌ Error executing post: $e');
      }

      return {'error': false};
    }
  }

  /// Reset the coordinator to its initial state
  void reset() {
    _currentPost = null;
    _isRecording = false;
    _isProcessing = false;
    _hasContent = false;
    _hasMedia = false;
    _needsMediaSelection = false;
    _isReadyForExecution = false;
    _transcription = '';
    _statusMessage = 'Tap and hold the mic to start recording';
    _statusType = StatusMessageType.info;
    _currentAmplitude = -160.0;
    _maxAmplitude = -160.0;
    _hasSpeechDetected = false;
    notifyListeners();

    if (kDebugMode) {
      print('🔄 SocialActionPostCoordinator: Reset to initial state');
    }
  }

  /// Sync with an existing post (e.g., from history)
  void syncWithExistingPost(SocialAction action) {
    _currentPost = action;
    _hasContent = action.content.text.isNotEmpty;
    _hasMedia = action.content.media.isNotEmpty;
    _needsMediaSelection = action.mediaQuery?.isNotEmpty == true;
    _isReadyForExecution = _hasContent && (_hasMedia || !_needsMediaSelection);
    _isRecording = false;
    _isProcessing = false;
    _transcription = action.internal.originalTranscription;
    _statusMessage = 'Loaded existing post';
    _statusType = StatusMessageType.info;
    notifyListeners();

    if (kDebugMode) {
      print('🔄 SocialActionPostCoordinator: Synced with existing post');
      print('   ID: ${action.actionId}');
      print('   Platforms: ${action.platforms.join(', ')}');
      print('   Has content: $_hasContent');
      print('   Has media: $_hasMedia');
      print('   Needs media selection: $_needsMediaSelection');
      print('   Is ready for execution: $_isReadyForExecution');
    }
  }

  /// Get formatted post content for a specific platform
  String getFormattedPostContent(String platform) {
    if (_currentPost == null) return '';

    final baseText = _currentPost!.content.text;
    final hashtags = _currentPost!.content.hashtags;

    if (hashtags.isEmpty) return baseText;

    // Get platform-specific hashtag format
    final hashtagFormat = SocialPlatforms.getHashtagFormat(platform);
    if (hashtagFormat == null) {
      // Fallback to default format
      return '$baseText\n\n${hashtags.map((tag) => '#$tag').join(' ')}';
    }

    // Format based on platform-specific rules
    switch (hashtagFormat.position) {
      case HashtagPosition.inline:
        // Inline hashtags (e.g., Twitter)
        final hashtagText = hashtags
            .take(hashtagFormat.maxLength)
            .map((tag) => '#$tag')
            .join(hashtagFormat.separator);
        return '$baseText${hashtagFormat.prefix}$hashtagText';

      case HashtagPosition.end:
        // End hashtags (e.g., Instagram, Facebook)
        final hashtagText = hashtags
            .take(hashtagFormat.maxLength)
            .map((tag) => '#$tag')
            .join(hashtagFormat.separator);
        return '$baseText${hashtagFormat.prefix}$hashtagText';
    }
  }

  /// Get status message for UI display
  String getStatusMessage() {
    return _statusMessage;
  }

  /// Get status color for UI display
  Color getStatusColor() {
    switch (_statusType) {
      case StatusMessageType.error:
        return Colors.red;
      case StatusMessageType.warning:
        return Colors.orange;
      case StatusMessageType.success:
        return const Color(0xFF4CAF50);
      case StatusMessageType.recording:
        return const Color(0xFFFF0055);
      case StatusMessageType.processing:
        return Colors.orange;
      case StatusMessageType.info:
      default:
        return Colors.white.withValues(alpha: 179);
    }
  }

  /// Get platforms that support automated posting
  List<String> getAutomatedPostingPlatforms() {
    if (_currentPost == null) return [];

    return _currentPost!.platforms
        .where((platform) => SocialPlatforms.supportsAutomatedPosting(platform))
        .toList();
  }

  /// Get platforms that require manual sharing
  List<String> getManualSharingPlatforms() {
    if (_currentPost == null) return [];

    return _currentPost!.platforms
        .where((platform) => !SocialPlatforms.supportsAutomatedPosting(platform))
        .toList();
  }

  /// Get platforms that require business accounts
  List<String> getPlatformsRequiringBusinessAccounts() {
    if (_currentPost == null) return [];

    return _currentPost!.platforms
        .where((platform) => SocialPlatforms.requiresBusinessAccount(platform))
        .toList();
  }

  /// Save the current post to Firestore
  Future<void> saveCurrentPost() async {
    if (_currentPost == null) return;

    try {
      await _firestoreService.saveAction(_currentPost!.toJson());
      _statusMessage = 'Post saved successfully';
      _statusType = StatusMessageType.success;
      notifyListeners();

      if (kDebugMode) {
        print('✅ Post saved to Firestore');
      }
    } catch (e) {
      _statusMessage = 'Error saving post: $e';
      _statusType = StatusMessageType.error;
      notifyListeners();

      if (kDebugMode) {
        print('❌ Error saving post: $e');
      }
    }
  }
}

/// Extension to add withValues method to Color
extension ColorWithValues on Color {
  Color withValues({int? red, int? green, int? blue, double? alpha}) {
    return Color.fromARGB(
      alpha != null ? (alpha * 255).round() : this.alpha,
      red ?? this.red,
      green ?? this.green,
      blue ?? this.blue,
    );
  }
}