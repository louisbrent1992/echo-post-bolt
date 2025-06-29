import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../services/video_validation_service.dart';

/// VideoPreviewWidget: Enhanced video preview for media selection
///
/// Shows video thumbnail, duration, format information, and platform
/// compatibility warnings for Instagram, TikTok, and Twitter videos.
class VideoPreviewWidget extends StatefulWidget {
  final Map<String, dynamic> mediaItem;
  final List<String> selectedPlatforms;
  final bool isSelected;
  final VoidCallback? onTap;

  const VideoPreviewWidget({
    super.key,
    required this.mediaItem,
    this.selectedPlatforms = const [],
    this.isSelected = false,
    this.onTap,
  });

  @override
  State<VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<VideoPreviewWidget> {
  VideoValidationResult? _validationResult;
  bool _isValidating = false;

  // Video thumbnail generation
  Uint8List? _videoThumbnail;
  bool _isGeneratingThumbnail = false;

  @override
  void initState() {
    super.initState();
    _generateVideoThumbnail();
    if (widget.selectedPlatforms.isNotEmpty) {
      _validateVideo();
    }
  }

  @override
  void didUpdateWidget(VideoPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Re-generate thumbnail if media item changed
    if (widget.mediaItem['file_uri'] != oldWidget.mediaItem['file_uri']) {
      _generateVideoThumbnail();
    }

    // Re-validate if platforms changed
    if (widget.selectedPlatforms != oldWidget.selectedPlatforms &&
        widget.selectedPlatforms.isNotEmpty) {
      _validateVideo();
    }
  }

  Future<void> _generateVideoThumbnail() async {
    if (_isGeneratingThumbnail) return;

    setState(() {
      _isGeneratingThumbnail = true;
      _videoThumbnail = null;
    });

    try {
      final fileUri = widget.mediaItem['file_uri'] as String;
      final videoPath = Uri.parse(fileUri).path;

      // Try to find the AssetEntity for this video file
      final assetEntity = await _findAssetEntityByPath(videoPath);

      if (assetEntity != null) {
        // Use PhotoManager to generate thumbnail
        final thumbnailData = await assetEntity.thumbnailDataWithSize(
          const ThumbnailSize(300, 300),
          quality: 75,
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

      // Fallback: use video_thumbnail package
      await _generateThumbnailFromVideoThumbnail(videoPath);
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

  Future<void> _generateThumbnailFromVideoThumbnail(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return;

      // Use video_thumbnail package for thumbnail generation
      final thumbnailData = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        maxHeight: 300,
        quality: 75,
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

  Future<void> _validateVideo() async {
    if (_isValidating) return;

    setState(() {
      _isValidating = true;
    });

    try {
      final fileUri = widget.mediaItem['file_uri'] as String;
      final filePath = Uri.parse(fileUri).path;

      final result = await VideoValidationService.validateVideoForPlatforms(
        filePath,
        widget.selectedPlatforms,
        strictMode: false, // Use lenient mode for warnings
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

  @override
  Widget build(BuildContext context) {
    final deviceMetadata =
        widget.mediaItem['device_metadata'] as Map<String, dynamic>? ?? {};
    final duration = (deviceMetadata['duration'] as num?)?.toDouble() ?? 0.0;
    final width = (deviceMetadata['width'] as num?)?.toInt() ?? 0;
    final height = (deviceMetadata['height'] as num?)?.toInt() ?? 0;
    final fileSizeBytes =
        (deviceMetadata['file_size_bytes'] as num?)?.toInt() ?? 0;
    final mimeType = widget.mediaItem['mime_type'] as String? ?? 'video/mp4';

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: const BoxDecoration(
            // Remove borderRadius to make corners square
            ),
        child: Stack(
          children: [
            // Video thumbnail/placeholder
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A2A),
                // Remove borderRadius to make corners square
              ),
              child: _buildVideoThumbnail(),
            ),

            // Video info overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  // Remove borderRadius to make corners square
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Duration and resolution
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatDuration(duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$width×$height',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatFileSize(fileSizeBytes),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),

                    // Format info
                    const SizedBox(height: 4),
                    Text(
                      _getFormatDisplayName(mimeType),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Platform compatibility indicators
            if (_validationResult != null &&
                widget.selectedPlatforms.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: _buildPlatformIndicators(),
              ),

            // Loading indicator during validation
            if (_isValidating)
              const Positioned(
                top: 8,
                right: 8,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
                  ),
                ),
              ),

            // Selection indicator
            if (widget.isSelected)
              const Positioned(
                top: 8,
                left: 8,
                child: Icon(
                  Icons.check_circle,
                  color: Color(0xFFFF0055),
                  size: 24,
                ),
              ),

            // Play icon overlay
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail() {
    if (_videoThumbnail != null) {
      return ClipRRect(
        // Remove rounded corners for consistency with image thumbnails
        borderRadius: BorderRadius.zero,
        child: Image.memory(
          _videoThumbnail!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildVideoPlaceholder();
          },
        ),
      );
    }

    return _buildVideoPlaceholder();
  }

  Widget _buildVideoPlaceholder() {
    if (_isGeneratingThumbnail) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
              strokeWidth: 2,
            ),
            SizedBox(height: 8),
            Text(
              'Loading thumbnail...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Icon(
        Icons.videocam,
        color: Colors.white54,
        size: 48,
      ),
    );
  }

  Widget _buildPlatformIndicators() {
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
        Container(
          margin: const EdgeInsets.only(left: 2),
          child: Icon(
            indicatorIcon,
            color: indicatorColor,
            size: 16,
          ),
        ),
      );
    }

    if (indicators.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: indicators,
      ),
    );
  }

  String _formatDuration(double durationSeconds) {
    if (durationSeconds <= 0) return '0:00';

    final minutes = (durationSeconds / 60).floor();
    final seconds = (durationSeconds % 60).floor();

    if (minutes >= 60) {
      final hours = (minutes / 60).floor();
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
      default:
        return mimeType.split('/').last.toUpperCase();
    }
  }
}

/// VideoCompatibilityDialog: Shows detailed platform compatibility info
class VideoCompatibilityDialog extends StatelessWidget {
  final VideoValidationResult validationResult;
  final List<String> platforms;

  const VideoCompatibilityDialog({
    super.key,
    required this.validationResult,
    required this.platforms,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      title: const Text(
        'Video Compatibility',
        style: TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!validationResult.isValid) ...[
              const Text(
                'Errors:',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (final error in validationResult.errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
            if (validationResult.warnings.isNotEmpty) ...[
              const Text(
                'Warnings:',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (final warning in validationResult.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warning,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Platform Recommendations:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final platform in platforms) ...[
              Text(
                platform.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFFF0055),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              ...VideoValidationService.getPlatformRecommendations(platform)
                  .entries
                  .map((entry) => Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 2),
                        child: Text(
                          '${entry.key.replaceAll('_', ' ').toUpperCase()}: ${entry.value}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      )),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'CLOSE',
            style: TextStyle(color: Color(0xFFFF0055)),
          ),
        ),
      ],
    );
  }
}
