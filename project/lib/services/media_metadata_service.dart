import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';

import 'directory_service.dart';
import 'app_settings_service.dart';

class MediaMetadataService extends ChangeNotifier {
  static const String _cacheFileName = 'media_metadata_cache.json';
  static const Duration _cacheRefreshInterval = Duration(hours: 1);

  Map<String, dynamic> _metadataCache = {};
  DateTime? _lastCacheUpdate;
  bool _isInitialized = false;
  DirectoryService? _directoryService;
  AppSettingsService? _appSettingsService;

  // Getters
  bool get isInitialized => _isInitialized;
  DateTime? get lastCacheUpdate => _lastCacheUpdate;
  Map<String, dynamic> get metadataCache => _metadataCache;

  /// Initialize the service with directory service and app settings service
  Future<void> initialize(DirectoryService directoryService,
      AppSettingsService appSettingsService) async {
    if (_isInitialized) return;

    _directoryService = directoryService;
    _appSettingsService = appSettingsService;

    // Ensure both services are initialized
    if (!_directoryService!.isInitialized) {
      await _directoryService!.initialize();
    }
    if (!_appSettingsService!.isInitialized) {
      await _appSettingsService!.initialize();
    }

    await _loadCache();
    _isInitialized = true;

    if (kDebugMode) {
      print('📊 MediaMetadataService initialized');
      print(
          '   Using AI Media Context Limit: ${_appSettingsService!.aiMediaContextLimit}');
    }
  }

  Future<void> _loadCache() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final cacheFile = File(path.join(cacheDir.path, _cacheFileName));

      if (await cacheFile.exists()) {
        final jsonString = await cacheFile.readAsString();
        _metadataCache = json.decode(jsonString);
        _lastCacheUpdate = DateTime.parse(_metadataCache['last_update'] ?? '');

        // Check if cache needs refresh
        if (_lastCacheUpdate != null &&
            DateTime.now().difference(_lastCacheUpdate!) >
                _cacheRefreshInterval) {
          await refreshCache();
        }
      } else {
        await refreshCache();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading media metadata cache: $e');
      }
      _metadataCache = {};
      await refreshCache();
    }
  }

  Future<void> refreshCache() async {
    if (_directoryService == null) {
      throw Exception('DirectoryService not initialized');
    }

    await _scanDirectories();
    _lastCacheUpdate = DateTime.now();

    // Save cache to file
    final cacheDir = await getApplicationCacheDirectory();
    final cacheFile = File(path.join(cacheDir.path, _cacheFileName));
    await cacheFile.writeAsString(json.encode(_metadataCache));

    notifyListeners();
  }

  Future<void> _scanDirectories() async {
    final directories = _directoryService!.enabledDirectories;
    final mediaItems = <String, Map<String, dynamic>>{};
    final mediaByDate = <String, List<String>>{};
    final mediaByFolder = <String, List<String>>{};
    final mediaByLocation = <String, List<String>>{};
    final directoriesInfo = <String, Map<String, dynamic>>{};

    for (final directory in directories) {
      final dirPath = directory.path;
      directoriesInfo[dirPath] = {
        'name': directory.displayName,
        'path': dirPath,
        'media_count': 0,
      };

      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final files = await dir.list().toList();
          for (final file in files) {
            if (file is File && _isMediaFile(path.extension(file.path))) {
              final metadata = await _extractMediaMetadata(file);
              if (metadata != null) {
                final mediaId = file.path;
                mediaItems[mediaId] = metadata;

                // Add to date index
                final date =
                    metadata['creation_time']?.toString().split('T')[0];
                if (date != null) {
                  mediaByDate.putIfAbsent(date, () => []).add(mediaId);
                }

                // Add to folder index
                mediaByFolder.putIfAbsent(dirPath, () => []).add(mediaId);

                // Add to location index if coordinates exist
                if (metadata['latitude'] != null &&
                    metadata['longitude'] != null) {
                  final locationKey =
                      '${metadata['latitude']},${metadata['longitude']}';
                  mediaByLocation
                      .putIfAbsent(locationKey, () => [])
                      .add(mediaId);
                }

                directoriesInfo[dirPath]!['media_count']++;
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error scanning directory $dirPath: $e');
        }
      }
    }

    _metadataCache = {
      'media_items': mediaItems,
      'media_by_date': mediaByDate,
      'media_by_folder': mediaByFolder,
      'media_by_location': mediaByLocation,
      'directories': directoriesInfo,
    };

    await _saveCache();
  }

  bool _isMediaFile(String extension) {
    // Remove leading dot and convert to lowercase
    final ext = extension.toLowerCase().replaceFirst('.', '');

    // Supported image formats that Flutter can display
    const supportedImageExtensions = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'heic',
      'heif',
      'tiff',
      'tif'
    };

    // Supported video formats
    const supportedVideoExtensions = {
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
      'm4v',
      '3gp',
      'flv',
      'wmv',
      'mpg',
      'mpeg'
    };

    return supportedImageExtensions.contains(ext) ||
        supportedVideoExtensions.contains(ext);
  }

  Future<Map<String, dynamic>?> _extractMediaMetadata(File file) async {
    try {
      final stats = await file.stat();
      final mimeType = _getMimeTypeFromExtension(path.extension(file.path));

      final metadata = <String, dynamic>{
        'id': path.basename(file.path),
        'file_uri': file.path,
        'mime_type': mimeType,
        'creation_time': stats.modified.toIso8601String(),
        'file_size_bytes': stats.size,
        'width': 0,
        'height': 0,
        'duration': 0,
        'folder': path.dirname(file.path),
      };

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
              final lat = _parseGpsCoordinate(gpsLat, gpsLatRef?.toString());
              final lon = _parseGpsCoordinate(gpsLon, gpsLonRef?.toString());
              if (lat != null) metadata['latitude'] = lat;
              if (lon != null) metadata['longitude'] = lon;
            }

            // Extract image dimensions
            final width =
                exifData['Image ImageWidth'] ?? exifData['EXIF ExifImageWidth'];
            final height = exifData['Image ImageLength'] ??
                exifData['EXIF ExifImageLength'];

            if (width != null) {
              metadata['width'] = int.tryParse(width.toString()) ?? 0;
            }
            if (height != null) {
              metadata['height'] = int.tryParse(height.toString()) ?? 0;
            }

            // Extract creation date from EXIF
            final dateTime =
                exifData['Image DateTime'] ?? exifData['EXIF DateTimeOriginal'];
            if (dateTime != null) {
              final dateString = dateTime.toString();
              final formattedDate =
                  dateString.substring(0, 10).replaceAll(':', '-') +
                      (dateString.length > 10 ? dateString.substring(10) : '');
              final parsedDate = DateTime.tryParse(formattedDate);
              if (parsedDate != null) {
                metadata['creation_time'] = parsedDate.toIso8601String();
              }
            }
          }
        } catch (e) {
          // EXIF parsing failed, use file stats
        }
      }

      return metadata;
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

  // Helper method to get media context for AI prompts
  Map<String, dynamic> getMediaContextForAi() {
    if (_directoryService == null) {
      throw StateError(
          'MediaMetadataService not initialized. Call initialize() first.');
    }

    if (_appSettingsService == null) {
      throw StateError(
          'MediaMetadataService not initialized with AppSettingsService. Call initialize() first.');
    }

    // Check if AI media context is enabled
    if (!_appSettingsService!.aiMediaContextEnabled) {
      if (kDebugMode) {
        print('🔇 AI Media Context disabled, returning empty context');
      }
      return {
        'media_context': {
          'recent_media': [],
          'directories': [],
          'total_count': 0,
          'summary': {
            'total_directories': 0,
            'total_files': 0,
            'date_range': null,
            'media_types_available': <String>[]
          }
        }
      };
    }

    try {
      // Get the configurable limit from settings
      final contextLimit = _appSettingsService!.aiMediaContextLimit;

      // Get all enabled directories
      final directories = _directoryService!.enabledDirectories;
      final mediaItems = _metadataCache['media_items'] ?? {};
      final mediaByDate = _metadataCache['media_by_date'] ?? {};
      final mediaByFolder = _metadataCache['media_by_folder'] ?? {};
      final mediaByLocation = _metadataCache['media_by_location'] ?? {};
      final directoriesInfo = _metadataCache['directories'] ?? {};

      // Use Map for automatic deduplication by media ID (same logic as Media Selection screen)
      final Map<String, Map<String, dynamic>> uniqueMediaItems = {};
      int totalProcessed = 0;

      if (kDebugMode) {
        print(
            '🔍 MediaMetadataService: Building AI context with limit: $contextLimit');
        print(
            '🔍 MediaMetadataService: Found ${directories.length} enabled directories to search');
      }

      // Process each directory and deduplicate media items
      for (final directory in directories) {
        final dirPath = directory.path;
        final mediaList =
            (mediaByFolder[dirPath] as List<dynamic>?)?.cast<String>() ??
                <String>[];

        if (kDebugMode) {
          print(
              '🔍 MediaMetadataService: Processing directory "${directory.displayName}" with ${mediaList.length} media items');
        }

        // Process media items from this directory
        for (final mediaId in mediaList) {
          // Stop if we've reached the limit
          if (uniqueMediaItems.length >= contextLimit) {
            if (kDebugMode) {
              print(
                  '🔍 MediaMetadataService: Reached context limit of $contextLimit, stopping');
            }
            break;
          }

          final item = mediaItems[mediaId];
          if (item != null) {
            // Use media ID as the key for deduplication
            uniqueMediaItems[mediaId] = {
              'file_uri': item['file_uri'],
              'file_name': path.basename(item['file_uri']),
              'mime_type': item['mime_type'],
              'timestamp': item['creation_time'],
              'directory': dirPath,
              'device_metadata': {
                'creation_time': item['creation_time'],
                'latitude': item['latitude'],
                'longitude': item['longitude'],
                'orientation': item['orientation'] ?? 1,
                'width': item['width'] ?? 0,
                'height': item['height'] ?? 0,
                'file_size_bytes': item['file_size_bytes'] ?? 0,
                'duration': item['duration'] ?? 0,
                'bitrate': item['bitrate'],
                'sampling_rate': item['sampling_rate'],
                'frame_rate': item['frame_rate']
              }
            };
            totalProcessed++;
          }
        }

        // Break if we've reached the limit
        if (uniqueMediaItems.length >= contextLimit) {
          break;
        }
      }

      // Convert deduplicated media back to list and sort by creation time (newest first)
      final deduplicatedMedia = uniqueMediaItems.values.toList();
      deduplicatedMedia.sort((a, b) {
        final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime); // Newest first
      });

      // Take only the limit amount after deduplication and sorting
      final recentMedia = deduplicatedMedia.take(contextLimit).toList();

      if (kDebugMode) {
        print(
            '🔍 MediaMetadataService: Processed $totalProcessed total items across directories');
        print(
            '🔍 MediaMetadataService: After deduplication: ${uniqueMediaItems.length} unique items');
        print(
            '🔍 MediaMetadataService: Final AI context contains: ${recentMedia.length} items');
      }

      // Get directory information with stats
      final directoryInfos = directories.map((directory) {
        final dirPath = directory.path;
        final dirInfo = directoriesInfo[dirPath] ?? {};
        final mediaList =
            (mediaByFolder[dirPath] as List<dynamic>?)?.cast<String>() ??
                <String>[];

        // Get sample files from this directory (limited to avoid overwhelming context)
        final sampleFiles = mediaList
            .take(10) // Only show first 10 files per directory as samples
            .map((id) => mediaItems[id])
            .where((item) => item != null)
            .map((item) => {
                  'file_uri': item!['file_uri'],
                  'file_name': path.basename(item!['file_uri']),
                  'mime_type': item['mime_type'],
                  'timestamp': item['creation_time'],
                })
            .toList();

        // Calculate directory statistics
        final locationStats = _calculateLocationStats(mediaList);
        final dateRange = _calculateDateRange(mediaList);

        return {
          'name': dirInfo['name'],
          'path': dirInfo['path'],
          'media_count': dirInfo['media_count'],
          'sample_files':
              sampleFiles, // Changed from 'recent_files' to 'sample_files' for clarity
          'stats': {
            'has_location_data': locationStats['has_location'],
            'common_locations': locationStats['common_locations'],
            'date_range': dateRange,
            'media_types': _getMediaTypesInDirectory(mediaList).keys.toList()
          }
        };
      }).toList();

      return {
        'media_context': {
          'recent_media': recentMedia,
          'directories': directoryInfos,
          'total_count': _metadataCache['media_items']?.length ?? 0,
          'context_limit': contextLimit,
          'deduplication_stats': {
            'total_processed': totalProcessed,
            'unique_items': uniqueMediaItems.length,
            'final_count': recentMedia.length,
          },
          'summary': {
            'total_directories': directories.length,
            'total_files': _metadataCache['media_items']?.length ?? 0,
            'date_range': _calculateGlobalDateRange(),
            'media_types_available': _getAllMediaTypes().keys.toList()
          }
        }
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting media context for AI: $e');
      }
      // Return empty context on error
      return {
        'media_context': {
          'recent_media': [],
          'directories': [],
          'total_count': 0,
          'context_limit': _appSettingsService?.aiMediaContextLimit ?? 100,
          'deduplication_stats': {
            'total_processed': 0,
            'unique_items': 0,
            'final_count': 0,
          },
          'summary': {
            'total_directories': 0,
            'total_files': 0,
            'date_range': null,
            'media_types_available': <String>[]
          }
        }
      };
    }
  }

  Map<String, dynamic> _calculateLocationStats(List<String> mediaIds) {
    final locations = <String>[];
    var hasLocation = false;

    for (final id in mediaIds) {
      final item = _metadataCache['media_items']?[id];
      if (item != null &&
          item['latitude'] != null &&
          item['longitude'] != null) {
        hasLocation = true;
        final locationKey = '${item['latitude']},${item['longitude']}';
        locations.add(locationKey);
      }
    }

    // Get the most common locations (up to 5)
    final locationCounts = <String, int>{};
    for (final location in locations) {
      locationCounts[location] = (locationCounts[location] ?? 0) + 1;
    }

    final commonLocations = locationCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'has_location': hasLocation,
      'common_locations': commonLocations.take(5).map((e) => e.key).toList()
    };
  }

  Map<String, String> _calculateDateRange(List<String> mediaIds) {
    DateTime? earliest;
    DateTime? latest;

    for (final id in mediaIds) {
      final item = _metadataCache['media_items']?[id];
      if (item != null && item['creation_time'] != null) {
        final date = DateTime.tryParse(item['creation_time']);
        if (date != null) {
          if (earliest == null || date.isBefore(earliest)) {
            earliest = date;
          }
          if (latest == null || date.isAfter(latest)) {
            latest = date;
          }
        }
      }
    }

    return {
      'earliest': earliest?.toIso8601String() ?? '',
      'latest': latest?.toIso8601String() ?? ''
    };
  }

  Map<String, String> _calculateGlobalDateRange() {
    final allMediaIds =
        (_metadataCache['media_items']?.keys.toList() as List<dynamic>?)
                ?.cast<String>() ??
            <String>[];
    return _calculateDateRange(allMediaIds);
  }

  Map<String, int> _getMediaTypesInDirectory(List<String> mediaIds) {
    final typeCounts = <String, int>{};

    for (final id in mediaIds) {
      final item = _metadataCache['media_items']?[id];
      if (item != null && item['mime_type'] != null) {
        final type = item['mime_type'];
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      }
    }

    return typeCounts;
  }

  Map<String, int> _getAllMediaTypes() {
    final allMediaIds =
        (_metadataCache['media_items']?.keys.toList() as List<dynamic>?)
                ?.cast<String>() ??
            <String>[];
    return _getMediaTypesInDirectory(allMediaIds);
  }

  Map<String, dynamic>? getMediaItem(String mediaId) {
    return _metadataCache['media_items']?[mediaId];
  }

  List<Map<String, dynamic>> getMediaByDate(String date) {
    final mediaIds = (_metadataCache['media_by_date']?[date] as List<dynamic>?)
            ?.cast<String>() ??
        <String>[];
    return mediaIds
        .map((id) => getMediaItem(id))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> getMediaByFolder(String folderPath) {
    final mediaIds =
        (_metadataCache['media_by_folder']?[folderPath] as List<dynamic>?)
                ?.cast<String>() ??
            <String>[];
    return mediaIds
        .map((id) => getMediaItem(id))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> getMediaByLocation(
      double latitude, double longitude) {
    final locationKey = '$latitude,$longitude';
    final mediaIds =
        (_metadataCache['media_by_location']?[locationKey] as List<dynamic>?)
                ?.cast<String>() ??
            <String>[];
    return mediaIds
        .map((id) => getMediaItem(id))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> getRecentMedia({int limit = 10}) {
    final dates = _metadataCache['media_by_date']?.keys.toList()
      ?..sort((a, b) => b.compareTo(a));

    if (dates == null || dates.isEmpty) return [];

    final recentMedia = <Map<String, dynamic>>[];
    for (final date in dates) {
      final media = getMediaByDate(date);
      recentMedia.addAll(media);
      if (recentMedia.length >= limit) break;
    }

    return recentMedia.take(limit).toList();
  }

  Future<void> _saveCache() async {
    // Implementation of _save_cache method
  }

  /// Extracts metadata from a media file
  Future<Map<String, dynamic>> extractMetadata(File file) async {
    try {
      if (!await file.exists()) {
        throw Exception('File does not exist: ${file.path}');
      }

      final extension = path.extension(file.path).toLowerCase();
      final mimeType = _getMimeTypeFromExtension(extension);

      Map<String, dynamic> metadata = {
        'mime_type': mimeType,
        'file_size_bytes': await file.length(),
        'last_modified': (await file.lastModified()).toIso8601String(),
      };

      // Extract EXIF data if available
      if (mimeType.startsWith('image/')) {
        try {
          final bytes = await file.readAsBytes();
          final exifData = await readExifFromBytes(bytes);

          if (exifData.isEmpty) {
            return metadata;
          }

          // Extract GPS coordinates if available
          final gpsLatitude = exifData['GPS GPSLatitude'];
          final gpsLatitudeRef = exifData['GPS GPSLatitudeRef']?.toString();
          final gpsLongitude = exifData['GPS GPSLongitude'];
          final gpsLongitudeRef = exifData['GPS GPSLongitudeRef']?.toString();

          if (gpsLatitude != null && gpsLongitude != null) {
            metadata['latitude'] =
                _parseGpsCoordinate(gpsLatitude, gpsLatitudeRef ?? 'N');
            metadata['longitude'] =
                _parseGpsCoordinate(gpsLongitude, gpsLongitudeRef ?? 'E');
          }

          // Extract creation date if available
          final dateTime = exifData['EXIF DateTimeOriginal']?.toString() ??
              exifData['EXIF DateTimeDigitized']?.toString();

          if (dateTime != null) {
            metadata['creation_time'] = dateTime;
          }

          // Extract image dimensions if available
          final width = exifData['EXIF ExifImageWidth']?.toString();
          final height = exifData['EXIF ExifImageLength']?.toString();

          if (width != null && height != null) {
            metadata['width'] = int.tryParse(width);
            metadata['height'] = int.tryParse(height);
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Failed to extract EXIF data: $e');
          }
        }
      }

      return metadata;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error extracting metadata: $e');
      }
      rethrow;
    }
  }
}
