import 'package:flutter/material.dart';
import 'dart:io';
import '../models/social_action.dart';

class PostPreview extends StatelessWidget {
  final SocialAction? action;
  final VoidCallback? onReviewMedia;
  final VoidCallback? onReviewPost;

  const PostPreview({
    super.key,
    this.action,
    this.onReviewMedia,
    this.onReviewPost,
  });

  @override
  Widget build(BuildContext context) {
    if (action == null) {
      return _buildEmptyState(context);
    }

    return AspectRatio(
      aspectRatio: 1.0, // Instagram square aspect ratio
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media preview if available - now takes more space without platform header
            if (action!.content.media.isNotEmpty)
              Expanded(
                flex: 3,
                child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    child: _buildMediaPreview(context),
                  ),
                ),
              ),

            // Content area - adjusts based on media presence
            Expanded(
              flex: action!.content.media.isNotEmpty ? 2 : 4,
              child: _buildContentArea(context),
            ),

            // Action buttons (compact)
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0, // Instagram square aspect ratio
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.post_add,
                color: Colors.white,
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                'Your post preview will appear here',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPreview(BuildContext context) {
    final mediaItem = action!.content.media.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');

    return Stack(
      fit: StackFit.expand,
      children: [
        // Media placeholder or actual image
        if (mediaItem.fileUri.isNotEmpty &&
            mediaItem.fileUri.startsWith('file://'))
          Image.file(
            File(Uri.parse(mediaItem.fileUri).path),
            fit: BoxFit.cover, // Maintains square aspect ratio
            errorBuilder: (context, error, stackTrace) {
              return _buildMediaPlaceholder(isVideo);
            },
          )
        else
          _buildMediaPlaceholder(isVideo),

        // Video play button overlay
        if (isVideo)
          const Center(
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white,
              size: 48,
              shadows: [
                Shadow(
                  blurRadius: 10.0,
                  color: Colors.black54,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMediaPlaceholder(bool isVideo) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isVideo ? Icons.videocam : Icons.image,
              color: Colors.grey.shade400,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              isVideo ? 'Video Preview' : 'Image Preview',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentArea(BuildContext context) {
    final text = action!.content.text;
    final hashtags = action!.content.hashtags;
    final hasContent = text.isNotEmpty || hashtags.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text.isNotEmpty) ...[
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
            if (hashtags.isNotEmpty) const SizedBox(height: 12),
          ],
          if (hashtags.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: hashtags.map((tag) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0080).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF0080).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      color: Color(0xFFFF0080),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (!hasContent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No caption provided. Add text on the review page.',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final hasMedia = action!.content.media.isNotEmpty;
    final hasMediaQuery = action!.mediaQuery?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          if (!hasMedia && hasMediaQuery) ...[
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Add Media'),
                onPressed: onReviewMedia,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF0080),
                  side: const BorderSide(color: Color(0xFFFF0080)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.send, size: 18),
              label: Text(hasMedia ? 'Review Post' : 'Continue'),
              onPressed: onReviewPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0080),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
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
        return Colors.black87;
      default:
        return Colors.grey.shade600;
    }
  }
}
