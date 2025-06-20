import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/social_action.dart';

/// Pure presentation widget for post content - no internal state management
/// All state comes from coordinators via parent widgets
class PostContentBox extends StatelessWidget {
  final SocialAction action;
  final VoidCallback? onEditText;
  final VoidCallback? onVoiceEdit;
  final Function(List<String>)? onEditHashtags;
  final bool isRecording;
  final bool isProcessingVoice;

  const PostContentBox({
    super.key,
    required this.action,
    this.onEditText,
    this.onVoiceEdit,
    this.onEditHashtags,
    this.isRecording = false,
    this.isProcessingVoice = false,
  });

  @override
  Widget build(BuildContext context) {
    final caption = action.content.text;
    final hashtags = action.content.hashtags;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(
            alpha: 0.7), // Translucent black like record button labels
        borderRadius: BorderRadius.circular(16),
        // No border for clean, subtle appearance
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with edit options
          Row(
            children: [
              Icon(
                Icons.edit_note,
                color: Colors.white.withValues(alpha: 0.9),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Post Content',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (onEditText != null)
                IconButton(
                  onPressed: onEditText,
                  icon: Icon(
                    Icons.edit,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 18,
                  ),
                  tooltip: 'Edit post text',
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Post text content
          if (caption.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                    alpha:
                        0.8), // Very dark gray using black translucency for subtle lift
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                caption,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                    alpha:
                        0.6), // Darker gray using black translucency for consistency
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Your post content will appear here',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Unified hashtag section
          _buildUnifiedHashtagsSection(context, hashtags),
        ],
      ),
    );
  }

  Widget _buildUnifiedHashtagsSection(
      BuildContext context, List<String> hashtags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.tag,
              color: Colors.white.withValues(alpha: 0.9),
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Hashtags',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${hashtags.length})',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
            const Spacer(),
            if (onEditHashtags != null)
              IconButton(
                onPressed: () => onEditHashtags!(hashtags),
                icon: Icon(
                  Icons.edit,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 16,
                ),
                tooltip: 'Edit hashtags',
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Hashtag display
        if (hashtags.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: hashtags
                  .map((hashtag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '#$hashtag',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Platform formatting preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Hashtags will be formatted automatically for each platform when posted',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(
                  alpha:
                      0.6), // Dark gray using black translucency for consistency
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'No hashtags yet - speak hashtags like "#photography #nature" or edit manually',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
