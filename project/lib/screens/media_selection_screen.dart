import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import '../models/social_action.dart';
import '../services/media_coordinator.dart';
import '../services/firestore_service.dart';
import '../screens/directory_selection_screen.dart';
import '../widgets/social_icon.dart';

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
      // CRITICAL: Always refresh media data when screen opens to ensure latest files are shown
      await _mediaCoordinator.refreshMediaData();

      if (kDebugMode) {
        print('🔄 MediaSelectionScreen: Refreshed media data on screen open');
      }

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

      // Check if we have an explicit file URI - but when coming from ReviewPostScreen,
      // we want to show the grid to allow changing media, not just preview existing media
      if (widget.action.content.media.isNotEmpty &&
          widget.action.content.media.first.fileUri.isNotEmpty) {
        final mediaItem = widget.action.content.media.first;
        if (await _mediaCoordinator.validateMediaURI(mediaItem.fileUri)) {
          // Get media candidates from query first (this will now get the latest data)
          final additionalCandidates = await _mediaCoordinator.getMediaForQuery(
            '', // Empty search to get recent media
            dateRange: null,
            mediaTypes: null,
          );

          // Create existing media candidate
          final existingMediaAsCandidate = {
            'id': 'current',
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

          // Deduplicate: check if existing media is already in additional candidates
          final existingUri = mediaItem.fileUri;
          final deduplicatedCandidates = additionalCandidates
              .where((candidate) => candidate['file_uri'] != existingUri)
              .toList();

          setState(() {
            // Add current media as first item, then deduplicated additional candidates
            _mediaCandidates = [
              existingMediaAsCandidate,
              ...deduplicatedCandidates
            ];
            _selectedMedia =
                existingMediaAsCandidate; // Pre-select the current media
            _isLoading = false;
          });

          if (kDebugMode) {
            print(
                '🔍 MediaSelectionScreen: Loaded ${_mediaCandidates.length} candidates (${deduplicatedCandidates.length} additional + 1 existing)');
          }

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
        // No candidates provided, get latest image as fallback (this will now get the latest data)
        final latestImage = await _mediaCoordinator
            .getLatestImageInDirectory(widget.action.mediaQuery?.directoryPath);

        if (latestImage != null) {
          setState(() {
            _mediaCandidates = [latestImage];
            _selectedMedia = null;
            _isLoading = false;
          });
        } else {
          // If no latest image found, apply filters to search for any media (this will now get the latest data)
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
    if (_searchTerms.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _mediaCoordinator.getMediaForQuery(
        _searchTerms.join(' '),
        dateRange: _dateRange,
        mediaTypes: _mediaType != null ? [_mediaType!] : null,
      );

      setState(() {
        _mediaCandidates = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
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

      // Only save to Firestore if this is NOT a temporary action (pre-selection)
      final isTemporaryAction = widget.action.actionId.startsWith('temp_');
      if (!isTemporaryAction) {
        // Save the updated action to Firestore for real actions
        final firestoreService =
            Provider.of<FirestoreService>(context, listen: false);
        await firestoreService.updateAction(
          updatedAction.actionId,
          updatedAction.toJson(),
        );

        if (kDebugMode) {
          print(
              '💾 Updated action saved to Firestore: ${updatedAction.actionId}');
        }
      } else {
        if (kDebugMode) {
          print(
              '🔄 Skipping Firestore update for temporary action: ${updatedAction.actionId}');
        }
      }

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

  /// Refreshes the media list by rescanning directories
  Future<void> _refreshMedia() async {
    try {
      if (kDebugMode) {
        print('🔄 MediaSelectionScreen: User triggered refresh');
      }

      // Force refresh the media data
      await _mediaCoordinator.refreshMediaData();

      // Re-apply current filters to get the latest data
      await _applyFilters();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Media refreshed! 🔄'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaSelectionScreen: Refresh failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh media: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.transparent, // Make scaffold transparent for gradient
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: TitleHeader(
          title: 'Select Media',
          leftAction: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          rightAction: IconButton(
            icon: Icon(
              _showFilters ? Icons.filter_list_off : Icons.filter_list,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Color(0xFF1A1A1A),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF0080)))
              : RefreshIndicator(
                  onRefresh: _refreshMedia,
                  color: const Color(0xFFFF0080),
                  backgroundColor: Colors.black,
                  child: Column(
                    children: [
                      // Dynamic query status display (only show if actively searching)
                      if (_searchTerms.isNotEmpty &&
                          _mediaCandidates.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search,
                                  color: Color(0xFFFF0080),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Found ${_mediaCandidates.length} result${_mediaCandidates.length == 1 ? '' : 's'} for "${_searchTerms.join(', ')}"',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
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

                      // Media grid - always show grid when we have candidates
                      Expanded(
                        child: _mediaCandidates.isNotEmpty
                            ? _buildMediaGrid() // Always show grid when we have candidates
                            : _selectedMedia != null
                                ? _buildSingleMediaPreview() // Only show single preview as fallback
                                : SingleChildScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    child: SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                              0.5,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.photo_library_outlined,
                                              size: 64,
                                              color: Colors.white
                                                  .withValues(alpha: 0.6),
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'No media available',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Pull down to refresh or try enabling custom directories',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.7),
                                                fontSize: 14,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                      ),

                      // Confirm button
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _selectedMedia != null
                                  ? _confirmSelection
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF0080),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Confirm Selection',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSourceIndicator() {
    final isCustomEnabled = _mediaCoordinator.isCustomDirectoriesEnabled;
    final enabledCount = _mediaCoordinator.enabledDirectories.length;

    return GestureDetector(
      onTap: _navigateToDirectorySelection,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCustomEnabled
              ? const Color(0xFFFF0080).withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCustomEnabled
                ? const Color(0xFFFF0080).withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCustomEnabled ? Icons.folder_open : Icons.photo_library,
              size: 16,
              color: isCustomEnabled ? const Color(0xFFFF0080) : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              isCustomEnabled
                  ? 'Searching $enabledCount custom director${enabledCount == 1 ? 'y' : 'ies'}'
                  : 'Searching photo albums',
              style: TextStyle(
                color: isCustomEnabled ? const Color(0xFFFF0080) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.edit,
              size: 14,
              color: isCustomEnabled ? const Color(0xFFFF0080) : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  /// Navigate to directory selection screen and refresh media when returning
  Future<void> _navigateToDirectorySelection() async {
    try {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const DirectorySelectionScreen(),
        ),
      );

      // If directories were changed, refresh the media grid
      // Note: result will be true if changes were made, false if no changes, or null if cancelled
      if (result == true) {
        if (kDebugMode) {
          print(
              '🔄 MediaSelectionScreen: Refreshing media after directory changes');
        }

        // Clear current media and reload
        setState(() {
          _isLoading = true;
          _mediaCandidates.clear();
          _selectedMedia = null;
        });

        // Re-initialize the screen with new directory settings
        await _initializeScreen();
      } else {
        if (kDebugMode) {
          print(
              '🔄 MediaSelectionScreen: No directory changes detected, keeping current media');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ MediaSelectionScreen: Error navigating to directory selection: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open directory selection: $e'),
            backgroundColor: Colors.red.withValues(alpha: 0.8),
          ),
        );
      }
    }
  }

  Widget _buildFiltersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field
          Row(
            children: [
              const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFFFF0080),
              ),
              const SizedBox(width: 8),
              const Text(
                'Search:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter search terms...',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF0080)),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    suffixIcon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFF0080),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search,
                                color: Color(0xFFFF0080)),
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
              const Icon(
                Icons.calendar_today,
                size: 18,
                color: Color(0xFFFF0080),
              ),
              const SizedBox(width: 8),
              const Text(
                'Date Range:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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
                  style: const TextStyle(color: Color(0xFFFF0080)),
                ),
              ),
              if (_dateRange != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: Colors.white),
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
              const Icon(
                Icons.perm_media,
                size: 18,
                color: Color(0xFFFF0080),
              ),
              const SizedBox(width: 8),
              const Text(
                'Media Type:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Photos'),
                labelStyle: TextStyle(
                  color: _mediaType == 'photo'
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                ),
                selected: _mediaType == 'photo',
                selectedColor: const Color(0xFFFF0080),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                onSelected: (selected) {
                  setState(() {
                    _mediaType = selected ? 'photo' : null;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Videos'),
                labelStyle: TextStyle(
                  color: _mediaType == 'video'
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                ),
                selected: _mediaType == 'video',
                selectedColor: const Color(0xFFFF0080),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0080),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Apply Filters',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
      children: [
        // Instagram-like post preview with dark theme
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Large media preview taking up majority of space
                Expanded(
                  flex: 3, // Takes up 3/4 of the available space
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(Uri.parse(media['file_uri']).path),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade800,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isVideo
                                          ? Icons.videocam_off
                                          : Icons.broken_image,
                                      color:
                                          Colors.white.withValues(alpha: 0.6),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Failed to load ${isVideo ? 'video' : 'image'}',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.7),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                        // Video play button overlay
                        if (isVideo)
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              color: Colors.white,
                              size: 64,
                              shadows: [
                                Shadow(
                                  blurRadius: 10.0,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Post content area (text and hashtags)
                Expanded(
                  flex: 1, // Takes up 1/4 of the available space
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Post text
                        if (widget.action.content.text.isNotEmpty) ...[
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                widget.action.content.text,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.4,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          if (widget.action.content.hashtags.isNotEmpty)
                            const SizedBox(height: 12),
                        ],

                        // Hashtags
                        if (widget.action.content.hashtags.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: widget.action.content.hashtags.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF0080)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFF0080)
                                        .withValues(alpha: 0.5),
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

                        // If no content, show placeholder
                        if (widget.action.content.text.isEmpty &&
                            widget.action.content.hashtags.isEmpty) ...[
                          Expanded(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit,
                                      color: Colors.orange.shade300,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Add caption on review page',
                                        style: TextStyle(
                                          color: Colors.orange.shade300,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
