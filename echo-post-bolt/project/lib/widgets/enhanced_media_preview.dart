import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:typed_data';

import '../models/social_action.dart';
import '../services/video_validation_service.dart';
import '../constants/typography.dart';
import '../route_observer.dart';

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
      _initializeMedia();
    }

    // Re-validate if platforms changed
    if (widget.selectedPlatforms != oldWidget.selectedPlatforms) {
      _validateVideo();
    }
  }

  @override
  void dispose() {
    _disposeVideoController();
    // Unsubscribe from route observer
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _disposeVideoController() {
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;
    _isPlaying = false;
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

    setState(() {
      _isGeneratingThumbnail = true;
      _videoThumbnail = null;
    });

    try {
      // Try to find the AssetEntity for this video file
      final assetEntity = await _findAssetEntityByPath(videoPath);

      if (assetEntity != null) {
        // Use PhotoManager to generate thumbnail
        final thumbnailData = await assetEntity.thumbnailDataWithSize(
          const ThumbnailSize(400, 400),
          quality: 80,
        );

        if (mounted && thumbnailData != null) {
          setState(() {
            _videoThumbnail = thumbnailData;
            _isGeneratingThumbnail = false;
          });

          if (kDebugMode) {
            print('✅ Generated video thumbnail using PhotoManager');
          }
          return;
        }
      }

      // Fallback: use video_thumbnail package for better thumbnail generation
      await _generateThumbnailFromVideoPlayer(videoPath);
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

  Future<void> _generateThumbnailFromVideoPlayer(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return;

      // Use video_thumbnail package for better thumbnail generation
      final thumbnailData = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        maxHeight: 400,
        quality: 80,
        timeMs: 1000, // Get thumbnail at 1 second
      );

      if (mounted && thumbnailData != null) {
        setState(() {
          _videoThumbnail = thumbnailData;
          _isGeneratingThumbnail = false;
        });

        if (kDebugMode) {
          print('✅ Generated video thumbnail using video_thumbnail package');
        }
        return;
      }

      // Final fallback: just mark as complete without thumbnail
      if (mounted) {
        setState(() {
          _isGeneratingThumbnail = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ Failed to generate thumbnail from video_thumbnail package: $e');
      }

      if (mounted) {
        setState(() {
          _isGeneratingThumbnail = false;
        });
      }
    }
  }

  Future<void> _initializeVideo(String videoPath) async {
    try {
      _disposeVideoController();

      final file = File(videoPath);
      if (!await file.exists()) {
        if (kDebugMode) {
          print('❌ Video file does not exist: $videoPath');
        }
        return;
      }

      _videoController = VideoPlayerController.file(file);
      _videoController!.addListener(_videoListener);
      _videoController!.setVolume(_isMuted ? 0.0 : 1.0);

      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }

      if (kDebugMode) {
        print('✅ Video initialized: ${_videoController!.value.duration}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize video: $e');
      }

      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
        });
      }
    }
  }

  void _videoListener() {
    if (_videoController != null && mounted) {
      setState(() {
        _isPlaying = _videoController!.value.isPlaying;
      });
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
    if (_videoController != null && _isVideoInitialized) {
      if (_isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    }
  }

  void _toggleVolume() {
    if (_videoController != null && _isVideoInitialized) {
      setState(() {
        _isMuted = !_isMuted;
        _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final mediaItem = widget.mediaItems.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        height: 250,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media content
            ClipRRect(
              child: isVideo ? _buildVideoDisplay() : _buildImageDisplay(),
            ),

            // Video controls overlay (only show when video is playing or can play)
            if (isVideo && (_isVideoInitialized || _videoThumbnail != null))
              _buildVideoControls(),

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
  }

  Widget _buildVideoDisplay() {
    // Show thumbnail if available, otherwise show video player or loading
    if (_videoThumbnail != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail as background
          Image.memory(
            _videoThumbnail!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildVideoPlayerOrLoading();
            },
          ),

          // If video is playing, overlay the video player with proper cropping
          if (_isPlaying && _isVideoInitialized && _videoController != null)
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: Transform.scale(
                  scale:
                      _calculateVideoScale(_videoController!.value.aspectRatio),
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
        ],
      );
    }

    return _buildVideoPlayerOrLoading();
  }

  Widget _buildVideoPlayerOrLoading() {
    if (_isVideoInitialized && _videoController != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: Transform.scale(
            scale: _calculateVideoScale(_videoController!.value.aspectRatio),
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(color: Color(0xFF2A2A2A)),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isGeneratingThumbnail || !_isVideoInitialized) ...[
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
                strokeWidth: 2,
              ),
              const SizedBox(height: 8),
              Text(
                _isGeneratingThumbnail
                    ? 'Generating thumbnail...'
                    : 'Loading video...',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ] else ...[
              const Icon(
                Icons.videocam,
                color: Colors.white54,
                size: 48,
              ),
              const SizedBox(height: 8),
              const Text(
                'Video preview',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Calculate the scale factor needed to fill the width while maintaining aspect ratio
  double _calculateVideoScale(double videoAspectRatio) {
    // Get the container's aspect ratio (width/height = 250 pixels height from CommandScreen)
    final containerWidth = MediaQuery.of(context).size.width;
    const containerHeight = 250.0;
    final containerAspectRatio = containerWidth / containerHeight;

    if (videoAspectRatio < containerAspectRatio) {
      // Video is taller than container - scale to match width
      return containerAspectRatio / videoAspectRatio;
    } else {
      // Video is wider than container - scale to match height
      return 1.0;
    }
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
        // Existing play/pause button in center
        Positioned.fill(
          child: Center(
            child: GestureDetector(
              onTap: _togglePlayback,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ),

        // Volume control button in top-left
        if (_isVideoInitialized || _videoThumbnail != null)
          Positioned(
            top: 12,
            left: 12,
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
                  size: 24,
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
                Text(
                  '${(_imageWidth ?? mediaItem.deviceMetadata.width)} × ${(_imageHeight ?? mediaItem.deviceMetadata.height)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTypography.small,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isVideo &&
                    _videoController != null &&
                    _isVideoInitialized) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatDuration(_videoController!.value.duration),
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

    // Subscribe to route changes so we can pause the video when this screen is covered
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // Another page is on top of us → pause playback to avoid background updates
    _videoController?.pause();
    _isPlaying = false;
    super.didPushNext();
  }

  @override
  void didPopNext() {
    // Returned to this page; we leave it paused (user can tap play)
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
