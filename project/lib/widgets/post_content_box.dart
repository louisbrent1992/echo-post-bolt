import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/social_action.dart';

class PostContentBox extends StatelessWidget {
  final SocialAction action;
  final VoidCallback? onEditText;
  final VoidCallback? onVoiceEdit;
  final bool isRecording;
  final bool isProcessingVoice;

  const PostContentBox({
    super.key,
    required this.action,
    this.onEditText,
    this.onVoiceEdit,
    this.isRecording = false,
    this.isProcessingVoice = false,
  });

  @override
  Widget build(BuildContext context) {
    final caption = action.content.text;
    final hashtags = action.content.hashtags;
    final mentions = action.content.mentions;
    final hasContent = caption.isNotEmpty || hashtags.isNotEmpty;

    if (kDebugMode) {
      if (caption.isEmpty && hashtags.isEmpty) {
        print('🔍 PostContentBox Debug: No content found');
        print('   Caption: "$caption"');
        print('   Hashtags: $hashtags');
        print('   Mentions: $mentions');
      } else {
        print('✅ PostContentBox Debug: Content available');
        print('   Caption: "$caption"');
        print('   Hashtags: $hashtags');
      }
    }

    return Container(
      width: double.infinity, // Full width, edge to edge
      constraints: const BoxConstraints(
        minHeight: 120,
        maxHeight: 300,
      ),
      decoration: BoxDecoration(
        // Sleek dark translucent background
        color: Colors.black.withValues(alpha: 0.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with edit controls
          _buildHeader(context),

          // Content area
          Flexible(
            child:
                _buildContent(context, caption, hashtags, mentions, hasContent),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 15, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.edit_note,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Post Content',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          Row(
            children: [
              // Voice edit button
              IconButton(
                icon: Icon(
                  isRecording ? Icons.stop_circle : Icons.mic,
                  color: isRecording ? Colors.red : const Color(0xFFFF0080),
                  size: 18,
                ),
                onPressed: isProcessingVoice ? null : onVoiceEdit,
                tooltip: isRecording
                    ? 'Stop recording'
                    : isProcessingVoice
                        ? 'Processing...'
                        : 'Add text with voice',
                constraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 16, color: Colors.white70),
                onPressed: onEditText,
                tooltip: 'Edit caption',
                constraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, String caption,
      List<String> hashtags, List<String> mentions, bool hasContent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Processing indicator
          if (isProcessingVoice) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF0080).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF0080),
                      ),
                    ),
                  ),
                  SizedBox(width: 9),
                  Text(
                    'Processing your voice edit...',
                    style: TextStyle(
                      color: Color(0xFFFF0080),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (hasContent) ...[
            // Caption text
            if (caption.isNotEmpty) ...[
              Text(
                caption,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.4,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (hashtags.isNotEmpty || mentions.isNotEmpty)
                const SizedBox(height: 15),
            ],

            // Hashtags and mentions
            if (hashtags.isNotEmpty || mentions.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...hashtags.map((tag) => _buildHashtagChip(tag)),
                  ...mentions.map((mention) => _buildMentionChip(mention)),
                ],
              ),
            ],
          ] else ...[
            // Empty state
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white
                    .withValues(alpha: 0.1), // Dark translucent background
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2), // Light border
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.text_fields,
                    color: Colors.white60, // White icon
                    size: 24,
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'No caption or hashtags yet',
                    style: TextStyle(
                      color: Colors.white, // White text
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Use the buttons above to add content',
                    style: TextStyle(
                      color: Colors.white70, // Light white text
                      fontSize: 12,
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

  Widget _buildHashtagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
  }

  Widget _buildMentionChip(String mention) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        '@$mention',
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
