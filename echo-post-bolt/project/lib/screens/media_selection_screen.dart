import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import '../models/social_action.dart';
import '../models/media_validation.dart';
import '../services/media_coordinator.dart';
import '../services/permission_manager.dart';
import '../services/video_validation_service.dart';
import '../screens/directory_selection_screen.dart';
import '../widgets/social_icon.dart';
import '../widgets/video_preview_widget.dart';

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

  // Debug message throttling
  static DateTime? _lastInitLog;
  static DateTime? _lastRefreshLog;

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
    _selectedMedia = null;
    _mediaCandidates = [];
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // ALWAYS request media permission when screen loads
      // This ensures permission is re-requested every time if previously denied
      final permissionManager =
          Provider.of<PermissionManager>(context, listen: false);
      final hasPermission = await permissionManager.requestMediaPermission();

      if (!hasPermission) {
        // Check if permanently denied to provide specific guidance
        final isPermanentlyDenied =
            await permissionManager.isMediaPermissionPermanentlyDenied();

        String errorMessage;
        if (isPermanentlyDenied) {
          errorMessage =
              'Media access permanently denied. Please enable it in device settings to view photos and videos.';
        } else {
          errorMessage =
              'Media access is required to view photos and videos. Please allow access to continue.';
        }

        if (kDebugMode) {
          print(
              '❌ Media permission denied on MediaSelectionScreen. Permanently denied: $isPermanentlyDenied');
        }

        setState(() {
          _isLoading = false;
          _mediaCandidates = [];
        });

        if (mounted) {
          if (isPermanentlyDenied) {
            // Show snackbar with settings button for permanently denied
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Media permission required. Enable in device settings.'),
                backgroundColor: Colors.red.withValues(alpha: 0.8),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () async {
                    await permissionManager.openDeviceSettings();
                    // After returning from settings, retry initialization
                    _initializeScreen();
                  },
                ),
              ),
            );
          } else {
            // Show retry option for non-permanently denied
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red.withValues(alpha: 0.8),
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () {
                    _initializeScreen(); // Retry initialization
                  },
                ),
              ),
            );
          }
        }
        return;
      }

      if (kDebugMode) {
        print(
            '✅ Media permission granted on MediaSelectionScreen, proceeding with initialization...');
      }

      final now = DateTime.now();
      final shouldLogInit =
          _lastInitLog == null || now.difference(_lastInitLog!).inMinutes > 5;

      if (kDebugMode && shouldLogInit) {
        print(
            '🔄 MediaSelectionScreen: Starting initialization with directory compliance enforcement');
        _lastInitLog = now;
      }

      // ========== PHASE 3: USE CONSOLIDATED DIRECTORY SCANNING ==========
      // Use MediaCoordinator's unified directory refresh instead of individual refresh calls
      await _mediaCoordinator.refreshDirectoryData(forceFullScan: true);

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
      } else {
        // Clear any existing filters
        setState(() {
          _searchTerms = [];
          _searchController.clear();
          _dateRange = null;
          _mediaType = null;
        });
      }

      // Get fresh media candidates with directory compliance
      List<Map<String, dynamic>> candidates;

      if (widget.action.content.media.isNotEmpty &&
          widget.action.content.media.first.fileUri.isNotEmpty) {
        final mediaItem = widget.action.content.media.first;

        // Validate both URI and directory compliance
        final validationResult =
            await _mediaCoordinator.validateAndRecoverMediaURI(
          mediaItem.fileUri,
          config: MediaValidationConfig.production,
        );

        if (validationResult.isValid) {
          // Get fresh media candidates
          candidates = await _mediaCoordinator.getMediaForQuery(
            '', // Empty search to get recent media
            dateRange: null,
            mediaTypes: null,
          );

          // Create existing media candidate
          final existingMediaAsCandidate = {
            'id': 'current',
            'file_uri': validationResult.effectiveUri,
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

          // Deduplicate candidates
          candidates = [
            existingMediaAsCandidate,
            ...candidates
                .where((c) => c['file_uri'] != validationResult.effectiveUri)
          ];

          _selectedMedia = existingMediaAsCandidate;
        } else {
          candidates = await _mediaCoordinator.getMediaForQuery('');
        }
      } else if (widget.initialCandidates?.isNotEmpty == true) {
        // Handle initial candidates with validation
        candidates = await _validateAndFilterMedia(widget.initialCandidates!);
      } else {
        // Get fresh candidates
        candidates = await _mediaCoordinator.getMediaForQuery('');
      }

      // Final validation pass
      final validatedCandidates = await _validateAndFilterMedia(candidates);

      setState(() {
        _mediaCandidates = validatedCandidates;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaSelectionScreen: Initialization failed: $e');
      }
      setState(() {
        _isLoading = false;
        _mediaCandidates = [];
      });
    }
  }

  /// Centralized media refresh function used by both initialization and pull-to-refresh
  Future<void> _refreshMediaData({bool showFeedback = true}) async {
    try {
      // Only log refresh details occasionally to prevent spam
      final now = DateTime.now();
      final shouldLogRefresh = _lastRefreshLog == null ||
          now.difference(_lastRefreshLog!).inMinutes > 2;

      if (kDebugMode && shouldLogRefresh) {
        print('🔄 MediaSelectionScreen: Starting media refresh...');
        _lastRefreshLog = now;
      }

      // Show immediate feedback if requested
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Refreshing media cache...'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFFFF0055),
          ),
        );
      }

      // ========== PHASE 3: USE CONSOLIDATED REFRESH SYSTEM ==========
      // Use MediaCoordinator's unified refresh instead of individual service calls
      await _mediaCoordinator.refreshMediaData(forceFullScan: true);

      // Re-apply current filters to get the latest data with fresh cache
      await _applyFilters();

      if (kDebugMode && shouldLogRefresh) {
        print('✅ MediaSelectionScreen: Media refresh completed successfully');
        print('   New media count: ${_mediaCandidates.length}');
      }

      // Show success feedback if requested
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Media refreshed! Found ${_mediaCandidates.length} items'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaSelectionScreen: Media refresh failed: $e');
      }

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to refresh: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () => _refreshMediaData(showFeedback: true),
            ),
          ),
        );
      }
    }
  }

  Future<void> _refreshMedia() async {
    await _refreshMediaData(showFeedback: true);
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

      // Proactively validate and filter out broken media
      final validatedCandidates = await _validateAndFilterMedia(candidates);

      setState(() {
        _mediaCandidates = validatedCandidates;
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

  /// Proactively validate media and exclude broken references
  Future<List<Map<String, dynamic>>> _validateAndFilterMedia(
    List<Map<String, dynamic>> candidates,
  ) async {
    if (candidates.isEmpty) return candidates;

    // ========== PHASE 3: USE UNIFIED VALIDATION SYSTEM ==========
    // Use MediaCoordinator's consolidated validation instead of manual validation
    return await _mediaCoordinator.validateAndFilterMediaCandidates(
      candidates,
      showProgress: false,
    );
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

      // Validate and filter results before displaying
      final validatedResults = await _validateAndFilterMedia(results);

      setState(() {
        _mediaCandidates = validatedResults;
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
          duration: (deviceMetadata['duration'] as num?)?.toDouble(),
          bitrate: (deviceMetadata['bitrate'] as num?)?.toInt(),
          samplingRate: (deviceMetadata['sampling_rate'] as num?)?.toInt(),
          frameRate: deviceMetadata['frame_rate']?.toDouble(),
        ),
      );

      // Update the action with the new media item
      final updatedAction = widget.action.copyWith(
        content: widget.action.content.copyWith(
          media: [mediaItem],
        ),
      );

      if (kDebugMode) {
        print('✅ Media selection confirmed:');
        print('   File URI: ${mediaItem.fileUri}');
        print('   MIME type: ${mediaItem.mimeType}');
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
          SnackBar(content: Text('Failed to update action: $e')),
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
        child: SafeArea(
          bottom: false,
          child: TitleHeader(
            title: 'Select Media',
            leftAction: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
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
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.black, // Set to solid color
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF0055)))
              : RefreshIndicator(
                  onRefresh: _refreshMedia,
                  color: const Color(0xFFFF0055),
                  backgroundColor: Colors.black,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // Dynamic query status display (only show if actively searching)
                      if (_searchTerms.isNotEmpty &&
                          _mediaCandidates.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
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
                                    color: Color(0xFFFF0055),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Found \\${_mediaCandidates.length} result\\${_mediaCandidates.length == 1 ? '' : 's'} for "\\${_searchTerms.join(', ')}"',
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
                        ),

                      // Source indicator
                      SliverToBoxAdapter(child: _buildSourceIndicator()),

                      // Filters section (collapsible)
                      if (_showFilters)
                        SliverToBoxAdapter(child: _buildFiltersSection()),

                      // Media grid or empty state
                      _mediaCandidates.isNotEmpty
                          ? _buildMediaGridSliver()
                          : _selectedMedia != null
                              ? SliverToBoxAdapter(
                                  child: _buildSingleMediaPreview())
                              : SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.search_off,
                                          size: 64,
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'No media found',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Try adjusting your search or filters',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.7),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                      // Confirm button - fixed at bottom
                      SliverToBoxAdapter(
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _selectedMedia != null
                                    ? _confirmSelection
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF0055),
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
              ? const Color(0xFFFF0055).withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCustomEnabled
                ? const Color(0xFFFF0055).withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCustomEnabled ? Icons.folder_open : Icons.photo_library,
              size: 16,
              color: isCustomEnabled ? const Color(0xFFFF0055) : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              isCustomEnabled
                  ? 'Searching $enabledCount custom director${enabledCount == 1 ? 'y' : 'ies'}'
                  : 'Searching photo albums',
              style: TextStyle(
                color: isCustomEnabled ? const Color(0xFFFF0055) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.edit,
              size: 14,
              color: isCustomEnabled ? const Color(0xFFFF0055) : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  /// Navigate to directory selection screen and refresh media when returning
  Future<void> _navigateToDirectorySelection() async {
    try {
      if (kDebugMode) {
        print('🔄 MediaSelectionScreen: Navigating to directory selection...');
      }

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const DirectorySelectionScreen(),
        ),
      );

      if (kDebugMode) {
        print(
            '🔄 MediaSelectionScreen: Returned from directory selection with result: $result');
      }

      // If directories were changed, refresh the media grid
      // Note: result will be true if changes were made, false if no changes, or null if cancelled
      if (result == true) {
        if (kDebugMode) {
          print(
              '🔄 MediaSelectionScreen: Directory changes detected - refreshing media automatically');
        }

        // Show immediate feedback to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Directory settings updated - refreshing media...'),
                ],
              ),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFFFF0055),
            ),
          );
        }

        // Clear current media and reload with full refresh
        setState(() {
          _isLoading = true;
          _mediaCandidates.clear();
          _selectedMedia = null;
        });

        // Re-initialize with full refresh
        await _refreshMediaData(showFeedback: true);
      } else {
        if (kDebugMode) {
          print(
              '🔄 MediaSelectionScreen: No directory changes detected (result: $result) - keeping current media');
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
                color: Color(0xFFFF0055),
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
                      borderSide: const BorderSide(color: Color(0xFFFF0055)),
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
                              color: Color(0xFFFF0055),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search,
                                color: Color(0xFFFF0055)),
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
                color: Color(0xFFFF0055),
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
                  style: const TextStyle(color: Color(0xFFFF0055)),
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
                color: Color(0xFFFF0055),
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
                selectedColor: const Color(0xFFFF0055),
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
                selectedColor: const Color(0xFFFF0055),
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
                backgroundColor: const Color(0xFFFF0055),
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
              // Remove borderRadius to make corners square
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
                    // Remove borderRadius to make corners square
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
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getFormatDisplayName(
                              media['mime_type'] ?? 'image/jpeg'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDate(media['device_metadata']?['creation_time']
                              as String?),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                          ),
                        ),
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

  Widget _buildMediaGridSliver() {
    if (_mediaCandidates.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              const Text(
                'No media found',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your search or filters',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.zero, // Remove padding
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // Changed to 2 columns for better video preview
          crossAxisSpacing: 0, // Remove spacing
          mainAxisSpacing: 0, // Remove spacing
          childAspectRatio: 0.8, // Adjusted for video info display
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final media = _mediaCandidates[index];
            final isSelected =
                _selectedMedia != null && _selectedMedia!['id'] == media['id'];
            final isVideo = media['mime_type'].toString().startsWith('video/');

            if (isVideo) {
              // Use enhanced video preview widget for videos
              return VideoPreviewWidget(
                mediaItem: media,
                selectedPlatforms: widget.action.platforms,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedMedia = media;
                  });

                  // Show video compatibility info if there are platform warnings
                  if (widget.action.platforms.isNotEmpty) {
                    _showVideoCompatibilityInfo(media);
                  }
                },
              );
            } else {
              // Use existing image preview for images
              return _buildImagePreview(media, isSelected);
            }
          },
          childCount: _mediaCandidates.length,
        ),
      ),
    );
  }

  /// Enhanced image preview widget with real-time validation
  Widget _buildImagePreview(Map<String, dynamic> media, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMedia = media;
        });
      },
      child: Container(
        decoration: BoxDecoration(
            // Remove border to make it sleeker
            ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Enhanced image thumbnail with validation
            ClipRRect(
              // Remove borderRadius to make corners square
              child: FutureBuilder<MediaValidationResult>(
                future: _mediaCoordinator.validateAndRecoverMediaURI(
                  media['file_uri'] as String,
                  config: MediaValidationConfig.production,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (!snapshot.hasData || !snapshot.data!.isValid) {
                    return const Center(
                      child: Icon(Icons.error, color: Colors.red),
                    );
                  }

                  return Image.file(
                    File(Uri.parse(snapshot.data!.effectiveUri).path),
                    fit: BoxFit.cover,
                  );
                },
              ),
            ),

            // Selection indicator
            if (isSelected)
              const Positioned(
                top: 8,
                left: 8,
                child: Icon(
                  Icons.check_circle,
                  color: Color(0xFFFF0055),
                  size: 24,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Shows video compatibility information for selected platforms
  Future<void> _showVideoCompatibilityInfo(Map<String, dynamic> media) async {
    if (widget.action.platforms.isEmpty) return;

    try {
      final fileUri = media['file_uri'] as String;
      final filePath = Uri.parse(fileUri).path;

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
          ),
        ),
      );

      final validationResult =
          await VideoValidationService.validateVideoForPlatforms(
        filePath,
        widget.action.platforms,
        strictMode: false,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        // Only show dialog if there are warnings or errors
        if (validationResult.errors.isNotEmpty ||
            validationResult.warnings.isNotEmpty) {
          showDialog(
            context: context,
            builder: (context) => VideoCompatibilityDialog(
              validationResult: validationResult,
              platforms: widget.action.platforms,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to validate video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }

  String _getFormatDisplayName(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/jpeg':
        return 'JPEG';
      case 'image/png':
        return 'PNG';
      case 'image/gif':
        return 'GIF';
      case 'image/webp':
        return 'WebP';
      case 'image/heic':
        return 'HEIC';
      case 'video/mp4':
        return 'MP4';
      case 'video/quicktime':
        return 'MOV';
      case 'video/x-msvideo':
        return 'AVI';
      case 'video/x-matroska':
        return 'MKV';
      case 'video/webm':
        return 'WebM';
      default:
        return mimeType.split('/').last.toUpperCase();
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) {
      return 'Unknown';
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
        return '${difference.inDays}d ago';
      } else if (difference.inDays < 30) {
        return '${(difference.inDays / 7).round()}w ago';
      } else {
        return '${date.month}/${date.day}/${date.year.toString().substring(2)}';
      }
    } catch (e) {
      return 'Invalid';
    }
  }
}
