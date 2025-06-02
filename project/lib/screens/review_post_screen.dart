import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/social_action.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/social_post_service.dart';
import '../screens/history_screen.dart';

class ReviewPostScreen extends StatefulWidget {
  final SocialAction action;

  const ReviewPostScreen({
    super.key,
    required this.action,
  });

  @override
  State<ReviewPostScreen> createState() => _ReviewPostScreenState();
}

class _ReviewPostScreenState extends State<ReviewPostScreen> {
  late SocialAction _action;
  bool _isPosting = false;
  Map<String, bool> _postResults = {};
  final TextEditingController _captionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _action = widget.action;
    _captionController.text = _action.content.text;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _editCaption() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Caption'),
        content: TextField(
          controller: _captionController,
          decoration: const InputDecoration(
            hintText: 'Enter your caption',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _captionController.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (result != null) {
      // Update the action with the new caption
      final updatedAction = SocialAction(
        action_id: _action.action_id,
        created_at: _action.created_at,
        platforms: _action.platforms,
        content: Content(
          text: result,
          hashtags: _action.content.hashtags,
          mentions: _action.content.mentions,
          link: _action.content.link,
          media: _action.content.media,
        ),
        options: _action.options,
        platform_data: _action.platform_data,
        internal: _action.internal,
      );

      // Save the updated action to Firestore
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      await firestoreService.updateAction(
        updatedAction.action_id,
        updatedAction.toJson(),
      );

      setState(() {
        _action = updatedAction;
        _captionController.text = result;
      });
    }
  }

  Future<void> _editSchedule() async {
    final now = DateTime.now();
    final initialDate = _action.options.schedule == 'now'
        ? now
        : DateTime.parse(_action.options.schedule);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );

      if (pickedTime != null) {
        final scheduledDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        // Update the action with the new schedule
        final updatedAction = SocialAction(
          action_id: _action.action_id,
          created_at: _action.created_at,
          platforms: _action.platforms,
          content: _action.content,
          options: Options(
            schedule: scheduledDateTime.toIso8601String(),
            locationTag: _action.options.locationTag,
            visibility: _action.options.visibility,
            replyToPostId: _action.options.replyToPostId,
          ),
          platform_data: _action.platform_data,
          internal: _action.internal,
        );

        // Save the updated action to Firestore
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        await firestoreService.updateAction(
          updatedAction.action_id,
          updatedAction.toJson(),
        );

        setState(() {
          _action = updatedAction;
        });
      }
    }
  }

  Future<void> _confirmAndPost() async {
    setState(() {
      _isPosting = true;
      _postResults = {};
    });

    try {
      final socialPostService = Provider.of<SocialPostService>(context, listen: false);
      final results = await socialPostService.postToAllPlatforms(_action);
      
      setState(() {
        _postResults = results;
        _isPosting = false;
      });

      // Show results dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Posting Results'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final platform in _postResults.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        _postResults[platform]! ? Icons.check_circle : Icons.error,
                        color: _postResults[platform]!
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        platform.substring(0, 1).toUpperCase() + platform.substring(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _postResults[platform]! ? 'Posted' : 'Failed',
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (_postResults.values.every((success) => success)) {
                  // All posts succeeded, navigate to history screen
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HistoryScreen(),
                    ),
                    (route) => route.isFirst,
                  );
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _isPosting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Posting failed: $e')),
      );
    }
  }

  Future<void> _cancelPost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Post?'),
        content: const Text('Are you sure you want to discard this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Delete the action from Firestore
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      await firestoreService.deleteAction(_action.action_id);
      
      // Pop back to the command screen
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Your Post'),
      ),
      body: _isPosting
          ? _buildLoadingView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Platform list
                  _buildPlatformList(),
                  const SizedBox(height: 24),
                  
                  // Caption
                  _buildCaptionSection(),
                  const SizedBox(height: 24),
                  
                  // Media preview
                  if (_action.content.media.isNotEmpty)
                    _buildMediaPreview(),
                  const SizedBox(height: 24),
                  
                  // Schedule
                  _buildScheduleSection(),
                  const SizedBox(height: 32),
                  
                  // Action buttons
                  _buildActionButtons(),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Posting to your social networks...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we process your request',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Posting to:',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Consumer<AuthService>(
          builder: (context, authService, _) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _action.platforms.map((platform) {
                return FutureBuilder<bool>(
                  future: authService.isPlatformConnected(platform),
                  builder: (context, snapshot) {
                    final isConnected = snapshot.data ?? false;
                    
                    return Chip(
                      avatar: _getPlatformIcon(platform),
                      label: Text(
                        platform.substring(0, 1).toUpperCase() + platform.substring(1),
                      ),
                      backgroundColor: isConnected
                          ? _getPlatformColor(platform).withOpacity(0.2)
                          : Theme.of(context).colorScheme.surfaceVariant,
                      side: BorderSide(
                        color: isConnected
                            ? _getPlatformColor(platform)
                            : Theme.of(context).colorScheme.outline,
                      ),
                      deleteIcon: isConnected
                          ? null
                          : const Icon(Icons.link_off, size: 16),
                      onDeleted: isConnected
                          ? null
                          : () {
                              // Show connect dialog
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Please connect to $platform first'),
                                  action: SnackBarAction(
                                    label: 'CONNECT',
                                    onPressed: () async {
                                      try {
                                        switch (platform) {
                                          case 'facebook':
                                            await authService.signInWithFacebook();
                                            break;
                                          case 'twitter':
                                            await authService.signInWithTwitter();
                                            break;
                                          case 'tiktok':
                                            await authService.signInWithTikTok();
                                            break;
                                        }
                                        // Refresh the UI
                                        setState(() {});
                                      } catch (e) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to connect: $e')),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCaptionSection() {
    final caption = _action.content.text;
    final hashtags = _action.content.hashtags;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Caption',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editCaption,
              tooltip: 'Edit caption',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(caption),
              if (hashtags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: hashtags.map((tag) {
                    return Chip(
                      label: Text(
                        '#$tag',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaPreview() {
    final mediaItem = _action.content.media.first;
    final isVideo = mediaItem.mimeType.startsWith('video/');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Media',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(Uri.parse(mediaItem.fileUri).path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: 300,
          ),
        ),
        const SizedBox(height: 8),
        // Media metadata
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetadataRow(
                Icons.calendar_today,
                'Created: ${_formatDate(mediaItem.deviceMetadata.creationTime)}',
              ),
              if (mediaItem.deviceMetadata.latitude != null && 
                  mediaItem.deviceMetadata.longitude != null)
                _buildMetadataRow(
                  Icons.location_on,
                  'Location: ${mediaItem.deviceMetadata.latitude!.toStringAsFixed(4)}, ${mediaItem.deviceMetadata.longitude!.toStringAsFixed(4)}',
                ),
              _buildMetadataRow(
                Icons.aspect_ratio,
                'Dimensions: ${mediaItem.deviceMetadata.width} × ${mediaItem.deviceMetadata.height}',
              ),
              if (isVideo)
                _buildMetadataRow(
                  Icons.videocam,
                  'Video',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleSection() {
    final isNow = _action.options.schedule == 'now';
    final scheduleText = isNow
        ? 'Posting immediately'
        : 'Scheduled for ${_formatDateTime(DateTime.parse(_action.options.schedule))}';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schedule',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              isNow ? Icons.send : Icons.schedule,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              scheduleText,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Spacer(),
            TextButton(
              onPressed: _editSchedule,
              child: const Text('Change'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Confirm & Post'),
            onPressed: _confirmAndPost,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.photo_library),
            label: const Text('Edit Media'),
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text('Cancel Post'),
            onPressed: _cancelPost,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _getPlatformIcon(String platform) {
    IconData icon;
    switch (platform) {
      case 'facebook':
        icon = Icons.facebook;
        break;
      case 'instagram':
        icon = Icons.camera_alt;
        break;
      case 'twitter':
        icon = Icons.flutter_dash;
        break;
      case 'tiktok':
        icon = Icons.music_note;
        break;
      default:
        icon = Icons.public;
    }
    
    return Icon(
      icon,
      size: 16,
      color: _getPlatformColor(platform),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'facebook':
        return Colors.blue.shade800;
      case 'instagram':
        return Colors.pink.shade400;
      case 'twitter':
        return Colors.lightBlue.shade400;
      case 'tiktok':
        return Colors.black87;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    final formatter = DateFormat('MMM d, yyyy');
    return formatter.format(date);
  }

  String _formatDateTime(DateTime dateTime) {
    final formatter = DateFormat('MMM d, yyyy \'at\' h:mm a');
    return formatter.format(dateTime);
  }
}