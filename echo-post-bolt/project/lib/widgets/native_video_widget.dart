import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/native_video_player.dart';

/// NativeVideoWidget: Memory-efficient video widget with platform-specific implementations
///
/// - Mobile (Android/iOS): Uses native player reuse via method channels
/// - Web: Falls back to standard video_player with HTML5 <video> element
/// Both approaches eliminate disposal issues and keep memory usage under control.
class NativeVideoWidget extends StatefulWidget {
  final String? videoPath;
  final bool autoPlay;
  final double volume;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const NativeVideoWidget({
    this.videoPath,
    this.autoPlay = false,
    this.volume = 1.0,
    this.backgroundColor = const Color(0xFF2A2A2A),
    this.onTap,
    super.key,
  });

  @override
  State<NativeVideoWidget> createState() => _NativeVideoWidgetState();
}

class _NativeVideoWidgetState extends State<NativeVideoWidget> {
  @override
  Widget build(BuildContext context) {
    // Platform-specific implementation
    if (kIsWeb) {
      // Web: Use HTML5 video via standard video_player
      return _WebVideoPlayer(
        videoPath: widget.videoPath,
        autoPlay: widget.autoPlay,
        volume: widget.volume,
        backgroundColor: widget.backgroundColor,
        onTap: widget.onTap,
      );
    } else {
      // Mobile: Use native player reuse
      return _MobileVideoPlayer(
        videoPath: widget.videoPath,
        autoPlay: widget.autoPlay,
        volume: widget.volume,
        backgroundColor: widget.backgroundColor,
        onTap: widget.onTap,
      );
    }
  }
}

/// Web implementation using standard video_player with HTML5 <video> element
class _WebVideoPlayer extends StatefulWidget {
  final String? videoPath;
  final bool autoPlay;
  final double volume;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const _WebVideoPlayer({
    this.videoPath,
    this.autoPlay = false,
    this.volume = 1.0,
    this.backgroundColor = const Color(0xFF2A2A2A),
    this.onTap,
  });

  @override
  State<_WebVideoPlayer> createState() => _WebVideoPlayerState();
}

class _WebVideoPlayerState extends State<_WebVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  String? _currentPath;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    if (widget.videoPath != null) {
      _initializeController();
    }
  }

  @override
  void didUpdateWidget(_WebVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.videoPath != oldWidget.videoPath) {
      _switchVideo();
    }

    if (widget.volume != oldWidget.volume && _controller != null) {
      _controller!.setVolume(widget.volume);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeController() async {
    if (widget.videoPath == null) return;

    setState(() {
      _isLoading = true;
      _initializationError = null;
    });

    try {
      if (kDebugMode) {
        print('🌐 Web: Initializing video controller for: ${widget.videoPath}');
      }

      // Create controller for local file (web will handle as network URL)
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(
            'file://${widget.videoPath}'), // Web converts file paths to blob URLs
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentPath = widget.videoPath;
        });

        // Set initial volume and autoplay
        await _controller!.setVolume(widget.volume);
        if (widget.autoPlay) {
          await _controller!.play();
        }

        if (kDebugMode) {
          print('✅ Web: Video controller initialized successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Web: Failed to initialize video controller: $e');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _initializationError = e.toString();
        });
      }
    }
  }

  Future<void> _switchVideo() async {
    if (widget.videoPath == null || widget.videoPath == _currentPath) return;

    // Dispose old controller
    await _controller?.dispose();
    _controller = null;

    // Initialize new controller
    await _initializeController();
  }

  Future<void> togglePlayback() async {
    if (_controller == null) return;

    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    } else {
      await _controller!.play();
    }
  }

  Future<void> setVolume(double volume) async {
    await _controller?.setVolume(volume);
  }

  @override
  Widget build(BuildContext context) {
    // Show error state if initialization failed
    if (_initializationError != null) {
      return _buildErrorState(_initializationError!);
    }

    // Show loading state if no controller or not initialized
    if (_controller == null || !_controller!.value.isInitialized) {
      return _buildLoadingState();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: widget.backgroundColor,
        child: Stack(
          children: [
            // Video player
            SizedBox.expand(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),

            // Loading overlay
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF0055),
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: widget.backgroundColor,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFFFF0055),
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      color: widget.backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load video',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _initializationError = null;
                });
                _initializeController();
              },
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Color(0xFFFF0055),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile implementation using native player reuse
class _MobileVideoPlayer extends StatefulWidget {
  final String? videoPath;
  final bool autoPlay;
  final double volume;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const _MobileVideoPlayer({
    this.videoPath,
    this.autoPlay = false,
    this.volume = 1.0,
    this.backgroundColor = const Color(0xFF2A2A2A),
    this.onTap,
  });

  @override
  State<_MobileVideoPlayer> createState() => _MobileVideoPlayerState();
}

class _MobileVideoPlayerState extends State<_MobileVideoPlayer> {
  final _nativePlayer = NativeVideoPlayer.instance;
  int? _textureId;
  bool _isLoading = false;
  String? _currentPath;
  String? _initializationError;

  // Loading state debouncing to prevent flicker
  Timer? _loadingDebounceTimer;

  // Listen to native player state changes
  late final VoidCallback _playerListener;

  @override
  void initState() {
    super.initState();

    // Listen to player state changes
    _playerListener = () {
      if (mounted) {
        setState(() {
          // Trigger rebuild when player state changes
        });
      }
    };
    _nativePlayer.addListener(_playerListener);

    _initializeTexture();
  }

  @override
  void didUpdateWidget(_MobileVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.videoPath != oldWidget.videoPath) {
      _switchVideo();
    }

    if (widget.volume != oldWidget.volume) {
      _nativePlayer.setVolume(widget.volume);
    }
  }

  @override
  void dispose() {
    _loadingDebounceTimer?.cancel();
    _nativePlayer.removeListener(_playerListener);
    super.dispose();
  }

  Future<void> _initializeTexture() async {
    try {
      if (kDebugMode) {
        print('📱 Mobile: Initializing native texture...');
      }

      final textureId = await _nativePlayer.getTextureId();
      if (mounted) {
        setState(() {
          _textureId = textureId;
          _initializationError = null;
        });

        if (widget.videoPath != null) {
          _switchVideo();
        }

        if (kDebugMode) {
          print('✅ Mobile: Native texture initialized with ID: $textureId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Mobile: Failed to initialize native texture: $e');
      }

      if (mounted) {
        setState(() {
          _initializationError = e.toString();
        });
      }
    }
  }

  Future<void> _switchVideo() async {
    if (widget.videoPath == null || widget.videoPath == _currentPath) return;

    // Enhanced: Debounced loading state to prevent flicker during rapid switches
    _loadingDebounceTimer?.cancel();
    _loadingDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
    });

    try {
      if (kDebugMode) {
        print('📱 Mobile: Switching to video: ${widget.videoPath}');
      }

      final success = await _nativePlayer.switchVideo(widget.videoPath!);

      // Cancel loading timer
      _loadingDebounceTimer?.cancel();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentPath = success ? widget.videoPath : _currentPath;
        });

        // Auto-play if requested and switch was successful
        if (success && widget.autoPlay) {
          await _nativePlayer.play();
        }

        if (kDebugMode) {
          print(
              '${success ? '✅' : '❌'} Mobile: Video switch ${success ? 'successful' : 'failed'}');
        }
      }
    } catch (e) {
      _loadingDebounceTimer?.cancel();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (kDebugMode) {
        print('❌ Mobile: Exception during video switch: $e');
      }
    }
  }

  Future<void> togglePlayback() async {
    await _nativePlayer.togglePlayback();
  }

  Future<void> setVolume(double volume) async {
    await _nativePlayer.setVolume(volume);
  }

  @override
  Widget build(BuildContext context) {
    // Show error state if initialization failed
    if (_initializationError != null) {
      return _buildErrorState(_initializationError!);
    }

    // Show loading state if texture not ready
    if (_textureId == null) {
      return _buildLoadingState();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: widget.backgroundColor,
        child: Stack(
          children: [
            // Native video texture
            SizedBox.expand(
              child: Texture(textureId: _textureId!),
            ),

            // Loading overlay
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF0055),
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: widget.backgroundColor,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFFFF0055),
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Initializing video player...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      color: widget.backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Video player initialization failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _initializationError = null;
                  _textureId = null;
                });
                _initializeTexture();
              },
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Color(0xFFFF0055),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
