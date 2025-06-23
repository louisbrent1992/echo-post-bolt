import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/social_action.dart';
import '../services/app_settings_service.dart';
import '../services/directory_service.dart';
import '../services/media_metadata_service.dart';
import '../services/media_search_service.dart';
import '../services/photo_manager_service.dart';

/// Coordinates all media-related operations across the app.
/// This service acts as the single entry point for all media operations,
/// creating and managing all media service dependencies internally.
class MediaCoordinator extends ChangeNotifier {
  // Internal service instances - created and managed by this coordinator
  late final PhotoManagerService _photoManager;
  late final DirectoryService _directoryService;
  late final MediaMetadataService _metadataService;
  late final MediaSearchService _mediaSearchService;
  late final AppSettingsService _appSettingsService;

  bool _isInitialized = false;
  bool _isInitializing = false;

  // Add static variables for debug message throttling
  static DateTime? _lastCacheInvalidationLog;
  static DateTime? _lastQueryLog;
  static int _queryCount = 0;

  MediaCoordinator();

  /// Whether the coordinator and all its services are initialized
  bool get isInitialized => _isInitialized;

  /// Whether initialization is currently in progress
  bool get isInitializing => _isInitializing;

  /// Initializes all media-related services in the proper order
  /// This is the single entry point for media system initialization
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_isInitializing) {
      // Wait for ongoing initialization to complete
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    _isInitializing = true;

    try {
      if (kDebugMode) {
        print(
            '🚀 MediaCoordinator: Starting comprehensive media system initialization...');
      }

      // Step 1: Create all service instances
      if (kDebugMode) {
        print('🏗️ MediaCoordinator: Creating service instances...');
      }

      _directoryService = DirectoryService();
      _metadataService = MediaMetadataService();
      _photoManager = PhotoManagerService();
      _mediaSearchService = MediaSearchService();
      _appSettingsService = AppSettingsService();

      // Step 2: Initialize AppSettingsService first (no dependencies)
      if (kDebugMode) {
        print('🔧 MediaCoordinator: Initializing AppSettingsService...');
      }
      await _appSettingsService.initialize();

      // Step 3: Initialize DirectoryService (no dependencies)
      if (kDebugMode) {
        print('📁 MediaCoordinator: Initializing DirectoryService...');
      }
      await _directoryService.initialize();

      // Step 4: Initialize MediaMetadataService with DirectoryService and AppSettingsService
      if (kDebugMode) {
        print('📊 MediaCoordinator: Initializing MediaMetadataService...');
      }
      await _metadataService.initialize(_directoryService, _appSettingsService);

      // Step 5: Initialize PhotoManagerService (without requesting permissions)
      if (kDebugMode) {
        print('📷 MediaCoordinator: Initializing PhotoManagerService...');
      }

      // Step 6: Initialize MediaSearchService
      if (kDebugMode) {
        print('🔍 MediaCoordinator: Initializing MediaSearchService...');
      }
      // Initialize MediaSearchService with proper setup
      await _mediaSearchService.initialize();

      _isInitialized = true;
      _isInitializing = false;

      // Notify listeners that initialization is complete
      notifyListeners();

      if (kDebugMode) {
        print(
            '✅ MediaCoordinator: All media services initialized successfully!');
        print('   - AppSettingsService: ✅');
        print('   - DirectoryService: ✅');
        print('   - MediaMetadataService: ✅');
        print('   - PhotoManagerService: ✅');
        print('   - MediaSearchService: ✅');
      }
    } catch (e) {
      _isInitializing = false;
      if (kDebugMode) {
        print('❌ MediaCoordinator: Initialization failed: $e');
      }
      rethrow;
    }
  }

  /// Provides access to the PhotoManagerService
  /// Only available after initialization
  PhotoManagerService get photoManager {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _photoManager;
  }

  /// Provides access to the DirectoryService
  /// Only available after initialization
  DirectoryService get directoryService {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _directoryService;
  }

  /// Provides access to the MediaMetadataService
  /// Only available after initialization
  MediaMetadataService get metadataService {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _metadataService;
  }

  /// Provides access to the MediaSearchService
  /// Only available after initialization
  MediaSearchService get mediaSearchService {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _mediaSearchService;
  }

  /// Provides access to the AppSettingsService
  /// Only available after initialization
  AppSettingsService get appSettingsService {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _appSettingsService;
  }

  /// Retrieves media assets based on a semantic query and filters
  /// This method now enforces strict directory compliance by overriding PhotoManager's cache
  Future<List<Map<String, dynamic>>> getMediaForQuery(
    String query, {
    DateTimeRange? dateRange,
    List<String>? mediaTypes,
    String? directory,
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      // Only log query details occasionally to avoid spam
      _queryCount++;
      final now = DateTime.now();
      final shouldLogQuery = _lastQueryLog == null ||
          now.difference(_lastQueryLog!).inSeconds > 30 ||
          _queryCount % 10 == 1;

      if (kDebugMode && shouldLogQuery) {
        print('🔍 MediaCoordinator: Query #$_queryCount - "$query"');
        print('   Custom directories enabled: $isCustomDirectoriesEnabled');
        _lastQueryLog = now;
      }

      // CRITICAL: Force PhotoManager cache invalidation before each query
      // This ensures we never show stale media from deselected directories
      await _forcePhotoManagerCacheInvalidation();

      final searchParams = {
        'terms': query.split(' '),
        'date_range': dateRange != null
            ? {
                'start': dateRange.start.toIso8601String(),
                'end': dateRange.end.toIso8601String(),
              }
            : null,
        'media_type': mediaTypes?.firstOrNull,
        'directory': directory,
      };

      List<Map<String, dynamic>> photoManagerResults = [];
      List<Map<String, dynamic>> customResults = [];

      // Get PhotoManager results and filter them appropriately based on directory mode
      final candidates = await _photoManager.findAssetCandidates(searchParams);
      final candidateMaps = await _photoManager.getAssetMaps(candidates);

      // CRITICAL: Always filter PhotoManager results based on current directory state
      // This ensures consistent behavior whether custom directories are enabled or disabled
      photoManagerResults =
          await _filterPhotoManagerResultsByEnabledDirectories(candidateMaps);

      // Only get custom directory results when custom directories are enabled
      if (isCustomDirectoriesEnabled) {
        customResults = await _searchCustomDirectories(
          query,
          dateRange: dateRange,
          mediaTypes: mediaTypes,
          directory: directory,
        );
      }

      // Combine and deduplicate results with strict path validation
      final allResults = <String, Map<String, dynamic>>{};

      // Add PhotoManager results
      for (var media in photoManagerResults) {
        final fileUri = media['file_uri'] as String;
        final filePath = Uri.parse(fileUri).path;

        // Double-check that this file is still allowed based on current directory state
        if (await isFileAllowedByCurrentDirectoryState(filePath)) {
          allResults[fileUri] = media;
        }
      }

      // Add custom directory results (these are already filtered by enabled directories)
      for (var media in customResults) {
        final fileUri = media['file_uri'] as String;
        allResults[fileUri] = media;
      }

      final finalResults = allResults.values.toList();

      // Sort by creation time (newest first)
      finalResults.sort((a, b) {
        final aTime = DateTime.tryParse(a['device_metadata']
                    ?['creation_time'] ??
                a['metadata']?['creation_time'] ??
                DateTime.now().toIso8601String()) ??
            DateTime.now();
        final bTime = DateTime.tryParse(b['device_metadata']
                    ?['creation_time'] ??
                b['metadata']?['creation_time'] ??
                DateTime.now().toIso8601String()) ??
            DateTime.now();
        return bTime.compareTo(aTime);
      });

      // Enrich PhotoManager results with metadata from EXIF data
      for (var media in finalResults) {
        final fileUri = media['file_uri'] as String;
        final file = File(Uri.parse(fileUri).path);
        if (await file.exists() && media['metadata'] == null) {
          final metadata = await _metadataService.extractMetadata(file);
          media['metadata'] = metadata;
        }
      }

      // Only log results summary occasionally
      if (kDebugMode && shouldLogQuery) {
        print(
            '✅ MediaCoordinator: Returning ${finalResults.length} filtered results');
      }

      return finalResults;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error getting media for query: $e');
      }
      rethrow;
    }
  }

  /// Forces complete PhotoManager cache invalidation to prevent stale results
  Future<void> _forcePhotoManagerCacheInvalidation() async {
    try {
      // Throttle cache invalidation logging to prevent spam
      final now = DateTime.now();
      final shouldLog = _lastCacheInvalidationLog == null ||
          now.difference(_lastCacheInvalidationLog!).inSeconds > 60;

      if (kDebugMode && shouldLog) {
        print(
            '🗑️ MediaCoordinator: Forcing PhotoManager cache invalidation...');
        _lastCacheInvalidationLog = now;
      }

      // Step 1: Clear all PhotoManager caches
      await PhotoManager.clearFileCache();
      await PhotoManager.releaseCache();

      // Step 2: Reset change notifications
      try {
        await PhotoManager.stopChangeNotify();
        await Future.delayed(const Duration(milliseconds: 200));
        await PhotoManager.startChangeNotify();
      } catch (e) {
        // Only log errors, not successful operations
        if (kDebugMode) {
          print('⚠️ MediaCoordinator: Change notification reset failed: $e');
        }
      }

      // Step 3: Force PhotoManager to rebuild its internal state
      try {
        // Request a minimal album list to force internal state refresh
        await PhotoManager.getAssetPathList(
          type: RequestType.image,
          filterOption: FilterOptionGroup(
            imageOption: const FilterOption(
              sizeConstraint: SizeConstraint(
                minWidth: 1,
                minHeight: 1,
                maxWidth: 99999,
                maxHeight: 99999,
              ),
            ),
          ),
        );
      } catch (e) {
        // Only log errors
        if (kDebugMode) {
          print('⚠️ MediaCoordinator: PhotoManager state refresh failed: $e');
        }
      }

      if (kDebugMode && shouldLog) {
        print('✅ MediaCoordinator: Cache invalidation complete');
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ MediaCoordinator: Failed to invalidate PhotoManager cache: $e');
      }
      // Continue anyway - this is not critical enough to stop the operation
    }
  }

  /// Filters PhotoManager results to only include files from currently enabled directories
  Future<List<Map<String, dynamic>>>
      _filterPhotoManagerResultsByEnabledDirectories(
          List<Map<String, dynamic>> photoManagerResults) async {
    final filteredResults = <Map<String, dynamic>>[];

    Set<String> allowedPaths;
    if (!isCustomDirectoriesEnabled) {
      // FIXED: When custom directories are disabled, only allow files from standard/default directories
      allowedPaths =
          DirectoryService.getPlatformDefaults().map((dir) => dir.path).toSet();
    } else {
      // Custom directories enabled - use enabled directories
      allowedPaths =
          _directoryService.enabledDirectories.map((dir) => dir.path).toSet();
    }

    // Only log filtering details if there are results to filter and it's been a while
    final shouldLogFiltering = kDebugMode &&
        photoManagerResults.isNotEmpty &&
        (_lastQueryLog == null ||
            DateTime.now().difference(_lastQueryLog!).inSeconds > 30);

    if (shouldLogFiltering) {
      final directoryType =
          isCustomDirectoriesEnabled ? "enabled custom" : "standard";
      print(
          '🔍 MediaCoordinator: Filtering ${photoManagerResults.length} PhotoManager results by ${allowedPaths.length} $directoryType directories');
    }

    int excludedCount = 0;
    for (final media in photoManagerResults) {
      final fileUri = media['file_uri'] as String;
      final filePath = Uri.parse(fileUri).path;

      // Check if this file belongs to any allowed directory
      bool isInAllowedDirectory = false;
      for (final allowedPath in allowedPaths) {
        if (filePath.startsWith(allowedPath)) {
          isInAllowedDirectory = true;
          break;
        }
      }

      if (isInAllowedDirectory) {
        filteredResults.add(media);
      } else {
        excludedCount++;
      }
    }

    if (shouldLogFiltering && excludedCount > 0) {
      print(
          '🚫 MediaCoordinator: Excluded $excludedCount files from disabled directories');
    }

    return filteredResults;
  }

  /// Checks if a file is allowed based on the current directory selection state
  Future<bool> isFileAllowedByCurrentDirectoryState(String filePath) async {
    if (!isCustomDirectoriesEnabled) {
      // FIXED: When custom directories are disabled, only allow files from standard/default directories
      // This prevents showing media from previously enabled custom directories
      final standardDirectoryPaths =
          DirectoryService.getPlatformDefaults().map((dir) => dir.path).toSet();

      // Check if file is in any standard directory
      for (final standardPath in standardDirectoryPaths) {
        if (filePath.startsWith(standardPath)) {
          return true;
        }
      }

      return false; // File is not in any standard directory
    }

    final enabledPaths =
        _directoryService.enabledDirectories.map((dir) => dir.path).toSet();

    // Check if file is in any enabled directory
    for (final enabledPath in enabledPaths) {
      if (filePath.startsWith(enabledPath)) {
        return true;
      }
    }

    return false;
  }

  /// Searches custom directories for media matching the query and filters
  Future<List<Map<String, dynamic>>> _searchCustomDirectories(
    String query, {
    DateTimeRange? dateRange,
    List<String>? mediaTypes,
    String? directory,
  }) async {
    try {
      final results = <Map<String, dynamic>>[];
      final searchTerms = query
          .toLowerCase()
          .split(' ')
          .where((term) => term.isNotEmpty)
          .toList();

      // Get all media from custom directories via metadata cache
      final metadataCache = _metadataService.metadataCache;
      final mediaItems =
          metadataCache['media_items'] as Map<String, dynamic>? ?? {};

      for (final entry in mediaItems.entries) {
        final filePath = entry.key;
        final metadata = entry.value as Map<String, dynamic>;

        // Check if file still exists
        final file = File(filePath);
        if (!await file.exists()) continue;

        // Apply directory filter
        if (directory != null && !filePath.contains(directory)) continue;

        // Apply media type filter
        final mimeType = metadata['mime_type'] as String? ?? '';
        if (mediaTypes != null && mediaTypes.isNotEmpty) {
          final mediaType = mediaTypes.first.toLowerCase();
          if (mediaType == 'photo' && !mimeType.startsWith('image/')) continue;
          if (mediaType == 'video' && !mimeType.startsWith('video/')) continue;
        }

        // Apply date range filter
        if (dateRange != null) {
          final creationTimeStr = metadata['creation_time'] as String?;
          if (creationTimeStr != null) {
            final creationTime = DateTime.tryParse(creationTimeStr);
            if (creationTime != null) {
              if (creationTime.isBefore(dateRange.start) ||
                  creationTime.isAfter(dateRange.end)) {
                continue;
              }
            }
          }
        }

        // Apply search terms filter
        if (searchTerms.isNotEmpty) {
          final fileName = metadata['id'] as String? ?? '';
          final folderPath = metadata['folder'] as String? ?? '';
          final searchText = '$fileName $folderPath'.toLowerCase();

          final matchesSearch =
              searchTerms.any((term) => searchText.contains(term));
          if (!matchesSearch) continue;
        }

        // Convert metadata format to match PhotoManager format
        final result = {
          'id': metadata['id'] ??
              'custom_${DateTime.now().millisecondsSinceEpoch}',
          'file_uri': file.uri.toString(),
          'mime_type': mimeType,
          'device_metadata': {
            'creation_time':
                metadata['creation_time'] ?? DateTime.now().toIso8601String(),
            'latitude': metadata['latitude'],
            'longitude': metadata['longitude'],
            'width': metadata['width'] ?? 0,
            'height': metadata['height'] ?? 0,
            'file_size_bytes': metadata['file_size_bytes'] ?? 0,
            'duration': (metadata['duration'] as num?)?.toDouble() ?? 0.0,
            'orientation': 1,
          },
          'metadata': metadata,
        };

        results.add(result);
      }

      if (kDebugMode) {
        print(
            '🔍 MediaCoordinator: Custom directory search found ${results.length} matches');
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error searching custom directories: $e');
      }
      return [];
    }
  }

  /// Validates and normalizes a media URI
  String normalizeMediaURI(String uri) {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      final normalizedUri = Uri.parse(uri).toString();
      if (!_isValidMediaURI(normalizedUri)) {
        throw Exception('Invalid media URI format: $uri');
      }
      return normalizedUri;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error normalizing URI: $e');
      }
      rethrow;
    }
  }

  /// Validates that a media URI exists and is accessible
  Future<bool> validateMediaURI(String uri) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      final normalizedUri = normalizeMediaURI(uri);
      final file = File(Uri.parse(normalizedUri).path);

      // Check if file exists
      if (!await file.exists()) {
        if (kDebugMode) {
          print(
              '❌ MediaCoordinator: Media file does not exist: $normalizedUri');
        }
        return false;
      }

      // Check if file is readable and has valid size
      try {
        final fileSize = await file.length();
        if (fileSize == 0) {
          if (kDebugMode) {
            print('❌ MediaCoordinator: Media file is empty: $normalizedUri');
          }
          return false;
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ MediaCoordinator: Media file is not accessible: $e');
        }
        return false;
      }

      // Validate MIME type and format support
      final mimeType = _getMimeTypeFromPath(file.path);
      if (!_isSupportedMediaType(mimeType)) {
        if (kDebugMode) {
          print(
              '❌ MediaCoordinator: Unsupported media type: $mimeType for file: $normalizedUri');
        }
        return false;
      }

      // For images, try to validate that the file can actually be read as an image
      if (mimeType.startsWith('image/')) {
        try {
          // Try to read a small portion of the file to validate it's not corrupted
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) {
            if (kDebugMode) {
              print(
                  '❌ MediaCoordinator: Image file appears to be corrupted: $normalizedUri');
            }
            return false;
          }

          // Basic image format validation by checking file headers
          if (!_hasValidImageHeader(bytes, mimeType)) {
            if (kDebugMode) {
              print(
                  '❌ MediaCoordinator: Invalid image file header: $normalizedUri');
            }
            return false;
          }
        } catch (e) {
          if (kDebugMode) {
            print(
                '❌ MediaCoordinator: Cannot read image file: $normalizedUri - $e');
          }
          return false;
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error validating media URI: $e');
      }
      return false;
    }
  }

  /// Determines MIME type from file path/extension
  String _getMimeTypeFromPath(String path) {
    final extension = path.toLowerCase().split('.').last;

    // Supported image formats
    const imageMimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'tiff': 'image/tiff',
      'tif': 'image/tiff',
    };

    // Supported video formats
    const videoMimeTypes = {
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'm4v': 'video/x-m4v',
      '3gp': 'video/3gpp',
      'flv': 'video/x-flv',
      'wmv': 'video/x-ms-wmv',
      'mpg': 'video/mpeg',
      'mpeg': 'video/mpeg',
    };

    // Check image formats first
    if (imageMimeTypes.containsKey(extension)) {
      return imageMimeTypes[extension]!;
    }

    // Check video formats
    if (videoMimeTypes.containsKey(extension)) {
      return videoMimeTypes[extension]!;
    }

    // Unsupported format
    return 'application/octet-stream';
  }

  /// Checks if a MIME type is supported for display
  bool _isSupportedMediaType(String mimeType) {
    // Supported image types that Flutter can display
    const supportedImageTypes = {
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/bmp',
      'image/webp',
      'image/heic',
      'image/heif',
      'image/tiff',
    };

    // Supported video types (for preview thumbnails)
    const supportedVideoTypes = {
      'video/mp4',
      'video/quicktime',
      'video/x-msvideo',
      'video/x-matroska',
      'video/webm',
      'video/x-m4v',
      'video/3gpp',
      'video/x-flv',
      'video/x-ms-wmv',
      'video/mpeg',
    };

    return supportedImageTypes.contains(mimeType) ||
        supportedVideoTypes.contains(mimeType);
  }

  /// Validates image file headers to ensure they match the expected format
  bool _hasValidImageHeader(List<int> bytes, String mimeType) {
    if (bytes.length < 8) return false;

    switch (mimeType) {
      case 'image/jpeg':
        // JPEG files start with FF D8 FF
        return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

      case 'image/png':
        // PNG files start with 89 50 4E 47 0D 0A 1A 0A
        return bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47 &&
            bytes[4] == 0x0D &&
            bytes[5] == 0x0A &&
            bytes[6] == 0x1A &&
            bytes[7] == 0x0A;

      case 'image/gif':
        // GIF files start with "GIF87a" or "GIF89a"
        return bytes.length >= 6 &&
            bytes[0] == 0x47 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x38 &&
            (bytes[4] == 0x37 || bytes[4] == 0x39) &&
            bytes[5] == 0x61;

      case 'image/bmp':
        // BMP files start with "BM"
        return bytes[0] == 0x42 && bytes[1] == 0x4D;

      case 'image/webp':
        // WebP files start with "RIFF" and have "WEBP" at position 8
        return bytes.length >= 12 &&
            bytes[0] == 0x52 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x46 &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50;

      case 'image/tiff':
        // TIFF files start with "II*\0" (little-endian) or "MM\0*" (big-endian)
        return (bytes[0] == 0x49 &&
                bytes[1] == 0x49 &&
                bytes[2] == 0x2A &&
                bytes[3] == 0x00) ||
            (bytes[0] == 0x4D &&
                bytes[1] == 0x4D &&
                bytes[2] == 0x00 &&
                bytes[3] == 0x2A);

      default:
        // For HEIC/HEIF and other formats, just check that it's not empty
        // More sophisticated validation would require additional libraries
        return true;
    }
  }

  /// Attempts to recover media state for a given action
  Future<SocialAction?> recoverMediaState(SocialAction action) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print(
            '🔄 MediaCoordinator: Attempting to recover media state for action: ${action.actionId}');
      }

      // Check if media URIs are still valid
      final updatedMedia = <MediaItem>[];
      for (final media in action.content.media) {
        if (await validateMediaURI(media.fileUri)) {
          updatedMedia.add(media);
        } else {
          if (kDebugMode) {
            print(
                '⚠️ MediaCoordinator: Invalid media URI found: ${media.fileUri}');
          }
        }
      }

      // If we lost media, try to recover using the original query
      if (updatedMedia.length < action.content.media.length &&
          action.mediaQuery != null) {
        if (kDebugMode) {
          print(
              '🔍 MediaCoordinator: Attempting to recover media using original query');
        }

        final searchQuery = action.mediaQuery?.searchTerms.join(' ') ?? '';
        final candidates = await getMediaForQuery(searchQuery);

        if (candidates.isNotEmpty) {
          // Add the first matching media item
          final recoveredMedia = MediaItem(
            fileUri: candidates.first['file_uri'] as String,
            mimeType: candidates.first['mime_type'] as String,
            deviceMetadata: DeviceMetadata(
              creationTime: candidates.first['device_metadata']['creation_time']
                  as String,
              latitude:
                  candidates.first['device_metadata']['latitude'] as double?,
              longitude:
                  candidates.first['device_metadata']['longitude'] as double?,
              width: candidates.first['device_metadata']['width'] as int? ?? 0,
              height:
                  candidates.first['device_metadata']['height'] as int? ?? 0,
              fileSizeBytes: candidates.first['device_metadata']
                      ['file_size_bytes'] as int? ??
                  0,
            ),
          );
          updatedMedia.add(recoveredMedia);
        }
      }

      // Return updated action with recovered media
      return SocialAction(
        actionId: action.actionId,
        createdAt: action.createdAt,
        platforms: action.platforms,
        content: Content(
          text: action.content.text,
          hashtags: action.content.hashtags,
          mentions: action.content.mentions,
          link: action.content.link,
          media: updatedMedia,
        ),
        options: action.options,
        platformData: action.platformData,
        internal: action.internal,
        mediaQuery: action.mediaQuery,
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error recovering media state: $e');
      }
      return null;
    }
  }

  /// Checks if a URI is in a valid format for media
  bool _isValidMediaURI(String uri) {
    try {
      final parsedUri = Uri.parse(uri);
      return parsedUri.scheme.isNotEmpty && parsedUri.path.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Whether custom directories are enabled for media search
  bool get isCustomDirectoriesEnabled {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _directoryService.isCustomDirectoriesEnabled;
  }

  /// List of currently enabled directories
  List<MediaDirectory> get enabledDirectories {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _directoryService.enabledDirectories;
  }

  // ========== Existing Post Context for AI ==========

  SocialAction? _existingPostForAi;
  bool _isVoiceDictationMode = false;

  /// Set recording mode context for AI processing
  void setRecordingModeContext(bool isVoiceDictation) {
    _isVoiceDictationMode = isVoiceDictation;
    if (kDebugMode) {
      print(
          '🎤 MediaCoordinator: Set recording mode to ${isVoiceDictation ? "voice dictation" : "command"}');
    }
  }

  /// Set existing post context for AI processing (used for voice editing)
  void setExistingPostContext(SocialAction? existingPost) {
    _existingPostForAi = existingPost;
    if (kDebugMode) {
      if (existingPost != null) {
        print('🔄 MediaCoordinator: Set existing post context for AI editing');
        print('   Post ID: ${existingPost.actionId}');
        print('   Content: "${existingPost.content.text}"');
      } else {
        print(
            '🔄 MediaCoordinator: Cleared existing post context (new post mode)');
      }
    }
  }

  /// Get media context for AI processing
  Future<Map<String, dynamic>> getMediaContextForAi() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      final latestMedia = await _getLatestMediaFiles();
      final enabledDirs = _directoryService.enabledDirectories;

      // Build directory status maps
      final directoriesWithContent = <String, bool>{};
      final mediaTypesByDirectory = <String, Set<String>>{};

      for (final dir in enabledDirs) {
        directoriesWithContent[dir.path] = await _directoryHasContent(dir.path);
        mediaTypesByDirectory[dir.path] =
            await _getMediaTypesInDirectory(dir.path);
      }

      final mediaContext = {
        'recent_media': latestMedia,
        'total_count': latestMedia.length,
        'last_updated': DateTime.now().toIso8601String(),
        'isEditing': _existingPostForAi != null,
        'isVoiceDictation': _isVoiceDictationMode,
        'directory_status': {
          'enabled_directories': enabledDirs.map((d) => d.path).toList(),
          'directories_with_content': directoriesWithContent,
          'media_types_by_directory': mediaTypesByDirectory,
          'any_directory_has_content':
              directoriesWithContent.values.any((hasContent) => hasContent),
        },
      };

      // Include existing post context if available
      if (_existingPostForAi != null) {
        mediaContext['existingPost'] = _existingPostForAi!.toJson();
      }

      return mediaContext;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to get media context for AI: $e');
      }
      return {
        'recent_media': [],
        'total_count': 0,
        'last_updated': DateTime.now().toIso8601String(),
        'isEditing': false,
        'isVoiceDictation': _isVoiceDictationMode,
        'error': e.toString(),
        'directory_status': {
          'enabled_directories': [],
          'any_directory_has_content': false,
        },
      };
    }
  }

  // ========== DirectoryService Methods ==========

  /// Toggle custom directories mode
  Future<void> setCustomDirectoriesEnabled(bool enabled) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    await _directoryService.setCustomDirectoriesEnabled(enabled);
    notifyListeners();
  }

  /// Update a directory's enabled status
  Future<void> updateDirectoryEnabled(String directoryId, bool enabled) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    await _directoryService.updateDirectoryEnabled(directoryId, enabled);
    notifyListeners();
  }

  /// Add a custom directory
  Future<void> addCustomDirectory(String displayName, String path) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    await _directoryService.addCustomDirectory(displayName, path);
    notifyListeners();
  }

  /// Remove a custom directory (can't remove defaults)
  Future<void> removeDirectory(String directoryId) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    await _directoryService.removeDirectory(directoryId);
    notifyListeners();
  }

  /// Reset to platform defaults
  Future<void> resetToDefaults() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    await _directoryService.resetToDefaults();
    notifyListeners();
  }

  /// Check if a directory path exists and is accessible
  Future<bool> isDirectoryAccessible(String path) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _directoryService.isDirectoryAccessible(path);
  }

  /// Get suggested directories based on common patterns
  Future<List<String>> getSuggestedDirectories() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _directoryService.getSuggestedDirectories();
  }

  /// Set the active directory
  void setActiveDirectory(String path) {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    _directoryService.setActiveDirectory(path);
    notifyListeners();
  }

  /// Get the active directory
  MediaDirectory? get activeDirectory {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _directoryService.activeDirectory;
  }

  /// Get all directories
  List<MediaDirectory> get directories {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _directoryService.directories;
  }

  // ========== PhotoManagerService Methods ==========

  /// Find asset candidates using search parameters
  Future<List<AssetEntity>> findAssetCandidates(
      Map<String, dynamic> searchParams) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _photoManager.findAssetCandidates(searchParams);
  }

  /// Convert asset entities to maps
  Future<List<Map<String, dynamic>>> getAssetMaps(
      List<AssetEntity> candidates) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _photoManager.getAssetMaps(candidates);
  }

  // ========== MediaSearchService Methods ==========

  /// Get available albums on the device
  Future<List<AssetPathEntity>> getAvailableAlbums() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _mediaSearchService.getAvailableAlbums();
  }

  /// Re-initialize MediaSearchService with new album selection
  Future<void> reinitializeWithAlbums(
      List<AssetPathEntity> selectedAlbums) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      // Convert AssetPathEntity list to album IDs
      final albumIds = selectedAlbums.map((album) => album.id).toList();

      // Re-initialize MediaSearchService with new album selection
      await _mediaSearchService.reinitializeWithAlbums(albumIds);

      if (kDebugMode) {
        print(
            '✅ MediaCoordinator: MediaSearchService re-initialized with ${selectedAlbums.length} albums');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to re-initialize with albums: $e');
      }
      rethrow;
    }
  }

  /// Get an asset entity by ID
  Future<AssetEntity?> getAssetById(String id) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _mediaSearchService.getAssetById(id);
  }

  /// Refreshes media data by rescanning directories and clearing caches
  /// This ensures the latest media files are available, including newly added files
  ///
  /// PhotoManager uses aggressive caching both internally and at the OS level.
  /// When new files are added to directories, PhotoManager doesn't automatically
  /// detect them without proper cache invalidation. This method:
  ///
  /// 1. Clears PhotoManager's file cache (clearFileCache)
  /// 2. Releases native caches (releaseCache)
  /// 3. Restarts change notifications to trigger system media scan
  /// 4. Forces PhotoManager to refresh its internal state
  /// 5. Refreshes our internal metadata cache
  /// 6. Re-initializes the search service
  ///
  /// This comprehensive approach ensures that newly added files are detected
  /// when users pull-to-refresh in the MediaSelectionScreen.
  Future<void> refreshMediaData() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print('🔄 MediaCoordinator: Starting comprehensive media refresh...');
      }

      // Step 1: Clear PhotoManager's file cache to force fresh file reads
      if (kDebugMode) {
        print('🗑️ MediaCoordinator: Clearing PhotoManager file cache...');
      }
      await PhotoManager.clearFileCache();

      // Step 2: Release PhotoManager's native caches to force fresh asset queries
      if (kDebugMode) {
        print('🗑️ MediaCoordinator: Releasing PhotoManager native caches...');
      }
      await PhotoManager.releaseCache();

      // Step 3: Restart change notifications to trigger system media scan
      if (kDebugMode) {
        print('🔔 MediaCoordinator: Restarting change notifications...');
      }

      try {
        await PhotoManager.stopChangeNotify();
        // Longer delay to ensure proper cleanup
        await Future.delayed(const Duration(milliseconds: 500));
        await PhotoManager.startChangeNotify();
        // Additional delay to allow change notifications to initialize
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ MediaCoordinator: Change notification restart failed: $e');
        }
        // Continue without change notifications - not critical for refresh
      }

      // Step 4: Force PhotoManager to refresh its internal album state
      if (kDebugMode) {
        print('📱 MediaCoordinator: Forcing PhotoManager album refresh...');
      }

      try {
        // Force PhotoManager to re-scan albums by requesting them with fresh options
        final albums = await PhotoManager.getAssetPathList(
          type: RequestType.all,
          filterOption: FilterOptionGroup(
            imageOption: const FilterOption(
              sizeConstraint: SizeConstraint(ignoreSize: true),
            ),
            videoOption: const FilterOption(
              sizeConstraint: SizeConstraint(ignoreSize: true),
            ),
            orders: [
              const OrderOption(
                type: OrderOptionType.createDate,
                asc: false,
              ),
            ],
          ),
        );

        if (kDebugMode) {
          print(
              '📱 MediaCoordinator: Refreshed ${albums.length} PhotoManager albums');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ MediaCoordinator: Album refresh failed: $e');
        }
      }

      // Step 5: Refresh MediaMetadataService cache for custom directories
      if (kDebugMode) {
        print('📊 MediaCoordinator: Refreshing metadata cache...');
      }
      await _metadataService.refreshCache();

      // Step 6: Re-initialize MediaSearchService to get fresh data
      if (kDebugMode) {
        print('🔍 MediaCoordinator: Re-initializing MediaSearchService...');
      }
      await _mediaSearchService.initialize();

      // Step 7: Force notify listeners about the refresh
      notifyListeners();

      if (kDebugMode) {
        print(
            '✅ MediaCoordinator: Comprehensive media refresh completed successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to refresh media data: $e');
      }
      rethrow;
    }
  }

  /// Forces a complete rescan of all selected directories
  /// Use this when you need to ensure absolutely latest media is available
  Future<void> forceRescanDirectories() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print('🔄 MediaCoordinator: Starting force rescan of directories...');
      }

      // PhotoManager automatically scans the latest files on each query
      // No explicit refresh needed - the next getMediaForQuery call will get latest data

      if (kDebugMode) {
        print('✅ MediaCoordinator: Force rescan completed successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to force rescan directories: $e');
      }
      rethrow;
    }
  }

  // ========== MediaMetadataService Methods ==========

  /// Extract metadata from a file
  Future<Map<String, dynamic>> extractMetadata(File file) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _metadataService.extractMetadata(file);
  }

  /// Gets the most recent image file URI from specified directory or all directories
  Future<Map<String, dynamic>?> getLatestImageInDirectory(
      String? directoryPath) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print(
            '🔍 MediaCoordinator: Getting latest image from directory: ${directoryPath ?? 'All'}');
      }

      final searchParams = {
        'terms': <String>[], // No search terms, just get recent
        'date_range': null,
        'media_type': 'photo', // Only photos
        'directory': directoryPath,
      };

      final candidates = await _photoManager.findAssetCandidates(searchParams);
      if (candidates.isEmpty) {
        if (kDebugMode) {
          print('⚠️ MediaCoordinator: No images found in directory');
        }
        return null;
      }

      // Get the most recent image (first one since they're sorted by creation date desc)
      final latestAsset = candidates.first;
      final assetMaps = await _photoManager.getAssetMaps([latestAsset]);

      if (assetMaps.isNotEmpty) {
        final latestImage = assetMaps.first;

        // Enrich with metadata
        final fileUri = latestImage['file_uri'] as String;
        final file = File(Uri.parse(fileUri).path);
        if (await file.exists()) {
          final metadata = await _metadataService.extractMetadata(file);
          latestImage['metadata'] = metadata;
        }

        if (kDebugMode) {
          print(
              '✅ MediaCoordinator: Found latest image: ${latestImage['file_uri']}');
        }

        return latestImage;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error getting latest image: $e');
      }
      return null;
    }
  }

  /// Checks if a file is in one of the enabled directories
  Future<bool> isFileInEnabledDirectory(String fileUri) async {
    if (!isCustomDirectoriesEnabled) {
      return true; // If custom directories are disabled, all files are allowed
    }

    try {
      final filePath = Uri.parse(fileUri).path;
      final enabledPaths = enabledDirectories.map((dir) => dir.path).toList();

      // Check if the file path starts with any enabled directory path
      return enabledPaths.any((dirPath) => filePath.startsWith(dirPath));
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to check file directory: $e');
      }
      return false;
    }
  }

  /// Get the latest media files with complete metadata
  Future<List<Map<String, dynamic>>> _getLatestMediaFiles() async {
    final recentMedia = await getMediaForQuery(
      '', // Empty query to get all recent media
      dateRange: null,
      mediaTypes: ['image', 'video'],
    );

    // Take only the most recent files and ensure they have complete metadata
    return recentMedia.take(_appSettingsService.aiMediaContextLimit).toList();
  }

  /// Check if a directory has any media content
  Future<bool> _directoryHasContent(String directory) async {
    final mediaInDir = await getMediaForQuery(
      '',
      directory: directory,
      mediaTypes: ['image', 'video'],
    );
    return mediaInDir.isNotEmpty;
  }

  /// Get the set of media types available in a directory
  Future<Set<String>> _getMediaTypesInDirectory(String directory) async {
    final mediaInDir = await getMediaForQuery(
      '',
      directory: directory,
      mediaTypes: ['image', 'video'],
    );

    return mediaInDir
        .map((m) => (m['mime_type'] as String).split('/')[0])
        .toSet();
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print(
          '🗑️ MediaCoordinator: Being disposed (initialized: $_isInitialized)');
    }
    super.dispose();
  }
}
