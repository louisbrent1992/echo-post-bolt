import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:ui' as ui;
import 'dart:async';

import '../models/social_action.dart';
import '../services/video_validation_service.dart';
import '../constants/typography.dart';
import '../route_observer.dart';
import '../services/native_video_player.dart';
import '../widgets/native_video_widget.dart';

/// EnhancedMediaPreview: Video and image preview widget for command screen
///
/// Supports both images and videos with playback controls, compatibility
/// indicators, and metadata display for social media posting.
class EnhancedMediaPreview extends StatefulWidget {
  final List<MediaItem> mediaItems;
  final List<String> selectedPlatforms;
  final bool showPreselectedBadge;
  final VoidCallback? onTap;

  const EnhancedMediaPreview({
    super.key,
    required this.mediaItems,
    this.selectedPlatforms = const [],
    this.showPreselectedBadge = false,
    this.onTap,
  });

  @override
  State<EnhancedMediaPreview> createState() => _EnhancedMediaPreviewState();
}

class _EnhancedMediaPreviewState extends State<EnhancedMediaPreview>
    with RouteAware {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;
  bool _isMuted = false;
  VideoValidationResult? _validationResult;
  bool _isValidating = false;
  String? _lastVideoPath;

  // Video thumbnail generation
  Uint8List? _videoThumbnail;
  bool _isGeneratingThumbnail = false;

  // Fallback image dimension cache for current media item
  int? _imageWidth;
  int? _imageHeight;

  // CRITICAL: Build phase protection to prevent setState during build
  bool _isInBuildPhase = false;
  bool _hasPendingStateUpdate = false;

  // FIXED: Remove static cache that was causing controller conflicts
  // Use instance-level cache instead for better memory management
  Uint8List? _cachedThumbnail;
  String? _cachedThumbnailPath;

  // Add video completion tracking
  bool _hasVideoCompleted = false;

  // UNIFIED: Static video operation limiter to prevent buffer overflow
  static int _activeVideoOperations = 0;
  static const int _maxConcurrentVideoOps = 2;

  @override
  void initState() {
    super.initState();
    _initializeMedia();
  }

  @override
  void didUpdateWidget(EnhancedMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if media changed
    final newMediaPath = widget.mediaItems.isNotEmpty
        ? Uri.parse(widget.mediaItems.first.fileUri).path
        : null;

    if (newMediaPath != _lastVideoPath) {
      // CRITICAL: Complete cleanup before reinitializing
      _completeVideoCleanup();
      _initializeMedia();
    }

    // Re-validate if platforms changed
    if (widget.selectedPlatforms != oldWidget.selectedPlatforms) {
      _validateVideo();
    }
  }

  @override
  void dispose() {
    _completeVideoCleanup();
    // Unsubscribe from route observer
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// CRITICAL: Complete video cleanup including all resources
  void _completeVideoCleanup() {
    _disposeVideoController();
    _cachedThumbnail = null;
    _cachedThumbnailPath = null;
    _hasVideoCompleted = false;

    // UNIFIED: Force garbage collection hint for video buffers
    if (kDebugMode) {
      print('🧹 UNIFIED: Complete video cleanup with buffer management');
    }
  }

  void _disposeVideoController() {
    if (_videoController != null) {
      // UNIFIED: Aggressive cleanup sequence to prevent buffer leaks
      try {
        // Pause playback before disposal to ensure clean shutdown
        _videoController!.pause();
        // Remove listener to prevent memory leaks
        _videoController!.removeListener(_videoListener);
        // Ensure proper resource cleanup
        _videoController!.dispose();
      } catch (e) {
        // Ignore disposal errors during cleanup
        if (kDebugMode) {
          print('⚠️ UNIFIED: Video controller disposal warning: $e');
        }
      } finally {
        _videoController = null;
        _isVideoInitialized = false;
        _isPlaying = false;
        _hasVideoCompleted = false;

        // UNIFIED: Decrement operation counter on disposal
        if (_activeVideoOperations > 0) {
          _activeVideoOperations--;
        }

        if (kDebugMode) {
          print(
              '🧹 UNIFIED: Video controller disposed with aggressive cleanup');
          print('   Active video operations: $_activeVideoOperations');
        }
      }
    }
  }

  Future<void> _initializeMedia() async {
    if (widget.mediaItems.isEmpty) {
      _disposeVideoController();
      setState(() {
        _videoThumbnail = null;
      });
      return;
    }

    final mediaItem = widget.mediaItems.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');
    final mediaPath = Uri.parse(mediaItem.fileUri).path;

    _lastVideoPath = mediaPath;

    // Reset cached dimensions whenever media changes
    _imageWidth = null;
    _imageHeight = null;

    if (isVideo) {
      // Generate thumbnail first for immediate display
      await _generateVideoThumbnail(mediaPath);

      // Then initialize video player for playback
      await _initializeVideo(mediaPath);

      if (widget.selectedPlatforms.isNotEmpty) {
        _validateVideo();
      }
    } else {
      _disposeVideoController();

      // Attempt to ensure image dimensions are available
      if (mediaItem.deviceMetadata.width == 0 ||
          mediaItem.deviceMetadata.height == 0) {
        await _decodeImageDimensions(mediaPath);
      } else {
        _imageWidth = mediaItem.deviceMetadata.width;
        _imageHeight = mediaItem.deviceMetadata.height;
      }

      if (mounted) {
        setState(() {
          _videoThumbnail = null;
        });
      }
    }
  }

  Future<void> _generateVideoThumbnail(String videoPath) async {
    if (_isGeneratingThumbnail) return;

    // Check cache first
    if (_cachedThumbnailPath == videoPath) {
      if (mounted) {
        setState(() {
          _videoThumbnail = _cachedThumbnail;
          _isGeneratingThumbnail = false;
        });
      }
      return;
    }

    setState(() {
      _isGeneratingThumbnail = true;
      _videoThumbnail = null;
    });

    try {
      // Try to find the AssetEntity for this video file
      final assetEntity = await _findAssetEntityByPath(videoPath);

      if (assetEntity != null) {
        // Generate a low-res thumbnail first for quick display
        final quickThumbnail = await assetEntity.thumbnailDataWithSize(
          const ThumbnailSize(100, 100),
          quality: 60,
        );

        // Show low-res thumbnail immediately if available
        if (mounted && quickThumbnail != null) {
          setState(() {
            _videoThumbnail = quickThumbnail;
            _cachedThumbnail = quickThumbnail;
            _cachedThumbnailPath = videoPath;
          });
        }

        // Then generate high-quality thumbnail
        final highQualityThumbnail = await assetEntity.thumbnailDataWithSize(
          const ThumbnailSize(400, 400),
          quality: 80,
        );

        if (mounted && highQualityThumbnail != null) {
          // Cache the high-quality thumbnail
          _cachedThumbnail = highQualityThumbnail;
          _cachedThumbnailPath = videoPath;

          setState(() {
            _videoThumbnail = highQualityThumbnail;
            _isGeneratingThumbnail = false;
          });

          if (kDebugMode) {
            print(
                '✅ Generated high-quality video thumbnail using PhotoManager');
          }
          return;
        }
      }

      // Fallback to video_thumbnail package with progressive quality
      await _generateProgressiveThumbnail(videoPath);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to generate video thumbnail: $e');
      }

      if (mounted) {
        setState(() {
          _isGeneratingThumbnail = false;
        });
      }
    }
  }

  Future<AssetEntity?> _findAssetEntityByPath(String videoPath) async {
    try {
      // Get all video albums
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        filterOption: FilterOptionGroup(
          videoOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true),
          ),
        ),
      );

      // Search through albums to find matching asset
      for (final album in albums) {
        final assets = await album.getAssetListRange(
          start: 0,
          end: await album.assetCountAsync,
        );

        for (final asset in assets) {
          final file = await asset.file;
          if (file != null && file.path == videoPath) {
            return asset;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error finding AssetEntity: $e');
      }
    }

    return null;
  }

  Future<void> _generateProgressiveThumbnail(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return;

      // Generate low-quality thumbnail first
      final quickThumbnail = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 100,
        maxHeight: 100,
        quality: 50,
        timeMs: 1000,
      );

      // Show low-quality thumbnail immediately if available
      if (mounted && quickThumbnail != null) {
        setState(() {
          _videoThumbnail = quickThumbnail;
          _cachedThumbnail = quickThumbnail;
          _cachedThumbnailPath = videoPath;
        });
      }

      // Then generate high-quality thumbnail
      final highQualityThumbnail = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        maxHeight: 400,
        quality: 80,
        timeMs: 1000,
      );

      if (mounted && highQualityThumbnail != null) {
        // Cache the high-quality thumbnail
        _cachedThumbnail = highQualityThumbnail;
        _cachedThumbnailPath = videoPath;

        setState(() {
          _videoThumbnail = highQualityThumbnail;
          _isGeneratingThumbnail = false;
        });

        if (kDebugMode) {
          print(
              '✅ Generated high-quality video thumbnail using video_thumbnail package');
        }
        return;
      }

      // Final fallback: just mark as complete
      if (mounted) {
        setState(() {
          _isGeneratingThumbnail = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to generate progressive thumbnail: $e');
      }

      if (mounted) {
        setState(() {
          _isGeneratingThumbnail = false;
        });
      }
    }
  }

  Future<void> _initializeVideo(String videoPath) async {
    // UNIFIED: Check operation limit to prevent buffer overflow
    if (_activeVideoOperations >= _maxConcurrentVideoOps) {
      if (kDebugMode) {
        print(
            '⚠️ UNIFIED: Video operation limit reached ($_activeVideoOperations/$_maxConcurrentVideoOps) - deferring initialization');
      }

      // Defer initialization to prevent buffer overflow
      await Future.delayed(const Duration(milliseconds: 500));

      // Retry if limit still exceeded
      if (_activeVideoOperations >= _maxConcurrentVideoOps) {
        if (kDebugMode) {
          print(
              '⚠️ UNIFIED: Video operation limit still exceeded - skipping initialization');
        }
        return;
      }
    }

    _activeVideoOperations++;

    try {
      // UNIFIED: Ensure complete cleanup before new initialization
      _completeVideoCleanup();

      final file = File(videoPath);
      if (!await file.exists()) {
        if (kDebugMode) {
          print('❌ UNIFIED: Video file does not exist: $videoPath');
        }
        return;
      }

      if (kDebugMode) {
        print(
            '🎬 UNIFIED: Initializing video with optimized buffer management: $videoPath');
        print(
            '   Active video operations: $_activeVideoOperations/$_maxConcurrentVideoOps');
      }

      // Create video player with optimized buffer configuration
      _videoController = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true, // Allow mixing with other audio
          allowBackgroundPlayback: false, // Prevent background resource usage
        ),
      );

      // Add listener before initialization to catch early events
      _videoController!.addListener(_videoListener);
      _videoController!.setVolume(_isMuted ? 0.0 : 1.0);

      // Set playback configuration for better buffering
      _videoController!.setPlaybackSpeed(1.0); // Ensure normal playback speed

      // Initialize with a timeout to prevent hanging
      await _videoController!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Video initialization timed out');
        },
      );

      // Reset completion flag for new video
      _hasVideoCompleted = false;

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }

      if (kDebugMode) {
        print(
            '✅ UNIFIED: Video initialized with buffer optimization: ${_videoController!.value.duration}');
        print('   Video path: $videoPath');
        print('   Ready for playback with managed buffers');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ UNIFIED: Failed to initialize video: $e');
      }

      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
        });
      }

      // UNIFIED: Aggressive cleanup on error
      _completeVideoCleanup();
    } finally {
      // UNIFIED: Always decrement operation counter
      _activeVideoOperations =
          (_activeVideoOperations - 1).clamp(0, _maxConcurrentVideoOps);

      if (kDebugMode) {
        print(
            '🔄 UNIFIED: Video operation completed, active operations: $_activeVideoOperations');
      }
    }
  }

  void _videoListener() {
    if (_videoController != null && mounted && !_isInBuildPhase) {
      final isCurrentlyPlaying = _videoController!.value.isPlaying;
      final position = _videoController!.value.position;
      final duration = _videoController!.value.duration;

      // Check for video completion
      if (!_hasVideoCompleted &&
          duration.inMilliseconds > 0 &&
          position.inMilliseconds >= duration.inMilliseconds - 100) {
        _hasVideoCompleted = true;
        _handleVideoCompletion();
      }

      // Only update state if playing status actually changed
      if (_isPlaying != isCurrentlyPlaying) {
        setState(() {
          _isPlaying = isCurrentlyPlaying;
        });
      }
    } else if (_videoController != null && mounted && _isInBuildPhase) {
      _hasPendingStateUpdate = true;
    }
  }

  /// Handle video completion - reset for replay
  void _handleVideoCompletion() {
    if (_videoController != null && mounted) {
      // Pause the video
      _videoController!.pause();

      // Reset to beginning for replay capability
      _videoController!.seekTo(Duration.zero);

      if (mounted) {
        setState(() {
          _isPlaying = false;
          _hasVideoCompleted = false; // Allow replay
        });
      }

      if (kDebugMode) {
        print('🔄 Video completed - reset for replay');
      }
    }
  }

  Future<void> _validateVideo() async {
    if (widget.mediaItems.isEmpty ||
        !widget.mediaItems.first.mimeType.startsWith('video/') ||
        widget.selectedPlatforms.isEmpty ||
        _isValidating) {
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      final videoPath = Uri.parse(widget.mediaItems.first.fileUri).path;
      final result = await VideoValidationService.validateVideoForPlatforms(
        videoPath,
        widget.selectedPlatforms,
        strictMode: false,
      );

      if (mounted) {
        setState(() {
          _validationResult = result;
          _isValidating = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error validating video: $e');
      }

      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  void _togglePlayback() {
    // Use NativeVideoPlayer instance instead of video controller
    NativeVideoPlayer.instance.togglePlayback();
  }

  void _toggleVolume() {
    // Toggle volume using native player
    final currentVolume = NativeVideoPlayer.instance.volume;
    final newVolume = currentVolume > 0 ? 0.0 : 1.0;
    setState(() {
      _isMuted = newVolume == 0.0;
    });
    NativeVideoPlayer.instance.setVolume(newVolume);
  }

  @override
  Widget build(BuildContext context) {
    _isInBuildPhase = true;

    if (widget.mediaItems.isEmpty) {
      _isInBuildPhase = false;
      return const SizedBox.shrink();
    }

    final mediaItem = widget.mediaItems.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');

    final builtWidget = GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        height: 250,
        decoration: const BoxDecoration(
          color: Color(0xFF2A2A2A),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media content - no ClipRRect to avoid constraint issues
            isVideo ? _buildVideoDisplay() : _buildImageDisplay(),

            // Video controls overlay (show for videos)
            if (isVideo) _buildVideoControls(),

            // Platform compatibility indicators
            if (isVideo && widget.selectedPlatforms.isNotEmpty)
              _buildCompatibilityIndicators(),

            // Media info overlay
            _buildMediaInfoOverlay(mediaItem, isVideo),

            // Pre-selected badge
            if (widget.showPreselectedBadge) _buildPreselectedBadge(),
          ],
        ),
      ),
    );

    _isInBuildPhase = false;

    // Handle any pending state updates after build phase completes
    if (_hasPendingStateUpdate) {
      _hasPendingStateUpdate = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }

    return builtWidget;
  }

  Widget _buildVideoDisplay() {
    final videoPath = Uri.parse(widget.mediaItems.first.fileUri).path;

    // Use NativeVideoWidget with explicit sizing to fill container
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: NativeVideoWidget(
        videoPath: videoPath,
        autoPlay: false, // Keep autoplay off on command screen
        volume: _isMuted ? 0.0 : 1.0,
        backgroundColor: const Color(0xFF2A2A2A),
        onTap: _togglePlayback,
      ),
    );
  }

  Widget _buildImageDisplay() {
    final imagePath = Uri.parse(widget.mediaItems.first.fileUri).path;

    return Image.file(
      File(imagePath),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: const BoxDecoration(color: Color(0xFF2A2A2A)),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.white54, size: 48),
                SizedBox(height: 8),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoControls() {
    return Stack(
      children: [
        // Play/pause button in center - NativeVideoWidget handles this internally
        // We can remove this since NativeVideoWidget has onTap for play/pause

        // Volume control button in top-right (moved to avoid conflicts with pre-selected badge)
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: _toggleVolume,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompatibilityIndicators() {
    if (_validationResult == null && !_isValidating) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      right: 12,
      child: _isValidating
          ? Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
                ),
              ),
            )
          : _buildPlatformStatus(),
    );
  }

  Widget _buildPlatformStatus() {
    if (_validationResult == null) return const SizedBox.shrink();

    final indicators = <Widget>[];

    for (final platform in widget.selectedPlatforms) {
      final platformResult = _validationResult!.platformResults[platform];
      if (platformResult == null) continue;

      Color indicatorColor;
      IconData indicatorIcon;

      if (!platformResult.isValid) {
        indicatorColor = Colors.red;
        indicatorIcon = Icons.error;
      } else if (platformResult.warnings.isNotEmpty) {
        indicatorColor = Colors.orange;
        indicatorIcon = Icons.warning;
      } else {
        indicatorColor = Colors.green;
        indicatorIcon = Icons.check_circle;
      }

      indicators.add(
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(
            indicatorIcon,
            color: indicatorColor,
            size: 20,
          ),
        ),
      );
    }

    if (indicators.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: indicators,
      ),
    );
  }

  Widget _buildMediaInfoOverlay(MediaItem mediaItem, bool isVideo) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Resolution and format info
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (context) {
                    final mediaItem = widget.mediaItems.first;
                    final isVideo = mediaItem.mimeType.startsWith('video/');

                    if (isVideo) {
                      // For videos: Use runtime detection via NativeVideoPlayer
                      final videoPath = Uri.parse(mediaItem.fileUri).path;
                      return FutureBuilder<Size>(
                        future:
                            NativeVideoPlayer.instance.getVideoSize(videoPath),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            final size = snapshot.data!;
                            return Text(
                              '${size.width.toInt()} × ${size.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTypography.small,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          } else {
                            // Show loading while detecting
                            return Text(
                              'Detecting...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: AppTypography.small,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          }
                        },
                      );
                    } else {
                      // For images: Use detected dimensions or MediaItem dimensions
                      return Text(
                        '${(_imageWidth ?? mediaItem.deviceMetadata.width)} × ${(_imageHeight ?? mediaItem.deviceMetadata.height)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTypography.small,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }
                  },
                ),
                // Show duration for videos from MediaItem metadata
                if (isVideo && mediaItem.deviceMetadata.duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatDuration(Duration(
                      seconds: mediaItem.deviceMetadata.duration!.toInt(),
                    )),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),

            const Spacer(),

            // Format and file size
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getFormatDisplayName(mediaItem.mimeType),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatFileSize(mediaItem.deviceMetadata.fileSizeBytes),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreselectedBadge() {
    return Positioned(
      top: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFF0055).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Pre-selected',
          style: TextStyle(
            color: Colors.white,
            fontSize: AppTypography.small,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }

  String _getFormatDisplayName(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'video/mp4':
        return 'MP4';
      case 'video/quicktime':
        return 'MOV';
      case 'video/x-msvideo':
        return 'AVI';
      case 'video/x-matroska':
        return 'MKV';
      case 'video/webm':
        return 'WebM';
      case 'video/x-m4v':
        return 'M4V';
      case 'video/3gpp':
        return '3GP';
      case 'image/jpeg':
        return 'JPEG';
      case 'image/png':
        return 'PNG';
      case 'image/gif':
        return 'GIF';
      case 'image/webp':
        return 'WebP';
      case 'image/heic':
        return 'HEIC';
      default:
        return mimeType.split('/').last.toUpperCase();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Subscribe to route changes for better memory management
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // UNIFIED: Aggressive video cleanup when navigating away to prevent buffer conflicts
    if (kDebugMode) {
      print(
          '🔄 UNIFIED: Navigation away detected - performing aggressive video cleanup');
    }

    _completeVideoCleanup();
    _isPlaying = false;
    super.didPushNext();
  }

  @override
  void didPopNext() {
    // UNIFIED: Smart reinitialization when returning to prevent resource conflicts
    if (kDebugMode) {
      print(
          '🔄 UNIFIED: Navigation return detected - smart video reinitialization');
    }

    // Only reinitialize if we have video content and no active controller
    if (_videoController == null && widget.mediaItems.isNotEmpty) {
      final mediaItem = widget.mediaItems.first;
      if (mediaItem.mimeType.startsWith('video/')) {
        final videoPath = Uri.parse(mediaItem.fileUri).path;

        // Delay reinitialization to ensure UI is stable
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _initializeVideo(videoPath);
          }
        });
      }
    }
    super.didPopNext();
  }

  // Decode image to retrieve intrinsic dimensions as a fallback
  Future<void> _decodeImageDimensions(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      final uiImage = await completer.future;

      if (mounted) {
        setState(() {
          _imageWidth = uiImage.width;
          _imageHeight = uiImage.height;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ EnhancedMediaPreview: Failed to decode image dimensions: $e');
      }
    }
  }
}
