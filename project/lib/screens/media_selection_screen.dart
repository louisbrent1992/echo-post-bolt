import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:exif/exif.dart';
import 'package:path/path.dart' as path;

import '../models/social_action.dart';
import '../services/media_search_service.dart' as media_service;
import '../services/firestore_service.dart';
import '../services/directory_service.dart';
import '../services/media_metadata_service.dart';

class MediaSelectionScreen extends StatefulWidget {
  final SocialAction action;
  final List<media_service.LocalMedia>? candidates;

  const MediaSelectionScreen({
    super.key,
    required this.action,
    this.candidates,
  });

  @override
  State<MediaSelectionScreen> createState() => _MediaSelectionScreenState();
}

class _MediaSelectionScreenState extends State<MediaSelectionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mediaCandidates = [];
  Map<String, dynamic>? _selectedMedia;
  String? _mediaQuery;
  bool _showFilters = false;
  DirectoryService? _directory_service;

  // Filter state
  DateTimeRange? _dateRange;
  media_service.MediaType? _mediaType;
  // final double _locationRadius = 10.0; // km

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    setState(() {
      _isLoading = true;
      _mediaQuery = _extractMediaQuery();
    });

    try {
      // Use DirectoryService and MediaMetadataService from Provider
      _directory_service =
          Provider.of<DirectoryService>(context, listen: false);
      final media_metadata_service =
          Provider.of<MediaMetadataService>(context, listen: false);

      await _directory_service!.initialize();
      await media_metadata_service.initialize(_directory_service!);

      // Check if we have an explicit file URI
      if (widget.action.content.media.isNotEmpty &&
          widget.action.content.media.first.fileUri.isNotEmpty) {
        // Show the single media item
        final mediaItem = widget.action.content.media.first;
        setState(() {
          _selectedMedia = {
            'id': 'explicit',
            'file_uri': mediaItem.fileUri,
            'mime_type': mediaItem.mimeType,
            'creation_time': mediaItem.deviceMetadata.creationTime,
            'latitude': mediaItem.deviceMetadata.latitude,
            'longitude': mediaItem.deviceMetadata.longitude,
            'width': mediaItem.deviceMetadata.width,
            'height': mediaItem.deviceMetadata.height,
          };
          _isLoading = false;
        });
        return;
      }

      // Check if custom directories are enabled
      if (_directory_service!.isCustomDirectoriesEnabled) {
        // Use metadata service to find relevant media
        if (_mediaQuery != null && _mediaQuery!.isNotEmpty) {
          // Search for media based on the query
          final query = _mediaQuery!.toLowerCase();
          final List<Map<String, dynamic>> matching_media = [];

          // Search in directories
          for (final directory in _directory_service!.enabledDirectories) {
            final dir_name = directory.displayName.toLowerCase();
            if (dir_name.contains(query)) {
              // Add all media from this directory
              matching_media.addAll(
                  media_metadata_service.get_media_by_folder(directory.path));
            }
          }

          // Search by date if query contains temporal references
          if (query.contains('today') ||
              query.contains('yesterday') ||
              query.contains('last night') ||
              query.contains('this week')) {
            final recent_dates = _get_recent_dates(query);
            for (final date in recent_dates) {
              matching_media
                  .addAll(media_metadata_service.get_media_by_date(date));
            }
          }

          // Search by location if query contains location references
          if (query.contains('beach') ||
              query.contains('park') ||
              query.contains('restaurant') ||
              query.contains('home')) {
            // Add location-based search logic here
            // This would require additional location metadata or reverse geocoding
          }

          setState(() {
            _mediaCandidates = matching_media;
            _isLoading = false;
          });
        } else {
          // No query, show recent media
          setState(() {
            _mediaCandidates = media_metadata_service.get_recent_media();
            _isLoading = false;
          });
        }
      } else {
        // Use existing album-based search
        await _searchPhotoAlbums();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load media: $e')),
        );
      }
    }
  }

  String? _extractMediaQuery() {
    // First try to use the mediaQuery field from the action
    if (widget.action.mediaQuery != null &&
        widget.action.mediaQuery!.isNotEmpty) {
      return widget.action.mediaQuery;
    }

    // Fallback to extracting from the transcription text
    final transcription = widget.action.content.text;
    if (transcription.contains('photo') ||
        transcription.contains('picture') ||
        transcription.contains('image') ||
        transcription.contains('video')) {
      return transcription;
    }

    return null;
  }

  Future<void> _applyFilters() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final mediaSearchService =
          Provider.of<media_service.MediaSearchService>(context, listen: false);

      // Build a query string from the filters
      String query = _mediaQuery ?? '';

      if (_mediaType == media_service.MediaType.photo) {
        query += ' photo';
      } else if (_mediaType == media_service.MediaType.video) {
        query += ' video';
      }

      if (_dateRange != null) {
        // Add date range to query
        query +=
            ' from ${_dateRange!.start.toString().split(' ')[0]} to ${_dateRange!.end.toString().split(' ')[0]}';
      }

      // Find media candidates with the updated query
      final candidates = await mediaSearchService.findCandidates(query);
      final candidateMaps = mediaSearchService.getCandidateMaps(candidates);

      setState(() {
        _mediaCandidates = candidateMaps;
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
          orientation: deviceMetadata['orientation'] ?? 1,
          width: deviceMetadata['width'] ?? 0,
          height: deviceMetadata['height'] ?? 0,
          fileSizeBytes: deviceMetadata['file_size_bytes'] ?? 0,
          duration: deviceMetadata['duration']?.toDouble(),
          bitrate: deviceMetadata['bitrate']?.toInt(),
          samplingRate: deviceMetadata['sampling_rate']?.toInt(),
          frameRate: deviceMetadata['frame_rate']?.toDouble(),
        ),
        caption: null,
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

      // Cache the selection for this query
      if (_mediaQuery != null && _mediaQuery!.isNotEmpty) {
        await firestoreService.cacheMediaSelection(
          _mediaQuery!,
          _selectedMedia!['id'],
        );
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

  Future<void> _searchCustomDirectories() async {
    final enabledDirectories = _directory_service!.enabledDirectories;

    if (enabledDirectories.isEmpty) {
      setState(() {
        _mediaCandidates = [];
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'No directories enabled. Please configure directories in settings.')),
        );
      }
      return;
    }

    final List<Map<String, dynamic>> allMedia = [];

    for (final directory in enabledDirectories) {
      try {
        final mediaFiles = await _scanDirectoryForMedia(directory.path);
        allMedia.addAll(mediaFiles);
      } catch (e) {
        print('Failed to scan directory ${directory.path}: $e');
        // Continue with other directories
      }
    }

    // Filter and sort media
    allMedia.sort((a, b) => (b['creation_time'] as DateTime)
        .compareTo(a['creation_time'] as DateTime));

    setState(() {
      _mediaCandidates = allMedia;
      _isLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _scanDirectoryForMedia(
      String directoryPath) async {
    final List<Map<String, dynamic>> mediaFiles = [];

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return mediaFiles;
      }

      final List<FileSystemEntity> files = directory.listSync(recursive: false);

      for (final file in files) {
        if (file is File) {
          final String extension = path.extension(file.path).toLowerCase();

          // Check if it's a media file
          if (_isMediaFile(extension)) {
            try {
              final mediaData = await _extractMediaMetadata(file);
              if (mediaData != null) {
                mediaFiles.add(mediaData);
              }
            } catch (e) {
              // Skip files that can't be processed
              continue;
            }
          }
        }
      }
    } catch (e) {
      print('Error scanning directory $directoryPath: $e');
    }

    return mediaFiles;
  }

  bool _isMediaFile(String extension) {
    const mediaExtensions = {
      // Images
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic', '.heif',
      // Videos
      '.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp', '.flv'
    };

    return mediaExtensions.contains(extension);
  }

  Future<Map<String, dynamic>?> _extractMediaMetadata(File file) async {
    try {
      final stats = await file.stat();
      final String mimeType =
          _getMimeTypeFromExtension(path.extension(file.path));

      // Basic metadata
      final mediaData = <String, dynamic>{
        'id': path.basename(file.path),
        'file_uri': file.path,
        'mime_type': mimeType,
        'creation_time': stats.modified,
        'file_size_bytes': stats.size,
        'width': 0,
        'height': 0,
        'duration': 0,
      };

      // Try to extract EXIF data for images
      if (mimeType.startsWith('image/')) {
        try {
          final bytes = await file.readAsBytes();
          final exifData = await readExifFromBytes(bytes);

          if (exifData.isNotEmpty) {
            // Extract GPS coordinates
            final gpsLat = exifData['GPS GPSLatitude'];
            final gpsLon = exifData['GPS GPSLongitude'];
            final gpsLatRef = exifData['GPS GPSLatitudeRef'];
            final gpsLonRef = exifData['GPS GPSLongitudeRef'];

            if (gpsLat != null && gpsLon != null) {
              mediaData['latitude'] =
                  _parseGpsCoordinate(gpsLat, gpsLatRef?.toString());
              mediaData['longitude'] =
                  _parseGpsCoordinate(gpsLon, gpsLonRef?.toString());
            }

            // Extract image dimensions
            final width =
                exifData['Image ImageWidth'] ?? exifData['EXIF ExifImageWidth'];
            final height = exifData['Image ImageLength'] ??
                exifData['EXIF ExifImageLength'];

            if (width != null) {
              mediaData['width'] = int.tryParse(width.toString()) ?? 0;
            }
            if (height != null) {
              mediaData['height'] = int.tryParse(height.toString()) ?? 0;
            }

            // Extract creation date from EXIF
            final dateTime =
                exifData['Image DateTime'] ?? exifData['EXIF DateTimeOriginal'];
            if (dateTime != null) {
              final dateString = dateTime.toString();
              // Convert EXIF date format "YYYY:MM:DD HH:MM:SS" to ISO format
              final formattedDate =
                  dateString.substring(0, 10).replaceAll(':', '-') +
                      (dateString.length > 10 ? dateString.substring(10) : '');
              final parsedDate = DateTime.tryParse(formattedDate);
              if (parsedDate != null) {
                mediaData['creation_time'] = parsedDate;
              }
            }
          }
        } catch (e) {
          // EXIF parsing failed, use file stats
        }
      }

      return mediaData;
    } catch (e) {
      return null;
    }
  }

  String _getMimeTypeFromExtension(String extension) {
    const mimeTypes = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.bmp': 'image/bmp',
      '.webp': 'image/webp',
      '.heic': 'image/heic',
      '.heif': 'image/heif',
      '.mp4': 'video/mp4',
      '.mov': 'video/quicktime',
      '.avi': 'video/x-msvideo',
      '.mkv': 'video/x-matroska',
      '.webm': 'video/webm',
      '.m4v': 'video/x-m4v',
      '.3gp': 'video/3gpp',
      '.flv': 'video/x-flv',
    };

    return mimeTypes[extension.toLowerCase()] ?? 'application/octet-stream';
  }

  double? _parseGpsCoordinate(dynamic coordinate, String? reference) {
    // Implementation for parsing GPS coordinates from EXIF data
    try {
      if (coordinate is List && coordinate.length >= 3) {
        final degrees = (coordinate[0] as num).toDouble();
        final minutes = (coordinate[1] as num).toDouble();
        final seconds = (coordinate[2] as num).toDouble();

        double result = degrees + minutes / 60.0 + seconds / 3600.0;

        if (reference == 'S' || reference == 'W') {
          result = -result;
        }

        return result;
      }
    } catch (e) {
      // Parsing failed
    }
    return null;
  }

  Future<void> _searchPhotoAlbums() async {
    // This is the existing album-based search logic
    final mediaSearchService =
        Provider.of<media_service.MediaSearchService>(context, listen: false);

    // If candidates are provided, use them directly
    if (widget.candidates != null) {
      final candidateMaps =
          mediaSearchService.getCandidateMaps(widget.candidates!);
      setState(() {
        _mediaCandidates = candidateMaps;
        _isLoading = false;
      });
      return;
    }

    // Otherwise search for media based on the query
    if (_mediaQuery != null && _mediaQuery!.isNotEmpty) {
      // Check if we have a cached selection for this query
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);
      final cachedAssetId =
          await firestoreService.getCachedMediaAsset(_mediaQuery!);

      // Find media candidates
      final candidates = await mediaSearchService.findCandidates(_mediaQuery!);
      final candidateMaps = mediaSearchService.getCandidateMaps(candidates);

      setState(() {
        _mediaCandidates = candidateMaps;

        // If we have a cached selection, pre-select it
        if (cachedAssetId != null) {
          try {
            _selectedMedia = _mediaCandidates.firstWhere(
              (media) => media['id'] == cachedAssetId,
            );
          } catch (e) {
            _selectedMedia =
                _mediaCandidates.isNotEmpty ? _mediaCandidates.first : null;
          }
        }

        _isLoading = false;
      });
    } else {
      // No query, show recent media
      final candidates = await mediaSearchService.findCandidates('recent');
      final candidateMaps = mediaSearchService.getCandidateMaps(candidates);

      setState(() {
        _mediaCandidates = candidateMaps;
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _find_media_in_cache(
      String media_id, Map<String, dynamic> cache) {
    // This is a placeholder - in a real implementation, you would need to store
    // the full media metadata in the cache and retrieve it here
    return null;
  }

  List<String> _get_recent_dates(String query) {
    final now = DateTime.now();
    final dates = <String>[];

    if (query.contains('today')) {
      dates.add(now.toIso8601String().split('T')[0]);
    }

    if (query.contains('yesterday') || query.contains('last night')) {
      final yesterday = now.subtract(const Duration(days: 1));
      dates.add(yesterday.toIso8601String().split('T')[0]);
    }

    if (query.contains('this week')) {
      for (int i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        dates.add(date.toIso8601String().split('T')[0]);
      }
    }

    return dates;
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
                // Search query display
                if (_mediaQuery != null && _mediaQuery!.isNotEmpty)
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
                              'Searching for: "$_mediaQuery"',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
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
    if (_directory_service == null) return const SizedBox.shrink();

    final isCustomEnabled = _directory_service!.isCustomDirectoriesEnabled;
    final enabledCount = _directory_service!.enabledDirectories.length;

    return Container(
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filters',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                  final now = DateTime.now();
                  final initialDateRange = DateTimeRange(
                    start: now.subtract(const Duration(days: 7)),
                    end: now,
                  );

                  final pickedRange = await showDateRangePicker(
                    context: context,
                    initialDateRange: _dateRange ?? initialDateRange,
                    firstDate: DateTime(2000),
                    lastDate: now,
                  );

                  if (pickedRange != null) {
                    setState(() {
                      _dateRange = pickedRange;
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
                selected: _mediaType == media_service.MediaType.photo,
                onSelected: (selected) {
                  setState(() {
                    _mediaType =
                        selected ? media_service.MediaType.photo : null;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Videos'),
                selected: _mediaType == media_service.MediaType.video,
                onSelected: (selected) {
                  setState(() {
                    _mediaType =
                        selected ? media_service.MediaType.video : null;
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
        final isVideo =
            (media['mime_type']?.toString() ?? '').startsWith('video/');

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedMedia = media;
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FutureBuilder<AssetEntity?>(
                  future: media['id'] != null
                      ? AssetEntity.fromId(media['id'])
                      : Future.value(null),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.broken_image),
                      );
                    }

                    final asset = snapshot.data!;
                    return FutureBuilder<Uint8List?>(
                      future: asset
                          .thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                      builder: (context, thumbnailSnapshot) {
                        if (!thumbnailSnapshot.hasData) {
                          return Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }

                        return Image.memory(
                          thumbnailSnapshot.data!,
                          fit: BoxFit.cover,
                        );
                      },
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
                      color: Colors.black.withValues(alpha: 0.6),
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
                        Colors.black.withValues(alpha: 0.7),
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

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return 'Today, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day - 1) {
        return 'Yesterday, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Invalid date';
    }
  }
}
