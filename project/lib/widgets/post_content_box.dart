import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants/typography.dart';
import '../services/social_action_post_coordinator.dart';
import '../services/auth_service.dart';
import '../models/social_action.dart';

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
            borderRadius: BorderRadius.circular(12),
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
                  // Text edit button
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

              // Add this after the header row, before post text content
              if (action.platforms.contains('facebook'))
                FacebookAccountSelector(
                  facebookData: action.platformData.facebook ?? FacebookData(),
                  onChanged: (
                      {required bool postAsPage,
                      required String pageId,
                      required String pageName}) {
                    final coordinator =
                        Provider.of<SocialActionPostCoordinator>(context,
                            listen: false);
                    final current = coordinator.currentPost;
                    // Construct new FacebookData
                    final newFacebookData = FacebookData(
                      postAsPage: postAsPage,
                      pageId: pageId,
                      postType: current.platformData.facebook?.postType,
                      mediaFileUri: current.platformData.facebook?.mediaFileUri,
                      videoFileUri: current.platformData.facebook?.videoFileUri,
                      audioFileUri: current.platformData.facebook?.audioFileUri,
                      thumbnailUri: current.platformData.facebook?.thumbnailUri,
                      scheduledTime:
                          current.platformData.facebook?.scheduledTime,
                      additionalFields:
                          current.platformData.facebook?.additionalFields,
                    );
                    // Construct new PlatformData
                    final newPlatformData = PlatformData(
                      facebook: newFacebookData,
                      instagram: current.platformData.instagram,
                      youtube: current.platformData.youtube,
                      twitter: current.platformData.twitter,
                      tiktok: current.platformData.tiktok,
                    );
                    // Use a public method to update the current post's platformData
                    coordinator.updatePlatformData(newPlatformData);
                  },
                ),

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
                        : const Color(0xFFFF0055).withValues(alpha: 0.8),
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

class FacebookAccountSelector extends StatefulWidget {
  final FacebookData facebookData;
  final void Function(
      {required bool postAsPage,
      required String pageId,
      required String pageName}) onChanged;
  const FacebookAccountSelector(
      {super.key, required this.facebookData, required this.onChanged});

  @override
  State<FacebookAccountSelector> createState() =>
      _FacebookAccountSelectorState();
}

class _FacebookAccountSelectorState extends State<FacebookAccountSelector> {
  late Future<Map<String, dynamic>> _optionsFuture;
  String? _selectedId;
  String? _selectedName;
  bool _isPage = false;

  @override
  void initState() {
    super.initState();
    _optionsFuture = Provider.of<AuthService>(context, listen: false)
        .getFacebookPostingOptions();
    _selectedId =
        widget.facebookData.postAsPage ? widget.facebookData.pageId : 'me';
    _isPage = widget.facebookData.postAsPage;
    _selectedName = null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _optionsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        final options = snapshot.data!;
        final pages = options['pages'] as List<dynamic>;
        final timeline = options['user_timeline'] as Map<String, dynamic>;
        final items = [
          DropdownMenuItem<String>(
            value: 'me',
            child: Text('My Timeline'),
          ),
          ...pages
              .map<DropdownMenuItem<String>>((page) => DropdownMenuItem<String>(
                    value: page['id'],
                    child: Text(page['name']),
                  )),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Post as:',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            DropdownButton<String>(
              value: _selectedId ?? 'me',
              items: items,
              onChanged: (value) {
                setState(() {
                  _selectedId = value;
                  if (value == 'me') {
                    _isPage = false;
                    _selectedName = timeline['name'];
                  } else {
                    _isPage = true;
                    _selectedName =
                        pages.firstWhere((p) => p['id'] == value)['name'];
                  }
                });
                widget.onChanged(
                  postAsPage: _isPage,
                  pageId: _selectedId ?? '',
                  pageName: _selectedName ?? '',
                );
              },
              dropdownColor: Colors.black,
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: Colors.white,
            ),
            if (_isPage && _selectedName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Automated posting as: $_selectedName',
                    style: const TextStyle(
                        color: Colors.greenAccent, fontSize: 12)),
              ),
            if (!_isPage)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Manual sharing to your timeline',
                    style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
              ),
          ],
        );
      },
    );
  }
}
