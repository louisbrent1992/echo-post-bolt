import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants/typography.dart';
import '../services/social_action_post_coordinator.dart';

/// Pure presentation widget for post content - no internal state management
/// All state comes directly from coordinator
class PostContentBox extends StatelessWidget {
  final VoidCallback? onEditText;
  final VoidCallback? onVoiceEdit;
  final VoidCallback? onEditSchedule;
  final Function(List<String>)? onEditHashtags;

  const PostContentBox({
    super.key,
    this.onEditText,
    this.onVoiceEdit,
    this.onEditSchedule,
    this.onEditHashtags,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialActionPostCoordinator>(
      builder: (context, coordinator, child) {
        final action = coordinator.currentPost;
        final caption = action.content.text;
        final hashtags = action.content.hashtags;
        final isRecording =
            coordinator.isRecording && coordinator.isVoiceDictating;
        final isProcessing = coordinator.isProcessing;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(0),
            ),
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
                      fontSize: AppTypography.large,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Voice dictation button
                  if (onVoiceEdit != null)
                    IconButton(
                      onPressed: onVoiceEdit,
                      icon: Icon(
                        coordinator.getVoiceDictationIcon(),
                        color: coordinator.getVoiceDictationColor(),
                        size: 18,
                      ),
                      tooltip:
                          isRecording ? 'Stop recording' : 'Voice dictation',
                    ),
                  // Text edit button
                  if (onEditText != null)
                    IconButton(
                      onPressed:
                          (isRecording || isProcessing) ? null : onEditText,
                      icon: Icon(
                        Icons.edit,
                        color: Colors.white.withValues(
                            alpha: isRecording || isProcessing ? 0.3 : 0.7),
                        size: 18,
                      ),
                      tooltip: 'Edit post text',
                    ),
                  // Schedule button (THIRD)
                  if (onEditSchedule != null)
                    IconButton(
                      onPressed: onEditSchedule,
                      icon: Icon(
                        Icons.schedule,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 18,
                      ),
                      tooltip: 'Schedule post',
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
                      fontSize:
                          AppTypography.body, // Body font for main content
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
                      fontSize:
                          AppTypography.body, // Body font for placeholder text
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Unified hashtag section
              _buildUnifiedHashtagsSection(context, hashtags),

              // Schedule section
              const SizedBox(height: 16),
              _buildScheduleSection(context),
            ],
          ),
        );
      },
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
                fontSize: AppTypography.small, // Small font for label
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${hashtags.length})',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: AppTypography.small, // Small font for count
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
                            fontSize: AppTypography
                                .small, // Small font for hashtag chips
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
                fontSize: AppTypography.small, // Small font for helper text
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
                fontSize: AppTypography.small, // Small font for helper text
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScheduleSection(BuildContext context) {
    return Consumer<SocialActionPostCoordinator>(
      builder: (context, coordinator, child) {
        final schedule = coordinator.currentPost.options.schedule;
        final isScheduled = schedule != 'now';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Schedule',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: AppTypography.small,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (onEditSchedule != null)
                  IconButton(
                    onPressed: onEditSchedule,
                    icon: Icon(
                      Icons.edit,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 16,
                    ),
                    tooltip: 'Edit schedule',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isScheduled ? Icons.access_time : Icons.flash_on,
                    color: isScheduled
                        ? Colors.orange.withValues(alpha: 0.8)
                        : const Color(0xFFFF0080).withValues(alpha: 0.8),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isScheduled
                          ? 'Scheduled for ${DateFormat('MMM d, yyyy \'at\' h:mm a').format(DateTime.parse(schedule))}'
                          : 'Post immediately when confirmed',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: AppTypography.small,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
