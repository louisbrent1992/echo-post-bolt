import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/social_action.dart';
import '../services/firestore_service.dart';
import '../services/social_post_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post History'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getActionsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No posts yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your post history will appear here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final actionJson = data['action_json'] as Map<String, dynamic>;
              final status = data['status'] as String;
              final createdAt = data['created_at'] as Timestamp?;

              try {
                final action = SocialAction.fromJson(actionJson);
                return _buildHistoryItem(
                  context,
                  action,
                  status,
                  createdAt?.toDate(),
                  data['error_log'] as List<dynamic>?,
                );
              } catch (e) {
                return ListTile(
                  title: Text('Error parsing action: $e'),
                  subtitle: Text('Action ID: ${doc.id}'),
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    SocialAction action,
    String status,
    DateTime? createdAt,
    List<dynamic>? errorLog,
  ) {
    final hasMedia = action.content.media.isNotEmpty;
    final statusColor = _getStatusColor(context, status);
    final formattedDate = createdAt != null
        ? DateFormat('MMM d, yyyy \'at\' h:mm a').format(createdAt)
        : 'Unknown date';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showActionDetails(context, action, status, errorLog),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status and date
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(status),
                          color: statusColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status.substring(0, 1).toUpperCase() +
                              status.substring(1),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formattedDate,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Content preview
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Media thumbnail
                  if (hasMedia)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: _buildMediaThumbnail(action.content.media.first),
                      ),
                    ),
                  const SizedBox(width: 12),

                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.content.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),

                        // Platform icons
                        Wrap(
                          spacing: 8,
                          children: action.platforms.map((platform) {
                            return Icon(
                              _getPlatformIcon(platform),
                              size: 16,
                              color: _getPlatformColor(platform),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Error indicator
              if (status == 'failed' && errorLog != null && errorLog.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Error: ${errorLog.last['message']}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaThumbnail(MediaItem mediaItem) {
    try {
      final file = File(Uri.parse(mediaItem.fileUri).path);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image),
          );
        },
      );
    } catch (e) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image),
      );
    }
  }

  void _showActionDetails(
    BuildContext context,
    SocialAction action,
    String status,
    List<dynamic>? errorLog,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    'Post Details',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Status
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              _getStatusColor(context, status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getStatusIcon(status),
                              color: _getStatusColor(context, status),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              status.substring(0, 1).toUpperCase() +
                                  status.substring(1),
                              style: TextStyle(
                                color: _getStatusColor(context, status),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Media preview
                  if (action.content.media.isNotEmpty) ...[
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
                        File(
                            Uri.parse(action.content.media.first.fileUri).path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 200,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: 200,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 48),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Caption
                  Text(
                    'Caption',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(action.content.text),
                        if (action.content.hashtags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            children: action.content.hashtags.map((tag) {
                              return Chip(
                                label: Text(
                                  '#$tag',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.1),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Platforms
                  Text(
                    'Platforms',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: action.platforms.map((platform) {
                      return Chip(
                        avatar: Icon(
                          _getPlatformIcon(platform),
                          size: 16,
                          color: _getPlatformColor(platform),
                        ),
                        label: Text(
                          platform.substring(0, 1).toUpperCase() +
                              platform.substring(1),
                        ),
                        backgroundColor:
                            _getPlatformColor(platform).withOpacity(0.1),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Error log
                  if (status == 'failed' &&
                      errorLog != null &&
                      errorLog.isNotEmpty) ...[
                    Text(
                      'Error Log',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: errorLog.map((error) {
                          final timestamp = error['timestamp'] as Timestamp?;
                          final message = error['message'] as String?;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (timestamp != null)
                                  Text(
                                    DateFormat('MMM d, yyyy \'at\' h:mm a')
                                        .format(timestamp.toDate()),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer
                                          .withOpacity(0.7),
                                    ),
                                  ),
                                if (message != null)
                                  Text(
                                    message,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Action buttons
                  if (status == 'failed') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Post'),
                        onPressed: () => _retryPost(context, action),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                  if (status == 'pending') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: const Text('Reschedule'),
                        onPressed: () => _reschedulePost(context, action),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      onPressed: () => _deletePost(context, action),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _retryPost(BuildContext context, SocialAction action) async {
    Navigator.pop(context); // Close the bottom sheet

    final socialPostService =
        Provider.of<SocialPostService>(context, listen: false);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retrying post...')),
      );

      final results = await socialPostService.postToAllPlatforms(action);

      final allSucceeded = results.values.every((success) => success);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allSucceeded
                ? 'Post successful! 🎉'
                : 'Some platforms failed. Check history for details.',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry failed: $e')),
      );
    }
  }

  Future<void> _reschedulePost(
      BuildContext context, SocialAction action) async {
    Navigator.pop(context); // Close the bottom sheet

    // Show date picker
    final now = DateTime.now();
    final initialDate = action.options.schedule == 'now'
        ? now
        : DateTime.parse(action.options.schedule);

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
          action_id: action.action_id,
          created_at: action.created_at,
          platforms: action.platforms,
          content: action.content,
          options: Options(
            schedule: scheduledDateTime.toIso8601String(),
            locationTag: action.options.locationTag,
            visibility: action.options.visibility,
            replyToPostId: action.options.replyToPostId,
          ),
          platform_data: action.platform_data,
          internal: action.internal,
        );

        // Save the updated action to Firestore
        final firestoreService =
            Provider.of<FirestoreService>(context, listen: false);
        await firestoreService.updateAction(
          updatedAction.action_id,
          updatedAction.toJson(),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Post rescheduled for ${DateFormat('MMM d, yyyy \'at\' h:mm a').format(scheduledDateTime)}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deletePost(BuildContext context, SocialAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      Navigator.pop(context); // Close the bottom sheet

      // Delete the action from Firestore
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);
      await firestoreService.deleteAction(action.action_id);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted')),
      );
    }
  }

  Color _getStatusColor(BuildContext context, String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'posted':
        return Colors.green;
      case 'failed':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.primary;
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
        return Colors.blue.shade800;
      case 'instagram':
        return Colors.pink.shade400;
      case 'twitter':
        return Colors.lightBlue.shade400;
      case 'tiktok':
        return Colors.black87;
      default:
        return Colors.grey;
    }
  }
}
