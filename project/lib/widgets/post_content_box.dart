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

    // Only log debug info when content is actually available to avoid console clutter
    if (kDebugMode && hasContent) {
      print('✅ PostContentBox Debug: Content available');
      print('   Caption: "$caption"');
      print('   Hashtags: $hashtags');
    }

    return Container(
      width: double.infinity, // Full width, edge to edge
      constraints: const BoxConstraints(
        minHeight: 120,
        maxHeight: 200,
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

          // Content area - now scrollable
          _buildContent(context, caption, hashtags, mentions, hasContent),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 12, 0),
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
                  minWidth: 26,
                  minHeight: 26,
                ),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 16, color: Colors.white70),
                onPressed: onEditText,
                tooltip: 'Edit caption',
                constraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: 26,
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
    return Expanded(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    // Hashtags
                    ...hashtags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF0080).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFFF0080)
                                  .withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '#$tag',
                            style: const TextStyle(
                              color: Color(0xFFFF0080),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )),

                    // Mentions
                    ...mentions.map((mention) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '@$mention',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )),
                  ],
                ),
              ],
            ] else ...[
              // Empty state - properly centered with minimum height
              Container(
                constraints: const BoxConstraints(minHeight: 80),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit_note,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your post content will appear here',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Use the microphone to dictate or the pencil to type',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
