import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// NativeVideoPlayer: Singleton service for memory-efficient video playback
///
/// Uses a single native player instance (ExoPlayer/AVPlayer) that gets reused
/// across all video switches, eliminating VideoPlayerController disposal issues
/// and keeping memory usage under 50MB.
class NativeVideoPlayer extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('echo_post/video_player');
  static NativeVideoPlayer? _instance;
  static NativeVideoPlayer get instance => _instance ??= NativeVideoPlayer._();

  NativeVideoPlayer._();

  int? _textureId;
  String? _currentVideoPath;
  bool _isInitialized = false;
  bool _isPlaying = false;
  double _volume = 1.0;

  // Throttling and debouncing for memory efficiency
  DateTime? _lastSwitchTime;
  static const _switchThrottleMs = 300;
  Timer? _debounceTimer;

  // Public getters
  int? get textureId => _textureId;
  String? get currentVideoPath => _currentVideoPath;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  double get volume => _volume;

  /// Get texture ID, initializing player if needed
  Future<int?> getTextureId() async {
    if (!_isInitialized) {
      await _initializePlayer();
    }
    return _textureId;
  }

  /// Initialize the native player and texture
  Future<void> _initializePlayer() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        print('🎬 Initializing native video player...');
      }

      // Fixed: Proper type casting for platform channel response
      final result = await _channel.invokeMethod('initializePlayer');
      final resultMap = result as Map<dynamic, dynamic>;
      _textureId = resultMap['textureId'] as int?;
      _isInitialized = true;

      if (kDebugMode) {
        print('✅ Native player initialized with textureId: $_textureId');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize native player: $e');
      }

      // Reset state on failure
      _isInitialized = false;
      _textureId = null;
      rethrow;
    }
  }

  /// Switch to a new video with debounced throttling
  Future<bool> switchVideo(String videoPath) async {
    // Cancel any pending debounced switch
    _debounceTimer?.cancel();

    // Check throttling
    final now = DateTime.now();
    if (_lastSwitchTime != null &&
        now.difference(_lastSwitchTime!).inMilliseconds < _switchThrottleMs) {
      if (kDebugMode) {
        print(
            '⏱️ Video switch throttled, debouncing for ${_switchThrottleMs}ms');
      }

      // Debounce: Schedule for later instead of dropping
      _debounceTimer = Timer(Duration(milliseconds: _switchThrottleMs), () {
        _switchVideoImmediate(videoPath);
      });
      return false;
    }

    return await _switchVideoImmediate(videoPath);
  }

  /// Immediate video switch (internal)
  Future<bool> _switchVideoImmediate(String videoPath) async {
    _lastSwitchTime = DateTime.now();

    if (_currentVideoPath == videoPath) {
      if (kDebugMode) {
        print('🔄 Video already loaded: $videoPath');
      }
      return true;
    }

    try {
      if (kDebugMode) {
        print('🎬 Switching to video: $videoPath');
      }

      final result =
          await _channel.invokeMethod('switchVideo', {'path': videoPath});
      final success = result as bool? ?? false;

      if (success) {
        _currentVideoPath = videoPath;
        _isPlaying = false; // Reset play state on switch
        notifyListeners();

        if (kDebugMode) {
          print('✅ Successfully switched to video: $videoPath');
        }
      } else {
        if (kDebugMode) {
          print('❌ Failed to switch video: $videoPath');
        }
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Exception switching video: $e');
      }
      return false;
    }
  }

  /// Play the current video
  Future<bool> play() async {
    if (!_isInitialized) return false;

    try {
      await _channel.invokeMethod('play');
      _isPlaying = true;
      notifyListeners();

      if (kDebugMode) {
        print('▶️ Video playback started');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to play video: $e');
      }
      return false;
    }
  }

  /// Pause the current video
  Future<bool> pause() async {
    if (!_isInitialized) return false;

    try {
      await _channel.invokeMethod('pause');
      _isPlaying = false;
      notifyListeners();

      if (kDebugMode) {
        print('⏸️ Video playback paused');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to pause video: $e');
      }
      return false;
    }
  }

  /// Toggle play/pause
  Future<bool> togglePlayback() async {
    return _isPlaying ? await pause() : await play();
  }

  /// Set video volume
  Future<bool> setVolume(double volume) async {
    volume = volume.clamp(0.0, 1.0);

    if (!_isInitialized) {
      _volume = volume;
      return false;
    }

    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
      _volume = volume;
      notifyListeners();

      if (kDebugMode) {
        print('🔊 Volume set to: ${(volume * 100).round()}%');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to set volume: $e');
      }
      return false;
    }
  }

  /// Explicit disposal for proper resource management
  Future<void> dispose() async {
    _debounceTimer?.cancel();

    if (!_isInitialized) return;

    try {
      if (kDebugMode) {
        print('🗑️ Disposing native video player...');
      }

      await _channel.invokeMethod('dispose');

      _isInitialized = false;
      _textureId = null;
      _currentVideoPath = null;
      _isPlaying = false;

      if (kDebugMode) {
        print('✅ Native video player disposed');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error disposing native player: $e');
      }
    }
  }
}
