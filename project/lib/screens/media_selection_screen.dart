import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/social_action.dart';
import '../services/media_coordinator.dart';
import '../services/firestore_service.dart';

class MediaSelectionScreen extends StatefulWidget {
  final SocialAction action;
  final List<Map<String, dynamic>>? initialCandidates;

  const MediaSelectionScreen({
    super.key,
    required this.action,
    this.initialCandidates,
  });

  @override
  State<MediaSelectionScreen> createState() => _MediaSelectionScreenState();
}

class _MediaSelectionScreenState extends State<MediaSelectionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mediaCandidates = [];
  Map<String, dynamic>? _selectedMedia;
  late final MediaCoordinator _mediaCoordinator;
  bool _showFilters = false;

  // Filter state
  DateTimeRange? _dateRange;
  String? _mediaType;
  List<String> _searchTerms = [];

  // Search functionality
  late final TextEditingController _searchController;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _mediaCoordinator = Provider.of<MediaCoordinator>(context, listen: false);
    _searchController = TextEditingController();
    _initializeScreen();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize filters from MediaSearchQuery if available
      if (widget.action.mediaQuery != null) {
        final query = widget.action.mediaQuery!;
        setState(() {
          _searchTerms = query.searchTerms;
          _searchController.text = query.searchTerms.join(' ');
          if (query.dateRange != null) {
            _dateRange = DateTimeRange(
              start: query.dateRange!.startDate ?? DateTime.now(),
              end: query.dateRange!.endDate ?? DateTime.now(),
            );
          }
          if (query.mediaTypes.isNotEmpty) {
            _mediaType = query.mediaTypes.first.toLowerCase();
          }
        });
      }

      // Check if we have an explicit file URI
      if (widget.action.content.media.isNotEmpty &&
          widget.action.content.media.first.fileUri.isNotEmpty) {
        final mediaItem = widget.action.content.media.first;
        if (await _mediaCoordinator.validateMediaURI(mediaItem.fileUri)) {
          setState(() {
            _selectedMedia = {
              'id': 'explicit',
              'file_uri': mediaItem.fileUri,
              'mime_type': mediaItem.mimeType,
              'device_metadata': {
                'creation_time': mediaItem.deviceMetadata.creationTime,
                'latitude': mediaItem.deviceMetadata.latitude,
                'longitude': mediaItem.deviceMetadata.longitude,
                'width': mediaItem.deviceMetadata.width,
                'height': mediaItem.deviceMetadata.height,
                'file_size_bytes': mediaItem.deviceMetadata.fileSizeBytes,
              }
            };
            _isLoading = false;
          });
          return;
        }
      }

      // Use initial candidates if provided, otherwise get latest image as fallback
      if (widget.initialCandidates != null &&
          widget.initialCandidates!.isNotEmpty) {
        setState(() {
          _mediaCandidates = widget.initialCandidates!;
          _selectedMedia = null;
          _isLoading = false;
        });
      } else {
        // No candidates provided, get latest image as fallback
        final latestImage = await _mediaCoordinator
            .getLatestImageInDirectory(widget.action.mediaQuery?.directoryPath);

        if (latestImage != null) {
          setState(() {
            _mediaCandidates = [latestImage];
            _selectedMedia = null;
            _isLoading = false;
          });
        } else {
          // If no latest image found, apply filters to search for any media
          await _applyFilters();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize screen: $e')),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _applyFilters() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final candidates = await _mediaCoordinator.getMediaForQuery(
        _searchTerms.join(' '),
        dateRange: _dateRange,
        mediaTypes: _mediaType != null ? [_mediaType!] : null,
      );

      setState(() {
        _mediaCandidates = candidates;
        _selectedMedia = null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply filters: $e')),
        );
      }
    }
  }

  Future<void> _fetchMedia() async {
    setState(() {
      _isSearching = true;
    });

    try {
      final candidates = await _mediaCoordinator.getMediaForQuery(
        _searchTerms.join(' '),
        dateRange: _dateRange,
        mediaTypes: _mediaType != null ? [_mediaType!] : null,
      );

      setState(() {
        _mediaCandidates = candidates;
        _selectedMedia = null;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to search media: $e')),
        );
      }
    }
  }

  Future<void> _confirmSelection() async {
    if (_selectedMedia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a media item')),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Create a new MediaItem from the selected media
      final deviceMetadata =
          _selectedMedia!['device_metadata'] as Map<String, dynamic>? ?? {};
      final mediaItem = MediaItem(
        fileUri: _selectedMedia!['file_uri'],
        mimeType: _selectedMedia!['mime_type'],
        deviceMetadata: DeviceMetadata(
          creationTime: deviceMetadata['creation_time'] ??
              DateTime.now().toIso8601String(),
          latitude: deviceMetadata['latitude']?.toDouble(),
          longitude: deviceMetadata['longitude']?.toDouble(),
          orientation: (deviceMetadata['orientation'] as num?)?.toInt() ?? 1,
          width: (deviceMetadata['width'] as num?)?.toInt() ?? 0,
          height: (deviceMetadata['height'] as num?)?.toInt() ?? 0,
          fileSizeBytes:
              (deviceMetadata['file_size_bytes'] as num?)?.toInt() ?? 0,
          duration: deviceMetadata['duration']?.toDouble(),
          bitrate: (deviceMetadata['bitrate'] as num?)?.toInt(),
          samplingRate: (deviceMetadata['sampling_rate'] as num?)?.toInt(),
          frameRate: deviceMetadata['frame_rate']?.toDouble(),
        ),
      );

      // Update the action with the new media item
      final updatedAction = SocialAction(
        actionId: widget.action.actionId,
        createdAt: widget.action.createdAt,
        platforms: widget.action.platforms,
        content: Content(
          text: widget.action.content.text,
          hashtags: widget.action.content.hashtags,
          mentions: widget.action.content.mentions,
          link: widget.action.content.link,
          media: [mediaItem],
        ),
        options: widget.action.options,
        platformData: widget.action.platformData,
        internal: widget.action.internal,
        mediaQuery: widget.action.mediaQuery,
      );

      // Save the updated action to Firestore
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);
      await firestoreService.updateAction(
        updatedAction.actionId,
        updatedAction.toJson(),
      );

      // Return the updated action to the previous screen
      if (mounted) {
        Navigator.pop(context, updatedAction);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm selection: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Media'),
        actions: [
          IconButton(
            icon:
                Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Dynamic query status display (only show if actively searching)
                if (_searchTerms.isNotEmpty && _mediaCandidates.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Found ${_mediaCandidates.length} result${_mediaCandidates.length == 1 ? '' : 's'} for "${_searchTerms.join(', ')}"',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Source indicator
                _buildSourceIndicator(),

                // Filters section (collapsible)
                if (_showFilters) _buildFiltersSection(),

                // Single media preview or grid
                Expanded(
                  child: _selectedMedia != null && _mediaCandidates.isEmpty
                      ? _buildSingleMediaPreview()
                      : _buildMediaGrid(),
                ),

                // Confirm button
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _selectedMedia != null ? _confirmSelection : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Confirm Selection'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSourceIndicator() {
    final isCustomEnabled = _mediaCoordinator.isCustomDirectoriesEnabled;
    final enabledCount = _mediaCoordinator.enabledDirectories.length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCustomEnabled
            ? const Color(0xFFFF0080).withAlpha((0.1 * 255).round())
            : Colors.grey.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCustomEnabled
              ? const Color(0xFFFF0080).withAlpha((0.3 * 255).round())
              : Colors.grey.withAlpha((0.3 * 255).round()),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCustomEnabled ? Icons.folder_open : Icons.photo_library,
            size: 16,
            color: isCustomEnabled ? const Color(0xFFFF0080) : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            isCustomEnabled
                ? 'Searching $enabledCount custom directories'
                : 'Searching photo albums',
            style: TextStyle(
              color: isCustomEnabled ? const Color(0xFFFF0080) : Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outline
                .withAlpha((0.1 * 255).round()),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field
          Row(
            children: [
              Icon(
                Icons.search,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Search:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Enter search terms...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    suffixIcon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              setState(() {
                                _searchTerms = _searchController.text
                                    .trim()
                                    .split(' ')
                                    .where((term) => term.isNotEmpty)
                                    .toList();
                              });
                              _fetchMedia();
                            },
                          ),
                  ),
                  onChanged: (text) {
                    setState(() {
                      _searchTerms = text
                          .trim()
                          .split(' ')
                          .where((term) => term.isNotEmpty)
                          .toList();
                    });
                  },
                  onSubmitted: (text) {
                    setState(() {
                      _searchTerms = text
                          .trim()
                          .split(' ')
                          .where((term) => term.isNotEmpty)
                          .toList();
                    });
                    _fetchMedia();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date range filter
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Date Range:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    initialDateRange: _dateRange,
                  );
                  if (picked != null) {
                    setState(() {
                      _dateRange = picked;
                    });
                  }
                },
                child: Text(
                  _dateRange != null
                      ? '${_dateRange!.start.toString().split(' ')[0]} - ${_dateRange!.end.toString().split(' ')[0]}'
                      : 'Select dates',
                ),
              ),
              if (_dateRange != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    setState(() {
                      _dateRange = null;
                    });
                  },
                ),
            ],
          ),

          // Media type filter
          Row(
            children: [
              Icon(
                Icons.perm_media,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Media Type:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Photos'),
                selected: _mediaType == 'photo',
                onSelected: (selected) {
                  setState(() {
                    _mediaType = selected ? 'photo' : null;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Videos'),
                selected: _mediaType == 'video',
                onSelected: (selected) {
                  setState(() {
                    _mediaType = selected ? 'video' : null;
                  });
                },
              ),
            ],
          ),

          // Apply filters button
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _applyFilters,
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleMediaPreview() {
    final media = _selectedMedia!;
    final isVideo = media['mime_type'].toString().startsWith('video/');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Confirm this ${isVideo ? 'video' : 'photo'}?',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(Uri.parse(media['file_uri']).path),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetadataRow(
                Icons.calendar_today,
                'Created: ${_formatDate(media['device_metadata']?['creation_time'] as String?)}',
              ),
              if (media['device_metadata']?['latitude'] != null &&
                  media['device_metadata']?['longitude'] != null)
                _buildMetadataRow(
                  Icons.location_on,
                  'Location: ${media['device_metadata']!['latitude'].toStringAsFixed(4)}, ${media['device_metadata']!['longitude'].toStringAsFixed(4)}',
                ),
              _buildMetadataRow(
                Icons.aspect_ratio,
                'Dimensions: ${media['device_metadata']?['width'] ?? 'Unknown'} × ${media['device_metadata']?['height'] ?? 'Unknown'}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaGrid() {
    if (_mediaCandidates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No media found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _mediaCandidates.length,
      itemBuilder: (context, index) {
        final media = _mediaCandidates[index];
        final isSelected =
            _selectedMedia != null && _selectedMedia!['id'] == media['id'];
        final isVideo = media['mime_type'].toString().startsWith('video/');

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedMedia = media;
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media thumbnail with error handling
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(Uri.parse(media['file_uri']).path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey.shade300,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isVideo ? Icons.videocam_off : Icons.broken_image,
                            color: Colors.grey.shade600,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Failed to load',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Video indicator
              if (isVideo)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha((0.6 * 255).round()),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),

              // Date overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withAlpha((0.7 * 255).round()),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    _formatDate(
                        media['device_metadata']?['creation_time'] as String?),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              // Selection indicator
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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

  String _formatDate(String? isoDate) {
    if (isoDate == null) {
      return 'Unknown date';
    }

    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return 'Invalid date';
    }
  }
}
