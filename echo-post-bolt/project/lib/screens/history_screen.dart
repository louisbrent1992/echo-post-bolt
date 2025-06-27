import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/social_action.dart';
import '../models/media_validation.dart';
import '../services/firestore_service.dart';
import '../services/social_post_service.dart';
import '../services/auth_service.dart';
import '../services/media_coordinator.dart';
import '../services/social_action_post_coordinator.dart';
import '../screens/command_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isDeleting = false;

  // Video thumbnail cache
  final Map<String, Uint8List?> _videoThumbnailCache = {};
  final Set<String> _generatingThumbnails = {};

  @override
  void dispose() {
    _videoThumbnailCache.clear();
    _generatingThumbnails.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Post History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back to the previous screen (Profile or Command Screen)
            Navigator.pop(context);
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF2A2A2A),
            onSelected: (value) {
              switch (value) {
                case 'validate_media':
                  _validateAllPostsMedia(context);
                  break;
                case 'clear_all':
                  _showClearAllDialog(context, firestoreService);
                  break;
                case 'refresh':
                  setState(() {}); // Refresh the stream
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Refresh', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'validate_media',
                child: Row(
                  children: [
                    Icon(Icons.healing, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Validate & Recover Media',
                        style: TextStyle(color: Colors.green)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear All History',
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.black, // Set to solid color
        ),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: firestoreService.getActionsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF0055)));
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading history',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Error: ${snapshot.error}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF0055),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.history,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No posts yet',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your post history will appear here after\nyou create and publish your first post',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Navigate to CommandScreen to create a new post
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CommandScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create Your First Post'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF0055),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final actionJson =
                      data['action_json'] as Map<String, dynamic>;
                  final status = data['status'] as String;
                  final createdAt = data['created_at'] as Timestamp?;
                  final postedAt = data['posted_at'] as Timestamp?;

                  try {
                    final action = SocialAction.fromJson(actionJson);
                    return _buildHistoryItem(
                      context,
                      action,
                      status,
                      createdAt?.toDate(),
                      postedAt?.toDate(),
                      data['error_log'] as List<dynamic>?,
                      doc.id,
                    );
                  } catch (e) {
                    return _buildErrorItem(context, doc.id, e.toString());
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    SocialAction action,
    String status,
    DateTime? createdAt,
    DateTime? postedAt,
    List<dynamic>? errorLog,
    String docId,
  ) {
    final hasMedia = action.content.media.isNotEmpty;
    final statusColor = _getStatusColor(status);
    final formattedDate = createdAt != null
        ? DateFormat('MMM d, yyyy \'at\' h:mm a').format(createdAt)
        : 'Unknown date';
    final formattedPostedDate = postedAt != null
        ? DateFormat('MMM d, yyyy \'at\' h:mm a').format(postedAt)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF0055).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () =>
            _showActionDetails(context, action, status, errorLog, docId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status and date
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(status),
                          color: statusColor,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          status.substring(0, 1).toUpperCase() +
                              status.substring(1),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Content preview
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Media thumbnail
                  if (hasMedia)
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: _buildMediaThumbnail(action.content.media.first),
                    ),
                  if (hasMedia) const SizedBox(width: 16),

                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (action.content.text.isNotEmpty)
                          Text(
                            action.content.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        if (action.content.text.isEmpty)
                          Text(
                            'Media post without caption',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Platform icons
                        Wrap(
                          spacing: 8,
                          children: action.platforms.map((platform) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getPlatformColor(platform)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getPlatformColor(platform)
                                      .withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getPlatformIcon(platform),
                                    color: _getPlatformColor(platform),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getPlatformDisplayName(platform),
                                    style: TextStyle(
                                      color: _getPlatformColor(platform),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Posted date for successful posts
              if (status == 'posted' && formattedPostedDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: Colors.green.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Posted $formattedPostedDate',
                        style: TextStyle(
                          color: Colors.green.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              // Error indicator
              if (status == 'failed')
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error,
                        size: 14,
                        color: Colors.red.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Failed to post',
                        style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
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

  Widget _buildErrorItem(BuildContext context, String docId, String error) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error,
                  color: Colors.red.withValues(alpha: 0.8),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Corrupted Post Data',
                  style: TextStyle(
                    color: Colors.red.withValues(alpha: 0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _deleteCorruptedPost(context, docId),
                  icon: Icon(
                    Icons.delete,
                    color: Colors.red.withValues(alpha: 0.8),
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Error parsing post: $error',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            Text(
              'Document ID: $docId',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaThumbnail(MediaItem mediaItem) {
    return Consumer<MediaCoordinator>(
      builder: (context, mediaCoordinator, child) {
        return FutureBuilder<MediaValidationResult>(
          future: mediaCoordinator.validateAndRecoverMediaURI(
            mediaItem.fileUri,
            config: MediaValidationConfig.production,
          ),
          builder: (context, validationSnapshot) {
            if (validationSnapshot.connectionState == ConnectionState.waiting) {
              // Show loading while validating - match the 80x80 container size
              return Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(128, 255, 255, 255),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF0055),
                    ),
                  ),
                ),
              );
            }

            final validationResult = validationSnapshot.data;

            if (validationResult == null || !validationResult.isValid) {
              // Custom EchoPost-themed placeholder for unavailable media
              return _buildCustomMediaPlaceholder();
            }

            // Use the effective URI (recovered or original)
            final effectiveUri = validationResult.effectiveUri;

            try {
              final file = File(Uri.parse(effectiveUri).path);

              // Check if this is a video file based on MIME type
              final isVideo = mediaItem.mimeType.startsWith('video/');

              if (isVideo) {
                // Route videos directly to enhanced thumbnail generator
                return _buildVideoThumbnail(file, mediaItem);
              }

              // Keep existing Image.file logic for images
              return Stack(
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Image.file(
                      file,
                      fit: BoxFit.cover,
                      width: 100,
                      height: 100,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildCustomMediaPlaceholder();
                      },
                    ),
                  ),
                  // Show recovery indicator if media was recovered
                  if (validationResult.wasRecovered)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 8,
                        ),
                      ),
                    ),
                ],
              );
            } catch (e) {
              return _buildCustomMediaPlaceholder();
            }
          },
        );
      },
    );
  }

  /// Custom EchoPost-themed placeholder for unavailable media
  Widget _buildCustomMediaPlaceholder() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        border: Border.all(
          color: const Color(0xFFFF0055).withValues(alpha: 77),
          width: 2,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.mic, // Match login screen icon
          color: Color(0xFFFF0055),
          size: 60,
        ),
      ),
    );
  }

  /// Build video thumbnail with actual thumbnail generation
  Widget _buildVideoThumbnail(File videoFile, MediaItem mediaItem) {
    final videoPath = videoFile.path;
    final cachedThumbnail = _videoThumbnailCache[videoPath];
    final isGenerating = _generatingThumbnails.contains(videoPath);

    // If we have a cached thumbnail, show it
    if (cachedThumbnail != null) {
      return Stack(
        children: [
          Image.memory(
            cachedThumbnail,
            fit: BoxFit.cover,
            width: 100,
            height: 100,
            errorBuilder: (context, error, stackTrace) {
              return _buildVideoPlaceholder();
            },
          ),
          // Video play indicator overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // If not generating and no cache, start generation
    if (!isGenerating) {
      _generateVideoThumbnail(videoPath);
    }

    // Show loading or placeholder while generating
    return _buildVideoPlaceholder(isGenerating: isGenerating);
  }

  /// Generate video thumbnail using the same logic as VideoPreviewWidget
  Future<void> _generateVideoThumbnail(String videoPath) async {
    if (_generatingThumbnails.contains(videoPath)) return;

    _generatingThumbnails.add(videoPath);

    try {
      Uint8List? thumbnailData;

      // Method 1: Try PhotoManager first (same as VideoPreviewWidget)
      final assetEntity = await _findAssetEntityByPath(videoPath);
      if (assetEntity != null) {
        thumbnailData = await assetEntity.thumbnailDataWithSize(
          const ThumbnailSize(300, 300),
          quality: 75,
        );

        if (kDebugMode && thumbnailData != null) {
          print('✅ PostHistory: Generated video thumbnail using PhotoManager');
        }
      }

      // Method 2: Fallback to video_thumbnail package
      if (thumbnailData == null) {
        final file = File(videoPath);
        if (await file.exists()) {
          thumbnailData = await VideoThumbnail.thumbnailData(
            video: videoPath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 300,
            maxHeight: 300,
            quality: 75,
            timeMs: 1000, // Get thumbnail at 1 second
          );

          if (kDebugMode && thumbnailData != null) {
            print(
                '✅ PostHistory: Generated video thumbnail using video_thumbnail package');
          }
        }
      }

      // Cache the result and update UI
      if (mounted) {
        setState(() {
          _videoThumbnailCache[videoPath] = thumbnailData;
          _generatingThumbnails.remove(videoPath);
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ PostHistory: Failed to generate video thumbnail: $e');
      }

      if (mounted) {
        setState(() {
          _videoThumbnailCache[videoPath] = null;
          _generatingThumbnails.remove(videoPath);
        });
      }
    }
  }

  /// Detailed media placeholder for modal view
  Widget _buildDetailedMediaPlaceholder() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A2A2A),
            Color(0xFF1A1A1A),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_none,
            color: const Color(0xFFFF0055).withValues(alpha: 0.6),
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Media Unavailable',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This media file is no longer accessible',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showActionDetails(
    BuildContext context,
    SocialAction action,
    String status,
    List<dynamic>? errorLog,
    String docId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Header Container - following Directory Screen top widget style
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title and Delete Button
                          Row(
                            children: [
                              const Icon(
                                Icons.article,
                                color: Color(0xFFFF0055),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Post Details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () =>
                                    _deletePost(context, action, docId),
                                icon: Icon(
                                  Icons.delete,
                                  color: Colors.red.withValues(alpha: 0.7),
                                ),
                                tooltip: 'Delete Post',
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Status
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _getStatusColor(status)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getStatusIcon(status),
                                  color: _getStatusColor(status),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  status.substring(0, 1).toUpperCase() +
                                      status.substring(1),
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Media preview
                    if (action.content.media.isNotEmpty) ...[
                      Row(
                        children: [
                          Text(
                            'Media',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Consumer<MediaCoordinator>(
                            builder: (context, mediaCoordinator, child) {
                              return FutureBuilder<MediaValidationResult>(
                                future:
                                    mediaCoordinator.validateAndRecoverMediaURI(
                                  action.content.media.first.fileUri,
                                  config: MediaValidationConfig.production,
                                ),
                                builder: (context, validationSnapshot) {
                                  final result = validationSnapshot.data;
                                  if (result != null && result.wasRecovered) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.green
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.refresh,
                                            color: Colors.green,
                                            size: 12,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Recovered',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: Consumer<MediaCoordinator>(
                          builder: (context, mediaCoordinator, child) {
                            return FutureBuilder<MediaValidationResult>(
                              future:
                                  mediaCoordinator.validateAndRecoverMediaURI(
                                action.content.media.first.fileUri,
                                config: MediaValidationConfig.production,
                              ),
                              builder: (context, validationSnapshot) {
                                if (validationSnapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Container(
                                    width: double.infinity,
                                    height: 200,
                                    color: Colors.white.withValues(alpha: 0.1),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFFF0055),
                                      ),
                                    ),
                                  );
                                }

                                final validationResult =
                                    validationSnapshot.data;

                                if (validationResult == null ||
                                    !validationResult.isValid) {
                                  return Container(
                                    width: double.infinity,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF2A2A2A),
                                          Color(0xFF1A1A1A),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color.fromRGBO(
                                            255, 255, 255, 0.1),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.mic_none,
                                          size: 64,
                                          color: const Color(0xFFFF0055)
                                              .withValues(alpha: 0.6),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Media Unavailable',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          validationResult?.errorMessage ??
                                              'This media file is no longer accessible',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.5),
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final effectiveUri =
                                    validationResult.effectiveUri;

                                // Check if this is a video or image
                                final mediaItem = action.content.media.first;
                                final isVideo =
                                    mediaItem.mimeType.startsWith('video/');
                                final file = File(Uri.parse(effectiveUri).path);

                                if (isVideo) {
                                  // Use video thumbnail for videos
                                  return _buildDetailVideoThumbnail(
                                      file, mediaItem);
                                } else {
                                  // Use existing image display for images
                                  return Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 200,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildDetailedMediaPlaceholder();
                                    },
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Caption
                    Text(
                      'Caption',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.content.text.isNotEmpty
                                ? action.content.text
                                : 'No caption provided',
                            style: TextStyle(
                              color: action.content.text.isNotEmpty
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white.withValues(alpha: 0.5),
                              fontSize: 16,
                              fontStyle: action.content.text.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                          if (action.content.hashtags.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: action.content.hashtags.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF0055)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFFF0055)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFFF0055),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Platforms
                    Text(
                      'Platforms',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: action.platforms.map((platform) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _getPlatformColor(platform)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getPlatformColor(platform)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getPlatformIcon(platform),
                                size: 18,
                                color: _getPlatformColor(platform),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                platform.substring(0, 1).toUpperCase() +
                                    platform.substring(1),
                                style: TextStyle(
                                  color: _getPlatformColor(platform),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Error log
                    if (status == 'failed' &&
                        errorLog != null &&
                        errorLog.isNotEmpty) ...[
                      Text(
                        'Error Details',
                        style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.8),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: errorLog.map((error) {
                            final timestamp = error['timestamp'] as Timestamp?;
                            final message = error['error'] as String? ??
                                error['message'] as String?;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (timestamp != null)
                                    Text(
                                      DateFormat('MMM d, yyyy \'at\' h:mm a')
                                          .format(timestamp.toDate()),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            Colors.white.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  if (message != null)
                                    Text(
                                      message,
                                      style: TextStyle(
                                        color:
                                            Colors.red.withValues(alpha: 0.8),
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Action buttons
                    if (status == 'failed') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retry Post'),
                          onPressed: () => _retryPost(context, action),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFFF0055).withValues(alpha: 0.1),
                            foregroundColor: const Color(0xFFFF0055),
                            side: BorderSide(
                              color: const Color(0xFFFF0055)
                                  .withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (status == 'pending') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.schedule, size: 18),
                          label: const Text('Reschedule'),
                          onPressed: () => _reschedulePost(context, action),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.orange.withValues(alpha: 0.1),
                            foregroundColor: Colors.orange,
                            side: BorderSide(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit Post'),
                        onPressed: () => _editPost(context, action),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Delete Post'),
                        onPressed: () => _deletePost(context, action, docId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                          foregroundColor: Colors.red,
                          side: BorderSide(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _retryPost(BuildContext context, SocialAction action) async {
    Navigator.pop(context); // Close the bottom sheet

    final socialPostService =
        Provider.of<SocialPostService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // Check authentication for each platform
      final authChecks = <String, bool>{};
      for (final platform in action.platforms) {
        authChecks[platform] = await authService.isPlatformConnected(platform);
      }

      final unauthenticatedPlatforms = authChecks.entries
          .where((entry) => !entry.value)
          .map((entry) => entry.key)
          .toList();

      if (unauthenticatedPlatforms.isNotEmpty) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Please authenticate with: ${unauthenticatedPlatforms.join(', ')}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Retrying post...'),
          backgroundColor: Color(0xFFFF0055),
        ),
      );

      final results = await socialPostService.postToAllPlatforms(action,
          authService: authService);

      final allSucceeded = results.values.every((success) => success);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            allSucceeded
                ? 'Post successful! 🎉'
                : 'Some platforms failed. Check history for details.',
          ),
          backgroundColor: allSucceeded ? Colors.green : Colors.orange,
        ),
      );

      final currentContext = context;
      if (currentContext.mounted) {
        Navigator.pushReplacement(
          currentContext,
          MaterialPageRoute(builder: (context) => const HistoryScreen()),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to retry post: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _reschedulePost(
      BuildContext context, SocialAction action) async {
    final navigator = Navigator.of(context);
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    navigator.pop(); // Close the bottom sheet

    // Show date picker
    final now = DateTime.now();
    final initialDate = action.options.schedule == 'now'
        ? now.add(const Duration(hours: 1))
        : DateTime.tryParse(action.options.schedule) ??
            now.add(const Duration(hours: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now)
          ? initialDate
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(0xFFFF0055),
                ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null && context.mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: const Color(0xFFFF0055),
                  ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        final scheduledDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        if (scheduledDateTime.isBefore(now)) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Cannot schedule posts in the past'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        try {
          // Update the action with the new schedule
          final updatedAction = SocialAction(
            actionId: action.actionId,
            createdAt: action.createdAt,
            platforms: action.platforms,
            content: action.content,
            options: Options(
              schedule: scheduledDateTime.toIso8601String(),
              locationTag: action.options.locationTag,
              visibility: action.options.visibility,
              replyToPostId: action.options.replyToPostId,
            ),
            platformData: action.platformData,
            internal: action.internal,
            mediaQuery: action.mediaQuery,
          );

          await firestoreService.updateAction(
            updatedAction.actionId,
            updatedAction.toJson(),
          );

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                'Post rescheduled for ${DateFormat('MMM d, yyyy \'at\' h:mm a').format(scheduledDateTime)}',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Failed to reschedule: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deletePost(
      BuildContext context, SocialAction action, String docId) async {
    final navigator = Navigator.of(context);
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Delete Post?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this post? This action cannot be undone.',
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
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      navigator.pop(); // Close the bottom sheet

      try {
        await firestoreService.deleteAction(action.actionId);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Post deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to delete post: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteCorruptedPost(BuildContext context, String docId) async {
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Delete Corrupted Post?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This post data is corrupted and cannot be displayed properly. Would you like to delete it?',
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
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await firestoreService.deleteActionById(docId);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Corrupted post deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to delete corrupted post: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showClearAllDialog(
      BuildContext context, FirestoreService firestoreService) async {
    if (_isDeleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Clear All History?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete all post history? This action cannot be undone.',
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
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('CLEAR ALL'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isDeleting = true;
      });

      try {
        await firestoreService.clearAllActions();
        final currentContext = context;
        if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            const SnackBar(
              content: Text('All post history cleared successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        final currentContext = context;
        if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            SnackBar(
              content: Text('Failed to clear history: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isDeleting = false;
          });
        }
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'posted':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return const Color(0xFFFF0055);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.schedule;
      case 'processing':
        return Icons.sync;
      case 'posted':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'facebook':
        return Icons.facebook;
      case 'instagram':
        return Icons.camera_alt;
      case 'twitter':
        return Icons.flutter_dash;
      case 'tiktok':
        return Icons.music_note;
      default:
        return Icons.public;
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'facebook':
        return Colors.blue.shade700;
      case 'instagram':
        return Colors.pink.shade400;
      case 'twitter':
        return Colors.lightBlue.shade400;
      case 'tiktok':
        return Colors.white;
      default:
        return Colors.grey;
    }
  }

  String _getPlatformDisplayName(String platform) {
    switch (platform) {
      case 'facebook':
        return 'Facebook';
      case 'instagram':
        return 'Instagram';
      case 'twitter':
        return 'Twitter';
      case 'tiktok':
        return 'TikTok';
      default:
        return platform.toUpperCase();
    }
  }

  /// Validates and recovers media for all posts in the history
  Future<void> _validateAllPostsMedia(BuildContext context) async {
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);
    final mediaCoordinator =
        Provider.of<MediaCoordinator>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Validate All Media?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will check all media files in your post history and attempt to recover any broken links. This may take a few moments.',
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
            style: TextButton.styleFrom(
              foregroundColor: Colors.green,
            ),
            child: const Text('VALIDATE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Capture context before any async operations
    final dialogContext = context;

    // Show progress dialog immediately after confirmation, before any async operations
    if (!mounted) return;

    // ignore: use_build_context_synchronously
    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFF0055)),
            const SizedBox(height: 16),
            Text(
              'Validating media files...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );

    // Perform async operations
    _performMediaValidationAsync(
        firestoreService, mediaCoordinator, navigator, scaffoldMessenger);
  }

  Future<void> _performMediaValidationAsync(
    FirestoreService firestoreService,
    MediaCoordinator mediaCoordinator,
    NavigatorState navigator,
    ScaffoldMessengerState scaffoldMessenger,
  ) async {
    try {
      // Get all posts
      final querySnapshot = await firestoreService.getActionsStream().first;
      if (!mounted) return;
      final posts = <SocialAction>[];

      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final actionJson = data['action_json'] as Map<String, dynamic>;
          final action = SocialAction.fromJson(actionJson);
          if (action.content.media.isNotEmpty) {
            posts.add(action);
          }
        } catch (e) {
          // Skip corrupted posts
          continue;
        }
      }

      if (!mounted) return;
      if (posts.isEmpty) {
        if (mounted) navigator.pop(); // Close progress dialog
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('No posts with media found'),
            backgroundColor: Colors.blue,
          ),
        );
        return;
      }

      // Validate media for all posts
      int totalMediaItems = 0;
      int recoveredItems = 0;
      int failedItems = 0;

      for (final post in posts) {
        totalMediaItems += post.content.media.length;

        // ========== PHASE 4: USE UNIFIED VALIDATION SYSTEM ==========
        // Use MediaCoordinator's unified validation instead of individual calls
        final mediaUris = post.content.media.map((m) => m.fileUri).toList();
        final batchResult = await mediaCoordinator.validateMediaBatch(
          mediaUris,
          config: MediaValidationConfig.production,
          enableRecovery: true,
          enableCaching: true,
        );

        if (batchResult.hasRecoveredItems || batchResult.hasFailedItems) {
          recoveredItems += batchResult.recoveredItems;
          failedItems += batchResult.failedItems;

          // Update post in Firestore if there were recoveries
          if (batchResult.hasRecoveredItems) {
            try {
              final recoveredMedia = <MediaItem>[];

              for (int i = 0; i < batchResult.results.length; i++) {
                final result = batchResult.results[i];
                final originalMedia = post.content.media[i];

                if (result.isValid) {
                  if (result.wasRecovered) {
                    final recoveredItem = mediaCoordinator
                        .createRecoveredMediaItem(originalMedia, result);
                    if (recoveredItem != null) {
                      recoveredMedia.add(recoveredItem);
                    }
                  } else {
                    recoveredMedia.add(originalMedia);
                  }
                }
              }

              if (recoveredMedia.isNotEmpty) {
                final updatedPost = post.copyWith(
                  content: post.content.copyWith(media: recoveredMedia),
                );

                await firestoreService.updateAction(
                    post.actionId, updatedPost.toJson());
              }
            } catch (e) {
              // Handle update error
            }
          }
        }
      }

      if (!mounted) return;
      if (mounted) navigator.pop(); // Close progress dialog

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Validation complete: $totalMediaItems items checked, $recoveredItems recovered, $failedItems failed',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (mounted) navigator.pop(); // Close progress dialog
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to validate media: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editPost(BuildContext context, SocialAction action) async {
    final navigator = Navigator.of(context);
    final socialActionPostCoordinator =
        Provider.of<SocialActionPostCoordinator>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Close the overlay first
    navigator.pop();

    try {
      if (kDebugMode) {
        print('🔄 Starting post edit flow for action: ${action.actionId}');
      }

      // Load historical post into coordinator
      await socialActionPostCoordinator.loadHistoricalPost(action);

      // Navigate to CommandScreen with rehydrated state
      if (context.mounted) {
        await navigator.push(
          MaterialPageRoute(builder: (context) => const CommandScreen()),
        );
      }

      if (kDebugMode) {
        print('✅ Post edit flow completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to edit post: $e');
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to load post for editing: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Find AssetEntity by path (same logic as VideoPreviewWidget)
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
        print('❌ PostHistory: Error finding AssetEntity: $e');
      }
    }

    return null;
  }

  /// Enhanced video placeholder with loading state
  Widget _buildVideoPlaceholder({bool isGenerating = false}) {
    if (isGenerating) {
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3A3A3A),
              Color(0xFF2A2A2A),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFFF0055).withValues(alpha: 77),
            width: 2,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3A3A3A),
            Color(0xFF2A2A2A),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFFF0055).withValues(alpha: 77),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.videocam,
            color: Color(0xFFFF0055),
            size: 40,
          ),
          const SizedBox(height: 4),
          Text(
            'Video',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build video thumbnail for Post Detail overlay (larger format)
  Widget _buildDetailVideoThumbnail(File videoFile, MediaItem mediaItem) {
    final videoPath = videoFile.path;
    final cachedThumbnail = _videoThumbnailCache[videoPath];
    final isGenerating = _generatingThumbnails.contains(videoPath);

    // If we have a cached thumbnail, show it
    if (cachedThumbnail != null) {
      return Stack(
        children: [
          Image.memory(
            cachedThumbnail,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 200,
            errorBuilder: (context, error, stackTrace) {
              return _buildDetailedMediaPlaceholder();
            },
          ),
          // Video play indicator overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
              ),
              child: const Center(
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
          ),
          // Video format and duration info overlay
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getFormatDisplayName(mediaItem.mimeType),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (mediaItem.deviceMetadata.duration != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(Duration(
                          seconds: mediaItem.deviceMetadata.duration!.toInt())),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    // If not generating and no cache, start generation
    if (!isGenerating) {
      _generateVideoThumbnail(videoPath);
    }

    // Show loading or placeholder while generating
    return _buildDetailVideoPlaceholder(isGenerating: isGenerating);
  }

  /// Enhanced video placeholder for Post Detail overlay
  Widget _buildDetailVideoPlaceholder({bool isGenerating = false}) {
    if (isGenerating) {
      return Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3A3A3A),
              Color(0xFF2A2A2A),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFFF0055).withValues(alpha: 77),
            width: 2,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Generating video thumbnail...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3A3A3A),
            Color(0xFF2A2A2A),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFFF0055).withValues(alpha: 77),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.videocam,
            color: Color(0xFFFF0055),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Video Preview',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Generating thumbnail...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Helper method to format video duration
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

  /// Helper method to get format display name
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
