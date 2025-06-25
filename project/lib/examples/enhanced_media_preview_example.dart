import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/social_action.dart';
import '../widgets/enhanced_media_preview.dart';

/// Example usage of EnhancedMediaPreview for command screen
///
/// This example demonstrates how to use the enhanced media preview widget
/// for both images and videos with platform compatibility indicators.
class EnhancedMediaPreviewExample {
  /// Example: Create sample media items for testing
  static List<MediaItem> createSampleMediaItems() {
    return [
      // Sample image
      MediaItem(
        fileUri: 'file:///storage/emulated/0/Pictures/sample_image.jpg',
        mimeType: 'image/jpeg',
        deviceMetadata: DeviceMetadata(
          creationTime: DateTime.now().toIso8601String(),
          latitude: 37.7749,
          longitude: -122.4194,
          orientation: 1,
          width: 1920,
          height: 1080,
          fileSizeBytes: 2048000, // 2MB
        ),
      ),

      // Sample video
      MediaItem(
        fileUri: 'file:///storage/emulated/0/Movies/sample_video.mp4',
        mimeType: 'video/mp4',
        deviceMetadata: DeviceMetadata(
          creationTime: DateTime.now().toIso8601String(),
          latitude: 37.7749,
          longitude: -122.4194,
          orientation: 1,
          width: 1920,
          height: 1080,
          fileSizeBytes: 15728640, // 15MB
          duration: 30.0, // 30 seconds
          frameRate: 30.0,
          bitrate: 5000000, // 5Mbps
        ),
      ),
    ];
  }

  /// Example: Build enhanced media preview widget
  static Widget buildEnhancedMediaPreview({
    required List<MediaItem> mediaItems,
    List<String> platforms = const ['instagram', 'tiktok'],
    bool showPreselectedBadge = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 250,
      child: EnhancedMediaPreview(
        mediaItems: mediaItems,
        selectedPlatforms: platforms,
        showPreselectedBadge: showPreselectedBadge,
        onTap: onTap,
      ),
    );
  }

  /// Example: Demo screen showing enhanced media preview
  static Widget buildDemoScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Enhanced Media Preview Demo'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image example
              const Text(
                'Image Preview Example',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              buildEnhancedMediaPreview(
                mediaItems: [createSampleMediaItems()[0]], // Image only
                platforms: ['instagram'],
                onTap: () {
                  if (kDebugMode) {
                    print('🖼️ Image preview tapped');
                  }
                },
              ),

              const SizedBox(height: 32),

              // Video example
              const Text(
                'Video Preview Example',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              buildEnhancedMediaPreview(
                mediaItems: [createSampleMediaItems()[1]], // Video only
                platforms: ['instagram', 'tiktok', 'twitter'],
                onTap: () {
                  if (kDebugMode) {
                    print('🎬 Video preview tapped');
                  }
                },
              ),

              const SizedBox(height: 32),

              // Pre-selected media example
              const Text(
                'Pre-selected Media Example',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              buildEnhancedMediaPreview(
                mediaItems: createSampleMediaItems(),
                platforms: ['instagram'],
                showPreselectedBadge: true,
                onTap: () {
                  if (kDebugMode) {
                    print('📋 Pre-selected media preview tapped');
                  }
                },
              ),

              const SizedBox(height: 32),

              // Feature overview
              const Text(
                'Features',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FeatureItem(
                      icon: Icons.play_arrow,
                      title: 'Video Playback',
                      description:
                          'Tap to play/pause videos with native controls',
                    ),
                    SizedBox(height: 12),
                    FeatureItem(
                      icon: Icons.check_circle,
                      title: 'Platform Compatibility',
                      description:
                          'Real-time validation for Instagram, TikTok, Twitter',
                    ),
                    SizedBox(height: 12),
                    FeatureItem(
                      icon: Icons.info,
                      title: 'Rich Metadata',
                      description:
                          'Shows resolution, duration, format, and file size',
                    ),
                    SizedBox(height: 12),
                    FeatureItem(
                      icon: Icons.image,
                      title: 'Image Support',
                      description: 'Displays images with format information',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feature item widget for demo
class FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const FeatureItem({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: const Color(0xFFFF0055),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Integration example for CommandScreen
class CommandScreenIntegrationExample {
  /// Example: How to integrate with SocialActionPostCoordinator
  static Widget buildMediaPreviewIntegration({
    required List<MediaItem> mediaItems,
    required List<String> selectedPlatforms,
    required bool isPreselected,
    required VoidCallback onMediaTap,
  }) {
    return Container(
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
      child: mediaItems.isNotEmpty
          ? EnhancedMediaPreview(
              mediaItems: mediaItems,
              selectedPlatforms: selectedPlatforms,
              showPreselectedBadge: isPreselected,
              onTap: onMediaTap,
            )
          : _buildEmptyMediaPlaceholder(),
    );
  }

  /// Empty media placeholder
  static Widget _buildEmptyMediaPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A2A2A),
            Color(0xFF1F1F1F),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
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
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
